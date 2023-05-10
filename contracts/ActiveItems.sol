// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract ActiveItems {
    struct ActiveItem {
        uint256 next;
        uint256 prev;
    }

    uint256 nextNodeID = 1;
    mapping(uint256 => ActiveItem) internal activeItems;
    uint256 private head;
    uint256 private tail;
    uint256 private count = 0;

    function append() internal {
        if (tail == 0) {
            head = nextNodeID;
            tail = nextNodeID;
        } else {
            activeItems[tail].next = nextNodeID;
            activeItems[nextNodeID].prev = tail;
            tail = nextNodeID;
        }

        nextNodeID += 1;
        count += 1;
    }

    function validNode(uint256 nodeID) internal view returns (bool) {
        return nodeID == head || activeItems[nodeID].prev != 0;
    }

    function remove(uint256 nodeID) internal {
        require(validNode(nodeID));

        ActiveItem storage activePool = activeItems[nodeID];

        // Update head and tail.
        if (tail == nodeID) {
            tail = activeItems[nodeID].prev;
        }
        if (head == nodeID) {
            head = activeItems[nodeID].next;
        }

        // Update previous node's next pointer.
        if (activePool.prev != 0) {
            activeItems[activePool.prev].next = activePool.next;
        }

        // Update next node's previous pointer.
        if (activePool.next != 0) {
            activeItems[activePool.next].prev = activePool.prev;
        }

        // Reclaim storage for the removed node.
        delete activeItems[nodeID];

        count -= 1;
    }

    function getActiveItemsIDs() public view returns (uint256[] memory ids) {
        ids = new uint256[](count);

        uint256 current = head;
        for (uint256 i = 0; i < count; i++) {
            ids[i] = current;
            current = activeItems[current].next;
        }
    }
}