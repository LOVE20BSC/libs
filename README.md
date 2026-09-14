# Shared Solidity libraries

## OrderedHistoryIndex

`OrderedHistoryIndex` stores ordered change-point keys. New keys must increase; re-recording the latest key is allowed, while older keys revert. Values remain in the consuming contract's typed storage.

**API:**
- `record(uint256 key)` - Record a new key (must be >= last key)
- `contains(uint256 key)` - Check if a key was recorded
- `nearest(uint256 key)` - Find the largest recorded key <= target
- `latest()` - Get the most recent key

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
