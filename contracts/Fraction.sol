// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import '@chainlink/contracts/src/v0.8/ChainlinkClient.sol';
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "./ActivePools.sol";

contract Fraction is Ownable, ChainlinkClient, ActivePools {
  using SafeMath for uint256;
  using Chainlink for Chainlink.Request;

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
  uint256 public lastTimeStamp;
  uint256 public immutable interval;
  uint256 public poolsAmount;
  // We presume that we devide asset into 1000 pieces
  uint256 public defaultPiecesAmountToCollect = 1000;
  // Default creator share is 1%
  uint256 public defaultCreatorShare = defaultPiecesAmountToCollect.div(100);

  mapping(uint256 => address[]) public usersInPool;
  mapping(uint256 => Pool) public pools;
  // user address => poolId will return pieces in pool by user
  mapping(address => mapping(uint256 => uint256)) public usersPieces;

  event NewPoolCreated(Pool pool);
  event PoolClosed(uint256 poolId);
  event PurchasedAsset(uint256 poolId);
  event EmergencyStopped();
  event ChangedDefaultPiecesAmount(uint256 newAmount);
  event ChangedCreatorShare(uint256 newPercent);

  constructor(uint256 updateInterval) {
    interval = updateInterval;
    lastTimeStamp = block.timestamp;
    // add interface address into constructor
    ethPriceFeed = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
  }

  // function bytesToUint(bytes memory b) internal pure returns (uint256){
  //       uint256 number;
  //       for(uint i=0;i<b.length;i++){
  //           number = number + uint(uint8(b[i]))*(2**(8*(b.length-(i+1))));
  //       }
  //   return number;
  // }

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
                      address assetOwner, uint256 needToCollect) external {
    uint256 peiceCost = needToCollect.div(defaultPiecesAmountToCollect.sub(defaultCreatorShare));
    pools[poolsAmount] = Pool(msg.sender, buyTokenAddress, isERC721, defaultPiecesAmountToCollect, needToCollect, defaultCreatorShare, assetAddress, assetId, assetOwner, peiceCost, false, false);
    usersPieces[msg.sender][poolsAmount] = defaultCreatorShare;
    ActivePools.append();

    emit NewPoolCreated(pools[poolsAmount]);

    poolsAmount = poolsAmount + 1;
  }

  function buyAssetPiece(uint256 poolId, uint256 piecesAmount) external {
    Pool memory pool = pools[poolId];
    require(pool.unavailable != true, 'Pool is unavailable');
    require(pool.closed != true, 'Pool is closed');
    require(piecesAmount > 0, 'Amount of pieces have to be more then 0');
    require(piecesAmount <= (pool.piecesNeedToCollect - pool.piecesCollected), 'Amount too big to buy');

    pool.piecesCollected = pool.piecesCollected.add(piecesAmount);
    usersPieces[msg.sender][poolId] = usersPieces[msg.sender][poolId].add(piecesAmount);
    transfer(msg.sender, address(this), piecesAmount.mul(pool.pieceCost), pool.buyTokenAddress);

    if (pool.piecesCollected >= pool.piecesNeedToCollect) {
      pool.unavailable = true;
    }
  }

  function withdraw(uint256 poolId) external {
    Pool memory pool = pools[poolId];
    // We presume that piece cost is always > 0
    require(pool.pieceCost > 0,'Pool does not exist');
    require(pool.unavailable != true, 'Pool is unavailable');
    uint256 amoutToWithdraw = (usersPieces[msg.sender][poolId]).mul(pool.pieceCost);
    usersPieces[msg.sender][poolId] = 0;
    pool.piecesCollected = pool.piecesCollected.sub(amoutToWithdraw);
    transfer(address(this), msg.sender, amoutToWithdraw, pool.buyTokenAddress);
  }

  function buyAsset(uint256 poolId) internal {
    Pool memory pool = pools[poolId];
    // pool.unavailable = true;
    transfer(address(this), owner(), pool.piecesCollected.mul(pool.pieceCost), pool.buyTokenAddress);

    // TODO: move all constants to constructor
    Chainlink.Request memory req = buildChainlinkRequest('7da2702f37fd48e5b1b9a5715e3509b6', address(this), this.fulfill.selector);
    req.add('get', string(abi.encodePacked('https://platform.prosper.so/buy/', Strings.toHexString(pool.assetAddress), '/', Strings.toString(pool.assetId), '/', Strings.toHexString(pool.assetOwner))));
    req.add('path', 'result');
    sendChainlinkRequest(req, (1 * LINK_DIVISIBILITY) / 10);
  }

  function askBotToFinalize() private {
    Chainlink.Request memory req = buildChainlinkRequest('7da2702f37fd48e5b1b9a5715e3509b6', address(this), this.fulfill.selector);
    req.add('get', 'https://platform.prosper.so/finalize-purchase');
    req.add('path', 'result');
    sendChainlinkRequest(req, (1 * LINK_DIVISIBILITY) / 10);
  }

  function fulfill(bytes32 _requestId, bytes calldata _result) public recordChainlinkFulfillment(_requestId) {
    // finished result returned from askBotToFinalize function
    if (keccak256(_result) != keccak256('finished')) {
      askBotToFinalize();
    }
  }

  function closePool(uint256 poolId) public onlyOwner {
    pools[poolId].closed = true;

    emit PoolClosed(poolId);
  }

  function finalizeAssetPurchase(uint256 poolId, address assetAddress, bool success, uint256 returnAmount) public onlyOwner {
    pools[poolId].unavailable = false;

    if (!success) {
      closePool(poolId);
      transfer(msg.sender, address(this), returnAmount, pools[poolId].buyTokenAddress);
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

  function checkIfNeedToFulfill() public {
    uint256 poolIdToServe = MAX_UINT;
    uint256[] memory activePoolsIDs = ActivePools.getActivePoolsIDs();

    for (uint i = 0; i < activePoolsIDs.length; i++) {
      if (pools[activePoolsIDs[i]].piecesCollected >= pools[activePoolsIDs[i]].piecesNeedToCollect) {
        poolIdToServe = activePoolsIDs[i];
        break;
      }
    }

    if (poolIdToServe < MAX_UINT) {
      buyAsset(poolIdToServe);
    }
  }

  function withdrawAssetWithFullFractions(uint256 poolId) public {
    // TODO: add require if contract has the asset
    require(usersPieces[msg.sender][poolId] >= pools[poolId].piecesNeedToCollect, 'You do not own all the pieces');
    require(pools[poolId].unavailable == true, 'The pool is not finished yet');

    usersPieces[msg.sender][poolId] = 0;
    assetTransfer(address(this), msg.sender, pools[poolId].assetAddress, pools[poolId].isERC721, pools[poolId].assetId);
  }

  // function checkUpkeep(
  //     bytes calldata checkData
  // ) external view override returns (bool upkeepNeeded, bytes memory performData) {
  //   if (keccak256(checkData) == keccak256('hourly')) {
  //     uint256 poolIdToServe = -1;
  //     uint256[] activePoolsIDs = getActivePoolsIDs();
  //     for (uint i; i < activePoolsIDs.length; i++) {
  //       if (pools[activePoolsIDs[i]].piecesCollected >= pools[activePoolsIDs[i]].piecesNeedToCollect) {
  //         poolIdToServe = activePoolsIDs[i];
  //         break;
  //       }
  //     }
  //     upkeepNeeded = ((block.timestamp - lastTimeStamp) > interval) && anyOfPoolsIsFull > -1;
  //     performData = string(abi.encodePacked('buy asset ', Strings.toString(poolIdToServe)));
  //   }

  //   return (upkeepNeeded, performData);
  // }

  // function performUpkeep(
  //   // I guess I can put custom performData, not like checkData
  //     bytes calldata performData
  // ) external override {
  //   if (keccak256(performData[:9]) == keccak256('buy asset')) {
  //     bytes poolIdBytes = performData[10:];
  //     uint256 poolId = bytesToUint(poolIdBytes);

  //     if ((block.timestamp - lastTimeStamp) > interval) && pools[poolId].piecesCollected >= pools[poolId].piecesNeedToCollect) {
  //       lastTimeStamp = block.timestamp;
  //       buyAsset(poolId);
  //     }
  //   }
  // }
}