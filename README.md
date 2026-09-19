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

## Design

All `RoundHistory*` libraries share the same core pattern:
1. Use `OrderedHistoryIndex` for managing the ordered round keys
2. Store typed values in a `mapping(uint256 => T)`
3. Query logic: exact match (fast path) or binary search via `nearest()` (slow path)

This design eliminates code duplication—the index management logic exists once in `OrderedHistoryIndex`, and each history type only adds the value storage and type-specific operations.
