#!/usr/bin/env bash
set -euo pipefail

# Run the benchmark and compute total encode+decode time for LuaJIT
# Output structured METRIC lines for autoresearch

cd "$(dirname "$0")"

# Pre-check: ensure library loads
if ! nix develop .#luajit -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" luajit -e "require('wjson')" 2>/dev/null; then
    echo "ERROR: wjson module failed to load"
    exit 1
fi

# Run benchmark and capture output
output=$(nix develop .#luajit -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" luajit bench/bench.lua 2>&1)

# Extract encode and decode times per line
encode_sum=0
decode_sum=0
while IFS= read -r line; do
    if [[ "$line" =~ Encode:[[:space:]]+([0-9]+\.[0-9]+)[[:space:]]+ms.*Decode:[[:space:]]+([0-9]+\.[0-9]+)[[:space:]]+ms ]]; then
        encode="${BASH_REMATCH[1]}"
        decode="${BASH_REMATCH[2]}"
        encode_sum=$(echo "$encode_sum + $encode" | bc -l)
        decode_sum=$(echo "$decode_sum + $decode" | bc -l)
    fi
done <<< "$output"

# Compute total time (encode + decode) in milliseconds
total_ms=$(echo "$encode_sum + $decode_sum" | bc -l)

# Output structured metrics
echo "METRIC total_ms=$total_ms"
echo "METRIC encode_ms=$encode_sum"
echo "METRIC decode_ms=$decode_sum"

# Also run benchmarks for other Lua versions to ensure no regression
for env in lua52 lua53 lua54; do
    echo "Running $env..."
    output_env=$(nix develop .#"$env" -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" lua bench/bench.lua 2>&1)
    env_encode_sum=0
    env_decode_sum=0
    while IFS= read -r line; do
        if [[ "$line" =~ Encode:[[:space:]]+([0-9]+\.[0-9]+)[[:space:]]+ms.*Decode:[[:space:]]+([0-9]+\.[0-9]+)[[:space:]]+ms ]]; then
            encode="${BASH_REMATCH[1]}"
            decode="${BASH_REMATCH[2]}"
            env_encode_sum=$(echo "$env_encode_sum + $encode" | bc -l)
            env_decode_sum=$(echo "$env_decode_sum + $decode" | bc -l)
        fi
    done <<< "$output_env"
    env_total=$(echo "$env_encode_sum + $env_decode_sum" | bc -l)
    echo "METRIC ${env}_total_ms=$env_total"
done