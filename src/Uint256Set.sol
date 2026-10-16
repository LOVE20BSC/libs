// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Pagination} from "./Pagination.sol";

/**
 * @title Uint256Set
 * @notice Unbounded deduplicated set of uint256: appends on insert, removes via swap-and-pop
 *         (the last element is moved into the removed slot).
 * @dev Ordering: removal moves elements, so the same `offset` is not stable across calls;
 *      `reverse` only means "walk the current storage order backwards".
 *      Enumeration has exactly one complete path (pagination); an unbounded set exposes no
 *      whole-set getter and no `AtIndex`. `contains` / `count` are O(1) point queries rather
 *      than a second enumeration path, and `count` always equals the `total` returned by
 *      `values(...)`. Window semantics follow `Pagination`.
 *      `indexPlusOne` encodes `index + 1` so a single mapping expresses both "is it present"
 *      and "at which index"; `0` is the "absent" sentinel.
 */
library Uint256Set {
    using Pagination for uint256[];

    struct Storage {
        uint256[] items;
        mapping(uint256 => uint256) indexPlusOne;
    }

    /**
     * @notice Insert an element
     * @return added Whether the element was actually inserted; a no-op (no state change, no new
     *         slot, `false`) if already present. Callers that need idempotent side effects (event
     *         emission, operator bookkeeping) must branch on this instead of testing membership
     *         beforehand.
     */
    function add(Storage storage self, uint256 value) internal returns (bool added) {
        if (self.indexPlusOne[value] != 0) return false;

        self.items.push(value);
        self.indexPlusOne[value] = self.items.length;
        return true;
    }

    /**
     * @notice Swap-and-pop removal
     * @dev `indexPlusOne[value] != 0` implies the element lives in `items`, hence
     *      `items.length >= 1`, so the `items.length - 1` below cannot underflow.
     * @return removed Whether the element was actually removed; a no-op (no state change, no
     *         revert, `false`) if absent
     */
    function remove(Storage storage self, uint256 value) internal returns (bool removed) {
        uint256 slot = self.indexPlusOne[value];
        if (slot == 0) return false;

        uint256 removedIndex = slot - 1;
        uint256 lastIndex = self.items.length - 1;
        if (removedIndex != lastIndex) {
            uint256 lastValue = self.items[lastIndex];
            self.items[removedIndex] = lastValue;
            self.indexPlusOne[lastValue] = removedIndex + 1;
        }
        self.items.pop();
        delete self.indexPlusOne[value];
        return true;
    }

    /**
     * @notice O(1) membership test; a non-zero sentinel means the element is present
     */
    function contains(Storage storage self, uint256 value) internal view returns (bool) {
        return self.indexPlusOne[value] != 0;
    }

    /**
     * @notice Current number of elements
     */
    function count(Storage storage self) internal view returns (uint256) {
        return self.items.length;
    }

    /**
     * @notice Paginated read; out of range returns an empty page with the real total and does not
     *         revert; `limit = 0` returns the total only
     */
    function values(Storage storage self, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory page, uint256 total)
    {
        return self.items.paginate(offset, limit, reverse);
    }
}
