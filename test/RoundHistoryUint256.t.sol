// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryUint256} from "../src/RoundHistoryUint256.sol";
import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";

contract RoundHistoryUint256Harness {
    using RoundHistoryUint256 for RoundHistoryUint256.History;

    RoundHistoryUint256.History private _history;

    function record(uint256 round, uint256 newValue) external {
        _history.record(round, newValue);
    }

    function value(uint256 round) external view returns (uint256) {
        return _history.value(round);
    }

    function latestValue() external view returns (uint256) {
        return _history.latestValue();
    }

    function increase(uint256 round, uint256 increaseValue) external {
        _history.increase(round, increaseValue);
    }

    function decrease(uint256 round, uint256 decreaseValue) external {
        _history.decrease(round, decreaseValue);
    }
}

contract RoundHistoryUint256Test {
    function testRecord() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);
        require(harness.value(1) == 100);
        require(harness.latestValue() == 100);
    }

    function testRecordMultiple() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);
        harness.record(2, 200);
        harness.record(5, 500);

        require(harness.value(1) == 100);
        require(harness.value(2) == 200);
        require(harness.value(5) == 500);
        require(harness.latestValue() == 500);
    }

    function testValueAtNonRecordedRound() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);
        harness.record(5, 500);

        require(harness.value(3) == 100);
        require(harness.value(4) == 100);
        require(harness.value(5) == 500);
        require(harness.value(6) == 500);
    }

    function testValueBeforeFirstRecord() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(5, 500);
        require(harness.value(1) == 0);
        require(harness.value(4) == 0);
    }

    function testIncrease() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);
        harness.increase(2, 50);

        require(harness.value(1) == 100);
        require(harness.value(2) == 150);
    }

    function testDecrease() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);
        harness.decrease(2, 30);

        require(harness.value(1) == 100);
        require(harness.value(2) == 70);
    }

    function testRevertInvalidRound() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(5, 500);
        try harness.record(3, 300) {
            revert("expected InvalidKeyOrder");
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            require(bytes4(reason) == OrderedHistoryIndex.InvalidKeyOrder.selector);
        }
    }

    function testRecordSameRoundTwice() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);
        harness.record(1, 200);
        require(harness.value(1) == 200);
    }

    function testEmptyHistory() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        require(harness.latestValue() == 0);
        require(harness.value(1) == 0);
    }
}
