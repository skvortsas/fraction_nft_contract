pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

contract Fraction is Ownable {
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

  uint256 public poolsAmount;
  // We presume that we devide asset into 1000 pieces
  uint256 public defaultPiecesAmountToCollect = 1000;
  // Default creator share is 1%
  uint256 public defaultCreatorShare = defaultPiecesAmountToCollect.div(100);

  mapping(uint256 => address[]) usersInPool;
  mapping(uint256 => Pool) pools;
  // user address => poolId will give pieces in pool
  mapping(address => mapping(uint256 => uint256)) usersPieces;

  event NewPoolCreated(Pool pool);
  event BoughtAssetPiece(address user, uint256 poolId);
  event WithdwanTokens(address user, uint256 poolId, uint256 tokensAmount);
  event TransferedTokensToBuyAsset(uint256 poolId);
  event PoolClosed(uint256 poolId);
  event PurchasedAsset(uint256 poolId);
  event EmergencyStopped();
  event EnoughPiecesCollected(uint256 poolId);
  event ChangedDefaultPiecesAmount(uint256 newAmount);
  event ChangedCreatorShare(uint256 newPercent);

  constructor() {
    poolsAmount = 0;
  }

  function transfer(address _from, address _to, uint256 _amount, address _transferToken) internal {
    if (_from == address(this)) {
      IERC20(_transferToken).transfer(_to, _amount);
    } else {
      IERC20(_transferToken).transferFrom(_from, _to, _amount);
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
                      address assetOwner, uint256 needToCollect) public {
    uint256 peiceCost = needToCollect.div(defaultPiecesAmountToCollect.sub(defaultCreatorShare));
    pools[poolsAmount] = Pool(msg.sender, buyTokenAddress, isERC721, defaultPiecesAmountToCollect, needToCollect, defaultCreatorShare, assetAddress, assetId, assetOwner, peiceCost, false, false);
    usersPieces[msg.sender][poolsAmount] = defaultCreatorShare;

    emit NewPoolCreated(pools[poolsAmount]);

    poolsAmount = poolsAmount + 1;
  }

  function getAssetPiece(uint256 poolId, uint256 piecesAmount) public {
    Pool memory pool = pools[poolId];
    require(pool.unavailable != true, 'Pool is unavailable');
    require(pool.closed != true, 'Pool is closed');
    require(piecesAmount > 0, 'Amount of pieces have to be more then 0');
    require(piecesAmount <= (pool.piecesNeedToCollect - pool.piecesCollected), 'Amount too big to buy');

    transfer(msg.sender, address(this), piecesAmount.mul(pool.pieceCost), pool.buyTokenAddress);
    pool.piecesCollected = pool.piecesCollected.add(piecesAmount);
    usersPieces[msg.sender][poolId] = usersPieces[msg.sender][poolId].add(piecesAmount);

    emit BoughtAssetPiece(msg.sender, poolId);

    if (pool.piecesCollected == pool.piecesNeedToCollect) {
      emit EnoughPiecesCollected(poolId);
    }
  }

  function withdraw(uint256 poolId) public {
    Pool memory pool = pools[poolId];
    // We presume that piece cost is always > 0
    require(pool.pieceCost > 0,'Pool does not exist');
    require(pool.unavailable != true, 'Pool is unavailable');
    uint256 amoutToWithdraw = (usersPieces[msg.sender][poolId]).mul(pool.pieceCost);
    usersPieces[msg.sender][poolId] = 0;

    transfer(address(this), msg.sender, amoutToWithdraw, pool.buyTokenAddress);
    pool.piecesCollected = pool.piecesCollected.sub(amoutToWithdraw);

    emit WithdwanTokens(msg.sender, poolId, amoutToWithdraw);
  }

  function buyAsset(uint256 poolId) public onlyOwner {
    require(pools[poolId].piecesCollected < pools[poolId].piecesNeedToCollect, 'Not anough pieces to buy');
    Pool memory pool = pools[poolId];
    transfer(address(this), owner(), pool.piecesCollected.mul(pool.pieceCost), pool.buyTokenAddress);
    pool.unavailable = true;

    emit TransferedTokensToBuyAsset(poolId);
  }

  function closePool(uint256 poolId) public onlyOwner {
    pools[poolId].closed = true;

    emit PoolClosed(poolId);
  }

  function finalizeAssetPurchase(uint256 poolId, address assetAddress, bool success, uint256 returnAmount) public onlyOwner {
    if (!success) {
      closePool(poolId);
      transfer(msg.sender, address(this), returnAmount, pools[poolId].buyTokenAddress);
    } else {
      assetTransfer(msg.sender, address(this), assetAddress, pools[poolId].isERC721, pools[poolId].assetId);
    }
    pools[poolId].unavailable = false;

    emit PurchasedAsset(poolId);
  }

  function changeDefaultPiecesAmountToCollect(uint256 newAmount) public onlyOwner {
    defaultPiecesAmountToCollect = newAmount;

    emit ChangedDefaultPiecesAmount(newAmount);
  }

  function changeCreatorShare(uint256 newPercent) public onlyOwner {
    defaultCreatorShare = (defaultPiecesAmountToCollect.div(100)).mul(newPercent);

    emit ChangedCreatorShare(newPercent);
  }

  function emergencyStop() public onlyOwner {
    for (uint256 i = 0; i < poolsAmount; i++) {
      pools[i].closed = true;
    }

    emit EmergencyStopped();
  }
}