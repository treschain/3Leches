/*
    Website: https://tresleches.finance
    Telegram Group: https://t.me/TresLechesCakeOfficial_EN
    Telegram Channel: https://t.me/TresLechesCakeOfficial
    Donate: 0xcbFA1ce0b8bFb9C09E713162771C31F176fB1ADE
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
 
import "https://github.com/0xcert/ethereum-erc721/src/contracts/tokens/nf-token-metadata.sol";
import "https://github.com/0xcert/ethereum-erc721/src/contracts/ownership/ownable.sol";
 
contract TresLechesCakeNFT is NFTokenMetadata, Ownable {
 
  constructor() {
    nftName = "Tres Leches Cake NFT";
    nftSymbol = "3LechesNFT";
  }
 
  function mint(address _to, uint256 _tokenId, string calldata _uri) external onlyOwner {
    super._mint(_to, _tokenId);
    super._setTokenUri(_tokenId, _uri);
  }
 
}