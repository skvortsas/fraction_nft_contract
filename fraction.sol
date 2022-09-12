pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

contract Fraction is Ownable {
  using SafeMath for uint256;

  struct Pool {
    address buyTokenAddress;
    bool isERC721;
    uint256 needToCollect;
    uint256 collected;
    address assetAddress;
    uint256 assetId;
    address assetOwner;
    uint256 pieceCost;
    bool unavailable;
    bool closed;
  }

  uint256 public poolsAmount;

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
                        // TODO: find out piece cost
    pools[poolsAmount] = Pool(buyTokenAddress, isERC721, needToCollect, 0, assetAddress, assetId, assetOwner, 1, false, false);

    emit NewPoolCreated(pools[poolsAmount]);

    poolsAmount = poolsAmount + 1;
  }

  // TODO: need to return money if user gave more money then pieces bought
  // TODO: return money if overflow
  function getAssetPiece(uint256 poolId, uint256 amount) payable public {
    Pool memory pool = pools[poolId];
    require(pool.unavailable != true, 'Pool is unavailable');
    require(pool.closed != true, 'Pool is closed');
    require(amount > pool.pieceCost, 'Not anough to buy a piece');
    require(amount < (pool.needToCollect - pool.collected), 'Amount too big to buy');

    transfer(msg.sender, address(this), amount, pool.buyTokenAddress);
    pool.collected = pool.collected.add(amount);
    // TODO: make the pieces functiononality
    usersPieces[msg.sender][poolId] = usersPieces[msg.sender][poolId].add(amount.div(pool.pieceCost));

    emit BoughtAssetPiece(msg.sender, poolId);
  }

  function withdraw(uint256 poolId) public {
    Pool memory pool = pools[poolId];
    // We presume that piece cost is always > 0
    require(pool.pieceCost > 0,'Pool does not exist');
    require(pool.unavailable != true, 'Pool is unavailable');
    uint256 amoutToWithdraw = (usersPieces[msg.sender][poolId]).mul(pool.pieceCost);
    usersPieces[msg.sender][poolId] = 0;

    transfer(address(this), msg.sender, amoutToWithdraw, pool.buyTokenAddress);
    pool.collected = pool.collected.sub(amoutToWithdraw);

    emit WithdwanTokens(msg.sender, poolId, amoutToWithdraw);
  }

  function buyAsset(uint256 poolId) public onlyOwner {
    require(pools[poolId].collected < pools[poolId].needToCollect, 'Not anough tokens to buy');
    Pool memory pool = pools[poolId];
    transfer(address(this), owner(), pool.collected, pool.buyTokenAddress);
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

  function emergencyStop() public onlyOwner {
    for (uint256 i = 0; i < poolsAmount; i++) {
      pools[i].closed = true;
    }

    emit EmergencyStopped();
  }
}