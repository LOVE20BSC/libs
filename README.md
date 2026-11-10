# Shared Solidity libraries

## OrderedHistoryIndex

`OrderedHistoryIndex` stores ordered change-point keys. New keys must increase; re-recording the latest key is allowed, while older keys revert. Values remain in the consuming contract's typed storage.

Because the index only appends, a key written *ahead* of the current round moves the tip immediately and cannot be undone: every later write at a key below it reverts with `InvalidKeyOrder`, so the rounds in between can never be recorded, and `latest()` — hence every `latestValue()` derived from it — already reports the future key's value. Writers must therefore take the key from one monotonically non-decreasing source; "greater than the last key" is not a sufficient test. The constraint is not enforceable by the library, since it depends on what the caller's round means.

`nearest` and `latest` return `(bool found, uint256 key)`. `found = false` means no recorded key satisfies the query — an empty index, or a target below the first key.

That flag stops at the index. The typed histories discard it and return the type's default (`0`, `address(0)`, `""`, empty array) both for "no record at or before this round" and for a recorded default value, so **the two cases are not distinguishable through `RoundHistory*.value` / `values`**. Reading `value(round) == 0` as "no record" is therefore wrong: it also fires for a legitimately recorded zero and for every later round that inherits one. A caller that needs the distinction must ask the index itself (`OrderedHistoryIndex.contains` / `nearest` on the same `History`) instead of inferring it from the returned value.

**API:**
- `record(uint256 key)` - Record a new key (must be >= last key; older keys revert with `InvalidKeyOrder`)
- `contains(uint256 key)` - Check if a key was recorded
- `nearest(uint256 key)` - Largest recorded key <= target, plus a `found` flag
- `latest()` - Most recent key, plus a `found` flag

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
- `pageCount(uint256 total, uint256 offset, uint256 limit)` - Window size only; the shared math behind every page helper, for callers that only need the count.
- `pageIndex(uint256 total, uint256 offset, uint256 i, bool reverse)` - Position of the `i`-th entry in the requested window; the shared index math. Precondition: `i < pageCount(total, offset, limit)`. The page helpers always satisfy it, but a direct caller that passes `i` past the window underflows in the reverse direction (`Panic(0x11)`) instead of clamping.

The two `paginate` overloads return `(page, total)`; the window math lives once in `pageCount`/`pageIndex`, so the different element types only differ in what they copy out.

## Uint256Set

An unbounded set of `uint256` values with O(1) membership, deduplicated on insert. Removal is swap-and-pop: the last element is moved into the removed slot, so **the order of `items` is not stable across calls** — the same `offset` may return different elements after a removal, and `reverse` means "walk the current storage order backwards", not "newest insert first". Enumeration goes through `Pagination` only: there is no whole-set getter and no `AtIndex` accessor. `contains` and `count` are O(1) point lookups rather than a second enumeration path; `count` returns the same total that `values` reports.

Membership and position share one mapping `indexPlusOne`, encoding `index + 1` so that `0` means "absent".

**API:**
- `add(uint256 value)` - Insert; returns whether the element was actually inserted (`false` when already present, no state change)
- `remove(uint256 value)` - Swap-and-pop removal; returns whether the element was actually removed (`false` when absent, no state change, no revert)
- `contains(uint256 value)` - O(1) membership check
- `count()` - Number of elements
- `clear()` - Remove every element; the only correct way to empty the set (see below)
- `values(uint256 offset, uint256 limit, bool reverse)` - Paginated page and real total

`clear()` exists because the storage struct cannot be reset with `delete`: in Solidity `delete` empties the dynamic array but leaves the `indexPlusOne` mapping untouched, which desynchronises the two representations — `count()` reads zero while `contains()` still answers `true`, and a later `remove` of a stale element underflows. `clear()` walks `items` and deletes each entry before emptying the array.

The two `bool` returns are the set's idempotence signal: group-chat's member list and ban list write through `listed ? set.add(id) : set.remove(id)` and emit their event only when that returns `true`, rather than testing membership beforehand. `add` always leaves the element present, so the return answers "did this call change the set", not "did it succeed".

## AddressSet

The `address`-keyed sibling of `Uint256Set`: same sentinel encoding, same swap-and-pop removal, same pagination-only enumeration. An unbounded set of `address` values with O(1) membership, deduplicated on insert. Removal is swap-and-pop: the last element is moved into the removed slot, so **the order of `items` is not stable across calls** — the same `offset` may return different elements after a removal, and `reverse` means "walk the current storage order backwards", not "newest insert first". Enumeration goes through `Pagination` only: there is no whole-set getter and no `AtIndex` accessor. `contains` and `count` are O(1) point lookups rather than a second enumeration path; `count` returns the same total that `values` reports.

Membership and position share one mapping `indexPlusOne`, encoding `index + 1` so that `0` means "absent".

**API:**
- `add(address value)` - Insert; returns whether the element was actually inserted (`false` when already present, no state change)
- `remove(address value)` - Swap-and-pop removal; returns whether the element was actually removed (`false` when absent, no state change, no revert)
- `contains(address value)` - O(1) membership check
- `count()` - Number of elements
- `clear()` - Remove every element; the only correct way to empty the set (see below)
- `values(uint256 offset, uint256 limit, bool reverse)` - Paginated page and real total

`clear()` exists because the storage struct cannot be reset with `delete`: in Solidity `delete` empties the dynamic array but leaves the `indexPlusOne` mapping untouched, which desynchronises the two representations — `count()` reads zero while `contains()` still answers `true`, and a later `remove` of a stale element underflows. `clear()` walks `items` and deletes each entry before emptying the array.

The two `bool` returns carry the same idempotence signal as `Uint256Set`: `add` always leaves the element present, so the return answers "did this call change the set", not "did it succeed".

## RoundHistory*

Complete history tracking systems built on top of `OrderedHistoryIndex`. Each type manages both the index and typed value storage.

### RoundHistoryUint256

Tracks `uint256` values across rounds with arithmetic operations.

**API:**
- `record(uint256 round, uint256 value)` - Record a value at a round
- `value(uint256 round)` - Get value at round (uses nearest if not exact)
- `latestValue()` - Get the most recent value
- `increase(uint256 round, uint256 amount)` - Add to the value in force at `round`. `round` must be at least the latest recorded round: re-recording the latest round overwrites it, while an earlier round — recorded or not — reverts with `InvalidKeyOrder`
- `decrease(uint256 round, uint256 amount)` - Subtract from the value in force at `round`, under the same round constraint; reverts if the current value is smaller than `amount`

### RoundHistoryString

Tracks `string` values across rounds.

**API:**
- `record(uint256 round, string value)` - Record a string at a round
- `value(uint256 round)` - Get string at round
- `latestValue()` - Get the most recent string

### RoundHistoryAddress

Tracks `address` values across rounds. It is the scalar `address` partner of `RoundHistoryString` and is kept for symmetry, but nothing in the owning workspace imports it: `core`, `action` and `group-chat` all use the other history types. It is covered only by its own suite, so treat it as available-but-unexercised rather than battle-tested.

**API:**
- `record(uint256 round, address value)` - Record an address at a round
- `value(uint256 round)` - Get address at round
- `latestValue()` - Get the most recent address

### RoundHistoryUint256Array

Tracks `uint256[]` values across rounds, for per-round configuration arrays such as secondary-distribution recipients and ratios. Recording an empty array is a regular record — it is how a round explicitly clears the value; rounds without a record inherit the latest earlier record, and `values()` returns an empty array when no earlier record exists. A deliberate clear and a round that never had a record are indistinguishable through `values()`, since both yield an empty array: the clear is a statement about the history, not an observable state.

**API:**
- `record(uint256 round, uint256[] values)` - Record the round's values; re-recording the latest round overwrites it
- `values(uint256 round)` - Values as of a round (nearest earlier record if absent)
- `latestValues()` - Most recent recorded values

### RoundHistoryStringArray

Tracks `string[]` values across rounds, with the same inheritance semantics as `RoundHistoryUint256Array` (`remarks` arrays are the current consumer).

**API:**
- `record(uint256 round, string[] values)` - Record the round's values; re-recording the latest round overwrites it
- `values(uint256 round)` - Values as of a round (nearest earlier record if absent)
- `latestValues()` - Most recent recorded values

### RoundHistoryUint256Set

Tracks a **set** of `uint256` values across rounds, replacing the legacy `RoundHistoryAddressSet` — which lives in an external repository, not in this one — with `uint256` elements. Three histories are kept: the set size, `slot -> element`, and `element -> slot + 1` (`0` meaning "not in the set"). The current state is derived from these histories' `latestValue()`, so there is no separate snapshot array to keep in sync. A pairing does still have to hold — `slotHistory` and `indexPlusOneHistory` carry the same bijection — and a divergence between them fails silently rather than reverting, which is what the note on `remove` above is about.

Writes require a non-decreasing `round` (same constraint as `RoundHistoryUint256`); re-recording the same round keeps only that round's final value. Removal is swap-and-pop, so the order guarantee matches `Uint256Set`: an `offset` is not stable across calls, and enumeration is paginated only (`contains`/`count` are O(1) reads of the latest recorded value; `containsByRound`/`countByRound` are point queries that are O(1) on an exact round hit and fall back to a binary search — O(log rounds) — otherwise; none of them is a second enumeration path).

The two `bool` returns carry the same idempotence signal as the plain sets, so a caller can write `listed ? set.add(round, id) : set.remove(round, id)` and react only when the round's set actually changed. There is no `clear`: the other two sets offer one because a single `delete` would leave their
side mapping behind, but draining this one costs `n` full removals, so the caller should key a
fresh `Storage` off the round instead of wiping the struct. `delete` on any of the three set
structs is never correct — it empties the arrays and leaves the mappings populated.

**API:**
- `add(uint256 round, uint256 value)` - Insert; returns whether the round's set changed (`false` when already present, no state change)
- `remove(uint256 round, uint256 value)` - Swap-and-pop removal; returns whether the round's set changed (`false` when absent, no state change, no revert)
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

This design single-sources the risky part but not the glue. The index management exists once in `OrderedHistoryIndex`; the record/query skeleton on top of it — record, exact-hit fast path, `nearest()` fallback, `latestValue` — is repeated in each of the five scalar and array files, and 70–80% of their lines survive normalizing the element type (what differs is the type name and the default value returned on a miss). That duplication is deliberate: Solidity has no generics and each type wants its own storage layout, so the five files have to be changed together by hand. Only the `AddressSet`/`Uint256Set` mirror is gated by a test; the five histories are not.

`RoundHistoryUint256Set` extends the same pattern to a set: the index histories are keyed by slot (`slotHistory`) and by element (`indexPlusOneHistory`), with `countHistory` holding the size. Every read of the *current* state is O(1) or O(page) — `latestValue()` reads the last recorded key, and `values()` reads one `latestValue()` per slot — so the current state needs no extra copy. A read of a *past* round is not O(page): the set has no `value(round)`, and all three of its round accessors (`containsByRound`, `countByRound`, `valuesByRound`) fall back to `nearest()`; `valuesByRound` does so **per element**, making it O(page × log rounds) — roughly one binary search over the slot's history for each entry in the page. Size a page from that cost, not from the `values()` cost.

`AddressSet` applies the same shape to plain (non-historical) `address` membership: it is the element-type sibling of `Uint256Set` — same sentinel encoding and swap-and-pop removal, kept identical by construction, with only the element type differing. The two files are deliberate mirrors rather than one shared generic, so keeping them behaviorally identical is a maintenance obligation: any change to the sentinel, removal, or pagination semantics of one must be mirrored in the other in the same change. That obligation is gated: `test/MirrorParity.t.sol` runs one scripted and one fuzzed operation sequence through both libraries at once and compares every observable after each single operation, so a one-sided change fails there instead of shipping.

Collections here expose every enumeration through `Pagination` and never through a whole-set getter, matching the collection-read rule that a single collection keeps exactly one complete read path. Scalar `contains`/`count` are O(1) reads of the latest recorded value; their `*ByRound` forms are point queries that are O(1) on an exact round hit and O(log rounds) otherwise (`nearest()` binary search). None of them is a second enumeration path.

## Build and lint gate

`forge lint` is a build gate here, as in core and action: the post-build lint step fails on any finding, so a clean `forge build` implies a clean lint. Production sources are linted in full.

`[lint] ignore` covers `test/**/*.sol` only. The harnesses expose the set API verbatim, so every test that calls `add` / `remove` for its state effect alone drops the `bool` return and raises `unused-return` — that is most of the one-call unit tests as well as the state-machine and differential loops, 136 findings in total. Without the ignore the build fails.

One difference from the sibling repos: core, action and group-chat also `exclude_lints` `unused-return`, which switches that rule off for their production sources too. Here it stays on for `src`, and only test files are skipped.
