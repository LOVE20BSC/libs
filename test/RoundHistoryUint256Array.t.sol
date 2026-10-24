// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryUint256Array} from "../src/RoundHistoryUint256Array.sol";
import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";

contract RoundHistoryUint256ArrayHarness {
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;

    RoundHistoryUint256Array.History private _history;

    function record(uint256 round, uint256[] memory newValues) external {
        _history.record(round, newValues);
    }

    function values(uint256 round) external view returns (uint256[] memory) {
        return _history.values(round);
    }

    function latestValues() external view returns (uint256[] memory) {
        return _history.latestValues();
    }
}

contract RoundHistoryUint256ArrayTest {
    function _single(uint256 a) private pure returns (uint256[] memory out) {
        out = new uint256[](1);
        out[0] = a;
    }

    function _pair(uint256 a, uint256 b) private pure returns (uint256[] memory out) {
        out = new uint256[](2);
        out[0] = a;
        out[1] = b;
    }

    function _empty() private pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function _assertValues(uint256[] memory actual, uint256[] memory expected) private pure {
        require(keccak256(abi.encode(actual)) == keccak256(abi.encode(expected)));
    }

    function testRecord() external {
        RoundHistoryUint256ArrayHarness harness = new RoundHistoryUint256ArrayHarness();
        harness.record(1, _pair(1, 2));
        _assertValues(harness.values(1), _pair(1, 2));
        _assertValues(harness.latestValues(), _pair(1, 2));
    }

    function testValuesAtNonRecordedRoundInheritsNearest() external {
        RoundHistoryUint256ArrayHarness harness = new RoundHistoryUint256ArrayHarness();
        harness.record(1, _single(7));
        harness.record(5, _pair(8, 9));

        _assertValues(harness.values(3), _single(7));
        _assertValues(harness.values(5), _pair(8, 9));
        _assertValues(harness.values(6), _pair(8, 9));
        _assertValues(harness.latestValues(), _pair(8, 9));
    }

    function testValuesBeforeFirstRecordAreEmpty() external {
        RoundHistoryUint256ArrayHarness harness = new RoundHistoryUint256ArrayHarness();
        harness.record(5, _pair(1, 2));

        _assertValues(harness.values(1), _empty());
        _assertValues(harness.values(4), _empty());
    }

    function testEmptyRecordClearsAndInherits() external {
        RoundHistoryUint256ArrayHarness harness = new RoundHistoryUint256ArrayHarness();
        harness.record(1, _pair(1, 2));
        harness.record(2, _empty());

        _assertValues(harness.values(2), _empty());
        _assertValues(harness.values(3), _empty());
        _assertValues(harness.latestValues(), _empty());
    }

    function testRecordSameRoundTwiceOverwrites() external {
        RoundHistoryUint256ArrayHarness harness = new RoundHistoryUint256ArrayHarness();
        harness.record(1, _single(1));
        harness.record(1, _pair(2, 3));
        _assertValues(harness.values(1), _pair(2, 3));
    }

    function testRevertKeyOrderPanic() external {
        RoundHistoryUint256ArrayHarness harness = new RoundHistoryUint256ArrayHarness();
        harness.record(5, _single(1));
        try harness.record(3, _single(2)) {
            revert("expected key order panic");
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            require(bytes4(reason) == bytes4(0x4e487b71));
        }
    }

    function testEmptyHistory() external {
        RoundHistoryUint256ArrayHarness harness = new RoundHistoryUint256ArrayHarness();
        _assertValues(harness.values(1), _empty());
        _assertValues(harness.latestValues(), _empty());
    }
}
