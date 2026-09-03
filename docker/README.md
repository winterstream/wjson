# wjson Benchmark Arena Container

A self-contained benchmarking container that pits **wjson** against popular Lua
JSON libraries:

- **wjson** `[PURE LUA]`
- **dkjson** `[PURE LUA]` (in pure-Lua scanner mode)
- **lunajson** `[PURE LUA]`
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
docker run --rm -it ghcr.io/winterstream/wjson
```

Or for a quick (~5s) run:

```sh
docker run --rm -it ghcr.io/winterstream/wjson --quick
```

## Available Flags

- `--quick` or `-q`: Run fewer iterations for rapid evaluation.
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
