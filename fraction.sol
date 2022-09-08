pragma solidity >=0.8.13;

contract Fraction {
  struct User {
    uint256[] activePools;

  }
  struct Pool {
    User[] users;
    address buyTokenAddress;
    uint256 needToCollect;
    uint256 collected;
    address assetAddress;
    uint256 assetId;
    address assetOwner;
    uint256 pieceCost;
  }

  uint256 poolsAmount;

  mapping(uint256 => User[]) usersInPool;
  mapping(uint256 => Pool) pools;

  event NewPoolCreated(Pool pool);
  event BoughtAssetPiece(address user, uint256 poolId);

  constructor() {
    poolsAmount = 0;
  }

  function createPool(address assetAddress, uint256 assetId, address buyTokenAddress,
                      address assetOwner, uint256 needToCollect) public {
    pools[poolsAmount] = Pool(new User[](0), buyTokenAddress, needToCollect, 0, assetAddress, assetId, assetOwner, 1);

    emit NewPoolCreated(pools[poolsAmount]);

    poolsAmount = poolsAmount + 1;
  }

  // return money if overflow
  function getAssetPiece(uint256 poolId, uint256 amount) payable public {
    Pool memory pool = pools[poolId];
    require(amount > pool.pieceCost, 'Not anough to buy a piece');
    require(amount < (pool.needToCollect - pool.collected), 'Amount too big to buy');

    // TODO: make the transfer

    emit BoughtAssetPiece(msg.sender, poolId);
  }
}