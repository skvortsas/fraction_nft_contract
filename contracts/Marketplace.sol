// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Fraction.sol";
import "./ActiveItems.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error AlreadyListed(uint256 poolId, address seller);
error NotListed(uint256 poolId, address seller);
error NotEnoughPieces();
error PiecesAmountMustBeAboveZero();
error PriceMustBeAboveZero();
error NoProceeds();

contract Marketplace is Ownable, ReentrancyGuard, ActiveItems {
  struct Listing {
    uint256 id;
    uint256 poolId;
    address creator;
    address sellToken;
    uint256 price;
    uint256 piecesToSell;
    uint256 piecesTotalInPool;
    address assetAddress;
    uint256 assetId;
  }
  Fraction fractionContract;

  constructor (address _fractionContractAddress) {
    fractionContract = Fraction(_fractionContractAddress);
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
  uint256 private listingsAmount;
  // poolId => sellerAddress will return seller listing
  mapping(uint256 => mapping(address => Listing)) private s_listings;
  // userAddress => tokenAddress will return amount of proceeds
  mapping(address => mapping(address => uint256)) private s_proceeds;
  mapping(uint256 => Listing) public listings;

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
    if (fractionContract.usersPieces(_spender, _poolId) < _piecesToCheck) {
      revert NotEnoughPieces();
    }
    _;
  }

  function transfer(address _from, address payable _to, uint256 _amount, address _transferToken) internal {
    if (_transferToken == address(0)) {
      if (address(this) != _to) {
          _to.call{ value: _amount };
      }
    } else {
      if (_from == address(this)) {
          IERC20(_transferToken).transfer(_to, _amount);
      } else {
          IERC20(_transferToken).transferFrom(_from, _to, _amount);
      }
    }
  }

  function listPieces (
      uint256 poolId,
      uint256 piecesToSell,
      address sellToken,
      uint256 price,
      uint256 piecesCollected,
      address assetAddress,
      uint256 assetId
  ) external
    notListed(poolId, msg.sender)
    isEnough(poolId, piecesToSell, msg.sender)
  {
    if (price <= 0) {
      revert PriceMustBeAboveZero();
    }
    listings[listingsAmount] = Listing(
      listingsAmount,
      poolId,
      msg.sender,
      sellToken,
      price,
      piecesToSell,
      piecesCollected,
      assetAddress,
      assetId
    );
    s_listings[poolId][msg.sender] = Listing(
      listingsAmount,
      poolId,
      msg.sender,
      sellToken,
      price,
      piecesToSell,
      piecesCollected,
      assetAddress,
      assetId
    );
    ActiveItems.append();
    listingsAmount = listingsAmount + 1;
    emit PiecesListed(msg.sender, poolId, piecesToSell, price);
  }

  function cancelListing(uint256 poolId)
    external
    isListed(poolId, msg.sender)
  {
    ActiveItems.remove(s_listings[poolId][msg.sender].id);
    delete (listings[s_listings[poolId][msg.sender].id]);
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

    // TODO: remove doplicates like in cancel listing
    s_proceeds[listedItem.creator][listedItem.sellToken] += listedItem.price;
    ActiveItems.remove(s_listings[poolId][listedItem.creator].id);
    delete (listings[s_listings[poolId][listedItem.creator].id]);
    delete (s_listings[poolId][listedItem.creator]);
    fractionContract.transferTokensViaMarketplace(listedItem.creator, msg.sender, poolId, listedItem.piecesToSell);
    emit PiecesBought(msg.sender, poolId, listedItem.piecesToSell, listedItem.price);
  }

  function updateListing(
    uint256 poolId,
    uint256 newPrice,
    uint256 newPiecesAmount
  )
    external
    isListed(poolId, msg.sender)
    isEnough(poolId, newPiecesAmount, msg.sender)
    nonReentrant
  {
    if (newPrice == 0) {
      revert PriceMustBeAboveZero();
    }

    if (newPiecesAmount == 0) {
      revert PiecesAmountMustBeAboveZero();
    }

    listings[s_listings[poolId][msg.sender].id].price = newPrice;
    listings[s_listings[poolId][msg.sender].id].piecesToSell = newPiecesAmount;
    s_listings[poolId][msg.sender].price = newPrice;
    s_listings[poolId][msg.sender].piecesToSell = newPiecesAmount;
    emit PiecesListed(msg.sender, poolId, newPiecesAmount, newPrice);
  }

  function withdrawProceeds(address tokenAddress) external {
    uint256 proceeds = s_proceeds[msg.sender][tokenAddress];
    if (proceeds <= 0) {
      revert NoProceeds();
    }
    s_proceeds[msg.sender][tokenAddress] = 0;

    transfer(address(this), payable(msg.sender), proceeds, tokenAddress);
  }

  function getListing(address sellerAddress, uint256 poolId)
    external
    view
    returns (Listing memory)
  {
    return s_listings[poolId][sellerAddress];
  }

  function getProceeds(address seller, address tokenAddress) external view returns (uint256) {
    return s_proceeds[seller][tokenAddress];
  }

  function getActiveListings() view public returns(Listing[] memory) {
    uint256 [] memory activeListingsIDs = ActiveItems.getActiveItemsIDs();

    Listing[] memory tmpActiveListings = new Listing[](activeListingsIDs.length);
    for (uint i = 0; i < activeListingsIDs.length; i++) {
      Listing storage listing = listings[i];
      tmpActiveListings[i] = listing;
    }

    return tmpActiveListings;
  }
}