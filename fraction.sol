pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Fraction is Ownable {
  using SafeMath for uint256;

  struct Pool {
    address buyTokenAddress;
    uint256 needToCollect;
    uint256 collected;
    address assetAddress;
    string assetId;
    address assetOwner;
    uint256 pieceCost;
    bool purchaseInProgress;
  }

  uint256 poolsAmount;

  mapping(uint256 => address[]) usersInPool;
  mapping(uint256 => Pool) pools;
  // user address => poolId will give pieces in pool
  mapping(address => mapping(uint256 => uint256)) usersPieces;

  event NewPoolCreated(Pool pool);
  event BoughtAssetPiece(address user, uint256 poolId);
  event WithdwanTokens(address user, uint256 poolId, uint256 tokensAmount);
  event TransferedTokensToButAsset(uint256 poolId);

  constructor() {
    poolsAmount = 0;
  }

  function transfer(address _from, address _to, uint _amount, address transferToken) internal {
    if (_from == address(this)) {
      IERC20(transferToken).transfer(_to, _amount);
    } else {
      IERC20(transferToken).transferFrom(_from, _to, _amount);
    }
  }

  function createPool(address assetAddress, string memory assetId, address buyTokenAddress,
                      address assetOwner, uint256 needToCollect) public {
                        // TODO: find out piece cost
    pools[poolsAmount] = Pool(buyTokenAddress, needToCollect, 0, assetAddress, assetId, assetOwner, 1, false);

    emit NewPoolCreated(pools[poolsAmount]);

    poolsAmount = poolsAmount + 1;
  }

  // TODO: need to return money if user gave more money then pieces bought
  // TODO: return money if overflow
  function getAssetPiece(uint256 poolId, uint256 amount) payable public {
    Pool memory pool = pools[poolId];
    require(amount > pool.pieceCost, 'Not anough to buy a piece');
    require(amount < (pool.needToCollect - pool.collected), 'Amount too big to buy');

    transfer(msg.sender, address(this), amount, pool.buyTokenAddress);
    pool.collected = pool.collected.add(amount);
    // TODO: make the pieces functiononality
    usersPieces[msg.sender][poolId] = usersPieces[msg.sender][poolId].add(amount.div(pool.pieceCost));

    emit BoughtAssetPiece(msg.sender, poolId);
  }

  // TODO: check if pool is active or not buying NFt right now
  function withdraw(uint256 poolId) public {
    require(bytes(pools[poolId].assetId).length > 0,'pool does not exist');
    Pool memory pool = pools[poolId];
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
    pool.purchaseInProgress = true;

    emit TransferedTokensToButAsset(poolId);
  }
}