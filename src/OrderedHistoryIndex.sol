// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

library OrderedHistoryIndex {
    error InvalidKeyOrder();

    struct Index {
        uint256[] keys;
        mapping(uint256 => bool) recorded;
    }

    function record(Index storage self, uint256 key) internal {
        uint256 length = self.keys.length;
        if (length == 0 || key > self.keys[length - 1]) {
            self.keys.push(key);
            self.recorded[key] = true;
        } else if (key < self.keys[length - 1]) {
            revert InvalidKeyOrder();
        }
    }

    function contains(Index storage self, uint256 key) internal view returns (bool) {
        return self.recorded[key];
    }

    function nearest(Index storage self, uint256 key)
        internal
        view
        returns (bool found, uint256 nearestKey)
    {
        uint256 length = self.keys.length;
        if (length == 0 || self.keys[0] > key) return (false, 0);
        if (self.keys[length - 1] <= key) return (true, self.keys[length - 1]);

        uint256 low;
        uint256 high = length;
        while (low < high) {
            uint256 middle = (low + high) / 2;
            if (self.keys[middle] <= key) low = middle + 1;
            else high = middle;
        }
        return (true, self.keys[low - 1]);
    }

    function latest(Index storage self) internal view returns (bool found, uint256 key) {
        uint256 length = self.keys.length;
        return length == 0 ? (false, 0) : (true, self.keys[length - 1]);
    }
}
