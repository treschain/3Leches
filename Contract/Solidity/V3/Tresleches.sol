//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./DividendDistributor.sol";

contract Tresleches is IERC20, Ownable {
    using SafeMath for uint256;

    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    address public BUSD = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    string constant _name = "Tres Leches Cake";
    string constant _symbol = "3LechesCake";
    uint8 constant _decimals = 9;

    uint256 _totalSupply = 1000000000000 * (10**_decimals);

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;

    mapping(address => bool) isFeeExempt;
    mapping(address => bool) isDividendExempt;
    // allowed users to do transactions before trading enable
    mapping(address => bool) isAuthorized;

    // buy fees
    uint256 public buyBusdDividendRewardsFee = 5;
    uint256 public buyMarketingFee = 3;
    uint256 public buyLiquidityFee = 2;
    uint256 public buyScholarshipFee = 2;
    uint256 public buyTotalFees = 12;
    // sell fees
    uint256 public sellBusdDividendRewardsFee = 5;
    uint256 public sellMarketingFee = 3;
    uint256 public sellLiquidityFee = 2;
    uint256 public sellScholarshipFee = 2;
    uint256 public sellTotalFees = 12;

    address public marketingFeeReceiver;
    address public devFeeReceiver;
    address public scholarshipFeeReceiver;

    IUniswapV2Router02 public router;
    address public pair;

    bool public tradingOpen = false;

    DividendDistributor public busdDividendDistributor;

    uint256 distributorGas = 500000;

    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
    event ChangeRewardTracker(address token);
    event IncludeInReward(address holder);

    bool public swapEnabled = true;
    uint256 public swapThreshold = (_totalSupply * 10) / 10000; // 0.01% of supply
    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() {
        router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        pair = IUniswapV2Factory(router.factory()).createPair(
            WBNB,
            address(this)
        );
        _allowances[address(this)][address(router)] = type(uint256).max;

        busdDividendDistributor = new DividendDistributor(
            address(router),
            BUSD
        );

        isFeeExempt[msg.sender] = true;

        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;

        isAuthorized[owner()] = true;
        marketingFeeReceiver = 0xaCB48ee17DDfd41a3273837238D10C4680d40206;
        devFeeReceiver = 0xeEE36B8d8D3ea4d717B513Ba301D13927f1A54f9;
        scholarshipFeeReceiver = 0x558B624De1d61379E0A131C7a9C6F6D9DcC14abE;

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable {}

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    // tracker dashboard functions
    function getHolderDetailsBusd(address holder)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return busdDividendDistributor.getHolderDetails(holder);
    }

    function getLastProcessedIndexBusd() public view returns (uint256) {
        return busdDividendDistributor.getLastProcessedIndex();
    }

    function getNumberOfTokenHoldersBusd() public view returns (uint256) {
        return busdDividendDistributor.getNumberOfTokenHolders();
    }

    function totalDistributedRewardsBusd() public view returns (uint256) {
        return busdDividendDistributor.totalDistributedRewards();
    }

    function allowance(address holder, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender]
                .sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        if (!isAuthorized[sender]) {
            require(tradingOpen, "Trading not open yet");
        }

        if (shouldSwapBack()) {
            swapBackInBnb();
        }

        //Exchange tokens
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );

        uint256 amountReceived = shouldTakeFee(sender)
            ? takeFee(sender, amount, recipient)
            : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);

        // Dividend tracker
        if (!isDividendExempt[sender]) {
            // set busd share
            try
                busdDividendDistributor.setShare(sender, _balances[sender])
            {} catch {}
        }

        if (!isDividendExempt[recipient]) {
            // set busd share
            try
                busdDividendDistributor.setShare(
                    recipient,
                    _balances[recipient]
                )
            {} catch {}
        }

        try busdDividendDistributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function takeFee(
        address sender,
        uint256 amount,
        address to
    ) internal returns (uint256) {
        uint256 feeAmount = 0;
        if (to == pair) {
            feeAmount = amount.mul(sellTotalFees).div(100);
        } else {
            feeAmount = amount.mul(buyTotalFees).div(100);
        }
        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            msg.sender != pair &&
            !inSwap &&
            swapEnabled &&
            tradingOpen &&
            _balances[address(this)] >= swapThreshold;
    }

    function clearStuckBalance(uint256 amountPercentage) external onlyOwner {
        uint256 amountBNB = address(this).balance;
        payable(msg.sender).transfer((amountBNB * amountPercentage) / 100);
    }

    function updateBuyFees(
        uint256 busdReward,
        uint256 marketing,
        uint256 liquidity,
        uint256 scholarship
    ) public onlyOwner {
        buyBusdDividendRewardsFee = busdReward;
        buyMarketingFee = marketing;
        buyLiquidityFee = liquidity;
        buyScholarshipFee = scholarship;
        buyTotalFees = busdReward.add(marketing).add(liquidity).add(scholarship);
    }

    function updateSellFees(
        uint256 busdReward,
        uint256 marketing,
        uint256 liquidity,
        uint256 scholarship
    ) public onlyOwner {
        sellBusdDividendRewardsFee = busdReward;
        sellMarketingFee = marketing;
        sellLiquidityFee = liquidity;
        sellScholarshipFee = scholarship;
        sellTotalFees = busdReward.add(marketing).add(liquidity).add(scholarship);
    }

    // switch Trading
    function tradingStatus(bool _status) public onlyOwner {
        tradingOpen = _status;
    }

    function whitelistPreSale(address _preSale) public onlyOwner {
        isFeeExempt[_preSale] = true;
        isDividendExempt[_preSale] = true;
        isAuthorized[_preSale] = true;
    }

    // manual claim for the greedy humans
    function ___claimRewardsBusd(bool tryAll) public {
        busdDividendDistributor.claimDividend();
        if (tryAll) {
            try busdDividendDistributor.process(distributorGas) {} catch {}
        }
    }

    // manually clear the queue
    function claimProcessBusd() public {
        try busdDividendDistributor.process(distributorGas) {} catch {}
    }

    function swapBackInBnb() internal swapping {
        uint256 contractTokenBalance = _balances[address(this)];
        uint256 tokensToLiquidity = contractTokenBalance
            .mul(buyLiquidityFee)
            .div(buyTotalFees);

        uint256 tokensToRewardBusd = contractTokenBalance
            .mul(buyBusdDividendRewardsFee)
            .div(buyTotalFees);

        // calculate tokens amount to swap
        uint256 tokensToSwap = contractTokenBalance.sub(tokensToLiquidity).sub(
            tokensToRewardBusd
        );
        // swap the tokens
        swapTokensForEth(tokensToSwap);
        // get swapped bnb amount
        uint256 swappedBnbAmount = address(this).balance;

        uint256 totalSwapFee = buyMarketingFee.add(buyScholarshipFee);
        uint256 marketingFeeBnb = swappedBnbAmount.mul(buyMarketingFee).div(
            totalSwapFee
        );
        uint256 devFeeBnb = marketingFeeBnb.div(3);
        uint256 bnbToSendMarketing = marketingFeeBnb.sub(devFeeBnb);
        uint256 bnbForScholarship = swappedBnbAmount.sub(marketingFeeBnb);
        // calculate reward bnb amount
        if (tokensToRewardBusd > 0) {
            swapTokensForTokens(tokensToRewardBusd, BUSD);

            uint256 swappedTokensAmount = IERC20(BUSD).balanceOf(address(this));
            // send bnb to reward
            IERC20(BUSD).transfer(
                address(busdDividendDistributor),
                swappedTokensAmount
            );
            try busdDividendDistributor.deposit(swappedTokensAmount) {} catch {}
        }

        if (bnbToSendMarketing > 0) {
            (bool marketingSuccess, ) = payable(marketingFeeReceiver).call{
                value: bnbToSendMarketing,
                gas: 30000
            }("");
            marketingSuccess = false;
        }

        if (devFeeBnb > 0) {
            (bool devSuccess, ) = payable(devFeeReceiver).call{
                value: devFeeBnb,
                gas: 30000
            }("");
            // only to supress warning msg
            devSuccess = false;
        }

        if (bnbForScholarship > 0) {
            (bool scholarshipSuccess, ) = payable(scholarshipFeeReceiver).call{
                value: bnbForScholarship,
                gas: 30000
            }("");
            // only to supress warning msg
            scholarshipSuccess = false;
        }

        if (tokensToLiquidity > 0) {
            // add liquidity
            swapAndLiquify(tokensToLiquidity);
        }
    }

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit AutoLiquify(newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), tokenAmount);
        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForTokens(uint256 tokenAmount, address tokenToSwap)
        private
    {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = router.WETH();
        path[2] = tokenToSwap;
        _approve(address(this), address(router), tokenAmount);
        // make the swap
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of tokens
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function setIsDividendExemptBusd(address holder, bool exempt)
        external
        onlyOwner
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if (exempt) {
            busdDividendDistributor.setShare(holder, 0);
        } else {
            busdDividendDistributor.setShare(holder, _balances[holder]);
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setFeeReceivers(
        address _marketingFeeReceiver,
        address _devFeeReceiver,
        address _scholarshipFeeReceiver
    ) external onlyOwner {
        marketingFeeReceiver = _marketingFeeReceiver;
        devFeeReceiver = _devFeeReceiver;
        scholarshipFeeReceiver = _scholarshipFeeReceiver;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount)
        external
        onlyOwner
    {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

    function setDistributionCriteriaBusd(
        uint256 _minPeriod,
        uint256 _minDistribution
    ) external onlyOwner {
        busdDividendDistributor.setDistributionCriteria(
            _minPeriod,
            _minDistribution
        );
    }

    function setDistributorSettings(uint256 gas) external onlyOwner {
        require(gas < 750000);
        distributorGas = gas;
    }
}
