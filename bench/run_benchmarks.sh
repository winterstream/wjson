#!/usr/bin/env bash
set -e

RUN_DKJSON=false
for arg in "$@"; do
    if [ "$arg" == "--run_dkjson" ]; then
        RUN_DKJSON=true
        break
    fi
done

run_in_nix() {
    local shell_name=$1
    local cmd=$2
    echo "========================================================================="
    echo "Running with Nix environment: $shell_name"
    
    echo ">>> Running wjson benchmarks..."
    nix develop ".#$shell_name" -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" $cmd bench/bench.lua
    
    if [ "$RUN_DKJSON" = true ]; then
        echo ""
        echo ">>> Running dkjson benchmarks..."
        nix develop ".#$shell_name" -c env LUA_CPATH="" LUA_PATH="src/?.lua;bench/?.lua;;" USE_DKJSON=1 $cmd bench/bench.lua
    fi
}

if command -v nix > /dev/null 2>&1; then
    run_in_nix "luajit" "luajit"
    run_in_nix "lua52" "lua"
    run_in_nix "lua53" "lua"
    run_in_nix "lua54" "lua"
else
    echo "Nix is not available. Please install nix to run full matrix."
    exit 1
fi
