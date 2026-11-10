// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryAddress} from "../src/RoundHistoryAddress.sol";
import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";

contract RoundHistoryAddressHarness {
    using RoundHistoryAddress for RoundHistoryAddress.History;

    RoundHistoryAddress.History private _history;

    function record(uint256 round, address newValue) external {
        _history.record(round, newValue);
    }

    function value(uint256 round) external view returns (address) {
        return _history.value(round);
    }

    function latestValue() external view returns (address) {
        return _history.latestValue();
    }
}

contract RoundHistoryAddressTest {
    address constant ADDR1 = address(0x1);
    address constant ADDR2 = address(0x2);
    address constant ADDR3 = address(0x3);

    function testRecord() external {
        RoundHistoryAddressHarness harness = new RoundHistoryAddressHarness();
        harness.record(1, ADDR1);
        require(harness.value(1) == ADDR1);
        require(harness.latestValue() == ADDR1);
    }

    function testRecordMultiple() external {
        RoundHistoryAddressHarness harness = new RoundHistoryAddressHarness();
        harness.record(1, ADDR1);
        harness.record(2, ADDR2);
        harness.record(5, ADDR3);

        require(harness.value(1) == ADDR1);
        require(harness.value(2) == ADDR2);
        require(harness.value(5) == ADDR3);
        require(harness.latestValue() == ADDR3);
    }

    function testValueAtNonRecordedRound() external {
        RoundHistoryAddressHarness harness = new RoundHistoryAddressHarness();
        harness.record(1, ADDR1);
        harness.record(5, ADDR2);

        require(harness.value(3) == ADDR1);
        require(harness.value(4) == ADDR1);
        require(harness.value(5) == ADDR2);
        require(harness.value(6) == ADDR2);
    }

    function testValueBeforeFirstRecord() external {
        RoundHistoryAddressHarness harness = new RoundHistoryAddressHarness();
        harness.record(5, ADDR1);
        require(harness.value(1) == address(0));
        require(harness.value(4) == address(0));
    }

    function testRevertInvalidRound() external {
        RoundHistoryAddressHarness harness = new RoundHistoryAddressHarness();
        harness.record(5, ADDR1);
        try harness.record(3, ADDR2) {
            revert("expected InvalidKeyOrder");
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            require(bytes4(reason) == OrderedHistoryIndex.InvalidKeyOrder.selector);
        }
    }

    function testRecordSameRoundTwice() external {
        RoundHistoryAddressHarness harness = new RoundHistoryAddressHarness();
        harness.record(1, ADDR1);
        harness.record(1, ADDR2);
        require(harness.value(1) == ADDR2);
    }

    function testEmptyHistory() external {
        RoundHistoryAddressHarness harness = new RoundHistoryAddressHarness();
        require(harness.latestValue() == address(0));
        require(harness.value(1) == address(0));
    }
}
