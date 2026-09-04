# Autoresearch: Experiment 3 — Object-Key Allocation

## Objective

Optimize allocations caused by JSON object-key parsing in `src/wjson.lua` across
LuaJIT and PUC Lua 5.2–5.5. Reuse repeated schema keys where it is measurably
safe, without weakening validation, allowing unbounded memory growth, or
regressing another runtime.

Every iteration measures all five runtimes:

1. LuaJIT 2.1
2. PUC Lua 5.2
3. PUC Lua 5.3
4. PUC Lua 5.4
5. PUC Lua 5.5

Each experiment is one atomic source change. A result is not trusted from one
noisy runtime sample.

## Metrics and decision rule

The primary metric is `composite_decode_ms`, the geometric mean of the five
steady-state decode times:

```latex
G = (T_{JIT} T_{52} T_{53} T_{54} T_{55})^{1/5}
```

Lower is better. `autoresearch/baseline_metrics.json` stores the last accepted
measurements. A candidate is vetoed if any runtime is more than
`NOISE_THRESHOLD` (default `0.02`, or 2%) slower than its baseline. Vetoed runs
emit `METRIC composite_decode_ms=99999.00`.

The script also emits independent decode, number, and total-time metrics for
diagnosis. `latest_run.json` is only a measurement artifact; it is never a
baseline until explicitly promoted with:

```sh
./autoresearch/autoresearch.sh --update-baseline
```

## Benchmark methodology

LuaJIT measurements must separate trace compilation from steady-state decode:

- `bench/bench.lua` flushes LuaJIT before each dataset, warms it after the
  flush, then measures a contiguous batch of decodes.
- `BENCH_WARMUP` controls the post-flush warmup count; the default is `5`.
- `BENCH_MIN_ITERS` prevents quick runs from measuring a large dataset once; the
  default is `3`.
- `BENCH_REPEATS` runs each runtime in independent processes and uses the median
  per-runtime sample; the default is `3`.
- The arena uses `ARENA_REPEATS` with the same median policy; quick arena runs
  default to one repeat.

The old interleaved benchmark flushed LuaJIT before each pass and sometimes
measured only one Wikipedia decode. That mixed JIT compilation and throughput,
so its single-run LuaJIT results are historical evidence only.

Run the complete matrix with:

```sh
./autoresearch/autoresearch.sh
```

Run the public comparison arena with:

```sh
make arena ARGS="--no-color"
make arena ARGS="--datasets-only --no-color"
```

## Target workloads

- `wikipedia-movie-data`: 36,000+ uniform objects with repeated keys.
- `citm_catalog`: nested objects with repeated schema fields.
- `twitter`: heterogeneous metadata objects.
- `github-gists` and Barcelona universities: wider and escaped-key controls.
- Synthetic Unicode and number workloads: regression controls outside key
  parsing.

## Planned exploration

1. Measure key capture, string allocation, and GC costs on repeated object
   schemas.
2. Evaluate bounded schema-aware key reuse for common unescaped keys.
3. Test raw-byte matching for predicted keys without allocating a temporary key.
4. Keep cache checks out of heterogeneous or escaped-key paths when they do not
   pay.

Caches must be bounded. Escaped keys, duplicate keys, malformed delimiters,
trailing commas, invalid UTF-8, and exact error positions remain covered by the
full test suite.

## Verification and invariants

Before accepting a change:

1. `./run_tests.sh` passes all tests on LuaJIT and Lua 5.2–5.5.
2. All five decode metrics are present and positive.
3. The composite metric passes the per-runtime veto gate.
4. The arena and focused workload remain consistent with the autoresearch result
   when the change is substantial.

The implementation remains pure Lua with no external runtime dependencies.
