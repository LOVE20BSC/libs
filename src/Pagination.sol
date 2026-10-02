// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

/**
 * @title Pagination
 * @notice Generic pagination library supporting index pagination and typed array pagination
 * @dev Three ways to use it:
 *      1. paginateIndices - returns the source indices only; the caller fetches the data
 *      2. paginate(uint256[] storage) - paginate a uint256 array directly
 *      3. paginate(address[] storage) - paginate an address array directly
 *      Window semantics: an out-of-range window returns an empty array and does not revert; a
 *      `limit` above the remaining count returns the remaining count; `limit = 0` returns an
 *      empty page (the overloads that also return `total` still return the real total).
 *      `offset` skips that many items from the end the read starts at - forward skips the
 *      oldest, reverse skips the newest - so the same `offset` skips one end or the other
 *      depending on direction. For element types other than uint256/address, use
 *      `paginateIndices` to get the indices and fetch the values yourself.
 */
library Pagination {
    /**
     * @notice Index-only pagination - returns the source array indices; the caller fetches the data
     * @param total Total number of items
     * @param offset Offset (0-based; skips `offset` items from the end the read starts at: forward
     *        skips the oldest, reverse skips the newest)
     * @param limit Page size (above the remaining count returns the remaining count; 0 returns an
     *        empty array)
     * @param reverse Whether to walk backwards (true = newest to oldest)
     * @return indices The source array indices
     */
    function paginateIndices(uint256 total, uint256 offset, uint256 limit, bool reverse)
        internal
        pure
        returns (uint256[] memory indices)
    {
        uint256 count = _pageSize(total, offset, limit);
        indices = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            indices[i] = _sourceIndex(total, offset, i, reverse);
        }
    }

    /**
     * @notice Paginate a uint256[] array
     * @param items The storage array
     * @param offset Offset (0-based; skips `offset` items from the end the read starts at: forward
     *        skips the oldest, reverse skips the newest)
     * @param limit Page size (above the remaining count returns the remaining count; 0 returns an
     *        empty array)
     * @param reverse Whether to walk backwards
     * @return result The page
     * @return total Total number of items
     */
    function paginate(uint256[] storage items, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory result, uint256 total)
    {
        total = items.length;
        uint256 count = _pageSize(total, offset, limit);
        result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = items[_sourceIndex(total, offset, i, reverse)];
        }
    }

    /**
     * @notice Paginate an address[] array
     * @param items The storage array
     * @param offset Offset (0-based; skips `offset` items from the end the read starts at: forward
     *        skips the oldest, reverse skips the newest)
     * @param limit Page size (above the remaining count returns the remaining count; 0 returns an
     *        empty array)
     * @param reverse Whether to walk backwards
     * @return result The page
     * @return total Total number of items
     */
    function paginate(address[] storage items, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (address[] memory result, uint256 total)
    {
        total = items.length;
        uint256 count = _pageSize(total, offset, limit);
        result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = items[_sourceIndex(total, offset, i, reverse)];
        }
    }

    /**
     * @notice Window size: empty when `offset` is out of range, otherwise the smaller of `limit`
     *         and the remaining count (`limit = 0` also lands here)
     */
    function _pageSize(uint256 total, uint256 offset, uint256 limit) private pure returns (uint256) {
        if (offset >= total) {
            return 0;
        }
        uint256 remaining = total - offset;
        return remaining < limit ? remaining : limit;
    }

    /**
     * @notice Source index of item `i` within the page: walks backwards from the newest end when
     *         `reverse` is set
     */
    function _sourceIndex(uint256 total, uint256 offset, uint256 i, bool reverse)
        private
        pure
        returns (uint256)
    {
        return reverse ? (total - 1 - offset - i) : (offset + i);
    }
}
