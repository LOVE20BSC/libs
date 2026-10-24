// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryStringArray} from "../src/RoundHistoryStringArray.sol";
import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";

contract RoundHistoryStringArrayHarness {
    using RoundHistoryStringArray for RoundHistoryStringArray.History;

    RoundHistoryStringArray.History private _history;

    function record(uint256 round, string[] memory newValues) external {
        _history.record(round, newValues);
    }

    function values(uint256 round) external view returns (string[] memory) {
        return _history.values(round);
    }

    function latestValues() external view returns (string[] memory) {
        return _history.latestValues();
    }
}

contract RoundHistoryStringArrayTest {
    function _one(string memory a) private pure returns (string[] memory out) {
        out = new string[](1);
        out[0] = a;
    }

    function _pair(string memory a, string memory b) private pure returns (string[] memory out) {
        out = new string[](2);
        out[0] = a;
        out[1] = b;
    }

    function _empty() private pure returns (string[] memory) {
        return new string[](0);
    }

    function _assertValues(string[] memory actual, string[] memory expected) private pure {
        require(keccak256(abi.encode(actual)) == keccak256(abi.encode(expected)));
    }

    function testRecord() external {
        RoundHistoryStringArrayHarness harness = new RoundHistoryStringArrayHarness();
        harness.record(1, _pair("a", "b"));
        _assertValues(harness.values(1), _pair("a", "b"));
        _assertValues(harness.latestValues(), _pair("a", "b"));
    }

    function testValuesAtNonRecordedRoundInheritsNearest() external {
        RoundHistoryStringArrayHarness harness = new RoundHistoryStringArrayHarness();
        harness.record(1, _one("first"));
        harness.record(5, _pair("second", "third"));

        _assertValues(harness.values(3), _one("first"));
        _assertValues(harness.values(5), _pair("second", "third"));
        _assertValues(harness.values(6), _pair("second", "third"));
        _assertValues(harness.latestValues(), _pair("second", "third"));
    }

    function testValuesBeforeFirstRecordAreEmpty() external {
        RoundHistoryStringArrayHarness harness = new RoundHistoryStringArrayHarness();
        harness.record(5, _one("data"));

        _assertValues(harness.values(1), _empty());
        _assertValues(harness.values(4), _empty());
    }

    function testEmptyRecordClearsAndInherits() external {
        RoundHistoryStringArrayHarness harness = new RoundHistoryStringArrayHarness();
        harness.record(1, _one("kept"));
        harness.record(2, _empty());

        _assertValues(harness.values(2), _empty());
        _assertValues(harness.values(3), _empty());
        _assertValues(harness.latestValues(), _empty());
    }

    function testRecordSameRoundTwiceOverwrites() external {
        RoundHistoryStringArrayHarness harness = new RoundHistoryStringArrayHarness();
        harness.record(1, _one("old"));
        harness.record(1, _pair("new", "extra"));
        _assertValues(harness.values(1), _pair("new", "extra"));
    }

    function testRevertKeyOrderPanic() external {
        RoundHistoryStringArrayHarness harness = new RoundHistoryStringArrayHarness();
        harness.record(5, _one("data"));
        try harness.record(3, _one("error")) {
            revert("expected key order panic");
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            require(bytes4(reason) == bytes4(0x4e487b71));
        }
    }

    function testEmptyHistory() external {
        RoundHistoryStringArrayHarness harness = new RoundHistoryStringArrayHarness();
        _assertValues(harness.values(1), _empty());
        _assertValues(harness.latestValues(), _empty());
    }
}
