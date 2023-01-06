// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract ActivePools {
    struct ActivePool {
        uint256 next;
        uint256 prev;
    }

    uint256 nextNodeID = 1;
    mapping(uint256 => ActivePool) internal activePools;
    uint256 private head;
    uint256 private tail;
    uint256 private count = 0;

    function append() internal {
        if (tail == 0) {
            head = nextNodeID;
            tail = nextNodeID;
        } else {
            activePools[tail].next = nextNodeID;
            activePools[nextNodeID].prev = tail;
            tail = nextNodeID;
        }

        nextNodeID += 1;
        count += 1;
    }

    function validNode(uint256 nodeID) internal view returns (bool) {
        return nodeID == head || activePools[nodeID].prev != 0;
    }

    function remove(uint256 nodeID) internal {
        require(validNode(nodeID));

        ActivePool storage activePool = activePools[nodeID];

        // Update head and tail.
        if (tail == nodeID) {
            tail = activePools[nodeID].prev;
        }
        if (head == nodeID) {
            head = activePools[nodeID].next;
        }

        // Update previous node's next pointer.
        if (activePool.prev != 0) {
            activePools[activePool.prev].next = activePool.next;
        }

        // Update next node's previous pointer.
        if (activePool.next != 0) {
            activePools[activePool.next].prev = activePool.prev;
        }

        // Reclaim storage for the removed node.
        delete activePools[nodeID];

        count -= 1;
    }

    function getActivePoolsIDs() public view returns (uint256[] memory ids) {
        ids = new uint256[](count);

        uint256 current = head;
        for (uint256 i = 0; i < count; i++) {
            ids[i] = current;
            current = activePools[current].next;
        }
    }
}