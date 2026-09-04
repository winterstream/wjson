
## Benchmarking correction — run 6 audit
**Failure**: Run 6 kept the empty-container fast paths because `lua54_decode_ms` was the only effective primary metric. LuaJIT, Lua 5.2, and Lua 5.3 regressed in the same sample.
**Root cause**: The old harness flushed LuaJIT before interleaved passes and could measure only one large-dataset decode at `BENCH_SETS=5`, mixing trace compilation with throughput. The arena also discarded warmup traces before timing.
**Correction**: Warm after the final flush, measure contiguous batches, enforce a minimum iteration count, use repeated-process medians, and gate a geometric mean with per-runtime vetoes.
**Evidence**: Repeated arena samples for the same revision ranged from roughly 75 ms to 169 ms for the same LuaJIT dataset aggregate.
