// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

/**
 * @title Pagination
 * @notice 通用分页库，支持索引分页和类型化数组分页
 * @dev 提供三种使用方式：
 *      1. paginateIndices - 仅返回索引，由调用者自行获取数据
 *      2. paginate(uint256[] storage) - uint256 数组直接分页
 *      3. paginate(address[] storage) - address 数组直接分页
 */
library Pagination {
    /**
     * @notice 纯索引分页 - 返回索引数组，由调用者自行获取数据
     * @param total 总数量
     * @param offset 偏移量（从 0 开始）
     * @param limit 每页数量
     * @param reverse 是否逆序（true = 从最新到最旧）
     * @return indices 索引数组
     * @return actualTotal 实际总数
     */
    function paginateIndices(
        uint256 total,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal pure returns (uint256[] memory indices, uint256 actualTotal) {
        actualTotal = total;
        if (offset >= total) {
            return (new uint256[](0), actualTotal);
        }

        uint256 remaining = total - offset;
        uint256 count = remaining < limit ? remaining : limit;
        indices = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            indices[i] = reverse ? (total - 1 - offset - i) : (offset + i);
        }
    }

    /**
     * @notice uint256[] 数组分页
     * @param items 存储数组
     * @param offset 偏移量
     * @param limit 每页数量
     * @param reverse 是否逆序
     * @return result 分页结果
     * @return total 总数量
     */
    function paginate(
        uint256[] storage items,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (uint256[] memory result, uint256 total) {
        total = items.length;
        uint256[] memory indices;
        (indices, ) = paginateIndices(total, offset, limit, reverse);

        result = new uint256[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            result[i] = items[indices[i]];
        }
    }

    /**
     * @notice address[] 数组分页
     * @param items 存储数组
     * @param offset 偏移量
     * @param limit 每页数量
     * @param reverse 是否逆序
     * @return result 分页结果
     * @return total 总数量
     */
    function paginate(
        address[] storage items,
        uint256 offset,
        uint256 limit,
        bool reverse
    ) internal view returns (address[] memory result, uint256 total) {
        total = items.length;
        uint256[] memory indices;
        (indices, ) = paginateIndices(total, offset, limit, reverse);

        result = new address[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            result[i] = items[indices[i]];
        }
    }
}
