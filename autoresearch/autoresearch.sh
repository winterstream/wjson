#!/usr/bin/env bash
set -euo pipefail

# Experiment 2: Benchmark across LuaJIT and PUC Lua 5.2, 5.3, 5.4, 5.5
# Outputs structured METRIC lines for autoresearch.

cd "$(dirname "$0")/.."

export BENCH_SETS="${BENCH_SETS:-5}"

# Step 1: Pre-check library loading across all 5 environments
for env in luajit lua52 lua53 lua54 lua55; do
    bin="lua"
    if [ "$env" = "luajit" ]; then bin="luajit"; fi
    if ! nix develop .#"$env" -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" "$bin" -e "require('wjson')" 2>/dev/null; then
        echo "ERROR: wjson failed to load in $env"
        exit 1
    fi
done

# Step 2: Run the full test suite (must pass across all 5 engines)
echo "Running test suite across all 5 environments..."
if ! ./run_tests.sh > /dev/null 2>&1; then
    echo "ERROR: test suite failed on one or more environments"
    exit 1
fi

# Step 3: Helper function to parse benchmark output
parse_metrics() {
    local output="$1"
    echo "$output" | awk '
    /Encode:[[:space:]]+[0-9.]+[[:space:]]+ms.*Decode:[[:space:]]+[0-9.]+[[:space:]]+ms/ {
        for (i=1; i<=NF; i++) {
            if ($i == "Encode:") ev = $(i+1)
            if ($i == "Decode:") dv = $(i+1)
        }
        es += ev
        ds += dv
        if ($0 ~ /synthetic-complex-numbers/) {
            nd = dv
        }
    }
    END {
        printf "%.2f %.2f %.2f\n", (es ? es : 0), (ds ? ds : 0), (nd ? nd : 0)
    }'
}

# Step 4: Benchmark LuaJIT
echo "Benchmarking luajit..."
output_luajit=$(nix develop .#luajit -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" luajit bench/bench.lua 2>&1)
read -r luajit_encode luajit_decode luajit_numbers <<< "$(parse_metrics "$output_luajit")"
luajit_total=$(echo "$luajit_encode + $luajit_decode" | bc -l)

# Step 5: Benchmark PUC Lua versions (5.2, 5.3, 5.4, 5.5)
puc_decode_sum=0
puc_numbers_sum=0
puc_total_sum=0

# Individual version results
lua52_encode=0; lua52_decode=0; lua52_numbers=0; lua52_total=0
lua53_encode=0; lua53_decode=0; lua53_numbers=0; lua53_total=0
lua54_encode=0; lua54_decode=0; lua54_numbers=0; lua54_total=0
lua55_encode=0; lua55_decode=0; lua55_numbers=0; lua55_total=0

for env in lua52 lua53 lua54 lua55; do
    echo "Benchmarking $env..."
    output_env=$(nix develop .#"$env" -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" lua bench/bench.lua 2>&1)
    read -r e_val d_val n_val <<< "$(parse_metrics "$output_env")"
    tot=$(echo "$e_val + $d_val" | bc -l)

    case "$env" in
        lua52) lua52_encode=$e_val; lua52_decode=$d_val; lua52_numbers=$n_val; lua52_total=$tot ;;
        lua53) lua53_encode=$e_val; lua53_decode=$d_val; lua53_numbers=$n_val; lua53_total=$tot ;;
        lua54) lua54_encode=$e_val; lua54_decode=$d_val; lua54_numbers=$n_val; lua54_total=$tot ;;
        lua55) lua55_encode=$e_val; lua55_decode=$d_val; lua55_numbers=$n_val; lua55_total=$tot ;;
    esac

    puc_decode_sum=$(echo "$puc_decode_sum + $d_val" | bc -l)
    puc_numbers_sum=$(echo "$puc_numbers_sum + $n_val" | bc -l)
    puc_total_sum=$(echo "$puc_total_sum + $tot" | bc -l)
done

# Step 6: Output structured metrics
# Primary metric for Experiment 2: puc_decode_ms (lower is better)
echo "METRIC puc_decode_ms=$puc_decode_sum"
echo "METRIC puc_numbers_ms=$puc_numbers_sum"
echo "METRIC luajit_decode_ms=$luajit_decode"
echo "METRIC luajit_numbers_ms=$luajit_numbers"
echo "METRIC luajit_total_ms=$luajit_total"
echo "METRIC lua52_decode_ms=$lua52_decode"
echo "METRIC lua53_decode_ms=$lua53_decode"
echo "METRIC lua54_decode_ms=$lua54_decode"
echo "METRIC lua55_decode_ms=$lua55_decode"
echo "METRIC lua52_total_ms=$lua52_total"
echo "METRIC lua53_total_ms=$lua53_total"
echo "METRIC lua54_total_ms=$lua54_total"
echo "METRIC lua55_total_ms=$lua55_total"
echo "METRIC total_ms=$luajit_total"