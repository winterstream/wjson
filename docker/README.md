# wjson Benchmark Arena Container

A self-contained benchmarking container that pits **wjson** against popular Lua
JSON libraries:

- **wjson** `[PURE LUA]`
- **dkjson** `[PURE LUA]` (in pure-Lua scanner mode)
- **lunajson** `[PURE LUA]`
- **rxi/json.lua** `[PURE LUA]`
- **dkjson (LPeg)** `[C EXT]` (using the native C LPeg parsing expression
  grammar)
- **lua-cjson** `[C EXT]` (OpenResty native C module)

The arena runs synthetic benchmarks (shallow wide, deeply nested, unicode
escapes, complex numbers) as well as real-world multi-megabyte datasets (GitHub
gists, Turkish historical events, Barcelona universities, and Wikipedia movie
data).

## Running via Docker / Podman

Run directly:

```sh
# Default: LuaJIT
docker run --rm -it ghcr.io/winterstream/wjson

# Run under PUC Lua 5.5
docker run --rm -it ghcr.io/winterstream/wjson --lua55

# Run under PUC Lua 5.4
docker run --rm -it ghcr.io/winterstream/wjson --lua54

# Quick (~5s) run
docker run --rm -it ghcr.io/winterstream/wjson --quick
```

<!-- prettier-ignore -->
> [!NOTE]
> `wjson` supports LuaJIT and PUC Lua 5.2–5.5. It does not support PUC Lua 5.1
> because it uses `goto`.

## Available Flags

- `--quick` or `-q`: Run fewer iterations for rapid evaluation.
- `--lua55`: Run the arena under PUC Lua 5.5 instead of the default LuaJIT.
- `--lua54`: Run the arena under PUC Lua 5.4 instead of the default LuaJIT.
- `--datasets-only`: Run only real-world dataset benchmarks.
- `--synthetic-only`: Run only synthetic benchmarks.
- `--no-color`: Disable ANSI color codes (useful for logging to files).

## Building Locally

```sh
# Using Docker
docker build -t wjson-arena -f docker/Dockerfile .
docker run --rm -it wjson-arena

# Or using Make
make arena
```
