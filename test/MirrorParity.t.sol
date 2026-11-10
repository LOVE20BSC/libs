// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

import {Uint256Set} from "../src/Uint256Set.sol";
import {AddressSet} from "../src/AddressSet.sol";

// `AddressSet` is a deliberate mirror of `Uint256Set`, and the README makes keeping them
// behaviourally identical a maintenance obligation. Nothing enforced that: the two suites are
// written independently, so a one-sided change to the sentinel, the swap-and-pop removal or the
// pagination window could land green. These harnesses let one scripted and one fuzzed operation
// sequence run through both libraries at once, with `uint256 v` paired to `address(uint160(v))`.

contract Uint256SetProbe {
    using Uint256Set for Uint256Set.Storage;

    Uint256Set.Storage private _set;

    function add(uint256 value) external returns (bool) {
        return _set.add(value);
    }

    function remove(uint256 value) external returns (bool) {
        return _set.remove(value);
    }

    function clear() external {
        _set.clear();
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
}

contract AddressSetProbe {
    using AddressSet for AddressSet.Storage;

    AddressSet.Storage private _set;

    function add(address value) external returns (bool) {
        return _set.add(value);
    }

    function remove(address value) external returns (bool) {
        return _set.remove(value);
    }

    function clear() external {
        _set.clear();
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
}

contract MirrorParityTest {
    /// Elements are drawn from a small domain so both types represent them exactly, and `0` is
    /// included because it is the value the sentinel encoding is most likely to mishandle.
    uint256 private constant DOMAIN = 8;

    function testScriptedSequenceStaysInStep() external {
        (Uint256SetProbe u, AddressSetProbe a) = _fresh();

        uint256[6] memory added = [uint256(0), 1, 2, 3, 4, 5];
        for (uint256 i = 0; i < added.length; i++) {
            _assertAddInStep(u, a, added[i]);
            _assertInStep(u, a);
        }

        // Removal order walks every swap-and-pop branch: last, sole, middle, absent.
        uint256[4] memory removed = [uint256(5), 3, 0, 7];
        for (uint256 i = 0; i < removed.length; i++) {
            _assertRemoveInStep(u, a, removed[i]);
            _assertInStep(u, a);
        }

        // Re-adding a drained element must reuse the same slot in both.
        _assertAddInStep(u, a, 3);
        _assertInStep(u, a);

        u.clear();
        a.clear();
        _assertInStep(u, a);
    }

    function testFuzz_OperationsStayInStep(uint256 seed) external {
        (Uint256SetProbe u, AddressSetProbe a) = _fresh();

        for (uint256 i = 0; i < 24; i++) {
            uint256 value = uint256(keccak256(abi.encode(seed, i))) % DOMAIN;
            bool grow = (uint256(keccak256(abi.encode(seed, i, "grow"))) & 1) == 1;
            if (grow) {
                _assertAddInStep(u, a, value);
            } else {
                _assertRemoveInStep(u, a, value);
            }
            _assertInStep(u, a);
        }
    }

    /// Values the byte-sized `DOMAIN` never reaches: both ends of the address range, and a set that
    /// grows past `DOMAIN`, so a drift that only appears above 8 elements is still caught.
    function testWideValuesStayInStep() external {
        (Uint256SetProbe u, AddressSetProbe a) = _fresh();

        uint256[6] memory wide = [uint256(0), 255, 256, 65535, type(uint160).max - 1, type(uint160).max];
        for (uint256 i = 0; i < wide.length; i++) {
            _assertAddInStep(u, a, wide[i]);
            _assertInStep(u, a);
        }

        for (uint256 i = 0; i < 12; i++) {
            _assertAddInStep(u, a, 1000 + i);
        }
        _assertInStep(u, a);

        // Draining is where the sentinel encoding is most exposed.
        for (uint256 i = 0; i < wide.length; i++) {
            _assertRemoveInStep(u, a, wide[i]);
            _assertInStep(u, a);
        }
    }

    function _fresh() private returns (Uint256SetProbe u, AddressSetProbe a) {
        u = new Uint256SetProbe();
        a = new AddressSetProbe();
        _assertInStep(u, a);
    }

    function _assertAddInStep(Uint256SetProbe u, AddressSetProbe a, uint256 value) private {
        require(u.add(value) == a.add(_asAddress(value)), "add return diverged");
    }

    function _assertRemoveInStep(Uint256SetProbe u, AddressSetProbe a, uint256 value) private {
        require(u.remove(value) == a.remove(_asAddress(value)), "remove return diverged");
    }

    /// Compares every observable both libraries expose, after each single operation, so a divergence
    /// is reported at the operation that introduced it rather than at the end of the sequence.
    function _assertInStep(Uint256SetProbe u, AddressSetProbe a) private view {
        uint256 total = u.count();
        require(total == a.count(), "count diverged");

        for (uint256 i = 0; i < DOMAIN; i++) {
            require(u.contains(i) == a.contains(_asAddress(i)), "contains diverged");
        }

        // Offset and limit are as much part of the window contract as the direction, and a drift in
        // either stays invisible if every read pins offset to 0 and limit to max. Sweep the windows a
        // consumer actually passes, in both directions, including both edges.
        _assertWindowInStep(u, a, 0, type(uint256).max, false);
        _assertWindowInStep(u, a, 0, type(uint256).max, true);
        _assertWindowInStep(u, a, 1, type(uint256).max, false);
        _assertWindowInStep(u, a, 1, type(uint256).max, true);
        _assertWindowInStep(u, a, 0, 2, false);
        _assertWindowInStep(u, a, 0, 2, true);
        _assertWindowInStep(u, a, 2, 3, false);
        _assertWindowInStep(u, a, 2, 3, true);
        _assertWindowInStep(u, a, 0, 0, false);
        _assertWindowInStep(u, a, total, 4, false);
        _assertWindowInStep(u, a, total, 4, true);
        _assertWindowInStep(u, a, total + 1, 4, true);
    }

    /// Compares a single window, in one direction, across both libraries.
    function _assertWindowInStep(Uint256SetProbe u, AddressSetProbe a, uint256 offset, uint256 limit, bool reverse)
        private
        view
    {
        (uint256[] memory page, uint256 total) = u.values(offset, limit, reverse);
        (address[] memory mirrorPage, uint256 mirrorTotal) = a.values(offset, limit, reverse);
        require(total == mirrorTotal, "window total diverged");
        require(page.length == mirrorPage.length, "window size diverged");
        for (uint256 i = 0; i < page.length; i++) {
            require(_asAddress(page[i]) == mirrorPage[i], "window entry diverged");
        }
    }

    function _asAddress(uint256 value) private pure returns (address) {
        return address(uint160(value));
    }
}
