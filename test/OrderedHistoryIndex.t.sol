// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";
import {IOrderedHistoryIndexErrors} from "../src/interfaces/IOrderedHistoryIndexErrors.sol";

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
            // The whole payload is pinned, so swapped operands fail too: the expected error is
            // InvalidKeyOrder(15, 20).
            require(
                keccak256(reason)
                    == keccak256(
                        abi.encodeWithSelector(IOrderedHistoryIndexErrors.InvalidKeyOrder.selector, uint256(15), uint256(20))
                    )
            );
        }
        require(harness.length() == 2);
    }

    function testBinarySearchLongIndex() external {
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        // The loop intentionally exercises a long ordered index through the external harness.
        // forge-lint: disable-next-line(calls-loop)
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

    /// The binary search's equality branch is only reached by an exact *interior* key: every other
    /// assertion above exercises the two fast paths or a between-keys target.
    function testNearestInteriorExactKey() external {
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        harness.recordKey(10);
        harness.recordKey(20);
        harness.recordKey(40);

        (bool found, uint256 key) = harness.nearest(20);
        require(found && key == 20);
        (found, key) = harness.nearest(30);
        require(found && key == 20);
    }

    /// Differential fuzz of the hand-rolled binary search against a linear scan over a generated,
    /// strictly increasing key list — exact, between-keys, below-first and above-last targets.
    function testFuzz_NearestMatchesLinearScan(uint256 seed, uint8 rawCount, uint256 target) external {
        uint256 count = (uint256(rawCount) % 40) + 1;
        OrderedHistoryIndexHarness harness = new OrderedHistoryIndexHarness();
        uint256[] memory keys = new uint256[](count);
        uint256 rng = seed;
        uint256 key = 0;
        for (uint256 i = 0; i < count; i++) {
            rng = uint256(keccak256(abi.encodePacked(rng)));
            key += (rng % 97) + 1;
            keys[i] = key;
            harness.recordKey(key);
        }
        require(harness.length() == count);

        (bool found, uint256 nearestKey) = harness.nearest(target);
        bool expectedFound = false;
        uint256 expectedKey = 0;
        for (uint256 i = 0; i < count; i++) {
            if (keys[i] <= target) {
                expectedFound = true;
                expectedKey = keys[i];
            }
        }
        require(found == expectedFound, "found flag diverged from the linear scan");
        require(nearestKey == expectedKey, "nearest key diverged from the linear scan");

        (bool latestFound, uint256 latestKey) = harness.latest();
        require(latestFound && latestKey == keys[count - 1], "latest diverged");
        require(harness.contains(keys[count - 1]), "latest key not contained");
    }
}
