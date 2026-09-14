// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {OrderedHistoryIndex} from "./OrderedHistoryIndex.sol";

library RoundHistoryUint256 {
    using OrderedHistoryIndex for OrderedHistoryIndex.Index;

    struct History {
        OrderedHistoryIndex.Index index;
        mapping(uint256 => uint256) valueByRound;
    }

    function record(History storage self, uint256 round, uint256 newValue) internal {
        self.index.record(round);
        self.valueByRound[round] = newValue;
    }

    function value(History storage self, uint256 round) internal view returns (uint256) {
        if (self.index.contains(round)) {
            return self.valueByRound[round];
        }
        (bool found, uint256 nearestRound) = self.index.nearest(round);
        return found ? self.valueByRound[nearestRound] : 0;
    }

    function latestValue(History storage self) internal view returns (uint256) {
        (bool found, uint256 latestRound) = self.index.latest();
        return found ? self.valueByRound[latestRound] : 0;
    }

    function increase(History storage self, uint256 round, uint256 increaseValue) internal {
        record(self, round, value(self, round) + increaseValue);
    }

    function decrease(History storage self, uint256 round, uint256 decreaseValue) internal {
        record(self, round, value(self, round) - decreaseValue);
    }
}
