// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "./ActivePools.sol";

contract Fraction is Ownable, ActivePools {
  using SafeMath for uint256;

  struct Pool {
    address poolCreator;
    address buyTokenAddress;
    bool isERC721;
    uint256 piecesNeedToCollect;
    uint256 tokensNeedToCollect;
    uint256 piecesCollected;
    address assetAddress;
    uint256 assetId;
    address assetOwner;
    uint256 pieceCost;
    bool unavailable;
    bool closed;
  }

  uint256 MAX_UINT = 2**256 - 1;
  AggregatorV3Interface internal ethPriceFeed;
  uint256 public poolsAmount;
  uint256 public defaultPiecesAmountToCollect = 1000;
  // Default creator share is 1%
  uint256 public defaultCreatorShare = defaultPiecesAmountToCollect.div(100);

  mapping(address => Pool[]) public userPools;
  mapping(uint256 => Pool) public pools;
  // user address => poolId will return pieces in pool by user
  mapping(address => mapping(uint256 => uint256)) public usersPieces;

  event NewPoolCreated(Pool pool);
  event PoolClosed(uint256 poolId);
  event PurchasedAsset(uint256 poolId);
  event EmergencyStopped();
  event ChangedDefaultPiecesAmount(uint256 newAmount);
  event ChangedCreatorShare(uint256 newPercent);

  constructor(
    address ethPriceFeedAddress
  ) {
    ethPriceFeed = AggregatorV3Interface(ethPriceFeedAddress);
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

  function assetTransfer(address _from, address _to, address _transferAssetAddress, bool _isERC721, uint256 _assetId) internal {
    if (_isERC721) {
      ERC721Transfer(_from, _to, _transferAssetAddress, _assetId);
    } else {
      ERC1155Transfer(_from, _to, _transferAssetAddress, _assetId);
    }
  }

  function ERC721Transfer(address _from, address _to, address _transferAssetAddress, uint256 _assetId) internal {
    IERC721(_transferAssetAddress).safeTransferFrom(_from, _to, _assetId);
  }

  function ERC1155Transfer(address _from, address _to, address _transferAssetAddress, uint256 _assetId) internal {
    IERC1155(_transferAssetAddress).safeTransferFrom(_from, _to, _assetId, 1, '');
  }

  function createPool(address assetAddress, bool isERC721, uint256 assetId, address buyTokenAddress,
                      address assetOwner, uint256 needToCollect) external {
    uint256 peiceCost = needToCollect.div(defaultPiecesAmountToCollect.sub(defaultCreatorShare));
    pools[poolsAmount] = Pool(msg.sender, buyTokenAddress, isERC721, defaultPiecesAmountToCollect, needToCollect, defaultCreatorShare, assetAddress, assetId, assetOwner, peiceCost, false, false);
    usersPieces[msg.sender][poolsAmount] = defaultCreatorShare;
    ActivePools.append();

    emit NewPoolCreated(pools[poolsAmount]);

    poolsAmount = poolsAmount + 1;
  }

  function buyAssetPiece(uint256 poolId, uint256 piecesAmount) external payable {
    Pool storage pool = pools[poolId];
    require(pool.unavailable != true, 'Pool is unavailable');
    require(pool.closed != true, 'Pool is closed');
    require(piecesAmount > 0, 'Amount of pieces have to be more then 0');
    require(piecesAmount <= (pool.piecesNeedToCollect - pool.piecesCollected), 'Amount too big to buy');

    pool.piecesCollected = pool.piecesCollected.add(piecesAmount);
    usersPieces[msg.sender][poolId] = usersPieces[msg.sender][poolId].add(piecesAmount);
    transfer(msg.sender, payable(address(this)), piecesAmount.mul(pool.pieceCost), pool.buyTokenAddress);

    if (pool.piecesCollected >= pool.piecesNeedToCollect) {
      pool.unavailable = true;
    }
  }

  function withdraw(uint256 poolId) external {
    Pool memory pool = pools[poolId];
    // We presume that piece cost is always > 0
    require(pool.pieceCost > 0,'Pool does not exist');
    require(pool.unavailable != true, 'Pool is unavailable');
    require(usersPieces[msg.sender][poolId] > 0, 'User does not have any pieces');
    uint256 amoutToWithdraw = (usersPieces[msg.sender][poolId]).mul(pool.pieceCost);
    usersPieces[msg.sender][poolId] = 0;
    pool.piecesCollected = pool.piecesCollected.sub(amoutToWithdraw);
    transfer(address(this), payable(msg.sender), amoutToWithdraw, pool.buyTokenAddress);
  }

  function buyAsset(uint256 poolId) internal {
    Pool memory pool = pools[poolId];
    transfer(address(this), payable(owner()), pool.piecesCollected.mul(pool.pieceCost), pool.buyTokenAddress);
  }

  function closePool(uint256 poolId) public onlyOwner {
    pools[poolId].closed = true;

    emit PoolClosed(poolId);
  }

  function finalizeAssetPurchase(uint256 poolId, address assetAddress, bool success, uint256 returnAmount) public onlyOwner {
    pools[poolId].unavailable = false;

    if (!success) {
      closePool(poolId);
      transfer(msg.sender, payable(address(this)), returnAmount, pools[poolId].buyTokenAddress);
    } else {
      assetTransfer(msg.sender, address(this), assetAddress, pools[poolId].isERC721, pools[poolId].assetId);
    }

    emit PurchasedAsset(poolId);
  }

  function changeDefaultPiecesAmountToCollect(uint256 newAmount) external onlyOwner {
    defaultPiecesAmountToCollect = newAmount;

    emit ChangedDefaultPiecesAmount(newAmount);
  }

  function changeCreatorShare(uint256 newPercent) external onlyOwner {
    defaultCreatorShare = (defaultPiecesAmountToCollect.div(100)).mul(newPercent);

    emit ChangedCreatorShare(newPercent);
  }

  function emergencyStop() external onlyOwner {
    for (uint256 i = 0; i < poolsAmount; i++) {
      pools[i].closed = true;
    }

    emit EmergencyStopped();
  }

  function getLatestEthPrice() public view returns (int) {
        (
          ,
          int price,
          ,
          ,
        ) = ethPriceFeed.latestRoundData();
        return price;
  }

  function checkIfNeedToFulfill() public view returns (uint256) {
    uint256 poolIdToServe = MAX_UINT;
    uint256[] memory activePoolsIDs = ActivePools.getActivePoolsIDs();

    for (uint i = 0; i < activePoolsIDs.length; i++) {
      if (pools[activePoolsIDs[i] - 1].piecesCollected >= pools[activePoolsIDs[i] - 1].piecesNeedToCollect) {
        poolIdToServe = activePoolsIDs[i] - 1;
        break;
      }
    }

    if (poolIdToServe < MAX_UINT) {
      return poolIdToServe;
    }

    return MAX_UINT;
  }

  function contractHasAsset(Pool memory pool) private view returns(bool) {
    if (pool.isERC721) {
      return IERC721(pool.assetAddress).ownerOf(pool.assetId) == address(this);
    }

    return IERC1155(pool.assetAddress).balanceOf(address(this), pool.assetId) > 0;
  }

  function withdrawAssetWithFullFractions(uint256 poolId) public {
    require(usersPieces[msg.sender][poolId] >= pools[poolId].piecesNeedToCollect, 'You do not own all the pieces');
    require(pools[poolId].unavailable == true, 'The pool is not finished yet');
    require(contractHasAsset(pools[poolId]), 'Contract does not own the asset');

    usersPieces[msg.sender][poolId] = 0;
    assetTransfer(address(this), msg.sender, pools[poolId].assetAddress, pools[poolId].isERC721, pools[poolId].assetId);
  }

  function getActivePools() view public returns(Pool[] memory) {
    uint256[] memory activePoolsIDs = ActivePools.getActivePoolsIDs();
    Pool[] memory tmpActivePools = new Pool[](activePoolsIDs.length);
    for (uint i = 0; i < activePoolsIDs.length; i++) {
      Pool storage pool = pools[i];
      tmpActivePools[i] = pool;
    }

    return tmpActivePools;
  }
}