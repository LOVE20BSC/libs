// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Pagination} from "../src/Pagination.sol";

contract PaginationHarness {
    using Pagination for uint256[];
    using Pagination for address[];

    uint256[] private _values;
    address[] private _addresses;

    // The harness data encodes positions: index i holds the value i*10 and the address i+1, so a page
    // can be verified against the positions it selected instead of against another copy of the formula.
    function fill(uint256 count) external {
        for (uint256 i = 0; i < count; i++) {
            _values.push(i * 10);
            // Harness addresses only; every page walked below stays far below 2**160.
            // forge-lint: disable-next-line(unsafe-typecast)
            _addresses.push(address(uint160(i + 1)));
        }
    }

    function valueCount() external view returns (uint256) {
        return _values.length;
    }

    function addressCount() external view returns (uint256) {
        return _addresses.length;
    }

    function indicesPage(uint256 total, uint256 offset, uint256 limit, bool reverse)
        external
        pure
        returns (uint256[] memory indices)
    {
        return Pagination.paginateIndices(total, offset, limit, reverse);
    }

    function valuePage(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (uint256[] memory result, uint256 total)
    {
        return _values.paginate(offset, limit, reverse);
    }

    function addressPage(uint256 offset, uint256 limit, bool reverse)
        external
        view
        returns (address[] memory result, uint256 total)
    {
        return _addresses.paginate(offset, limit, reverse);
    }
}

contract PaginationTest {
    /// Largest collection the property tests build; keeps each fuzz run within a single block's gas.
    uint256 private constant MAX_COUNT = 64;

    function _filled(uint256 count) private returns (PaginationHarness) {
        PaginationHarness harness = new PaginationHarness();
        harness.fill(count);
        return harness;
    }

    /// Size of the requested window, recomputed by counting the positions that fall inside both the
    /// collection and the half-open range [offset, offset + limit). Deliberately not a restatement of the
    /// library's branching, so a mistake inside the library cannot be mirrored here.
    function _windowSize(uint256 count, uint256 offset, uint256 limit) private pure returns (uint256 size) {
        for (uint256 i = 0; i < count; i++) {
            if (i >= offset && i - offset < limit) {
                size++;
            }
        }
    }

    // ==================== Pinned windows ====================
    // Exact expectations, written out so the window semantics are readable without running the code.

    function testEmptyCollectionReturnsEmptyPageAndZeroTotal() external {
        PaginationHarness harness = new PaginationHarness();
        (uint256[] memory values, uint256 total) = harness.valuePage(0, 5, false);
        require(total == 0 && values.length == 0);

        (values, total) = harness.valuePage(0, 5, true);
        require(total == 0 && values.length == 0);

        (address[] memory addresses, uint256 addressTotal) = harness.addressPage(0, 5, true);
        require(addressTotal == 0 && addresses.length == 0);

        uint256[] memory indices = harness.indicesPage(0, 0, 5, false);
        require(indices.length == 0);
    }

    function testLimitZeroReadsTotalOnly() external {
        PaginationHarness harness = _filled(7);
        (uint256[] memory values, uint256 total) = harness.valuePage(0, 0, false);
        require(total == 7 && values.length == 0);

        (values, total) = harness.valuePage(5, 0, true);
        require(total == 7 && values.length == 0);

        // An offset past the end is the other "no data" case: same empty page, same real total.
        (values, total) = harness.valuePage(7, 10, false);
        require(total == 7 && values.length == 0);

        (address[] memory addresses, uint256 addressTotal) = harness.addressPage(9, 3, true);
        require(addressTotal == 7 && addresses.length == 0);
    }

    function testOffsetIsCountedFromTheOldestEnd() external {
        PaginationHarness harness = _filled(6);
        (uint256[] memory values, uint256 total) = harness.valuePage(2, 3, false);
        require(total == 6);
        require(values.length == 3);
        require(values[0] == 20 && values[1] == 30 && values[2] == 40);
    }

    function testReverseStartsFromTheNewestEnd() external {
        PaginationHarness harness = _filled(6);
        (uint256[] memory values, uint256 total) = harness.valuePage(0, 3, true);
        require(total == 6);
        require(values.length == 3);
        require(values[0] == 50 && values[1] == 40 && values[2] == 30);
    }

    function testOffsetIsSkippedFromTheEndTheReadingStarts() external {
        PaginationHarness harness = _filled(5);
        // Forward reads start at the oldest end, so offset 1 drops value 0 and keeps 10..40.
        (uint256[] memory forward, uint256 forwardTotal) = harness.valuePage(1, 10, false);
        require(forwardTotal == 5);
        require(forward.length == 4);
        require(forward[0] == 10 && forward[1] == 20 && forward[2] == 30 && forward[3] == 40);

        // Reverse reads start at the newest end, so the same offset drops value 40 instead.
        (uint256[] memory reverse, uint256 reverseTotal) = harness.valuePage(1, 10, true);
        require(reverseTotal == 5);
        require(reverse.length == 4);
        require(reverse[0] == 30 && reverse[1] == 20 && reverse[2] == 10 && reverse[3] == 0);
    }

    function testLimitAboveRemainingIsClamped() external {
        PaginationHarness harness = _filled(4);
        (uint256[] memory values, uint256 total) = harness.valuePage(2, 100, false);
        require(total == 4);
        require(values.length == 2);
        require(values[0] == 20 && values[1] == 30);

        (address[] memory addresses, uint256 addressTotal) = harness.addressPage(3, 99, true);
        require(addressTotal == 4);
        // Reversed reading counts the skipped items from its own start, so offset 3 skips the newest three.
        require(addresses.length == 1);
        require(addresses[0] == address(uint160(1)));
    }

    function testSingleItemCollectionNeverUnderflows() external {
        PaginationHarness harness = _filled(1);
        (uint256[] memory values, uint256 total) = harness.valuePage(0, 5, true);
        require(total == 1);
        require(values.length == 1);
        require(values[0] == 0);

        (values, total) = harness.valuePage(0, 1, false);
        require(total == 1);
        require(values[0] == 0);
    }

    function testAddressOverloadReturnsTheSameWindow() external {
        PaginationHarness harness = _filled(5);
        (address[] memory forward, uint256 forwardTotal) = harness.addressPage(1, 3, false);
        require(forwardTotal == 5);
        require(forward.length == 3);
        require(forward[0] == address(uint160(2)));
        require(forward[1] == address(uint160(3)));
        require(forward[2] == address(uint160(4)));

        (address[] memory reverse, uint256 reverseTotal) = harness.addressPage(0, 5, true);
        require(reverseTotal == 5);
        require(reverse.length == 5);
        require(reverse[0] == address(uint160(5)));
        require(reverse[4] == address(uint160(1)));
    }

    function testExtremeInputsStayNonReverting() external {
        PaginationHarness harness = _filled(3);
        // An enormous offset is just past the end; an enormous limit is clamped to what remains.
        (uint256[] memory values, uint256 total) = harness.valuePage(type(uint256).max, type(uint256).max, false);
        require(total == 3 && values.length == 0);

        (values, total) = harness.valuePage(0, type(uint256).max, true);
        require(total == 3 && values.length == 3);
        require(values[0] == 20 && values[1] == 10 && values[2] == 0);

        uint256[] memory indices = harness.indicesPage(3, type(uint256).max, type(uint256).max, true);
        require(indices.length == 0);

        indices = harness.indicesPage(3, 2, type(uint256).max, false);
        require(indices.length == 1 && indices[0] == 2);
    }

    function testRepeatedReadsAreIdenticalAndDoNotMutate() external {
        PaginationHarness harness = _filled(5);
        (uint256[] memory first, uint256 firstTotal) = harness.valuePage(1, 2, true);
        (uint256[] memory second, uint256 secondTotal) = harness.valuePage(1, 2, true);
        require(firstTotal == secondTotal && firstTotal == 5);
        require(first.length == second.length && first[0] == second[0] && first[1] == second[1]);
        require(harness.valueCount() == 5);
        require(harness.addressCount() == 5);
    }

    // ==================== Properties ====================
    // Invariants that must hold for every window, not just the pinned ones.

    function testFuzz_WindowIsTheRequestedRange(uint256 countRaw, uint256 offsetRaw, uint256 limitRaw, bool reverse)
        external
    {
        uint256 count = countRaw % (MAX_COUNT + 1);
        uint256 offset = offsetRaw % (count + 6);
        uint256 limit = limitRaw % (count + 4);
        uint256 size = _windowSize(count, offset, limit);
        PaginationHarness harness = _filled(count);

        (uint256[] memory values, uint256 valueTotal) = harness.valuePage(offset, limit, reverse);
        require(valueTotal == count, "total is the collection size");
        require(values.length == size, "value page selects the requested range");

        (address[] memory addresses, uint256 addressTotal) = harness.addressPage(offset, limit, reverse);
        require(addressTotal == count, "total is the collection size");
        require(addresses.length == size, "address page selects the requested range");

        uint256[] memory indices = harness.indicesPage(count, offset, limit, reverse);
        require(indices.length == size, "index page selects the requested range");
    }

    function testFuzz_PageFollowsDirectionWithoutRepeats(uint256 countRaw, uint256 offsetRaw, uint256 limitRaw, bool reverse)
        external
    {
        uint256 count = countRaw % (MAX_COUNT + 1);
        uint256 offset = offsetRaw % (count + 6);
        uint256 limit = limitRaw % (count + 4);
        PaginationHarness harness = _filled(count);

        (uint256[] memory values, uint256 total) = harness.valuePage(offset, limit, reverse);
        require(total == count, "total is the collection size");
        bool ordered = true;
        for (uint256 i = 1; i < values.length; i++) {
            uint256 step = reverse ? (values[i] + 10) : (values[i - 1] + 10);
            uint256 next = reverse ? values[i - 1] : values[i];
            if (step != next) {
                ordered = false;
            }
        }
        require(ordered, "consecutive page entries step by one position in the requested direction");
    }

    function testFuzz_BothOverloadsFollowPaginateIndices(
        uint256 countRaw,
        uint256 offsetRaw,
        uint256 limitRaw,
        bool reverse
    ) external {
        uint256 count = countRaw % (MAX_COUNT + 1);
        uint256 offset = offsetRaw % (count + 6);
        uint256 limit = limitRaw % (count + 4);
        PaginationHarness harness = _filled(count);

        uint256[] memory indices = harness.indicesPage(count, offset, limit, reverse);
        (uint256[] memory values, uint256 valueTotal) = harness.valuePage(offset, limit, reverse);
        (address[] memory addresses, uint256 addressTotal) = harness.addressPage(offset, limit, reverse);
        require(valueTotal == count && addressTotal == count, "total is the collection size");
        require(values.length == indices.length && addresses.length == indices.length);

        bool consistent = true;
        for (uint256 i = 0; i < indices.length; i++) {
            if (values[i] != indices[i] * 10) {
                consistent = false;
            }
            // Positions come from the same bounded harness that built them, so the cast cannot truncate.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (addresses[i] != address(uint160(indices[i] + 1))) {
                consistent = false;
            }
        }
        require(consistent, "typed overloads read exactly the positions the index entry returned");
    }

    function testFuzz_ConsecutivePagesCoverEverythingOnce(uint256 countRaw, uint256 limitRaw, bool reverse) external {
        uint256 count = countRaw % (MAX_COUNT + 1);
        uint256 limit = limitRaw % 8 + 1;
        PaginationHarness harness = _filled(count);

        // Enough rounds to walk past the end: the last one must come back empty.
        uint256 rounds = count / limit + 2;
        bool totalsHold = true;
        bool sequential = true;
        uint256 seen = 0;
        for (uint256 round = 0; round < rounds; round++) {
            // forge-lint: disable-next-line(calls-loop)
            (uint256[] memory values, uint256 total) = harness.valuePage(round * limit, limit, reverse);
            if (total != count) {
                totalsHold = false;
            }
            for (uint256 i = 0; i < values.length; i++) {
                uint256 position = reverse ? (count - 1 - seen - i) : (seen + i);
                if (values[i] != position * 10) {
                    sequential = false;
                }
            }
            seen += values.length;
        }

        require(totalsHold, "every page reports the same total");
        require(sequential, "pages continue the walk without gaps or repeats");
        require(seen == count, "walking pages covers each position exactly once");

        (uint256[] memory tail, uint256 tailTotal) = harness.valuePage(rounds * limit, limit, reverse);
        require(tailTotal == count && tail.length == 0, "past the end is always an empty page");
    }

    function testFuzz_LimitAboveTheCollectionReturnsItWhole(uint256 countRaw, bool reverse) external {
        uint256 count = countRaw % (MAX_COUNT + 1);
        PaginationHarness harness = _filled(count);

        (uint256[] memory values, uint256 total) = harness.valuePage(0, MAX_COUNT + 1, reverse);
        require(total == count);
        require(values.length == count);

        bool complete = true;
        for (uint256 i = 0; i < count; i++) {
            uint256 position = reverse ? (count - 1 - i) : i;
            if (values[i] != position * 10) {
                complete = false;
            }
        }
        require(complete, "one oversized page returns the whole collection");
    }

    function testFuzz_EmptyCollectionsIgnoreTheWindow(uint256 offsetRaw, uint256 limitRaw, bool reverse) external {
        uint256 offset = offsetRaw;
        uint256 limit = limitRaw;
        PaginationHarness harness = new PaginationHarness();

        (uint256[] memory values, uint256 total) = harness.valuePage(offset, limit, reverse);
        require(total == 0 && values.length == 0);

        (address[] memory addresses, uint256 addressTotal) = harness.addressPage(offset, limit, reverse);
        require(addressTotal == 0 && addresses.length == 0);

        uint256[] memory indices = harness.indicesPage(0, offset, limit, reverse);
        require(indices.length == 0);
    }
}
