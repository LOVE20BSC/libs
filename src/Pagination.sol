// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

library Pagination {
    function paginateIndices(uint256 total, uint256 offset, uint256 limit, bool reverse)
        internal
        pure
        returns (uint256[] memory indices)
    {
        uint256 count = pageCount(total, offset, limit);
        indices = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            indices[i] = pageIndex(total, offset, i, reverse);
        }
    }

    function paginate(uint256[] storage items, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (uint256[] memory result, uint256 total)
    {
        total = items.length;
        uint256 count = pageCount(total, offset, limit);
        result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = items[pageIndex(total, offset, i, reverse)];
        }
    }

    function paginate(address[] storage items, uint256 offset, uint256 limit, bool reverse)
        internal
        view
        returns (address[] memory result, uint256 total)
    {
        total = items.length;
        uint256 count = pageCount(total, offset, limit);
        result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = items[pageIndex(total, offset, i, reverse)];
        }
    }

    function pageCount(uint256 total, uint256 offset, uint256 limit) internal pure returns (uint256) {
        if (offset >= total) {
            return 0;
        }
        uint256 remaining = total - offset;
        return remaining < limit ? remaining : limit;
    }

    function pageIndex(uint256 total, uint256 offset, uint256 i, bool reverse)
        internal
        pure
        returns (uint256)
    {
        return reverse ? (total - 1 - offset - i) : (offset + i);
    }
}
