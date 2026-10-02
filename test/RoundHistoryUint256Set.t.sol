// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {RoundHistoryUint256Set} from "../src/RoundHistoryUint256Set.sol";
import {RoundHistoryUint256} from "../src/RoundHistoryUint256.sol";
import {OrderedHistoryIndex} from "../src/OrderedHistoryIndex.sol";

/// Bundle returned by `RoundHistoryUint256SetHarness.probe`, shared with the test contract.
struct RhProbe {
    uint256[] items;
    uint256 total;
    uint256[] itemsAtRound;
    uint256 totalAtRound;
    uint256[] itemIndexPlusOne;
    uint256[] domainIndexPlusOne;
    bool[] domainContains;
    bool[] domainContainsAtRound;
}

/// Per-round naive snapshots, flat and pre-allocated so the fuzz loops never allocate.
struct Snapshots {
    uint256[] rounds;
    uint256[] lens;
    uint256[] flat;
    uint256 count;
}

contract RoundHistoryUint256SetHarness {
    using RoundHistoryUint256Set for RoundHistoryUint256Set.Storage;
    using RoundHistoryUint256 for RoundHistoryUint256.History;

    RoundHistoryUint256Set.Storage private _set;

    function add(uint256 round, uint256 value) external {
        _set.add(round, value);
    }

    function remove(uint256 round, uint256 value) external {
        _set.remove(round, value);
    }

    function contains(uint256 value) external view returns (bool) {
        return _set.contains(value);
    }

    function count() external view returns (uint256) {
        return _set.count();
    }

    function values(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory page, uint256 total)
    {
        return _set.values(offset, limit, reverse);
    }

    function containsByRound(uint256 value, uint256 round) external view returns (bool) {
        return _set.containsByRound(value, round);
    }

    function countByRound(uint256 round) external view returns (uint256) {
        return _set.countByRound(round);
    }

    function valuesByRound(uint256 round, uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory page, uint256 total)
    {
        return _set.valuesByRound(round, offset, limit, reverse);
    }

    /// Test-only windows onto the three histories. The library keeps these private on purpose; the
    /// state-machine checks need them to assert the inverse-mapping and underflow-guard invariants
    /// directly instead of only through the public reads.
    function slotAt(uint256 index) external view returns (uint256) {
        return _set.slotHistory[index].latestValue();
    }

    function indexPlusOneOf(uint256 value) external view returns (uint256) {
        return _set.indexPlusOneHistory[value].latestValue();
    }

    /// One-call dump of every observable the state-machine checks need: the current page, the page as
    /// of `round`, and both sentinel/membership views for a caller-chosen domain.
    function probe(uint256 round, uint256[] calldata domain) external view returns (RhProbe memory p) {
        (p.items, p.total) = _set.values(0, type(uint256).max, false);
        (p.itemsAtRound, p.totalAtRound) = _set.valuesByRound(round, 0, type(uint256).max, false);
        p.domainIndexPlusOne = new uint256[](domain.length);
        p.domainContains = new bool[](domain.length);
        p.domainContainsAtRound = new bool[](domain.length);
        for (uint256 i = 0; i < domain.length; i++) {
            p.domainIndexPlusOne[i] = _set.indexPlusOneHistory[domain[i]].latestValue();
            p.domainContains[i] = _set.contains(domain[i]);
            p.domainContainsAtRound[i] = _set.containsByRound(domain[i], round);
        }
        p.itemIndexPlusOne = new uint256[](p.items.length);
        for (uint256 i = 0; i < p.items.length; i++) {
            p.itemIndexPlusOne[i] = _set.indexPlusOneHistory[p.items[i]].latestValue();
        }
    }
}

contract RoundHistoryUint256SetTest {
    uint256 private constant DOMAIN = 16;
    uint256 private constant MAX_STEPS = 24;
    /// Two extra probe values (DOMAIN and type(uint256).max) are never inserted and must stay absent.
    uint256 private constant EXTRA = 2;

    function _expect2(uint256[] memory page, uint256 a, uint256 b) private pure {
        require(page.length == 2);
        require(page[0] == a);
        require(page[1] == b);
    }

    function _expect1(uint256[] memory page, uint256 a) private pure {
        require(page.length == 1);
        require(page[0] == a);
    }

    // ==================== Pinned behaviour ====================

    function testAddAndCurrentState() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        require(!harness.contains(1));
        require(harness.count() == 0);

        harness.add(1, 10);
        harness.add(1, 20);
        require(harness.contains(10));
        require(harness.contains(20));
        require(!harness.contains(30));
        require(harness.count() == 2);
        require(harness.slotAt(0) == 10);
        require(harness.slotAt(1) == 20);
        require(harness.indexPlusOneOf(10) == 1);
        require(harness.indexPlusOneOf(20) == 2);
    }

    function testDuplicateAddIsNoop() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 10);
        harness.add(2, 10);
        require(harness.count() == 1);
        require(harness.contains(10));
        require(harness.indexPlusOneOf(10) == 1);

        (uint256[] memory page, uint256 total) = harness.values(0, 10, false);
        _expect1(page, 10);
        require(total == 1);
    }

    function testRemoveAbsentIsNoop() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 10);
        harness.remove(2, 99);
        require(harness.count() == 1);
        require(harness.contains(10));
        require(harness.indexPlusOneOf(99) == 0);
    }

    function testSnapshotAcrossRounds() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 10);
        harness.add(1, 20);
        harness.add(2, 30);
        harness.remove(2, 20);

        require(harness.count() == 2);
        require(!harness.contains(20));

        (uint256[] memory page, uint256 total) = harness.valuesByRound(1, 0, 10, false);
        _expect2(page, 10, 20);
        require(total == 2);
        require(harness.countByRound(1) == 2);
        require(harness.containsByRound(10, 1));
        require(harness.containsByRound(20, 1));
        require(!harness.containsByRound(30, 1));

        (page, total) = harness.valuesByRound(2, 0, 10, false);
        _expect2(page, 10, 30);
        require(total == 2);
        require(harness.countByRound(2) == 2);
        require(harness.containsByRound(30, 2));
        require(!harness.containsByRound(20, 2));
    }

    function testLaterRemovalKeepsHistory() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 10);
        harness.add(1, 20);
        harness.add(2, 30);
        harness.remove(2, 20);
        // 第 3 轮删 10 会触发 swap：30 被搬到槽位 0
        harness.remove(3, 10);

        require(harness.count() == 1);
        require(harness.contains(30));
        require(!harness.contains(10));

        (uint256[] memory page, uint256 total) = harness.valuesByRound(1, 0, 10, false);
        _expect2(page, 10, 20);
        require(total == 2);

        (page, total) = harness.valuesByRound(2, 0, 10, false);
        _expect2(page, 10, 30);
        require(total == 2);

        (page, total) = harness.valuesByRound(3, 0, 10, false);
        _expect1(page, 30);
        require(total == 1);

        require(!harness.containsByRound(30, 1));
        require(harness.containsByRound(30, 3));
        require(!harness.containsByRound(10, 3));
    }

    /// A round that falls strictly between two writes must read the earlier write's state.
    function testRoundBetweenWritesReturnsPrevious() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 10);
        harness.add(1, 20);
        harness.add(5, 30);

        // rounds 2..4 sit between the round-1 and round-5 writes
        (uint256[] memory page, uint256 total) = harness.valuesByRound(3, 0, 10, false);
        _expect2(page, 10, 20);
        require(total == 2, "round before the 5th still sees round 1");
        require(harness.countByRound(4) == 2);
        require(harness.containsByRound(20, 4));
        require(!harness.containsByRound(30, 4));

        harness.remove(9, 10);
        // rounds 5..8 sit between the round-9 removal and the earlier writes
        (page, total) = harness.valuesByRound(6, 0, 10, false);
        require(total == 3, "removal at round 9 does not affect earlier rounds");
        require(page.length == 3);
        require(harness.containsByRound(10, 8));
        require(harness.countByRound(9) == 2);
        require(!harness.containsByRound(10, 9));
    }

    function testSameRoundAddRemoveNetsAbsent() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(5, 11);
        harness.remove(5, 11);

        require(!harness.contains(11));
        require(harness.count() == 0);
        require(!harness.containsByRound(11, 5));
        require(harness.countByRound(5) == 0);

        harness.add(6, 11);
        require(harness.contains(11));
        require(harness.containsByRound(11, 6));
        require(!harness.containsByRound(11, 5));
    }

    function testSameRoundSwapKeepsFinalOrder() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 1);
        harness.add(1, 2);
        harness.add(1, 3);
        harness.remove(1, 1);

        // 同一 round 内多次变更只保留该轮最终值
        (uint256[] memory page, uint256 total) = harness.values(0, 10, false);
        _expect2(page, 3, 2);
        require(total == 2);

        (page, total) = harness.valuesByRound(1, 0, 10, false);
        _expect2(page, 3, 2);
        require(total == 2);
        require(!harness.containsByRound(1, 1));
    }

    function testDrainThenReAdd() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 1);
        harness.add(1, 2);
        harness.remove(2, 1);
        harness.remove(2, 2);

        require(harness.count() == 0);
        require(harness.countByRound(2) == 0);
        require(!harness.containsByRound(1, 2));
        require(!harness.containsByRound(2, 2));

        harness.add(3, 2);
        require(harness.count() == 1);
        require(harness.containsByRound(2, 3));
        require(!harness.containsByRound(2, 2));
        require(harness.countByRound(2) == 0);

        (uint256[] memory page, uint256 total) = harness.valuesByRound(3, 0, 10, false);
        _expect1(page, 2);
        require(total == 1);
    }

    /// A slot vacated in one round and reused later must read back the element that was there at each
    /// round: `slotHistory[k].value(round)` is per-round, not the latest slot content.
    function testSlotReuseKeepsPerRoundValue() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 70); // slot 0
        harness.remove(2, 70); // slot 0 -> 0
        harness.add(3, 80); // slot 0 reused

        require(harness.count() == 1);
        require(harness.slotAt(0) == 80);

        (uint256[] memory page, uint256 total) = harness.valuesByRound(1, 0, 10, false);
        _expect1(page, 70);
        require(total == 1);

        (page, total) = harness.valuesByRound(2, 0, 10, false);
        require(total == 0);
        require(page.length == 0);

        (page, total) = harness.valuesByRound(3, 0, 10, false);
        _expect1(page, 80);
        require(total == 1);

        require(harness.containsByRound(70, 1));
        require(!harness.containsByRound(70, 2));
        require(!harness.containsByRound(70, 3));
        require(harness.containsByRound(80, 3));
    }

    function testBeforeFirstWriteRound() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(5, 11);

        require(harness.countByRound(4) == 0);
        require(!harness.containsByRound(11, 4));
        (uint256[] memory page, uint256 total) = harness.valuesByRound(4, 0, 10, false);
        require(page.length == 0);
        require(total == 0);

        // 空集合的按轮查询
        require(harness.countByRound(0) == 0);
    }

    function testCurrentPaginationWindow() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 1);
        harness.add(1, 2);
        harness.add(1, 3);
        harness.add(1, 4);

        (uint256[] memory page, uint256 total) = harness.values(1, 2, false);
        require(page.length == 2);
        require(page[0] == 2);
        require(page[1] == 3);
        require(total == 4);

        (page, total) = harness.values(0, 2, true);
        require(page.length == 2);
        require(page[0] == 4);
        require(page[1] == 3);

        (page, total) = harness.values(0, 0, false);
        require(page.length == 0);
        require(total == 4);

        (page, total) = harness.values(9, 2, false);
        require(page.length == 0);
        require(total == 4);
    }

    function testByRoundPaginationWindow() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 1);
        harness.add(1, 2);
        harness.add(1, 3);

        (uint256[] memory page, uint256 total) = harness.valuesByRound(1, 2, 5, false);
        require(page.length == 1);
        require(page[0] == 3);
        require(total == 3);

        (page, total) = harness.valuesByRound(1, 0, 0, false);
        require(page.length == 0);
        require(total == 3);

        (page, total) = harness.valuesByRound(1, 9, 5, false);
        require(page.length == 0);
        require(total == 3);

        // reverse walks the round's storage order backwards
        (page, total) = harness.valuesByRound(1, 0, 2, true);
        require(page.length == 2);
        require(page[0] == 3);
        require(page[1] == 2);
        require(total == 3);
    }

    function testRemoveSoleElement() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 8);
        harness.remove(1, 8);

        require(harness.count() == 0);
        require(!harness.contains(8));
        require(harness.countByRound(1) == 0);
        require(harness.indexPlusOneOf(8) == 0);

        (uint256[] memory page, uint256 total) = harness.values(0, 10, false);
        require(page.length == 0);
        require(total == 0);
    }

    function testRemoveTailBranch() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 10);
        harness.add(1, 20);
        harness.remove(2, 20); // tail: no swap

        require(harness.count() == 1);
        require(harness.slotAt(0) == 10);
        require(harness.indexPlusOneOf(10) == 1);
        require(harness.indexPlusOneOf(20) == 0);

        (uint256[] memory page, uint256 total) = harness.values(0, 10, false);
        _expect1(page, 10);
        require(total == 1);
    }

    function testRemoveMiddleBranch() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 10);
        harness.add(1, 20);
        harness.add(1, 30);
        harness.add(1, 40);
        harness.remove(2, 20); // middle: 40 swaps into slot 1

        require(harness.count() == 3);
        require(harness.slotAt(0) == 10);
        require(harness.slotAt(1) == 40);
        require(harness.slotAt(2) == 30);
        require(harness.indexPlusOneOf(10) == 1);
        require(harness.indexPlusOneOf(40) == 2);
        require(harness.indexPlusOneOf(30) == 3);
        require(harness.indexPlusOneOf(20) == 0);

        (uint256[] memory page, uint256 total) = harness.valuesByRound(2, 0, 10, false);
        require(total == 3);
        require(page[0] == 10);
        require(page[1] == 40);
        require(page[2] == 30);

        // the moved element is still removable through its new slot
        harness.remove(3, 40);
        require(harness.count() == 2);
        require(harness.indexPlusOneOf(30) == 2);
    }

    /// Element `0` is legal; `0` is not the "absent" marker here (the marker is `indexPlusOne == 0`).
    function testZeroAndMaxElement() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 0);
        harness.add(1, type(uint256).max);
        require(harness.contains(0));
        require(harness.contains(type(uint256).max));
        require(harness.count() == 2);
        require(harness.indexPlusOneOf(0) == 1);
        require(harness.indexPlusOneOf(type(uint256).max) == 2);

        (uint256[] memory page, uint256 total) = harness.valuesByRound(1, 0, 10, false);
        require(total == 2);
        require(page[0] == 0);
        require(page[1] == type(uint256).max);

        harness.remove(2, 0);
        require(!harness.contains(0));
        require(harness.contains(type(uint256).max));
        require(harness.indexPlusOneOf(0) == 0);
        require(!harness.containsByRound(0, 2));
        require(harness.containsByRound(0, 1));
    }

    /// A swap whose moved element is `0`, including the per-round reads: the element value `0` must
    /// not be confused with the "not in the set" marker (`indexPlusOne == 0`).
    function testSwapMovesZeroValue() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, type(uint256).max);
        harness.add(1, 0);
        harness.remove(2, type(uint256).max); // the last element (0) is swapped into slot 0

        require(harness.count() == 1);
        require(harness.contains(0));
        require(!harness.contains(type(uint256).max));
        require(harness.indexPlusOneOf(0) == 1);

        (uint256[] memory page, uint256 total) = harness.valuesByRound(1, 0, 10, false);
        require(total == 2);
        require(page[0] == type(uint256).max);
        require(page[1] == 0);

        (page, total) = harness.valuesByRound(2, 0, 10, false);
        require(total == 1);
        require(page.length == 1);
        require(page[0] == 0);
        require(harness.containsByRound(0, 2));
        require(!harness.containsByRound(type(uint256).max, 2));

        // same-round variant: the removal shares the round used by the two inserts
        RoundHistoryUint256SetHarness h2 = new RoundHistoryUint256SetHarness();
        h2.add(5, type(uint256).max);
        h2.add(5, 0);
        h2.remove(5, type(uint256).max);
        require(h2.count() == 1);
        require(h2.contains(0));
        require(h2.containsByRound(0, 5));
        (page, total) = h2.valuesByRound(5, 0, 10, false);
        require(total == 1);
        require(page.length == 1);
        require(page[0] == 0);
    }

    function testRoundZeroAndMaxRound() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(0, 5);
        require(harness.countByRound(0) == 1);
        require(harness.containsByRound(5, 0));
        (uint256[] memory page0, uint256 total0) = harness.valuesByRound(0, 0, 10, false);
        require(total0 == 1 && page0.length == 1 && page0[0] == 5);

        harness.add(type(uint256).max, 6);
        require(harness.count() == 2);
        require(harness.containsByRound(6, type(uint256).max));
        require(harness.countByRound(type(uint256).max) == 2);
        // a round before the last write still sees only the first element
        require(harness.countByRound(type(uint256).max - 1) == 1);
        require(!harness.containsByRound(6, type(uint256).max - 1));
    }

    /// Pins the accepted order contract for the history-backed set, same as `Uint256Set`.
    function testOffsetIsUnstableAcrossRemoval() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 1);
        harness.add(1, 2);
        harness.add(1, 3);

        (uint256[] memory page, uint256 total) = harness.values(0, 1, false);
        require(total == 3);
        require(page[0] == 1);

        harness.remove(2, 1); // tail (3) is swapped into slot 0
        (page, total) = harness.values(0, 1, false);
        require(total == 2);
        require(page[0] == 3, "same offset now yields a different element");
    }

    function testRevertOnDecreasingRound() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(5, 11);
        try harness.add(3, 12) {
            revert("expected InvalidKeyOrder");
        } catch (bytes memory reason) {
            // forge-lint: disable-next-line(unsafe-typecast)
            require(bytes4(reason) == OrderedHistoryIndex.InvalidKeyOrder.selector);
        }
    }

    /// The `countHistory.latestValue() - 1` in `remove` would underflow if an element were marked
    /// present while the size were 0. That state is unreachable, so removing from an empty or drained
    /// set must never revert.
    function testRemoveNeverUnderflowsOnEmptySet() external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.remove(0, 1);
        harness.remove(7, 2);
        require(harness.count() == 0);
        require(harness.indexPlusOneOf(1) == 0);

        harness.add(1, 9);
        harness.remove(2, 9);
        require(harness.count() == 0);
        harness.remove(3, 9); // already gone
        harness.remove(4, 12345);
        require(harness.count() == 0);
        require(harness.indexPlusOneOf(9) == 0);
    }

    // ==================== Properties ====================

    function _next(uint256 x) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(x)));
    }

    /// Domain plus two never-inserted sentinels; the extras must always read back absent.
    function _domain() private pure returns (uint256[] memory domain) {
        domain = new uint256[](DOMAIN + EXTRA);
        for (uint256 i = 0; i < DOMAIN; i++) {
            domain[i] = i;
        }
        domain[DOMAIN] = DOMAIN;
        domain[DOMAIN + 1] = type(uint256).max;
    }

    // --- deliberately naive reference model: fixed-capacity flat array + linear scan ---

    function _modelIndexOf(uint256[] memory model, uint256 len, uint256 value) private pure returns (uint256) {
        for (uint256 i = 0; i < len; i++) {
            if (model[i] == value) return i;
        }
        return type(uint256).max;
    }

    function _modelContains(uint256[] memory model, uint256 len, uint256 value) private pure returns (bool) {
        return _modelIndexOf(model, len, value) != type(uint256).max;
    }

    function _modelAdd(uint256[] memory model, uint256 len, uint256 value) private pure returns (uint256) {
        if (_modelContains(model, len, value)) return len;
        model[len] = value;
        return len + 1;
    }

    function _modelRemove(uint256[] memory model, uint256 len, uint256 value) private pure returns (uint256) {
        uint256 idx = _modelIndexOf(model, len, value);
        if (idx == type(uint256).max) return len;
        for (uint256 i = idx; i + 1 < len; i++) {
            model[i] = model[i + 1];
        }
        return len - 1;
    }

    // --- per-round snapshots: the model is copied after every operation, and a repeated round
    // overwrites its snapshot (matching "same round keeps only that round's final value") ---

    function _snapWrite(Snapshots memory s, uint256 round, uint256[] memory model, uint256 modelLen) private pure {
        if (s.count > 0 && s.rounds[s.count - 1] == round) {
            _snapStore(s, s.count - 1, model, modelLen);
        } else {
            s.rounds[s.count] = round;
            _snapStore(s, s.count, model, modelLen);
            s.count = s.count + 1;
        }
    }

    function _snapStore(Snapshots memory s, uint256 idx, uint256[] memory model, uint256 modelLen) private pure {
        for (uint256 i = 0; i < modelLen; i++) {
            s.flat[idx * DOMAIN + i] = model[i];
        }
        s.lens[idx] = modelLen;
    }

    /// Nearest snapshot at or before `round`; returns its base offset into `flat` and its length.
    function _snapAt(Snapshots memory s, uint256 round) private pure returns (uint256 base, uint256 len) {
        uint256 idx = type(uint256).max;
        for (uint256 i = 0; i < s.count; i++) {
            if (s.rounds[i] <= round) idx = i;
            else break;
        }
        if (idx == type(uint256).max) return (0, 0);
        base = idx * DOMAIN;
        len = s.lens[idx];
    }

    function _snapContains(Snapshots memory s, uint256 base, uint256 len, uint256 value)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < len; i++) {
            if (s.flat[base + i] == value) return true;
        }
        return false;
    }

    /// Pure, allocation-free checks so they can run inside a fuzz loop. `ok` is accumulated, no
    /// `require` is used, and nothing is allocated.
    function _currentOk(RhProbe memory p, uint256[] memory domain, uint256[] memory model, uint256 modelLen)
        private
        pure
        returns (bool ok)
    {
        ok = p.total == modelLen && p.items.length == modelLen && p.itemIndexPlusOne.length == modelLen;
        for (uint256 i = 0; i < p.items.length; i++) {
            if (p.itemIndexPlusOne[i] != i + 1) ok = false; // element -> slot+1 inverse mapping
        }
        for (uint256 i = 0; i < domain.length; i++) {
            bool inModel = _modelContains(model, modelLen, domain[i]);
            if (p.domainContains[i] != inModel) ok = false;
            if ((p.domainIndexPlusOne[i] != 0) != inModel) ok = false;
            if (inModel) {
                // round-trip plus the underflow guard: a present element must sit at 1..modelLen
                uint256 pos = p.domainIndexPlusOne[i];
                if (pos == 0 || pos > modelLen) ok = false;
                else if (p.items[pos - 1] != domain[i]) ok = false;
            }
        }
    }

    function _roundOk(RhProbe memory p, uint256[] memory domain, Snapshots memory s, uint256 round)
        private
        pure
        returns (bool ok)
    {
        (uint256 base, uint256 len) = _snapAt(s, round);
        ok = p.totalAtRound == len && p.itemsAtRound.length == len;
        for (uint256 i = 0; i < p.itemsAtRound.length; i++) {
            if (!_snapContains(s, base, len, p.itemsAtRound[i])) ok = false;
        }
        for (uint256 i = 0; i < domain.length; i++) {
            if (p.domainContainsAtRound[i] != _snapContains(s, base, len, domain[i])) ok = false;
        }
    }

    /// State machine: a random add/remove walk over non-decreasing rounds must match a naive
    /// per-round snapshot model after every single step, and keep the representation invariants.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_StateMachineAgainstSnapshots(uint256 seed, uint8 rawSteps) external {
        uint256 steps = (uint256(rawSteps) % MAX_STEPS) + 1;
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        uint256[] memory domain = _domain();
        uint256[] memory model = new uint256[](DOMAIN);
        uint256 modelLen = 0;
        Snapshots memory snaps = Snapshots({
            rounds: new uint256[](MAX_STEPS),
            lens: new uint256[](MAX_STEPS),
            flat: new uint256[](MAX_STEPS * DOMAIN),
            count: 0
        });
        uint256 rng = seed;
        uint256 round = 0;
        bool ok = true;

        for (uint256 s = 0; s < steps; s++) {
            rng = _next(rng);
            round += rng % 3; // non-decreasing, sometimes repeated
            rng = _next(rng);
            uint256 value = rng % DOMAIN;
            rng = _next(rng);
            if (rng % 2 == 0) {
                // forge-lint: disable-next-line(calls-loop)
                harness.add(round, value);
                modelLen = _modelAdd(model, modelLen, value);
            } else {
                // forge-lint: disable-next-line(calls-loop)
                harness.remove(round, value);
                modelLen = _modelRemove(model, modelLen, value);
            }
            _snapWrite(snaps, round, model, modelLen);

            RhProbe memory p = harness.probe(round, domain); // forge-lint: disable-line(calls-loop)
            if (!_currentOk(p, domain, model, modelLen)) ok = false;
            if (!_roundOk(p, domain, snaps, round)) ok = false;

            // a round strictly before the current one must read the previous snapshot
            if (round > 0) {
                RhProbe memory earlier = harness.probe(round - 1, domain); // forge-lint: disable-line(calls-loop)
                if (!_roundOk(earlier, domain, snaps, round - 1)) ok = false;
            }
        }

        require(ok, "snapshot state machine invariant violated");
    }

    /// The same walk as `testFuzz_StateMachineAgainstSnapshots`, plus explicit `count()` /
    /// `countByRound()` comparisons, against the naive per-round model.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DifferentialAgainstSnapshotModel(uint256 seed, uint8 rawSteps) external {
        uint256 steps = (uint256(rawSteps) % MAX_STEPS) + 1;
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        uint256[] memory domain = _domain();
        uint256[] memory model = new uint256[](DOMAIN);
        uint256 modelLen = 0;
        Snapshots memory snaps = Snapshots({
            rounds: new uint256[](MAX_STEPS),
            lens: new uint256[](MAX_STEPS),
            flat: new uint256[](MAX_STEPS * DOMAIN),
            count: 0
        });
        uint256 rng = seed;
        uint256 round = 0;
        bool ok = true;

        for (uint256 s = 0; s < steps; s++) {
            rng = _next(rng);
            round += rng % 3;
            rng = _next(rng);
            uint256 value = rng % DOMAIN;
            rng = _next(rng);
            if (rng % 2 == 0) {
                // forge-lint: disable-next-line(calls-loop)
                harness.add(round, value);
                modelLen = _modelAdd(model, modelLen, value);
            } else {
                // forge-lint: disable-next-line(calls-loop)
                harness.remove(round, value);
                modelLen = _modelRemove(model, modelLen, value);
            }
            _snapWrite(snaps, round, model, modelLen);

            // current reads agree with the model
            if (harness.count() != modelLen) ok = false; // forge-lint: disable-line(calls-loop)
            if (harness.countByRound(round) != modelLen) ok = false; // forge-lint: disable-line(calls-loop)

            RhProbe memory p = harness.probe(round, domain); // forge-lint: disable-line(calls-loop)
            if (!_currentOk(p, domain, model, modelLen)) ok = false;
            if (!_roundOk(p, domain, snaps, round)) ok = false;

            // a strictly earlier round reads the previous snapshot
            if (round > 0) {
                RhProbe memory earlier = harness.probe(round - 1, domain); // forge-lint: disable-line(calls-loop)
                if (!_roundOk(earlier, domain, snaps, round - 1)) ok = false;
            }
        }

        require(ok, "differential check against the snapshot model failed");
    }

    /// Same-round hammering: many operations inside a single round must only keep that round's final
    /// value. Rounds never advance, so every write targets the same history key.
    function testFuzz_SameRoundHammersKeepFinalValue(uint256 seed, uint8 rawOps) external {
        uint256 ops = (uint256(rawOps) % MAX_STEPS) + 1;
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        uint256[] memory domain = _domain();
        uint256[] memory model = new uint256[](DOMAIN);
        uint256 modelLen = 0;
        uint256 rng = seed;
        bool ok = true;

        for (uint256 s = 0; s < ops; s++) {
            rng = _next(rng);
            uint256 value = rng % DOMAIN;
            rng = _next(rng);
            if (rng % 2 == 0) {
                // forge-lint: disable-next-line(calls-loop)
                harness.add(7, value);
                modelLen = _modelAdd(model, modelLen, value);
            } else {
                // forge-lint: disable-next-line(calls-loop)
                harness.remove(7, value);
                modelLen = _modelRemove(model, modelLen, value);
            }
        }

        RhProbe memory p = harness.probe(7, domain);
        if (!_currentOk(p, domain, model, modelLen)) ok = false;
        // the single write round holds exactly the final state
        if (p.totalAtRound != modelLen) ok = false;
        if (p.itemsAtRound.length != modelLen) ok = false;
        // every round before the first write is empty
        for (uint256 r = 0; r < 7; r++) {
            RhProbe memory before = harness.probe(r, domain); // forge-lint: disable-line(calls-loop)
            if (before.totalAtRound != 0) ok = false;
            if (before.itemsAtRound.length != 0) ok = false;
        }

        require(ok, "same-round hammering left inconsistent state");
    }

    /// Full-width values on the fuzz paths, exercising both branches of add/remove.
    function testFuzz_ArbitraryValues(uint256 a, uint256 b) external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        bool same = (a == b);

        harness.add(0, a);
        require(harness.contains(a));
        require(harness.indexPlusOneOf(a) == 1);
        require(harness.containsByRound(a, 0));

        harness.add(1, b);
        require(harness.count() == (same ? 1 : 2));
        require(harness.containsByRound(b, 1));
        require(harness.containsByRound(b, 0) == same, "b only exists at round 0 when it equals a");

        harness.remove(2, a);
        require(!harness.contains(a));
        require(harness.containsByRound(a, 1));
        require(!harness.containsByRound(a, 2));
        require(harness.count() == (same ? 0 : 1));
        if (!same) {
            require(harness.contains(b));
            require(harness.containsByRound(b, 2));
        }
    }

    /// Both read paths must expose the same order in both directions: the reverse page is exactly the
    /// forward page read backwards. All writes land in one round, so the same-round path is exercised
    /// in both directions as well.
    function testFuzz_ReversePageMirrorsForward(uint256 seed, uint8 rawOps) external {
        uint256 ops = (uint256(rawOps) % MAX_STEPS) + 1;
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        uint256 rng = seed;
        bool ok = true;

        for (uint256 s = 0; s < ops; s++) {
            rng = _next(rng);
            uint256 value = rng % DOMAIN;
            rng = _next(rng);
            if (rng % 2 == 0) {
                // forge-lint: disable-next-line(calls-loop)
                harness.add(3, value);
            } else {
                // forge-lint: disable-next-line(calls-loop)
                harness.remove(3, value);
            }
        }

        (uint256[] memory fwd, uint256 fwdTotal) = harness.values(0, type(uint256).max, false);
        (uint256[] memory rev, uint256 revTotal) = harness.values(0, type(uint256).max, true);
        if (fwdTotal != revTotal || fwd.length != rev.length) {
            ok = false;
        } else {
            for (uint256 i = 0; i < fwd.length; i++) {
                if (rev[i] != fwd[fwd.length - 1 - i]) ok = false;
            }
        }

        (uint256[] memory fwdR, uint256 fwdRTotal) = harness.valuesByRound(3, 0, type(uint256).max, false);
        (uint256[] memory revR, uint256 revRTotal) = harness.valuesByRound(3, 0, type(uint256).max, true);
        if (fwdRTotal != revRTotal || fwdR.length != revR.length) {
            ok = false;
        } else {
            for (uint256 i = 0; i < fwdR.length; i++) {
                if (revR[i] != fwdR[fwdR.length - 1 - i]) ok = false;
            }
        }

        require(ok, "reverse page is not the forward page reversed");
    }

    /// Extreme windows on both read paths must stay non-reverting and report the real total.
    function testFuzz_ExtremeWindows(uint256 offsetRaw, bool reverse) external {
        RoundHistoryUint256SetHarness harness = new RoundHistoryUint256SetHarness();
        harness.add(1, 5);
        harness.add(1, 6);
        harness.add(1, 7);

        uint256 offset = offsetRaw % 5;
        (uint256[] memory page, uint256 total) = harness.values(offset, type(uint256).max, reverse);
        require(total == 3);
        require(page.length == (offset >= 3 ? 0 : 3 - offset));

        (page, total) = harness.valuesByRound(1, offset, type(uint256).max, reverse);
        require(total == 3);
        require(page.length == (offset >= 3 ? 0 : 3 - offset));

        (page, total) = harness.values(type(uint256).max, type(uint256).max, reverse);
        require(total == 3 && page.length == 0);

        (page, total) = harness.valuesByRound(1, type(uint256).max, type(uint256).max, reverse);
        require(total == 3 && page.length == 0);
    }
}
