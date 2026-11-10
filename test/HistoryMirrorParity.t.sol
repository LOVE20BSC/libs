// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryUint256} from "../src/RoundHistoryUint256.sol";
import {RoundHistoryString} from "../src/RoundHistoryString.sol";
import {RoundHistoryAddress} from "../src/RoundHistoryAddress.sol";
import {RoundHistoryUint256Array} from "../src/RoundHistoryUint256Array.sol";
import {RoundHistoryStringArray} from "../src/RoundHistoryStringArray.sol";

// The five scalar and array histories repeat the same record / exact-hit / nearest / latest
// skeleton and differ only in element type and default value. Their suites are independent, so a
// one-sided change to that skeleton can land green. This gate runs the same sequence through all
// five and compares a normalized token after every write, at the written round and on both sides
// of it. `0` is the common default (`0`, `address(0)`, `""`, empty array); arrays record `[token]`,
// with token 0 recorded as an empty array.

interface IHistoryProbe {
    function record(uint256 round, uint256 token) external;
    function latestToken() external view returns (uint256);
    function tokenAt(uint256 round) external view returns (uint256);
}

contract Uint256HistoryProbe is IHistoryProbe {
    using RoundHistoryUint256 for RoundHistoryUint256.History;

    RoundHistoryUint256.History private _history;

    function record(uint256 round, uint256 token) external override {
        _history.record(round, token);
    }

    function latestToken() external view override returns (uint256) {
        return _history.latestValue();
    }

    function tokenAt(uint256 round) external view override returns (uint256) {
        return _history.value(round);
    }
}

contract StringHistoryProbe is IHistoryProbe {
    using RoundHistoryString for RoundHistoryString.History;

    RoundHistoryString.History private _history;

    function record(uint256 round, uint256 token) external override {
        _history.record(round, _encode(token));
    }

    function latestToken() external view override returns (uint256) {
        return _decode(_history.latestValue());
    }

    function tokenAt(uint256 round) external view override returns (uint256) {
        return _decode(_history.value(round));
    }

    function _encode(uint256 token) private pure returns (string memory) {
        require(token < 10, "token out of string domain");
        return string(abi.encodePacked(bytes1(uint8(48 + token))));
    }

    function _decode(string memory value) private pure returns (uint256) {
        bytes memory raw = bytes(value);
        if (raw.length == 0) return 0;
        require(raw.length == 1, "unexpected string length");
        return uint8(raw[0]) - 48;
    }
}

contract AddressHistoryProbe is IHistoryProbe {
    using RoundHistoryAddress for RoundHistoryAddress.History;

    RoundHistoryAddress.History private _history;

    function record(uint256 round, uint256 token) external override {
        _history.record(round, address(uint160(token)));
    }

    function latestToken() external view override returns (uint256) {
        return uint256(uint160(_history.latestValue()));
    }

    function tokenAt(uint256 round) external view override returns (uint256) {
        return uint256(uint160(_history.value(round)));
    }
}

contract Uint256ArrayHistoryProbe is IHistoryProbe {
    using RoundHistoryUint256Array for RoundHistoryUint256Array.History;

    RoundHistoryUint256Array.History private _history;

    function record(uint256 round, uint256 token) external override {
        uint256[] memory values;
        if (token == 0) {
            values = new uint256[](0);
        } else {
            values = new uint256[](1);
            values[0] = token;
        }
        _history.record(round, values);
    }

    function latestToken() external view override returns (uint256) {
        return _normalize(_history.latestValues());
    }

    function tokenAt(uint256 round) external view override returns (uint256) {
        return _normalize(_history.values(round));
    }

    function _normalize(uint256[] memory values) private pure returns (uint256) {
        if (values.length == 0) return 0;
        require(values.length == 1, "unexpected array length");
        return values[0];
    }
}

contract StringArrayHistoryProbe is IHistoryProbe {
    using RoundHistoryStringArray for RoundHistoryStringArray.History;

    RoundHistoryStringArray.History private _history;

    function record(uint256 round, uint256 token) external override {
        string[] memory values;
        if (token == 0) {
            values = new string[](0);
        } else {
            values = new string[](1);
            values[0] = _encode(token);
        }
        _history.record(round, values);
    }

    function latestToken() external view override returns (uint256) {
        return _normalize(_history.latestValues());
    }

    function tokenAt(uint256 round) external view override returns (uint256) {
        return _normalize(_history.values(round));
    }

    function _encode(uint256 token) private pure returns (string memory) {
        require(token < 10, "token out of string domain");
        return string(abi.encodePacked(bytes1(uint8(48 + token))));
    }

    function _normalize(string[] memory values) private pure returns (uint256) {
        if (values.length == 0) return 0;
        require(values.length == 1, "unexpected string array length");
        bytes memory raw = bytes(values[0]);
        if (raw.length == 0) return 0;
        require(raw.length == 1, "unexpected string length");
        return uint8(raw[0]) - 48;
    }
}

contract HistoryMirrorParityTest {
    /// Tokens fit one decimal digit, so the string histories can encode them without a parser.
    uint256 private constant DOMAIN = 8;
    uint256 private constant HISTORIES = 5;

    function testScriptedSequenceStaysInStep() external {
        IHistoryProbe[] memory histories = _fresh();
        _assertInStep(histories, 0);

        // Recording the same round twice keeps only the final value, in every type.
        _recordAll(histories, 1, 3);
        _assertInStep(histories, 1);
        _recordAll(histories, 1, 5);
        _assertInStep(histories, 1);

        // A recorded default (scalar 0 / empty array) is still a record that later rounds inherit.
        _recordAll(histories, 2, 0);
        _assertInStep(histories, 2);

        // Exact hits and the nearest-earlier fallback across a gap.
        _recordAll(histories, 4, 7);
        _assertInStep(histories, 4);
        _recordAll(histories, 4, 6);
        _assertInStep(histories, 4);

        // Round 1 keeps the first value even after the later writes, in every type.
        _assertRound(histories, 0, 0);
        _assertRound(histories, 1, 5);
        _assertRound(histories, 2, 0);
        _assertRound(histories, 3, 0);
        _assertRound(histories, 4, 6);
        _assertRound(histories, 5, 6);
        _assertLatest(histories, 6);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_OperationsStayInStep(uint256 seed) external {
        IHistoryProbe[] memory histories = _fresh();
        uint256 round = 0;

        for (uint256 i = 0; i < 24; i++) {
            uint256 rng = uint256(keccak256(abi.encode(seed, i)));
            round += rng % 3; // non-decreasing, sometimes repeated
            uint256 token = uint256(keccak256(abi.encode(seed, i, "token"))) % DOMAIN;
            _recordAll(histories, round, token);
            _assertInStep(histories, round);
        }
    }

    function _fresh() private returns (IHistoryProbe[] memory histories) {
        histories = new IHistoryProbe[](HISTORIES);
        histories[0] = new Uint256HistoryProbe();
        histories[1] = new StringHistoryProbe();
        histories[2] = new AddressHistoryProbe();
        histories[3] = new Uint256ArrayHistoryProbe();
        histories[4] = new StringArrayHistoryProbe();
        _assertInStep(histories, 0);
    }

    function _recordAll(IHistoryProbe[] memory histories, uint256 round, uint256 token) private {
        for (uint256 i = 0; i < histories.length; i++) {
            histories[i].record(round, token);
        }
    }

    /// Compares every history against the first one at the current round, the round before it, the
    /// round after it, and round 0. Exact hits, gap fallbacks and future inheritance are all covered.
    function _assertInStep(IHistoryProbe[] memory histories, uint256 round) private view {
        uint256 latest = histories[0].latestToken();
        uint256 current = histories[0].tokenAt(round);
        uint256 previous = round == 0 ? 0 : histories[0].tokenAt(round - 1);
        uint256 future = histories[0].tokenAt(round + 1);
        uint256 first = histories[0].tokenAt(0);

        for (uint256 i = 1; i < histories.length; i++) {
            require(histories[i].latestToken() == latest, "latestToken diverged");
            require(histories[i].tokenAt(round) == current, "tokenAt(current) diverged");
            require(histories[i].tokenAt(round + 1) == future, "tokenAt(future) diverged");
            require(histories[i].tokenAt(0) == first, "tokenAt(first) diverged");
            if (round != 0) {
                require(histories[i].tokenAt(round - 1) == previous, "tokenAt(previous) diverged");
            }
        }
    }

    function _assertRound(IHistoryProbe[] memory histories, uint256 round, uint256 expected) private view {
        for (uint256 i = 0; i < histories.length; i++) {
            require(histories[i].tokenAt(round) == expected, "round token diverged");
        }
    }

    function _assertLatest(IHistoryProbe[] memory histories, uint256 expected) private view {
        for (uint256 i = 0; i < histories.length; i++) {
            require(histories[i].latestToken() == expected, "latest token diverged");
        }
    }
}
