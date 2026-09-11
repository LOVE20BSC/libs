// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";

contract OrderedHistoryIndexHarness {
    using OrderedHistoryIndex for OrderedHistoryIndex.Index;

    OrderedHistoryIndex.Index private _index;

    function recordKey(uint256 key) external { _index.record(key); }
    function contains(uint256 key) external view returns (bool) { return _index.contains(key); }
    function nearest(uint256 key) external view returns (bool, uint256) { return _index.nearest(key); }
    function latest() external view returns (bool, uint256) { return _index.latest(); }
    function length() external view returns (uint256) { return _index.keys.length; }
}

contract OrderedHistoryIndexTest {
    function testEmpty() external {
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        require(!harness.contains(1));
        (bool found, uint256 key) = harness.nearest(1);
        require(!found && key == 0);
        (found, key) = harness.latest();
        require(!found && key == 0);
    }

    function testNearestBoundaries() external {
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        harness.recordKey(10);
        harness.recordKey(20);
        harness.recordKey(40);
        require(harness.contains(10) && harness.contains(20) && !harness.contains(30));
        (bool found, uint256 key) = harness.nearest(9);
        require(!found && key == 0);
        (found, key) = harness.nearest(10);
        require(found && key == 10);
        (found, key) = harness.nearest(39);
        require(found && key == 20);
        (found, key) = harness.nearest(40);
        require(found && key == 40);
        (found, key) = harness.nearest(type(uint256).max);
        require(found && key == 40);
    }

    function testDuplicateLatestAndOutOfOrder() external {
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        harness.recordKey(10);
        harness.recordKey(20);
        harness.recordKey(20);
        require(harness.length() == 2);

        try harness.recordKey(15) {
            revert("expected InvalidKeyOrder");
        } catch (bytes memory reason) {
            require(bytes4(reason) == OrderedHistoryIndex.InvalidKeyOrder.selector);
        }
        require(harness.length() == 2);
    }

    function testBinarySearchLongIndex() external {
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        for (uint256 i = 1; i <= 64; ++i) harness.recordKey(i * 10);
        require(harness.length() == 64);
        (bool found, uint256 key) = harness.nearest(1);
        require(!found && key == 0);
        (found, key) = harness.nearest(635);
        require(found && key == 630);
        (found, key) = harness.nearest(640);
        require(found && key == 640);
    }

    function testZeroAndMaxKeys() external {
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        harness.recordKey(0);
        harness.recordKey(type(uint256).max);
        (bool found, uint256 key) = harness.nearest(0);
        require(found && key == 0);
        (found, key) = harness.nearest(type(uint256).max - 1);
        require(found && key == 0);
    }
}
