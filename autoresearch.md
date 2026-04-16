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
- **Gated JIT/PUC Paths** *(Run 7)*: Separated JIT and PUC implementations for `parse_array`, `parse_object`, and `encode_value`. Improved LuaJIT by **2.4%** by removing branching complexity that inhibited tracing.
- **Flattened Object Encoder** *(Run 7)*: Handle first key-value pair outside the loop to remove the `first` branch.
- **Escaped Key Cache** *(Run 6)*: Weak-valued cache for escaped object keys. Gated to **PUC Lua only** as it regressed LuaJIT encoding.
- **Structural Peeking** *(Run 4)*: Byte peeking for structural characters. Gated to **PUC Lua only** to avoid redundant branching in LuaJIT.
- **Multi-byte Literal Fetch** *(Run 3)*: Multi-arg `str_byte` for literals and hex digits. **2.3% win**, consistent.
- **Single-pass Escape String (LuaJIT)** *(Run 2)*: Removed dual-pass scanning. **~8% encode win**.

### Discarded Attempts (Regressions or Noise)
- **Positive Integer Fast-Path (decode_value)**: Removed from `decode_value` to reduce trace root size. LuaJIT performance improved when this was extracted back to `parse_number` (Run 7).
- **Remove top-level UTF-8 Check**: Discarded as it regressed performance in PUC Lua 5.3+ environments.

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
- **Single-pass Integer Number Parsing**: Regressed LuaJIT by 1.4% (Run 8).
- **Nil-fill elimination in shared buffers**: Regressed LuaJIT by 3.4% (Run 8).
- **Small String Interning Cache (Keys)**: Branching overhead > savings on LuaJIT; regressed PUC Lua by 2.8% (Run 8/9).
- **Fused Quote Writes in Encoder**: Extra string allocation/concatenation overhead was ~17% slower (Run 9).
- **Inlined skip_whitespace**: Trace complexity hurt LuaJIT performance by ~4% (Run 9).
- **Remove top-level utf8.len scan (JIT)**: No measurable win; environment noise masked any potential gain (Run 9).
</details>

## Optimization Ideas

### Status of Previous Tier 1 Ideas
- ✅ **Simplify `decode_value`** — Done in Run 7. Positive-integer fast-path extracted back to `parse_number`.
- ✅ **Gate PUC-Lua-only optimizations** — Done in Run 7. `parse_array`, `parse_object` now have separate JIT/PUC paths.
- ✅ **Flatten object encoder loop** — Done in Run 7. First key handled outside loop.
- ❌ **Nil-fill elimination** — Tried in Run 8, regressed LuaJIT by 3.4%. `tbl_concat` with bounds apparently relies on nil-terminated arrays internally in some cases.
- ❌ **Fused quote writes** — Tried in Run 9, 17% regression. String concatenation allocation cost exceeds buffer-write savings.
- ❌ **Skip utf8.len on JIT** — Tried in Run 9, no measurable win. LuaJIT doesn't use utf8.len (it's nil), so this was only relevant for PUC 5.3+.

### Architectural Analysis: Where the Time Goes

**PUC Lua cost model**: The PUC Lua VM dispatches ~20-50ns per opcode. Every Lua-level comparison, assignment, function call, and loop iteration is an opcode. In contrast, C-implemented functions like `string.find`, `string.gsub`, `string.match`, and `tonumber` process bytes at ~1-2ns/byte. The fundamental optimization strategy for PUC Lua is: **minimize Lua-level loop iterations by pushing work into C functions**.

**Current PUC Lua performance breakdown** (estimated from code structure):

| Component | Bottleneck | Why |
|---|---|---|
| `parse_string` fast path | ✅ Already optimal | Single `str_find` + `str_sub` |
| `parse_string` slow path (escapes) | 🔶 Moderate | Re-enters `str_find` per chunk, but escape handling is per-character Lua |
| `parse_number` | 🔴 **Major bottleneck** | 4-5 Lua-level loops scanning byte-by-byte. Every digit = 3-4 opcodes. On a number like `123456`, that's ~24 opcodes vs. 1 C call |
| `skip_whitespace` | ✅ Already optimal | Single `str_find` call |
| `parse_object` / `parse_array` | 🔶 Moderate | Structural peeking helps, but each element still requires multiple `str_byte` calls |
| `encode_value` (strings) | ✅ Already optimal | `str_find` + `str_gsub` with ESCAPED_KEY_CACHE |
| `encode_value` (numbers) | 🔶 Moderate | `tostring()` is a C call but allocates a string. SMALL_INTS covers 0-99 |
| `encode_value` (recursion) | 🔶 Moderate | ~8 opcodes per function call setup/teardown in PUC Lua |

**Comparison with dkjson** (which is the PUC Lua speed target):

dkjson's `scanstring` uses pattern `'["\\]'` — it only looks for quote and backslash, **not** for control characters or UTF-8 bytes. wjson's `STRING_PATTERN` is heavier because it also validates control chars and (on Lua 5.2) high bytes. This is the documented "2x penalty."

dkjson's number parsing uses a **single `strfind` pattern**: `"^%-?[%d%.]+[eE]?[%+%-]?%d*"`. This extracts the entire number token in one C call, then validates with `tonumber`. wjson's `parse_number` does manual byte-by-byte scanning — far more opcodes.

### Tier 1 — High impact PUC Lua ideas

1. **Pattern-based `parse_number` for PUC Lua** ⭐ *Likely biggest remaining PUC Lua win*

   Replace the byte-by-byte integer accumulation and slow-path re-scanning with a two-step approach:
   
   ```lua
   -- Step 1: Find number boundary in one C call
   local _, num_end = str_find(str, '^%-?%d+%.?%d*[eE]?[%+%-]?%d*', pos)
   -- Step 2: Extract and convert
   local num_str = str_sub(str, pos, num_end)
   local num = tonumber(num_str)
   ```
   
   Then do targeted validation (leading-zero check, trailing-dot check) on the extracted substring. This replaces 4-5 Lua loops (integer accumulation, slow-path digit skip, decimal scanning, exponent scanning) with **one C-level `str_find`** plus a few validation checks.
   
   The integer fast-path can still be kept (it avoids `tonumber` + string allocation for small ints), but the *slow path* should be pattern-driven. The current slow path re-scans from `start_pos` (line 1002) — this is pure waste on PUC Lua where every `str_byte` is an opcode dispatch.
   
   **Why it should work**: dkjson uses exactly this approach and it's one reason dkjson's number parsing is faster on PUC Lua. The pattern engine in PUC Lua is C code that runs at native speed.
   
   **Risk**: Pattern matching has overhead for very short numbers (1-2 digits). The integer fast-path should still handle those. Only fall through to pattern-based parsing for `.`/`e`/`E` cases.

2. **Reduce `parse_number` slow-path re-scanning** (simpler variant)

   Even without full pattern-based parsing, the current slow path (lines 1000-1061) is wasteful: it re-scans digits it already scanned in the fast path. Instead, when the fast path encounters `.`/`e`/`E`, just continue scanning forward:
   
   ```lua
   -- Fast path hit '.' or 'e' at current pos, just keep going:
   while pos <= len do
     b = str_byte(str, pos)
     if (b >= BYTE_0 and b <= BYTE_9) or b == BYTE_DOT 
       or b == BYTE_E or b == BYTE_UPPER_E 
       or b == BYTE_PLUS or b == BYTE_MINUS then
       pos = pos + 1
     else break end
   end
   return tonumber(str_sub(str, start_pos, pos - 1)), pos
   ```
   
   This eliminates the re-scan entirely. Validation is deferred to `tonumber` returning nil for invalid formats. The leading-zero check was already done in the fast path.

3. **PUC Lua `parse_object`: reduce per-entry `str_byte` calls**

   The PUC Lua `parse_object` currently does multiple `str_byte` calls per entry for structural peeking (colon peek, comma peek, brace peek). Each is a C function call with Lua dispatch overhead.
   
   Consider: after `parse_string` returns the key and position, use `str_find` to skip whitespace AND find the colon in one call:
   ```lua
   local colon_pos = str_find(str, ':', pos, true)  -- plain search, fast
   ```
   Similarly, after value parsing, find comma-or-brace with one `str_find`:
   ```lua
   local next_pos, next_b = str_find(str, '[,}]', pos)
   -- or for arrays: str_find(str, '[,%]]', pos)
   ```
   This replaces the peek-then-whitespace-then-check pattern (3+ C calls) with a single C call.

4. **Separate PUC Lua `encode_value` into specialized per-type helpers**

   Currently `encode_value` is a single function with `if t == "string" then ... elseif t == "number" then ...` chains. On PUC Lua, the `type()` call returns a string, and string equality checks are pointer comparisons (since Lua interns all strings). So the dispatch is cheap.
   
   BUT: the function is long (~150 lines). PUC Lua's register allocator handles shorter functions better. If encode performance matters for PUC Lua, consider splitting the table encoding (array + object branches) into separate functions. This keeps the hot leaf paths (string, number, boolean) in a compact function with fewer local variables competing for registers.

### Tier 2 — Moderate confidence

5. **`tostring` bypass for integers via digit extraction**

   Instead of extending SMALL_INTS (which had lookup overhead for large tables), compute the string representation for positive integers < 10000 using digit extraction:
   ```lua
   if val >= 0 and val < 10000 and val % 1 == 0 then
     local d1 = val % 10
     val = (val - d1) / 10
     -- ... build string from digits
   ```
   This avoids both the `tostring` C call (which allocates via `luaL_Buffer`) and the hash table lookup. For PUC Lua this trades ~15 opcodes for the `tostring` C call + string creation overhead. Marginal, but integers 100-9999 are extremely common in real JSON.

6. **`string.match` for combined whitespace+structural tokens in PUC Lua decode**

   Instead of `skip_whitespace` + `str_byte` peek, use a single `string.match`:
   ```lua
   local token = str_match(str, '^[ \n\r\t]*(.)', pos)
   ```
   This returns the first non-whitespace character in one C call. But: `str_match` allocates a return string, which `skip_whitespace` + `str_byte` doesn't. Test whether the allocation cost < the call overhead savings.

7. **Benchmark methodology: run N≥5 trials and use median**
   The current benchmark variance makes it hard to distinguish real 1-3% improvements from noise. Running each benchmark 5+ times and using the median (not mean) would dramatically improve confidence.

### Tier 3 — Speculative / already tried

8. **Encode boolean as direct table lookup**: `BOOLS[val]` instead of `val and "true" or "false"`. Marginal.

9. **Small String Interning Cache for Object Keys**: Tried in Run 8/9, discarded. Overhead > savings.

10. **Extended SMALL_INTS to 0-999**: Tried (archived Run 7), lookup cost > savings. The digit-extraction approach (Tier 2 #5) may be better.

### Code Growth vs LuaJIT: Is It a Problem?

The codebase has grown from ~900 lines to 1335 lines. This is **not a concern for LuaJIT** because:
- LuaJIT traces execute paths, not functions. Code size doesn't affect trace quality.
- The JIT/PUC gating means LuaJIT only "sees" the lean JIT paths (~40% of the code).
- `decode_value` (the hottest trace root) is now 36 lines with 8 branches — clean.

It's also **not a concern for PUC Lua** because:
- PUC Lua interprets bytecodes; source code size doesn't affect execution speed.
- The additional code is in `if _G.jit` branches that PUC Lua never enters.
- PUC Lua benefits from expanded code when it replaces expensive abstractions (function calls) with inline logic.

The code *is* harder to maintain due to duplication, but that's the correct trade-off for a performance-critical library.