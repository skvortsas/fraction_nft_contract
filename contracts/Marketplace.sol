// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Fraction.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error AlreadyListed(uint256 poolId, address seller);
error NotListed(uint256 poolId, address seller);
error NotEnoughPieces();
error PriceMustBeAboveZero();
error ItemNotForSale(address nftAddress, uint256 tokenId);
error NoProceeds();
error NotApprovedForMarketplace();

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
  }

  // Events
  event PiecesListed (
    address indexed sender,
    uint256 indexed poolId,
    uint256 piecesAmount,
    uint256 price
  );
  event ListingCanceled (
    address indexed sender,
    uint256 poolId
  );
  event PiecesBought(
    address indexed buyer,
    uint256 indexed poolId,
    uint256 piecesBought,
    uint256 price
  );

  // State Variables
  // poolId => sellerAddress will return seller listing
  mapping(uint256 => mapping(address => Listing)) private s_listings;
  // userAddress => tokenAddress will return amount of proceeds
  mapping(address => mapping(address => uint256)) private s_proceeds;

  // Function modifiers
  modifier notListed (
    uint256 _poolId,
    address _seller
  ) {
      Listing memory listing = s_listings[_poolId][_seller];
      // Because uset can't list 0 pieces
      if (listing.piecesToSell > 0) {
        revert AlreadyListed(_poolId, _seller);
      }
      _;
  }

  modifier isListed (
    uint256 _poolId,
    address _seller
  ) {
    Listing memory listing = s_listings[_poolId][_seller];
    // Because uset can't list 0 pieces
    if (listing.piecesToSell < 1) {
      revert NotListed(_poolId, _seller);
    }
    _;
  }

  modifier isEnough (
    uint256 _poolId,
    uint256 _piecesToCheck,
    address _spender
  ) {
    if (usersPieces[_spender][_poolId] < _piecesToCheck) {
      revert NotEnoughPieces();
    }
    _;
  }

  function listPieces (
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
      s_listings[poolId][msg.sender] = Listing(
        poolId,
        msg.sender,
        sellToken,
        price,
        piecesToSell,
        pools[poolId].piecesCollected,
        pools[poolId].assetAddress,
        pools[poolId].assetId
      );
      emit PiecesListed(msg.sender, poolId, piecesToSell, price);
  }

  function cancelListing(uint256 poolId)
    external
    isListed(poolId, msg.sender)
  {
    delete (s_listings[poolId][msg.sender]);
    emit ListingCanceled(msg.sender, poolId);
  }

  function buyPieces(uint256 poolId, address seller)
    external
    payable
    isListed(poolId, seller)
    nonReentrant
  {
    Listing memory listedItem = s_listings[poolId][seller];
    // transfer or check
    transfer(msg.sender, payable(address(this)), listedItem.price, listedItem.sellToken);

    s_proceeds[listedItem.creator][listedItem.sellToken] += listedItem.price;
    delete (s_listings[poolId][listedItem.creator]);
    usersPieces[listedItem.creator][poolId] -= listedItem.piecesToSell;
    usersPieces[msg.sender][poolId] += listedItem.piecesToSell;
    emit PiecesBought(msg.sender, poolId, listedItem.piecesToSell, listedItem.price);
  }

  function updateListing(
    uint256 poolId,
    uint256 newPrice,
    uint256 newPiecesAmount
  )
    external
    isListed(poolId, msg.sender)
    nonReentrant
  {
    if (newPrice == 0) {
      revert PriceMustBeAboveZero();
    }

    if (newPiecesAmount == 0) {
      revert NotEnoughPieces();
    }

    s_listings[poolId][msg.sender].price = newPrice;
    s_listings[poolId][msg.sender].piecesToSell = newPiecesAmount;
    emit PiecesListed(msg.sender, poolId, newPiecesAmount, newPrice);
  }

  function withdrawProceeds(){} // method caller should be withdrawer

  function getListing(address nftAddress, uint256 tokenId){}
}