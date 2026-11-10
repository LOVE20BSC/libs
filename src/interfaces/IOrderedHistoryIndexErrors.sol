// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

interface IOrderedHistoryIndexErrors {
    error InvalidKeyOrder(
        uint256 key,
        uint256 lastKey
    );
}
