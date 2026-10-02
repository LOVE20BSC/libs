// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryUint256} from "./RoundHistoryUint256.sol";
import {Pagination} from "./Pagination.sol";

/**
 * @title RoundHistoryUint256Set
 * @notice Deduplicated uint256 set with per-round snapshots; replaces the legacy
 *         `RoundHistoryAddressSet`, with `uint256` elements instead of `address`.
 * @dev Three histories are kept: the set size, `slot -> element`, and `element -> slot + 1`
 *      (`0` meaning "absent"). The current state is derived from their `latestValue()`, so no
 *      second copy exists that could drift away from the history.
 *      Writes require a non-decreasing `round` (inherited from `RoundHistoryUint256` ->
 *      `OrderedHistoryIndex`); re-recording the same round overwrites that round's entry.
 *      Ordering: removal is swap-and-pop, so the same `offset` is not stable across calls;
 *      `reverse` only means "walk the current storage order backwards".
 *      Enumeration has exactly one complete path (pagination). `contains` / `count` read the
 *      latest recorded value in O(1); `containsByRound` / `countByRound` are point queries as
 *      well (an exact round hit is O(1), otherwise `nearest()` binary-searches the recorded
 *      rounds, i.e. O(log rounds)). None of them is a second enumeration path.
 */
library RoundHistoryUint256Set {
    using RoundHistoryUint256 for RoundHistoryUint256.History;

    struct Storage {
        RoundHistoryUint256.History countHistory;
        mapping(uint256 => RoundHistoryUint256.History) slotHistory;
        mapping(uint256 => RoundHistoryUint256.History) indexPlusOneHistory;
    }

    /**
     * @notice Insert an element; a no-op if already present
     */
    function add(Storage storage self, uint256 round, uint256 value) internal {
        if (self.indexPlusOneHistory[value].latestValue() != 0) return;

        uint256 index = self.countHistory.latestValue();
        self.slotHistory[index].record(round, value);
        self.indexPlusOneHistory[value].record(round, index + 1);
        self.countHistory.record(round, index + 1);
    }

    /**
     * @notice Swap-and-pop removal; a no-op (no state change, no revert) if absent
     * @dev Invariant: whenever `indexPlusOneHistory[v].latestValue() != 0` that value lies in
     *      `1..count()`, i.e. an element marked present always points at an occupied slot.
     *      `add` / `remove` are the only writers and both preserve it, hence
     *      `indexPlusOne != 0 => countHistory.latestValue() >= 1`, so the
     *      `countHistory.latestValue() - 1` below cannot underflow (pinned by a state-machine test).
     */
    function remove(Storage storage self, uint256 round, uint256 value) internal {
        uint256 indexPlusOne = self.indexPlusOneHistory[value].latestValue();
        if (indexPlusOne == 0) return;

        uint256 removedIndex = indexPlusOne - 1;
        uint256 lastIndex = self.countHistory.latestValue() - 1;
        if (removedIndex != lastIndex) {
            uint256 lastValue = self.slotHistory[lastIndex].latestValue();
            self.slotHistory[removedIndex].record(round, lastValue);
            self.indexPlusOneHistory[lastValue].record(round, removedIndex + 1);
        }
        self.slotHistory[lastIndex].record(round, 0);
        self.countHistory.record(round, lastIndex);
        self.indexPlusOneHistory[value].record(round, 0);
    }

    /**
     * @notice Whether the element is currently in the set, decided by the latest value of
     *         `indexPlusOneHistory` (O(1))
     */
    function contains(Storage storage self, uint256 value) internal view returns (bool) {
        return self.indexPlusOneHistory[value].latestValue() != 0;
    }

    /**
     * @notice Current size of the set, decided by the latest value of `countHistory` (O(1))
     */
    function count(Storage storage self) internal view returns (uint256) {
        return self.countHistory.latestValue();
    }

    /**
     * @notice Paginated read of the current set; out of range returns an empty page with the real
     *         total and does not revert; `limit = 0` returns the total only
     */
    function values(Storage storage self, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory page, uint256 total)
    {
        total = self.countHistory.latestValue();
        uint256[] memory slots = Pagination.paginateIndices(total, offset, limit, reverse);
        page = new uint256[](slots.length);
        for (uint256 i = 0; i < slots.length; i++) {
            page[i] = self.slotHistory[slots[i]].latestValue();
        }
    }

    /**
     * @notice Whether the element was in the set as of `round`; `false` before the first write
     */
    function containsByRound(Storage storage self, uint256 value, uint256 round) internal view returns (bool) {
        return self.indexPlusOneHistory[value].value(round) != 0;
    }

    /**
     * @notice Size of the set as of `round`; `0` before the first write
     */
    function countByRound(Storage storage self, uint256 round) internal view returns (uint256) {
        return self.countHistory.value(round);
    }

    /**
     * @notice Paginated read of the set as of `round`; out of range returns an empty page with the
     *         real total and does not revert; `limit = 0` returns the total only
     */
    function valuesByRound(Storage storage self, uint256 round, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory page, uint256 total)
    {
        total = self.countHistory.value(round);
        uint256[] memory slots = Pagination.paginateIndices(total, offset, limit, reverse);
        page = new uint256[](slots.length);
        for (uint256 i = 0; i < slots.length; i++) {
            page[i] = self.slotHistory[slots[i]].value(round);
        }
    }
}
