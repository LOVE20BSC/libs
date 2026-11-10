// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryUint256} from "../src/RoundHistoryUint256.sol";
import {IOrderedHistoryIndexErrors} from "../src/interfaces/IOrderedHistoryIndexErrors.sol";

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

    /// `decrease` is checked arithmetic, so subtracting past the value in force must revert rather
    /// than wrap. The branch had no coverage: only the happy path was exercised.
    function testDecreaseBelowCurrentValueReverts() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);

        (bool ok, bytes memory reason) =
            address(harness).call(abi.encodeWithSelector(harness.decrease.selector, uint256(1), uint256(101)));
        require(!ok, "decrease past zero must revert");
        _requireArithmeticPanic(reason);
    }

    /// `increase` can overflow on a long-lived history; that must surface as an arithmetic panic
    /// rather than silently wrapping the accumulator.
    function testIncreasePastMaximumReverts() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, type(uint256).max);

        (bool ok, bytes memory reason) =
            address(harness).call(abi.encodeWithSelector(harness.increase.selector, uint256(1), uint256(1)));
        require(!ok, "increase past the maximum must revert");
        _requireArithmeticPanic(reason);
    }

    function testRevertInvalidRound() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(5, 500);
        try harness.record(3, 300) {
            revert("expected InvalidKeyOrder");
        } catch (bytes memory reason) {
            // The whole payload is pinned, so swapped operands fail too: the expected error is
            // InvalidKeyOrder(3, 5).
            require(
                keccak256(reason)
                    == keccak256(
                        abi.encodeWithSelector(IOrderedHistoryIndexErrors.InvalidKeyOrder.selector, uint256(3), uint256(5))
                    )
            );
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

    /// The README documents that `increase`/`decrease` on an earlier round revert whether or not that
    /// round was recorded; pin the full payload for both directions.
    function testArithmeticHelpersOnEarlierRoundRevert() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, 100);
        harness.record(5, 100);

        (bool ok, bytes memory reason) =
            address(harness).call(abi.encodeWithSelector(harness.increase.selector, uint256(3), uint256(1)));
        require(!ok, "increase on an earlier round must revert");
        _requireInvalidKeyOrder(reason, 3, 5);

        (ok, reason) = address(harness).call(abi.encodeWithSelector(harness.decrease.selector, uint256(3), uint256(1)));
        require(!ok, "decrease on an earlier round must revert");
        _requireInvalidKeyOrder(reason, 3, 5);
    }

    /// Overflow through the *push* branch (a new round inheriting the maximum), not just the
    /// same-round overwrite covered above.
    function testIncreaseAtNewRoundInheritingMaximumReverts() external {
        RoundHistoryUint256Harness harness = new RoundHistoryUint256Harness();
        harness.record(1, type(uint256).max);

        (bool ok, bytes memory reason) =
            address(harness).call(abi.encodeWithSelector(harness.increase.selector, uint256(2), uint256(1)));
        require(!ok, "increase past the maximum at a new round must revert");
        _requireArithmeticPanic(reason);
    }

    /// Decodes the `Panic(uint256)` payload and asserts the code, not only the selector: a
    /// selector-only check would also accept `Panic(0x01)` from an `assert`.
    function _requireArithmeticPanic(bytes memory reason) private pure {
        require(reason.length == 4 + 32, "expected Panic(uint256)");
        // forge-lint: disable-next-line(unsafe-typecast)
        require(bytes4(reason) == bytes4(0x4e487b71), "not a Panic");
        require(abi.decode(_payload(reason), (uint256)) == 0x11, "not an arithmetic panic");
    }

    /// Asserts the full `InvalidKeyOrder` payload so swapped operands fail too.
    function _requireInvalidKeyOrder(bytes memory reason, uint256 expectedKey, uint256 expectedLastKey) private pure {
        require(
            keccak256(reason)
                == keccak256(
                    abi.encodeWithSelector(IOrderedHistoryIndexErrors.InvalidKeyOrder.selector, expectedKey, expectedLastKey)
                ),
            "unexpected revert payload"
        );
    }

    /// Strips the four-byte selector so the arguments can be `abi.decode`d.
    function _payload(bytes memory reason) private pure returns (bytes memory args) {
        args = new bytes(reason.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = reason[i + 4];
        }
    }
}
