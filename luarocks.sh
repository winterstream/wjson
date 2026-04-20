#!/usr/bin/env bash

set -e

if command -v nix &> /dev/null; then
    echo "Found nix, executing via 'nix shell'..."
    nix shell nixpkgs#luarocks --command luarocks "$@"
else
    echo "nix not found, using global luarocks directly..."
    luarocks "$@"
fi
