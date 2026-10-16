// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryUint256} from "./RoundHistoryUint256.sol";
import {Pagination} from "./Pagination.sol";

library RoundHistoryUint256Set {
    using RoundHistoryUint256 for RoundHistoryUint256.History;

    struct Storage {
        RoundHistoryUint256.History countHistory;
        // slot => element history
        mapping(uint256 => RoundHistoryUint256.History) slotHistory;
        // element => slot + 1 history; 0 means absent
        mapping(uint256 => RoundHistoryUint256.History) indexPlusOneHistory;
    }

    function add(Storage storage self, uint256 round, uint256 value) internal {
        if (self.indexPlusOneHistory[value].latestValue() != 0) return;

        uint256 index = self.countHistory.latestValue();
        self.slotHistory[index].record(round, value);
        self.indexPlusOneHistory[value].record(round, index + 1);
        self.countHistory.record(round, index + 1);
    }

    // Load-bearing: an element whose `indexPlusOneHistory` is non-zero must sit below
    // `countHistory`. `slotHistory` is a mapping, so a broken pairing is not caught by a bounds
    // check: `remove` would write past the last slot and shrink the count, silently dropping a
    // different element from the set instead of reverting.
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

    function contains(Storage storage self, uint256 value) internal view returns (bool) {
        return self.indexPlusOneHistory[value].latestValue() != 0;
    }

    function count(Storage storage self) internal view returns (uint256) {
        return self.countHistory.latestValue();
    }

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

    function containsByRound(Storage storage self, uint256 value, uint256 round) internal view returns (bool) {
        return self.indexPlusOneHistory[value].value(round) != 0;
    }

    function countByRound(Storage storage self, uint256 round) internal view returns (uint256) {
        return self.countHistory.value(round);
    }

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
