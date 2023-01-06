// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Fraction.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Marketplace is Ownable, ReentrancyGuard, Fraction {
  struct Listing {
    uint256 poolId;
    address creator;
    address sellToken;
    uint256 price;
    uint256 piecesToSell;
    uint256 piecesTotalInPool;
    address assetAddress;
    uint256 assetId;
    bool closed;
  }

  // Events
  event ItemListed (
    address indexed sender,
    uint256 poolId,
    uint256 piecesAmount,
    uint256 price
  );

  // State Variables
  // poolId => sellerAddress will return seller listing
  mapping(uint256 => mapping(address => Listing)) private s_listings;
  mapping(address => uint256) private s_proceeds;

  // Function modifiers
  modifier notListed(
    uint256 _poolId,
    address _owner
  ) {
      Listing memory listing = s_listings[_poolId][_owner];
      // Because uset can't list 0 pieces
      if (listing.piecesToSell > 0) {
        revert AlreadyListed(_poolId, _owner);
      }
      _;
  }

  modifier isEnough(
    uint256 _poolId,
    uint256 _piecesToSell,
    address _spender
  ) {
    if (usersPieces[_spender][_poolId] < _piecesToSell) {
      revert NotEnoughPieces();
    }
    _;
  }

  function listItem (
      uint256 poolId,
      uint256 piecesToSell,
      address sellToken,
      uint256 price
  ) external
    notListed(poolId, msg.sender)
    isEnough(poolId, piecesToSell, msg.sender)
  {
    if (price <= 0) {
          revert PriceMustBeAboveZero();
      }
      s_listings[poolId][msg.sender] = Listing(price, msg.sender);
      emit ItemListed(msg.sender, poolId, piecesToSell, price);
  }

  function cancelListing(address nftAddress, uint256 tokenId){}

  function buyItem(address nftAddress, uint256 tokenId){}

  function updateListing(
          address nftAddress,
          uint256 tokenId,
          uint256 newPrice
      ){}
  function withdrawProceeds(){} // method caller should be withdrawer

  function getListing(address nftAddress, uint256 tokenId){}
}