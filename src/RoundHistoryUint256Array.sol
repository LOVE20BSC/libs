// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {OrderedHistoryIndex} from "./OrderedHistoryIndex.sol";

library RoundHistoryUint256Array {
    using OrderedHistoryIndex for OrderedHistoryIndex.Index;

    struct History {
        OrderedHistoryIndex.Index index;
        mapping(uint256 => uint256[]) valueByRound;
    }

    function record(History storage self, uint256 round, uint256[] memory newValues) internal {
        self.index.record(round);
        self.valueByRound[round] = newValues;
    }

    function values(History storage self, uint256 round) internal view returns (uint256[] memory) {
        if (self.index.contains(round)) {
            return self.valueByRound[round];
        }
        (bool found, uint256 nearestRound) = self.index.nearest(round);
        return found ? self.valueByRound[nearestRound] : new uint256[](0);
    }

    function latestValues(History storage self) internal view returns (uint256[] memory) {
        (bool found, uint256 latestRound) = self.index.latest();
        return found ? self.valueByRound[latestRound] : new uint256[](0);
    }
}
