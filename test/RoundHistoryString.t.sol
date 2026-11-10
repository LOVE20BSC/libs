// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryString} from "../src/RoundHistoryString.sol";
import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";

contract RoundHistoryStringHarness {
    using RoundHistoryString for RoundHistoryString.History;

    RoundHistoryString.History private _history;

    function record(uint256 round, string memory newValue) external {
        _history.record(round, newValue);
    }

    function value(uint256 round) external view returns (string memory) {
        return _history.value(round);
    }

    function latestValue() external view returns (string memory) {
        return _history.latestValue();
    }
}

contract RoundHistoryStringTest {
    function testRecord() external {
        RoundHistoryStringHarness harness = new RoundHistoryStringHarness();
        harness.record(1, "hello");
        require(keccak256(bytes(harness.value(1))) == keccak256(bytes("hello")));
        require(keccak256(bytes(harness.latestValue())) == keccak256(bytes("hello")));
    }

    function testRecordMultiple() external {
        RoundHistoryStringHarness harness = new RoundHistoryStringHarness();
        harness.record(1, "first");
        harness.record(2, "second");
        harness.record(5, "fifth");

        require(keccak256(bytes(harness.value(1))) == keccak256(bytes("first")));
        require(keccak256(bytes(harness.value(2))) == keccak256(bytes("second")));
        require(keccak256(bytes(harness.value(5))) == keccak256(bytes("fifth")));
        require(keccak256(bytes(harness.latestValue())) == keccak256(bytes("fifth")));
    }

    function testValueAtNonRecordedRound() external {
        RoundHistoryStringHarness harness = new RoundHistoryStringHarness();
        harness.record(1, "alpha");
        harness.record(5, "beta");

        require(keccak256(bytes(harness.value(3))) == keccak256(bytes("alpha")));
        require(keccak256(bytes(harness.value(4))) == keccak256(bytes("alpha")));
        require(keccak256(bytes(harness.value(5))) == keccak256(bytes("beta")));
        require(keccak256(bytes(harness.value(6))) == keccak256(bytes("beta")));
    }

    function testValueBeforeFirstRecord() external {
        RoundHistoryStringHarness harness = new RoundHistoryStringHarness();
        harness.record(5, "data");
        require(keccak256(bytes(harness.value(1))) == keccak256(bytes("")));
        require(keccak256(bytes(harness.value(4))) == keccak256(bytes("")));
    }

    function testRevertInvalidRound() external {
        RoundHistoryStringHarness harness = new RoundHistoryStringHarness();
        harness.record(5, "data");
        try harness.record(3, "error") {
            revert("expected InvalidKeyOrder");
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            require(bytes4(reason) == OrderedHistoryIndex.InvalidKeyOrder.selector);
        }
    }

    function testRecordSameRoundTwice() external {
        RoundHistoryStringHarness harness = new RoundHistoryStringHarness();
        harness.record(1, "old");
        harness.record(1, "new");
        require(keccak256(bytes(harness.value(1))) == keccak256(bytes("new")));
    }

    function testEmptyHistory() external {
        RoundHistoryStringHarness harness = new RoundHistoryStringHarness();
        require(keccak256(bytes(harness.latestValue())) == keccak256(bytes("")));
        require(keccak256(bytes(harness.value(1))) == keccak256(bytes("")));
    }
}
