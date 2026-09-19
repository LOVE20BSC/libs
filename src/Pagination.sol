// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

/**
 * @title Pagination
 * @notice 通用分页库，支持索引分页和类型化数组分页
 * @dev 提供三种使用方式：
 *      1. paginateIndices - 仅返回索引，由调用者自行获取数据
 *      2. paginate(uint256[] storage) - uint256 数组直接分页
 *      3. paginate(address[] storage) - address 数组直接分页
 *      窗口语义：越界返回空数组不回滚；limit 超过剩余量按剩余量返回；limit = 0 只取总数（返回空数组）。
 *      offset 从读取方向的起始端跳过指定项数——正序跳过最旧的，逆序跳过最新的——同一 offset 在两种方向下
 *      跳过的是集合的两端。元素不是 uint256/address 时，用 paginateIndices 取下标后自行取值。
 */
library Pagination {
    /**
     * @notice 纯索引分页 - 返回源数组下标，由调用者自行获取数据
     * @param total 总数量
     * @param offset 偏移量（从 0 开始；跳过读取起始端的 offset 项：正序跳过最旧的，逆序跳过最新的）
     * @param limit 每页数量（超过剩余量按剩余量返回；传 0 返回空数组）
     * @param reverse 是否逆序（true = 从最新到最旧）
     * @return indices 源数组下标数组
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
     * @notice uint256[] 数组分页
     * @param items 存储数组
     * @param offset 偏移量（从 0 开始；跳过读取起始端的 offset 项：正序跳过最旧的，逆序跳过最新的）
     * @param limit 每页数量（超过剩余量按剩余量返回；传 0 返回空数组）
     * @param reverse 是否逆序
     * @return result 分页结果
     * @return total 总数量
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
     * @notice address[] 数组分页
     * @param items 存储数组
     * @param offset 偏移量（从 0 开始；跳过读取起始端的 offset 项：正序跳过最旧的，逆序跳过最新的）
     * @param limit 每页数量（超过剩余量按剩余量返回；传 0 返回空数组）
     * @param reverse 是否逆序
     * @return result 分页结果
     * @return total 总数量
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
     * @notice 窗口大小：offset 越界时为空，否则取 limit 与剩余量的较小值（limit 为 0 也落在这里）
     */
    function _pageSize(uint256 total, uint256 offset, uint256 limit) private pure returns (uint256) {
        if (offset >= total) {
            return 0;
        }
        uint256 remaining = total - offset;
        return remaining < limit ? remaining : limit;
    }

    /**
     * @notice 页内第 i 项对应的源下标：逆序时从最新一端倒着走
     */
    function _sourceIndex(uint256 total, uint256 offset, uint256 i, bool reverse)
        private
        pure
        returns (uint256)
    {
        return reverse ? (total - 1 - offset - i) : (offset + i);
    }
}
