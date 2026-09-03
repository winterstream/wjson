#!/usr/bin/env sh
set -e

if [ "$#" -eq 0 ]; then
    exec luajit /app/arena.lua
elif [ "$1" = "arena" ] || [ "$1" = "bench" ]; then
    shift
    exec luajit /app/arena.lua "$@"
elif [ "$1" = "sh" ] || [ "$1" = "bash" ] || [ "$1" = "luajit" ] || [ "$1" = "lua5.4" ]; then
    exec "$@"
else
    exec luajit /app/arena.lua "$@"
fi
