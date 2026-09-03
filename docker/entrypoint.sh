#!/usr/bin/env sh
set -e

if [ "$1" = "--lua55" ] || [ "$1" = "--lua5.5" ]; then
    shift
    export LUA_PATH="/app/?.lua;/app/src/?.lua;/app/src/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;;"
    export LUA_CPATH="/usr/lib/lua/5.5/?.so;;"
    exec lua5.5 /app/arena.lua "$@"
elif [ "$1" = "--lua54" ] || [ "$1" = "--lua5.4" ]; then
    shift
    export LUA_PATH="/app/?.lua;/app/src/?.lua;/app/src/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;;"
    export LUA_CPATH="/usr/lib/lua/5.4/?.so;;"
    exec lua5.4 /app/arena.lua "$@"
elif [ "$#" -eq 0 ]; then
    exec luajit /app/arena.lua
elif [ "$1" = "arena" ] || [ "$1" = "bench" ]; then
    shift
    exec luajit /app/arena.lua "$@"
elif [ "$1" = "sh" ] || [ "$1" = "bash" ] || [ "$1" = "luajit" ] || [ "$1" = "lua5.4" ] || [ "$1" = "lua5.5" ]; then
    exec "$@"
else
    exec luajit /app/arena.lua "$@"
fi
