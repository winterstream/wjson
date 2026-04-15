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

## What's Been Tried
### Kept Optimizations
- **Conditional String Escaping**: Use manual byte scanning for LuaJIT and `str_gsub` for PUC Lua (Run 3).
- **Direct Integer Parsing**: Avoid `tonumber(str_sub)` by accumulating integers from bytes (Run 4).
- **Extended Integer Cache**: Extended `SMALL_INTS` from 0-9 to 0-99 (Run 6).
- **Shared Encode Buffer**: Use a pre-allocated table for string building in `encode` (Run 14).
- **Shared String Parts Table**: Use a shared table for string parts in `parse_string` to avoid allocations (Run 19).
- **Faster Dispatch**: Moved the number check to the top of `decode_value` (Run 21).
- **Shared Escape Parts Table**: Use a shared table for parts in `escape_string` (Run 22).
- **Inlined UTF-8 Validation**: Inlined branches for 2, 3, and 4-byte UTF-8 sequences in `parse_string` (Run 23).
- **Reduced Whitespace Calls**: Optimized `parse_array` and `parse_object` loops to avoid redundant `skip_whitespace` calls (Run 33).

### Discarded Attempts (Regressions or Noise)
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

## Optimization Ideas
- Inline hot functions, reduce table allocations, improve string building.
- Optimize UTF-8 validation: maybe faster validation for ASCII-only strings.
- Use faster number parsing/formatting.
- Cache repeated string operations.
- Use byte caching for common characters.
- Improve escape handling.
- Reduce metatable overhead for arrays.
- Use `table.new` where appropriate.
- Optimize `skip_whitespace` for PUC Lua vs LuaJIT.
- Improve `parse_string` fast path for strings without escapes.
- Use pattern matching vs manual scanning for PUC Lua.
- Precompute escape mappings.
- Use integer arithmetic instead of bitwise operators where possible.
- Reduce function call overhead in recursive decode.
- Use local variables more aggressively.
- Avoid `tonumber`/`tostring` overhead for small integers.
- Optimize object encoding iteration (maybe sort keys? but not required).
- Use `string.pack` for UTF-8 encoding? (Lua 5.3+)
- Use `utf8.len` for validation when available.
- Use `string.gsub` with precompiled patterns.
- Use `table.concat` with pre-sized table.
- Use `math.type` for integer detection (Lua 5.3+).
- Use `string.unpack` for scanning (Lua 5.3+).