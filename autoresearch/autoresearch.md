# Autoresearch: Experiment 2 — Number Parsing via Anchored Regex in PUC Lua

## Objective

Optimize JSON number parsing performance in PUC Lua (5.2, 5.3, 5.4, 5.5) using
anchored pattern matching (`string.find` / `string.match`) to push digit
scanning from interpreted Lua bytecode into the C runtime, while maintaining
strict RFC 8259 compliance and ensuring **no regressions on LuaJIT**.

All 5 runtimes must be benchmarked on every iteration:

1. **LuaJIT 2.1**
2. **PUC Lua 5.2**
3. **PUC Lua 5.3**
4. **PUC Lua 5.4**
5. **PUC Lua 5.5**

The final code must introduce no obvious regressions across any of the 5
environments, though temporary regressions are permitted during intermediate
steps if an experiment requires multi-step refactoring.

## Metrics

- **Primary**: `puc_decode_ms` (milliseconds, lower is better) — total decode
  time summed across PUC Lua 5.2, 5.3, 5.4, and 5.5.
- **Target Secondary**: `puc_numbers_ms` (milliseconds, lower is better) —
  decode time for `synthetic-complex-numbers` summed across PUC Lua 5.2–5.5.
- **Guard Metrics**:
  - `luajit_decode_ms`, `luajit_total_ms` — LuaJIT decode and total time (must
    not regress; LuaJIT must retain its compiled byte-loop or integer
    fast-paths).
  - `lua52_decode_ms`, `lua53_decode_ms`, `lua54_decode_ms`, `lua55_decode_ms` —
    per-runtime decode times to verify consistent improvements across all PUC
    versions.

## How to Run

```bash
./autoresearch/autoresearch.sh
```

This runs:

1. Load check across all 5 environments (`luajit`, `lua52`, `lua53`, `lua54`,
   `lua55`).
2. Full test suite validation (`./run_tests.sh` across all 5 environments, 504
   tests each).
3. Full benchmark suite across all 5 environments, extracting structured
   `METRIC` lines.

## Files in Scope

- `src/wjson.lua` — main library implementation (focus on `parse_number` and
  PUC-specific decode paths).
- `bench/bench.lua` — benchmark harness (can add instrumentation or adjust
  iterations if justified).
- `autoresearch/autoresearch.sh` — test and benchmark runner.
- `autoresearch/autoresearch.md` — experiment tracker and documentation.

## Off Limits & Invariants

- **Correctness is non-negotiable**:
  - All 504 tests in `./run_tests.sh` must pass on all 5 engines (`luajit`,
    `lua52`, `lua53`, `lua54`, `lua55`).
  - Strict JSON number rules must remain enforced:
    - No leading zeros (`01`, `007` are invalid).
    - No bare leading signs without digits (`+1` is invalid in JSON, `-` alone
      is invalid).
    - No trailing decimal dots (`1.` is invalid).
    - Exponents must have digits (`1e`, `1e+` are invalid).
    - Numbers out of range or malformed must report accurate error messages and
      positions.
- **Pure Lua only**: Zero C dependencies or external modules.
- **Compatibility**: Must support LuaJIT and PUC Lua 5.2 through 5.5.

## Architectural Analysis: Experiment 2 (Why & How)

### Why PUC Lua is Slower at Number Decoding

In LuaJIT, bytecode loops over string bytes compile into native CPU machine code
instructions, making byte-by-byte scanning faster than calling into C runtime
functions.

In PUC Lua (5.2–5.5), every bytecode instruction is processed by the software
interpreter loop (`luaV_execute`). In the current `src/wjson.lua`:

- Lines 746–778: Integer accumulation loop executes `OP_GETTABUP`, `OP_LE`,
  `OP_GE`, `OP_ADD`, `OP_MUL` in Lua bytecode for every digit.
- Lines 780–835: When encountering a decimal point `.` or exponent `e`/`E`, the
  slow path rewinds `pos` to `start_pos` and **re-scans the integer digits from
  scratch in Lua bytecode**, followed by another loop for decimals and a third
  loop for exponents.
- For a dataset like `synthetic-complex-numbers` (3,000 floats/exponents) or
  `wikipedia-movie-data` (97,000 numbers), this results in hundreds of thousands
  of unnecessary interpreter opcode dispatches.

### How Competitors Handle This

`dkjson` and `lunajson` achieve significantly faster number decoding on PUC Lua
by offloading the number scan to a single C call:

- `dkjson`:
  ```lua
  local pstart, pend = strfind (str, "^%-?[%d%.]+[eE]?[%+%-]?%d*", pos)
  local number = str2num (strsub (str, pstart, pend))
  ```
  The entire number token boundary is identified in compiled C code inside
  `lstrlib.c`.
- `lunajson`: Uses anchored `string.match` regex patterns
  (`'^([0-9]+%.?[0-9]*)([-+.A-Za-z]?)'`) to capture the number in C before
  converting with `tonumber`.

### Planned Strategy for Experiment 2

1. **Separate JIT vs. PUC Paths**: Gate `parse_number` behind
   `if JIT then ... else ... end` so LuaJIT keeps its clean, trace-friendly byte
   accumulation while PUC Lua can use an optimized pattern scanner.
2. **C Pattern Number Scanner for PUC Lua**: Use an anchored pattern (e.g.
   `^%-?%d+%.?%d*[eE]?[%+%-]?%d*`) to locate the number boundary in a single C
   call.
3. **Targeted Validation**: Validate JSON constraints on the extracted substring
   (leading zero check, trailing dot check, exponent digits check) without
   multi-loop re-scanning.
4. **Preserve Small Integer Fast Path**: Retain direct integer accumulation for
   small 1–2 digit integers where pattern matching call overhead would exceed
   simple byte arithmetic.

---

## Historical Context & Prior Sessions

### Integrated Optimizations (Part of Baseline)

- **Conditional String Escaping**: Manual byte scanning for LuaJIT, `str_gsub`
  for PUC Lua.
- **Direct Integer Parsing**: Avoid `tonumber(str_sub)` for positive integers.
- **Extended Integer Cache**: `SMALL_INTS` covering 0–99.
- **Shared Encode Buffer**: Pre-allocated table for string building in `encode`.
- **Gated JIT/PUC Paths**: Separated implementations for `parse_array`,
  `parse_object`, and `encode_value`.
- **Batch UTF-8 Validation on PUC 5.3+**: Using `utf8.len` for multibyte runs in
  `parse_string`.
- **Fused Object Head on PUC**: `str_match('^[ \t\n\r]*"()')` for skipping
  whitespace and capturing key start.
