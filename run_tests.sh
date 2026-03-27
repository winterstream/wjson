#!/usr/bin/env bash

set -e

# Add src to LUA_PATH
export LUA_PATH="./src/?.lua;./src/?/init.lua;;"

if command -v nix >/dev/null 2>&1; then
  # Define environments
  ENVS=("luajit" "lua52" "lua53" "lua54")
  
  for env in "${ENVS[@]}"; do
    echo "--- Testing with ${env} ---"
    nix develop ".#$env" -c busted "$@"
  done
else
  echo "--- Nix not found, testing with local busted ---"
  busted "$@"
fi
