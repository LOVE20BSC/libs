# Shared Solidity libraries

## OrderedHistoryIndex

`OrderedHistoryIndex` stores ordered change-point keys. New keys must increase; re-recording the latest key is allowed, while older keys revert. Values remain in the consuming contract's typed storage.

**API:**
- `record(uint256 key)` - Record a new key (must be >= last key)
- `contains(uint256 key)` - Check if a key was recorded
- `nearest(uint256 key)` - Find the largest recorded key <= target
- `latest()` - Get the most recent key

## Pagination

Shared pagination window used by every collection getter. A page is described by `(uint256 offset, uint256 limit, bool reverse)` and returned together with the real total count.

**Window semantics:**
- `offset` skips entries from the end the reading starts at: a forward page skips the oldest entries, a reversed page skips the newest ones — the same `offset` trims opposite ends under the two directions. An `offset` past the end returns an empty page and the real total count, never a revert.
- `limit` above the remaining items returns the remainder.
- `limit = 0` returns an empty page; this is how callers read the total count when there is no separate counter getter.
- `reverse = true` walks from the newest item backwards.

**API:**
- `paginateIndices(uint256 total, uint256 offset, uint256 limit, bool reverse)` - Source indices only; the caller reads whatever it needs from them. Use this when the element type is not `uint256`/`address` (structs, parallel arrays, extracted fields).
- `paginate(uint256[] storage items, uint256 offset, uint256 limit, bool reverse)` - Page of a `uint256[]` storage array.
- `paginate(address[] storage items, uint256 offset, uint256 limit, bool reverse)` - Page of an `address[]` storage array.

The two `paginate` overloads return `(page, total)`; the window math lives once in the private helpers, so the different element types only differ in what they copy out.

## Uint256Set

An unbounded set of `uint256` values with O(1) membership, deduplicated on insert. Removal is swap-and-pop: the last element is moved into the removed slot, so **the order of `items` is not stable across calls** — the same `offset` may return different elements after a removal, and `reverse` means "walk the current storage order backwards", not "newest insert first". Enumeration goes through `Pagination` only: there is no whole-set getter and no `AtIndex` accessor. `contains` and `count` are O(1) point lookups rather than a second enumeration path; `count` returns the same total that `values` reports.

Membership and position share one mapping `indexPlusOne`, encoding `index + 1` so that `0` means "absent".

**API:**
- `add(uint256 value)` - Insert; no-op if already present
- `remove(uint256 value)` - Swap-and-pop removal; no-op if absent
- `contains(uint256 value)` - O(1) membership check
- `count()` - Number of elements
- `values(uint256 offset, uint256 limit, bool reverse)` - Paginated page and real total

## RoundHistory*

Complete history tracking systems built on top of `OrderedHistoryIndex`. Each type manages both the index and typed value storage.

### RoundHistoryUint256

Tracks `uint256` values across rounds with arithmetic operations.

**API:**
- `record(uint256 round, uint256 value)` - Record a value at a round
- `value(uint256 round)` - Get value at round (uses nearest if not exact)
- `latestValue()` - Get the most recent value
- `increase(uint256 round, uint256 amount)` - Add to current value
- `decrease(uint256 round, uint256 amount)` - Subtract from current value

### RoundHistoryString

Tracks `string` values across rounds.

**API:**
- `record(uint256 round, string value)` - Record a string at a round
- `value(uint256 round)` - Get string at round
- `latestValue()` - Get the most recent string

### RoundHistoryAddress

Tracks `address` values across rounds.

**API:**
- `record(uint256 round, address value)` - Record an address at a round
- `value(uint256 round)` - Get address at round
- `latestValue()` - Get the most recent address

### RoundHistoryUint256Set

Tracks a **set** of `uint256` values across rounds, replacing the legacy `RoundHistoryAddressSet` with `uint256` elements. Three histories are kept: the set size, `slot -> element`, and `element -> slot + 1` (`0` meaning "not in the set"). The current state is derived from these histories' `latestValue()`, so there is no second copy that could drift out of sync.

Writes require a non-decreasing `round` (same constraint as `RoundHistoryUint256`); re-recording the same round keeps only that round's final value. Removal is swap-and-pop, so the order guarantee matches `Uint256Set`: an `offset` is not stable across calls, and enumeration is paginated only (`contains`/`count` are O(1) reads of the latest recorded value; `containsByRound`/`countByRound` are point queries that are O(1) on an exact round hit and fall back to a binary search — O(log rounds) — otherwise; none of them is a second enumeration path).

**API:**
- `add(uint256 round, uint256 value)` - Insert; no-op if already present
- `remove(uint256 round, uint256 value)` - Swap-and-pop removal; no-op if absent
- `contains(uint256 value)` - Current membership
- `count()` - Current size
- `values(uint256 offset, uint256 limit, bool reverse)` - Paginated current page and real total
- `containsByRound(uint256 value, uint256 round)` - Membership as of a round; `false` before the first write
- `countByRound(uint256 round)` - Size as of a round; `0` before the first write
- `valuesByRound(uint256 round, uint256 offset, uint256 limit, bool reverse)` - Paginated page as of a round and its real total

## Design

All `RoundHistory*` libraries share the same core pattern:
1. Use `OrderedHistoryIndex` for managing the ordered round keys
2. Store typed values in a `mapping(uint256 => T)`
3. Query logic: exact match (fast path) or binary search via `nearest()` (slow path)

This design eliminates code duplication—the index management logic exists once in `OrderedHistoryIndex`, and each history type only adds the value storage and type-specific operations.

`RoundHistoryUint256Set` extends the same pattern to a set: the index histories are keyed by slot (`slotHistory`) and by element (`indexPlusOneHistory`), with `countHistory` holding the size. `latestValue()` is O(1) (it reads the last recorded key), so the current state needs no extra copy; only `value(round)` for a past round falls back to `nearest()`.

Collections here expose every enumeration through `Pagination` and never through a whole-set getter, matching the collection-read rule that a single collection keeps exactly one complete read path. Scalar `contains`/`count` are O(1) reads of the latest recorded value; their `*ByRound` forms are point queries that are O(1) on an exact round hit and O(log rounds) otherwise (`nearest()` binary search). None of them is a second enumeration path.
