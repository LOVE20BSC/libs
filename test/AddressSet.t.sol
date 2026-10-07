// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {AddressSet} from "../src/AddressSet.sol";

/// Bundle returned by `AddressSetHarness.probe`, shared with the test contract. Returning it from an
/// external call keeps the fuzz loops to a single external call per step and keeps their stack small.
struct SetProbe {
    address[] items;
    uint256 total;
    address[] reversed;
    uint256 reversedTotal;
    uint256[] domainIndexPlusOne;
    bool[] domainContains;
    uint256[] itemIndexPlusOne;
}

contract AddressSetHarness {
    using AddressSet for AddressSet.Storage;

    AddressSet.Storage private _set;

    function add(address value) external {
        _set.add(value);
    }

    function remove(address value) external {
        _set.remove(value);
    }

    function contains(address value) external view returns (bool) {
        return _set.contains(value);
    }

    function count() external view returns (uint256) {
        return _set.count();
    }

    function values(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (address[] memory page, uint256 total)
    {
        return _set.values(offset, limit, reverse);
    }

    /// Test-only window onto the sentinel encoding (`index + 1`, `0` = absent). The library keeps this
    /// mapping private on purpose; asserting it directly is what pins the off-by-one that `contains`
    /// depends on, independent of `contains` itself.
    function indexPlusOneOf(address value) external view returns (uint256) {
        return _set.indexPlusOne[value];
    }

    /// One-call dump of every observable the state-machine checks need: both page directions, plus the
    /// sentinel value for a caller-chosen domain and for each stored element.
    function probe(address[] calldata domain) external view returns (SetProbe memory p) {
        (p.items, p.total) = _set.values(0, type(uint256).max, false);
        (p.reversed, p.reversedTotal) = _set.values(0, type(uint256).max, true);
        p.domainIndexPlusOne = new uint256[](domain.length);
        p.domainContains = new bool[](domain.length);
        for (uint256 i = 0; i < domain.length; i++) {
            p.domainIndexPlusOne[i] = _set.indexPlusOne[domain[i]];
            p.domainContains[i] = _set.contains(domain[i]);
        }
        p.itemIndexPlusOne = new uint256[](p.items.length);
        for (uint256 i = 0; i < p.items.length; i++) {
            p.itemIndexPlusOne[i] = _set.indexPlusOne[p.items[i]];
        }
    }
}

contract AddressSetTest {
    // ==================== Pinned behaviour ====================

    function testAddAndContains() external {
        AddressSetHarness harness = new AddressSetHarness();
        require(!harness.contains(_val(1)));
        require(harness.count() == 0);

        harness.add(_val(1));
        harness.add(_val(2));
        require(harness.contains(_val(1)));
        require(harness.contains(_val(2)));
        require(!harness.contains(_val(3)));
        require(harness.count() == 2);
    }

    function testAddDuplicateIsNoop() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(7));
        harness.add(_val(7));
        require(harness.count() == 1);
        // Idempotence is asserted on both representations, not only on `count`.
        require(harness.indexPlusOneOf(_val(7)) == 1);

        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(total == 1);
        require(page.length == 1);
        require(page[0] == _val(7));
    }

    function testRemoveAbsentIsNoop() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(1));
        harness.remove(_val(2));
        require(harness.count() == 1);
        require(harness.contains(_val(1)));
        require(harness.indexPlusOneOf(_val(2)) == 0);
        require(harness.indexPlusOneOf(_val(1)) == 1);
    }

    /// The `indexPlusOne` sentinel is `index + 1`; the element stored at slot 0 is the classic
    /// off-by-one trap because `index` alone would encode it as `0`, i.e. "absent".
    function testSentinelEncodingForSlotZero() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(42));
        require(harness.indexPlusOneOf(_val(42)) == 1, "slot 0 must encode as 1, never 0");
        require(harness.contains(_val(42)));
        require(harness.count() == 1);

        // Element 0 is a legal value and must not be confused with the "absent" sentinel.
        harness.add(_val(0));
        require(harness.indexPlusOneOf(_val(0)) == 2);
        require(harness.contains(_val(0)));
        require(harness.count() == 2);
    }

    // ==================== The six removal paths ====================
    // Each path asserts both representations step by step: the `items` array (through the full page)
    // and the `indexPlusOne` sentinel for every relevant value.

    function testRemoveTailKeepsPrefix() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(1));
        harness.add(_val(2));
        harness.remove(_val(2));
        require(harness.count() == 1);
        require(harness.contains(_val(1)));
        require(!harness.contains(_val(2)));
        require(harness.indexPlusOneOf(_val(1)) == 1);
        require(harness.indexPlusOneOf(_val(2)) == 0);

        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(total == 1);
        require(page.length == 1);
        require(page[0] == _val(1));
    }

    function testRemoveHeadSwapsTailIn() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(10));
        harness.add(_val(20));
        harness.add(_val(30));
        harness.remove(_val(10));
        require(harness.count() == 2);
        require(!harness.contains(_val(10)));

        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(total == 2);
        require(page.length == 2);
        require(page[0] == _val(30));
        require(page[1] == _val(20));
        // both representations agree after the move
        require(harness.indexPlusOneOf(_val(30)) == 1);
        require(harness.indexPlusOneOf(_val(20)) == 2);
        require(harness.indexPlusOneOf(_val(10)) == 0);

        harness.remove(_val(30));
        (page, total) = harness.values(0, 10, false);
        require(total == 1);
        require(page[0] == _val(20));
        require(harness.indexPlusOneOf(_val(20)) == 1);
        require(harness.indexPlusOneOf(_val(30)) == 0);
    }

    function testRemoveMiddleSwapsTailIn() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(10));
        harness.add(_val(20));
        harness.add(_val(30));
        harness.add(_val(40));
        harness.remove(_val(20)); // middle: 40 is swapped into slot 1
        require(harness.count() == 3);
        require(!harness.contains(_val(20)));

        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(total == 3);
        require(page.length == 3);
        require(page[0] == _val(10));
        require(page[1] == _val(40));
        require(page[2] == _val(30));
        require(harness.indexPlusOneOf(_val(10)) == 1);
        require(harness.indexPlusOneOf(_val(40)) == 2);
        require(harness.indexPlusOneOf(_val(30)) == 3);
        require(harness.indexPlusOneOf(_val(20)) == 0);

        // The moved element is still removable through its new slot.
        harness.remove(_val(40));
        (page, total) = harness.values(0, 10, false);
        require(total == 2);
        require(page[0] == _val(10));
        require(page[1] == _val(30));
        require(harness.indexPlusOneOf(_val(30)) == 2);
    }

    function testRemoveSoleElementClearsBoth() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(5));
        harness.remove(_val(5));
        require(harness.count() == 0);
        require(!harness.contains(_val(5)));
        require(harness.indexPlusOneOf(_val(5)) == 0);

        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(page.length == 0);
        require(total == 0);
    }

    function testDrainToEmptyStepByStep() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(1));
        harness.add(_val(2));
        harness.add(_val(3));
        harness.add(_val(4));

        harness.remove(_val(2));
        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(total == 3);
        require(page[0] == _val(1));
        require(page[1] == _val(4));
        require(page[2] == _val(3));
        require(harness.indexPlusOneOf(_val(4)) == 2);

        harness.remove(_val(1));
        (page, total) = harness.values(0, 10, false);
        require(total == 2);
        require(page[0] == _val(3));
        require(page[1] == _val(4));
        require(harness.indexPlusOneOf(_val(3)) == 1);
        require(harness.indexPlusOneOf(_val(4)) == 2);

        harness.remove(_val(4));
        (page, total) = harness.values(0, 10, false);
        require(total == 1);
        require(page[0] == _val(3));

        harness.remove(_val(3));
        (page, total) = harness.values(0, 10, false);
        require(total == 0);
        require(page.length == 0);
        require(harness.count() == 0);

        // removing again from empty is a no-op
        harness.remove(_val(3));
        require(harness.count() == 0);
        require(harness.indexPlusOneOf(_val(3)) == 0);
    }

    function testRemoveAllAndReAddReusesSlotZero() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(1));
        harness.add(_val(2));
        harness.remove(_val(1));
        harness.remove(_val(2));
        require(harness.count() == 0);

        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(page.length == 0);
        require(total == 0);

        harness.add(_val(2));
        require(harness.count() == 1);
        require(harness.contains(_val(2)));
        require(harness.indexPlusOneOf(_val(2)) == 1, "reused slot 0 encodes as 1");
        (page, total) = harness.values(0, 10, false);
        require(total == 1);
        require(page[0] == _val(2));
    }

    function testRemoveAbsentTwiceIsNoop() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(5));
        harness.remove(_val(5));
        harness.remove(_val(5));
        require(harness.count() == 0);
    }

    function testZeroAndMaxElement() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(0));
        harness.add(MAX_VAL);
        require(harness.contains(_val(0)));
        require(harness.contains(MAX_VAL));
        require(harness.count() == 2);
        require(harness.indexPlusOneOf(_val(0)) == 1);
        require(harness.indexPlusOneOf(MAX_VAL) == 2);

        harness.remove(_val(0));
        require(!harness.contains(_val(0)));
        require(harness.contains(MAX_VAL));
        require(harness.count() == 1);
        require(harness.indexPlusOneOf(_val(0)) == 0);
    }

    /// A swap whose moved element is `0`: the element value must not be confused with the "absent"
    /// marker (which is `indexPlusOne == 0`, not the element value `0`).
    function testSwapMovesZeroValue() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(MAX_VAL);
        harness.add(_val(0));
        harness.remove(MAX_VAL); // the last element (0) is swapped into slot 0

        require(harness.count() == 1);
        require(harness.contains(_val(0)));
        require(!harness.contains(MAX_VAL));
        require(harness.indexPlusOneOf(_val(0)) == 1);
        require(harness.indexPlusOneOf(MAX_VAL) == 0);

        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(total == 1);
        require(page.length == 1);
        require(page[0] == _val(0));
    }

    // ==================== Pagination windows ====================

    function testPaginationWindow() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(1));
        harness.add(_val(2));
        harness.add(_val(3));

        (address[] memory page, uint256 total) = harness.values(1, 5, false);
        require(total == 3);
        require(page.length == 2);
        require(page[0] == _val(2));
        require(page[1] == _val(3));

        (page, total) = harness.values(0, 2, true);
        require(page.length == 2);
        require(page[0] == _val(3));
        require(page[1] == _val(2));

        (page, total) = harness.values(3, 5, false);
        require(page.length == 0);
        require(total == 3);

        (page, total) = harness.values(9, 5, false);
        require(page.length == 0);
        require(total == 3);
    }

    function testPaginationLimitZeroReturnsTotalOnly() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(11));
        harness.add(_val(12));

        (address[] memory page, uint256 total) = harness.values(0, 0, false);
        require(page.length == 0);
        require(total == 2);
    }

    function testPaginationEmptySet() external {
        AddressSetHarness harness = new AddressSetHarness();
        (address[] memory page, uint256 total) = harness.values(0, 10, false);
        require(page.length == 0);
        require(total == 0);
    }

    /// Pins the accepted order contract: order is not stable across removals, so the same `offset`
    /// may return a different element afterwards. This is expected, not a defect.
    function testOffsetIsUnstableAcrossRemoval() external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(1));
        harness.add(_val(2));
        harness.add(_val(3));

        (address[] memory page, uint256 total) = harness.values(0, 1, false);
        require(total == 3);
        require(page[0] == _val(1), "before removal slot 0 holds the first insert");

        harness.remove(_val(1)); // tail (3) is swapped into slot 0
        (page, total) = harness.values(0, 1, false);
        require(total == 2, "total drops with the removal");
        require(page[0] == _val(3), "same offset now yields a different element");
    }

    // ==================== Properties ====================

    /// Element domain for the state-machine checks. It deliberately contains `0`, the value that the
    /// "absent" sentinel would collide with under an off-by-one.
    uint256 private constant DOMAIN = 16;
    /// Upper bound on the number of operations per state-machine run.
    uint256 private constant MAX_STEPS = 24;
    /// Full-width address used by the extreme-element tests.
    address private constant MAX_VAL = address(uint160(type(uint256).max));

    /// Wrap a raw word into the element domain.
    function _val(uint256 v) private pure returns (address) {
        return address(uint160(v));
    }

    /// Cheap deterministic PRNG; the point is reproducibility, not statistical quality.
    function _next(uint256 x) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(x)));
    }

    function _domain() private pure returns (address[] memory domain) {
        domain = new address[](DOMAIN);
        for (uint256 i = 0; i < DOMAIN; i++) {
            domain[i] = _val(i);
        }
    }

    // --- deliberately naive reference model: fixed-capacity flat array + linear scan ---
    // It allocates nothing inside the fuzz loops (no `new`), so the lint loop-context analysis stays
    // quiet while the model stays intentionally dumb and shares no logic with the library.

    function _modelIndexOf(address[] memory model, uint256 len, address value) private pure returns (uint256) {
        for (uint256 i = 0; i < len; i++) {
            if (model[i] == value) return i;
        }
        return type(uint256).max;
    }

    function _modelContains(address[] memory model, uint256 len, address value) private pure returns (bool) {
        return _modelIndexOf(model, len, value) != type(uint256).max;
    }

    function _modelAdd(address[] memory model, uint256 len, address value) private pure returns (uint256) {
        if (_modelContains(model, len, value)) return len;
        model[len] = value;
        return len + 1;
    }

    function _modelRemove(address[] memory model, uint256 len, address value) private pure returns (uint256) {
        uint256 idx = _modelIndexOf(model, len, value);
        if (idx == type(uint256).max) return len;
        for (uint256 i = idx; i + 1 < len; i++) {
            model[i] = model[i + 1];
        }
        return len - 1;
    }

    /// Pure, allocation-free representation check so it can be called from inside a fuzz loop:
    /// the page covers every element, `indexPlusOne[items[i]] == i + 1`, membership agrees with the
    /// model, and nothing outside the inserted domain is set.
    function _representationOk(SetProbe memory p, address[] memory model, uint256 modelLen)
        private
        pure
        returns (bool ok)
    {
        ok = p.total == modelLen && p.items.length == modelLen;
        for (uint256 i = 0; i < p.items.length; i++) {
            if (p.itemIndexPlusOne[i] != i + 1) ok = false;
        }
        for (uint256 i = 0; i < DOMAIN; i++) {
            bool inModel = _modelContains(model, modelLen, _val(i));
            if (p.domainContains[i] != inModel) ok = false;
            if ((p.domainIndexPlusOne[i] != 0) != inModel) ok = false;
        }
    }

    /// Pure, allocation-free set-equality check against the model, covering both page directions.
    function _contentOk(SetProbe memory p, address[] memory model, uint256 modelLen)
        private
        pure
        returns (bool ok)
    {
        ok = p.total == modelLen && p.items.length == modelLen && p.reversedTotal == modelLen
            && p.reversed.length == modelLen && p.itemIndexPlusOne.length == p.items.length;
        for (uint256 i = 0; i < p.items.length; i++) {
            if (!_modelContains(model, modelLen, p.items[i])) ok = false;
        }
        for (uint256 i = 0; i < p.reversed.length; i++) {
            if (!_modelContains(model, modelLen, p.reversed[i])) ok = false;
        }
        for (uint256 i = 0; i < DOMAIN; i++) {
            bool inModel = _modelContains(model, modelLen, _val(i));
            if (p.domainContains[i] != inModel) ok = false;
            if ((p.domainIndexPlusOne[i] != 0) != inModel) ok = false;
        }
    }

    /// State machine: a random add/remove walk must keep every invariant after every single step.
    /// The failure flag is accumulated across steps (no `require` inside the loop) and asserted once.
    /// 1000 runs because each run walks a long sequence, not a single call.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_StateMachineInvariants(uint256 seed, uint8 rawSteps) external {
        uint256 steps = (uint256(rawSteps) % MAX_STEPS) + 1;
        AddressSetHarness harness = new AddressSetHarness();
        address[] memory domain = _domain();
        address[] memory model = new address[](DOMAIN);
        uint256 modelLen = 0;
        uint256 rng = seed;
        bool ok = true;

        for (uint256 s = 0; s < steps; s++) {
            rng = _next(rng);
            address value = _val(rng % DOMAIN);
            rng = _next(rng);
            if (rng % 2 == 0) {
                // forge-lint: disable-next-line(calls-loop)
                harness.add(value);
                modelLen = _modelAdd(model, modelLen, value);
            } else {
                // forge-lint: disable-next-line(calls-loop)
                harness.remove(value);
                modelLen = _modelRemove(model, modelLen, value);
            }

            SetProbe memory p = harness.probe(domain); // forge-lint: disable-line(calls-loop)
            if (!_representationOk(p, model, modelLen)) {
                ok = false;
            }
        }

        require(ok, "state-machine invariant violated");
    }

    /// Differential test against the naive model: a randomly driven add/remove walk must match the
    /// model's membership and content after every step, in both page directions.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_DifferentialAgainstNaiveModel(uint256 seed, uint8 rawSteps) external {
        uint256 steps = (uint256(rawSteps) % MAX_STEPS) + 1;
        AddressSetHarness harness = new AddressSetHarness();
        address[] memory domain = _domain();
        address[] memory model = new address[](DOMAIN);
        uint256 modelLen = 0;
        uint256 rng = seed;
        bool ok = true;

        for (uint256 s = 0; s < steps; s++) {
            rng = _next(rng);
            address value = _val(rng % DOMAIN);
            rng = _next(rng);
            if (rng % 2 == 0) {
                // forge-lint: disable-next-line(calls-loop)
                harness.add(value);
                modelLen = _modelAdd(model, modelLen, value);
            } else {
                // forge-lint: disable-next-line(calls-loop)
                harness.remove(value);
                modelLen = _modelRemove(model, modelLen, value);
            }

            SetProbe memory p = harness.probe(domain); // forge-lint: disable-line(calls-loop)
            if (!_contentOk(p, model, modelLen)) {
                ok = false;
            }
        }

        require(ok, "differential check against the naive model failed");
    }

    /// Arbitrary full-width values, including `0` and `type(uint160).max` on the fuzz paths.
    function testFuzz_AddRemoveArbitraryValue(uint160 raw) external {
        AddressSetHarness harness = new AddressSetHarness();
        address value = address(raw);

        harness.add(value);
        require(harness.contains(value), "inserted value is present");
        require(harness.indexPlusOneOf(value) == 1, "first insert lands in slot 0");
        require(harness.count() == 1);

        harness.add(value); // duplicate must not move or duplicate the slot
        require(harness.indexPlusOneOf(value) == 1);
        require(harness.count() == 1);

        harness.remove(value);
        require(!harness.contains(value));
        require(harness.indexPlusOneOf(value) == 0);
        require(harness.count() == 0);

        harness.remove(value); // already gone
        require(harness.count() == 0);
    }

    /// The whole window contract, checked against a size computed by counting positions instead of
    /// restating the library branching, in both directions.
    function testFuzz_PaginationWindowMatchesModel(uint256 offsetRaw, uint256 limitRaw, bool reverse) external {
        AddressSetHarness harness = new AddressSetHarness();
        uint256 count = 7;
        for (uint256 i = 0; i < count; i++) {
            // forge-lint: disable-next-line(calls-loop)
            harness.add(_val(i * 3 + 1));
        }

        uint256 offset = offsetRaw % (count + 3);
        uint256 limit = limitRaw % (count + 3);

        uint256 expectedSize = 0;
        for (uint256 i = 0; i < count; i++) {
            if (i >= offset && i - offset < limit) expectedSize++;
        }

        (address[] memory page, uint256 total) = harness.values(offset, limit, reverse);
        require(total == count, "total is the collection size");
        require(page.length == expectedSize, "window size matches the counted range");

        bool slotsHold = true;
        for (uint256 i = 0; i < page.length; i++) {
            uint256 slot = reverse ? (count - 1 - offset - i) : (offset + i);
            if (page[i] != _val(slot * 3 + 1)) slotsHold = false;
        }
        require(slotsHold, "page entry is the element at that slot");
    }

    /// Extreme windows must stay non-reverting and still report the real total.
    function testFuzz_ExtremeWindows(uint256 offsetRaw, bool reverse) external {
        AddressSetHarness harness = new AddressSetHarness();
        harness.add(_val(5));
        harness.add(_val(6));
        harness.add(_val(7));

        uint256 offset = offsetRaw % 5;
        (address[] memory page, uint256 total) = harness.values(offset, type(uint256).max, reverse);
        require(total == 3);
        uint256 expected = offset >= 3 ? 0 : 3 - offset;
        require(page.length == expected, "oversized limit returns the remainder");

        (page, total) = harness.values(type(uint256).max, type(uint256).max, reverse);
        require(total == 3 && page.length == 0, "offset past the end is an empty page");
    }
}
