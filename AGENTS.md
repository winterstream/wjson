# AGENTS

When making code changes in this repository:

1. Update documentation when public behavior or public API changes.
2. Run `./run_tests.sh` after changes.
3. Do not consider the task complete if tests fail.
4. If the change affects performance-sensitive paths in `src/wjson.lua`,
   consider running `bench/bench.lua` or the benchmark scripts as a follow-up.
5. Keep diffs small and favor readability unless a benchmark justifies added
   complexity.
