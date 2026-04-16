# Autoresearch: Optimize wjson performance

## Objective
Optimize the performance (encode and decode speed) of the wjson library while maintaining correctness and UTF-8 validation. The library is pure Lua and targets multiple Lua versions (5.2, 5.3, 5.4) and LuaJIT.

## Metrics
- **Primary**: `total_ms` (milliseconds, lower is better) — geometric mean of encode+decode times across all benchmark scenarios (4 synthetic, 4 real datasets) weighted by iteration counts. Computed for LuaJIT only (fastest environment) to keep benchmark fast.
- **Secondary**: `encode_ms`, `decode_ms` — separate timings for monitoring tradeoffs.
- **Secondary**: `lua52_total_ms`, `lua53_total_ms`, `lua54_total_ms` — total times for other Lua versions (to ensure no regression across environments).

## How to Run
`./autoresearch.sh` — runs the benchmark suite for LuaJIT and outputs structured `METRIC` lines.

## Files in Scope
- `src/wjson.lua` — the main library implementation (can modify any part)
- `bench/bench.lua` — benchmark script (can be updated to improve measurement or add instrumentation)
- `autoresearch.sh` — experiment runner (can be updated to adjust metric calculation)

## Off Limits
- Do not remove UTF-8 validation (must remain correct).
- Do not break JSONTestSuite compliance (tests must pass).
- Do not introduce external dependencies.

## Constraints
- Tests must pass for all Lua versions (luajit, lua52, lua53, lua54). Use `./run_tests.sh`.
- No new dependencies (pure Lua only).
- Keep compatibility with Lua 5.2+ and LuaJIT.

## Baseline (Established 2026-04-16)
New baseline established after modifying `bench/bench.lua` to clear JIT traces, randomize dataset order, and include new synthetic benchmarks. Previous benchmarks are now obsolete.

### Integrated Optimizations (Part of Baseline)
The following optimizations from previous runs are already integrated into the baseline code:
- **Conditional String Escaping**: Use manual byte scanning for LuaJIT and `str_gsub` for PUC Lua (prev Run 3).
- **Direct Integer Parsing**: Avoid `tonumber(str_sub)` by accumulating integers from bytes (prev Run 4).
- **Extended Integer Cache**: Extended `SMALL_INTS` from 0-9 to 0-99 (prev Run 6).
- **Shared Encode Buffer**: Use a pre-allocated table for string building in `encode` (prev Run 14).
- **Shared String Parts Table**: Use a shared table for string parts in `parse_string` to avoid allocations (prev Run 19).
- **Faster Dispatch**: Moved the number check to the top of `decode_value` (prev Run 21).
- **Shared Escape Parts Table**: Use a shared table for parts in `escape_string` (prev Run 22).
- **Inlined UTF-8 Validation**: Inlined branches for 2, 3, and 4-byte UTF-8 sequences in `parse_string` (prev Run 23).
- **Reduced Whitespace Calls**: Optimized `parse_array` and `parse_object` loops to avoid redundant `skip_whitespace` calls (prev Run 33).

## What's Been Tried
### Kept Optimizations
- **Escaped Key Cache** *(Run 6)*: Weak-valued cache for escaped object keys. +3.6% PUC Lua encode, but **-2.6% LuaJIT encode** (net: slightly worse LuaJIT total, better PUC Lua). ⚠️ The weak table lookup adds per-key overhead on LuaJIT where the JIT already inlines escape_string efficiently. Consider revisiting.
- **Positive Integer Fast-Path** *(Run 5)*: Inlined parsing for 1-9-leading integers in `decode_value`. Delta: total_ms 151.07→150.39 = **0.45% improvement** — this is within noise. ⚠️ Adds code complexity to a trace-critical function.
- **Structural Peeking** *(Run 4)*: Byte peeking for `,`, `]`, `}`, `:` in `parse_array`/`parse_object` to skip `skip_whitespace` in compact JSON. Delta: total_ms 150.89→151.07 = **+0.12% regression on LuaJIT** (noise), but solid win on PUC Lua 5.4 (-4.0%). Clearly good for PUC Lua; neutral for LuaJIT.
- **Multi-byte Literal Fetch** *(Run 3)*: Multi-arg `str_byte` for literals and hex digits. Delta: 154.48→150.89 = **2.3% win**, consistent. Good change.
- **Single-pass Escape String (LuaJIT)** *(Run 2)*: Removed dual-pass scanning. Delta: 159.46→154.48 = **3.1% total,  ~8% encode**. Clear win, well above noise.

### Discarded Attempts (Regressions or Noise)
- **Remove top-level UTF-8 Check**: Discarded as it regressed performance in PUC Lua 5.3+ environments where `utf8.len` is faster than manual scanning. Combined with Run 2 attempt.

## Revisit / Sanity-Check

The following kept optimizations have measured deltas ≤ 3% on the LuaJIT primary metric. Since benchmark run-to-run variance can easily be 2-3%, these changes may not actually help and should be temporarily reverted (one at a time) to verify they carry their weight — especially given that each adds branching complexity that can inhibit LuaJIT trace formation.

| Change | LuaJIT Δ | Concern |
|---|---|---|
| **Escaped Key Cache** (Run 6) | +0.08% total (noise), -2.6% encode | Weak table GC pressure + hash lookup per key. LuaJIT encode got *worse*. Net: only helps PUC Lua. Consider making this PUC-Lua-only (behind `not _G.jit`). |
| **Positive Integer Fast-Path** (Run 5) | -0.45% total | Within noise. Adds ~20 lines to `decode_value`, which is the hottest trace root. More code in the root trace = more risk of trace abort. |
| **Structural Peeking** (Run 4) | +0.12% total (regression!) | Adds `if/elseif/else` branching to every comma/bracket. Good for PUC Lua, but on LuaJIT the extra branches are redundant since `skip_whitespace` is already a tight loop that LuaJIT traces well. Consider gating behind `not _G.jit`. |

### How to test
Revert one change at a time, run `./autoresearch.sh` at least 3 times, compare the median. If the reverted version is within 1% or faster on LuaJIT, remove the change (or gate it to PUC Lua).

## Archive: Obsolete Runs (Prior to 2026-04-16 Reset)
<details>
<summary>View Archived Attempts</summary>

- **Manual escape_string for all Lua versions**: Massive regression in PUC Lua (Run 2).
- **Move depth check to array/object branches**: Worse performance (Run 5).
- **Extend SMALL_INTS to 0-999**: Table too large, lookup cost > savings (Run 7).
- **Reorder number encoding (SMALL_INTS before NaN)**: lookup for non-integers was wasteful (Run 8).
- **Remove clear_buffer from drain_buffer**: No measurable improvement (Run 9).
- **LuaJIT string.buffer for encode**: `sb:put()` overhead too high for this workload (Run 10).
- **Combine string writes into single buffer entry**: String concatenation overhead was too high (Run 11).
- **Split nil/null check**: Extra branch overhead (Run 12).
- **Peek byte for trailing comma**: Branch overhead > savings (Run 13).
- **Avoid re-scanning digits in parse_number slow path**: Extra logic complexity hurt LuaJIT (Run 15).
- **str_find fast-path in escape_string**: Massive regression in LuaJIT (Run 16).
- **str_sub comparison for true/false/null literals**: Manual byte checks were faster (Run 17).
- **Lookup table for skip_whitespace**: Hash lookup > 4 boolean comparisons (Run 18).
- **4-byte scan in parse_string fast path**: Overhead of multi-byte fetch > savings (Run 20).
- **Remove redundant byte nil checks in parse_number**: Slight regression/noise (Run 24).
- **Extend SMALL_INTS to negative integers (-1 to -9)**: Regression/noise (Run 25).
- **Increase initial table sizes to 32**: Overhead for many small objects was too high (Run 26).
- **Move string check to the very top of decode_value**: Numbers are better first branch (Run 27).
- **Use band instead of % for UTF-8 math**: Regression/noise (Run 28).
- **Remove redundant byte fallback in decode_value**: Regression/noise (Run 29).
- **Inline string key fast path in parse_object**: Code complexity hurt JIT (Run 30).
- **Add tight inner loop for ASCII characters in parse_string slow path**: Regression (Run 31).
- **Move number check before string check in encode_value**: Massive regression (Run 32).
</details>

## Optimization Ideas

### Tier 1 — High confidence, mechanistically motivated

1. **Simplify `decode_value` to reduce trace root size (LuaJIT)**
   The current `decode_value` function is 53 lines with 10+ branches. LuaJIT's tracing JIT records one linear path; every branch that *doesn't* get taken becomes a guard. More guards = more opportunities for trace aborts = more fallback to the interpreter.
   
   **Concrete idea**: Extract the positive-integer fast-path back into `parse_number`. The inline integer accumulator (lines 1181-1196) duplicates logic from `parse_number` and adds ~15 lines + 4 branches to the hottest trace root. LuaJIT already inlines short leaf calls *within the trace*; a clean `parse_number` that starts with the same integer fast-path is likely to be inlined by the JIT without polluting `decode_value`'s root trace. The prior Run 5 that added this measured only 0.45% — which is noise.

2. **Gate PUC-Lua-only optimizations behind `not _G.jit`**
   Several changes (escaped key cache, structural peeking) help PUC Lua but add hash lookups and branches that LuaJIT doesn't need. Use the existing pattern (like `skip_whitespace` and `escape_string`) of defining two implementations:
   ```lua
   if _G.jit then
     parse_array = function(...) -- lean version, no peeking
   else
     parse_array = function(...) -- version with structural peeking
   end
   ```
   This is already the established pattern in the codebase. Currently `parse_array`, `parse_object`, and `encode_value` use a single implementation that tries to serve both runtimes — this is an anti-pattern for LuaJIT specifically.

3. **Reduce `parse_number` slow-path re-scanning**
   `parse_number` has a fast path that accumulates digits, then on encountering `.`/`e`/`E` it *re-scans from `start_pos`* (line 989). This means every float is scanned twice. Instead, continue scanning forward from the current `pos`, building the substring `str_sub(start_pos, final_pos - 1)` and calling `tonumber` once. The prior Run 15 attempt failed because it "added extra logic complexity" — but the right approach is simpler: just keep advancing `pos` past the fractional/exponent digits without computing anything, then do a single `tonumber(str_sub(start_pos, pos-1))`. Remove the intermediate `b` tracking.

4. **Flatten the object encoder loop (LuaJIT)**
   The `encode_value` object loop (lines 520-555) has a `first` flag that adds a branch on every iteration. This is a classic pattern that hurts branch prediction on the first iteration and adds a pointless check on all subsequent iterations. Fix: handle the first key-value pair outside the loop, then loop `k, v = next(val, k)` without the `first` check. This removes one branch per key from the hot loop.

5. **Pre-size `shared_encode_parts` clearing with nil-fill elimination**
   In `escape_string` (LuaJIT), after building the result via `tbl_concat`, the code nil-fills the shared table (line 387: `for k = 1, pn do parts[k] = nil end`). Same in `parse_string` (line 631/776). These nil-fill loops are O(n) and happen on every string with escapes. Since you already pass explicit bounds to `tbl_concat(..., 1, pn)`, the stale entries are never read. You could skip the nil-fill entirely if you track a high-water mark or just accept that stale entries exist beyond `pn`. The only risk is memory retention, which is minimal for the shared table.

### Tier 2 — Moderate confidence, worth trying

6. **Hoist `#str` / `len` checks out of inner loops**
   In `parse_string` (LuaJIT version), the inner loop condition is `while i <= len`. LuaJIT can usually hoist the `len` comparison since `len` is loop-invariant, but in practice the loop body is complex enough that this may not happen. Try restructuring the inner hot loop to be a simple `while true` with explicit bounds checks only at escape transitions. This is the "tight ASCII inner loop" idea that failed in Run 31 — but the failure was in the *PUC Lua slow path*; it may work better if only applied to the JIT path. 

7. **Fuse quote + content writes in encode**
   Currently string encoding does 3 buffer writes: `buf[n+1] = '"'`, `buf[n+2] = content`, `buf[n+3] = '"'`. For strings that need no escaping (the common case), you could do a single write: `buf[n+1] = '"' .. val .. '"'`. Yes, this creates a temporary concatenation — but LuaJIT's string interning is fast and you eliminate 2 buffer index operations. This is different from Run 11 (which tried to concatenate *escaped* content). The key insight: for the no-escape fast path, `..` is a single `lj_str_cat` call that the JIT handles well. Test on hot benchmarks with mostly-ASCII data.

8. **Skip top-level `utf8.len` validation on LuaJIT**
   The `decode` function calls `utf8.len(str)` at the top (line 1235-1240) for Lua 5.3+. This is a full scan of the input before any parsing begins. Since `parse_string` already does inline UTF-8 validation, this is redundant work — the string content will be validated character-by-character during parsing. On PUC Lua 5.3+ where `utf8.len` is a fast C function, this is a reasonable trade-off (it fails fast on garbage input). But it's worth measuring how much decode time this consumes on typical valid inputs. If it's >5% of decode time, consider removing it and relying solely on the per-string validation.

9. **`tostring` bypass for common integer ranges in encode**
   The `SMALL_INTS` table covers 0-99 but `tostring()` is still called for 100-9999 (very common in real data). Extending to 0-999 was tried (Run 7, archived) and failed due to "table too large, lookup cost > savings." But a 1000-entry flat array is only 8KB — smaller than L1 cache. The failure may have been noise or an implementation issue (e.g., using a hash table instead of an array-part table). Worth re-trying with explicit integer keys `[100] = "100", ...` to ensure LuaJIT uses the array part.

### Tier 3 — Speculative / minor

10. **Encode boolean as direct string reference**
    `val and "true" or "false"` is fine, but the ternary pattern generates a branch. Alternatively: `local BOOLS = {[true]="true", [false]="false"}` and `buf[n] = BOOLS[val]`. Table lookup is a single hash probe in LuaJIT. Marginal, but trivial to try.

11. **`string.find` with plain flag for PUC Lua escape detection**
    In the PUC Lua encode path, `str_find(val, ESCAPE_PATTERN)` uses a pattern. `str_find(val, '"', 1, true)` with plain search is faster but only checks one character.  For PUC Lua, the current approach is already well-optimized.

12. **Benchmark methodology: run N≥5 trials and use median**
    The current benchmark variance makes it hard to distinguish real 1-3% improvements from noise. Running each benchmark 5+ times and using the median (not mean) would dramatically improve confidence. This doesn't change the code but changes how effectively you can evaluate the above ideas.