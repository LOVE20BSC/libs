// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {OrderedHistoryIndex} from "./OrderedHistoryIndex.sol";

library RoundHistoryAddress {
    using OrderedHistoryIndex for OrderedHistoryIndex.Index;

    struct History {
        OrderedHistoryIndex.Index index;
        mapping(uint256 => address) valueByRound;
    }

    function record(History storage self, uint256 round, address newValue) internal {
        self.index.record(round);
        self.valueByRound[round] = newValue;
    }

    function value(History storage self, uint256 round) internal view returns (address) {
        if (self.index.contains(round)) {
            return self.valueByRound[round];
        }
        (bool found, uint256 nearestRound) = self.index.nearest(round);
        return found ? self.valueByRound[nearestRound] : address(0);
    }

    function latestValue(History storage self) internal view returns (address) {
        (bool found, uint256 latestRound) = self.index.latest();
        return found ? self.valueByRound[latestRound] : address(0);
    }
}
