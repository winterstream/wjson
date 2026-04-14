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
- (Will be updated as experiments accumulate)

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