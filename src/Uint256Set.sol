// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Pagination} from "./Pagination.sol";

library Uint256Set {
    using Pagination for uint256[];

    struct Storage {
        uint256[] items;
        // element => index + 1; 0 means absent
        mapping(uint256 => uint256) indexPlusOne;
    }

    function add(Storage storage self, uint256 value) internal returns (bool added) {
        if (self.indexPlusOne[value] != 0) return false;

        self.items.push(value);
        self.indexPlusOne[value] = self.items.length;
        return true;
    }

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

    function contains(Storage storage self, uint256 value) internal view returns (bool) {
        return self.indexPlusOne[value] != 0;
    }

    function count(Storage storage self) internal view returns (uint256) {
        return self.items.length;
    }

    function values(Storage storage self, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory page, uint256 total)
    {
        return self.items.paginate(offset, limit, reverse);
    }
}
