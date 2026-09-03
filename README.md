# wjson

[![CI](https://github.com/winterstream/wjson/actions/workflows/ci.yml/badge.svg)](https://github.com/winterstream/wjson/actions/workflows/ci.yml)
[![LuaRocks](https://img.shields.io/luarocks/v/winterstream/wjson.svg)](https://luarocks.org/modules/winterstream/wjson)

A fast, correct JSON library for Lua.

## About

`wjson` is a pure Lua JSON library designed around two priorities: correctness
first, and good performance without native dependencies. It works across
multiple Lua versions, including LuaJIT.

The implementation keeps a small set of measured optimizations in hot paths
while preserving shared parsing and Unicode logic where possible. It also
performs strict UTF-8 validation during decoding.

## Features

- **Pure Lua:** No external dependencies, making it easy to integrate.
- **Correctness:** Includes UTF-8 validation and passes the JSONTestSuite.
- **Simple API:** A straightforward `encode`/`decode` API with `decode_next` for
  streaming-style parsing.

## Installation

You can install `wjson` using LuaRocks:

```sh
luarocks install wjson
```

If LuaRocks is unavailable, download the single-file distribution from the
[latest GitHub release](https://github.com/winterstream/wjson/releases/latest):

```sh
curl -fsSL -o wjson.lua \
  https://github.com/winterstream/wjson/releases/latest/download/wjson.lua
```

Each GitHub release also includes the corresponding source rock and SHA-256
checksums.

## Benchmark Arena

Run an automated head-to-head benchmark on your own machine without installing
Lua or dependencies:

```sh
docker run --rm -it ghcr.io/winterstream/wjson
```

This compares `wjson` directly against pure Lua alternatives (`dkjson`,
`lunajson`, `rxi/json.lua`) and native C modules (`lua-cjson`, `dkjson` with
LPeg) across both synthetic payloads and multi-megabyte real-world datasets.

## API

### `wjson.encode(value)`

Encodes a Lua value into a JSON string.

- Lua `nil` and `wjson.null` are encoded as `null`.
- Non-finite Lua numbers (`0/0`, `math.huge`, `-math.huge`) are also encoded as
  `null`.
- Lua strings, numbers, and booleans are encoded as their JSON equivalents.
- Lua tables are encoded as either JSON arrays or objects.

**Example:**

```lua
local wjson = require("wjson")

local data = {
    name = "wjson",
    loves_json = true,
    features = {"fast", "correct", "pure lua"},
    version = 0.1,
    other = wjson.null
}

local json_string = wjson.encode(data)
print(json_string)
-- Output: {"name":"wjson","loves_json":true,"features":["fast","correct","pure lua"],"version":0.1,"other":null}
```

### `wjson.decode(json_string)`

Decodes a JSON string into a Lua value.

- `null` is decoded into `wjson.null`.
- JSON strings, numbers, booleans, arrays, and objects are decoded into their
  Lua equivalents.

**Example:**

```lua
local wjson = require("wjson")

local json_string = '{"name":"wjson","features":["fast","correct"]}'

local data = wjson.decode(json_string)

print(data.name) -- Output: wjson
print(data.features[1]) -- Output: fast
```

### `wjson.null`

A sentinel value used to represent `null` in JSON. This is useful to
differentiate between a `null` value and a key that is not present in a table
(`nil`).

### Arrays vs. Objects

`wjson` automatically detects whether a Lua table should be encoded as a JSON
array or a JSON object.

- **Array:** A table is considered an array if it is a sequence (keys are
  integers from 1 to `n`). You can also force a table to be treated as an array
  by setting its metatable to `wjson.array_mt`. `wjson.empty_array()` returns a
  new empty array, and `wjson.array_mt` is exported for callers that need to tag
  existing tables.
- **Object:** Any other table is encoded as a JSON object.

**Example:**

```lua
local wjson = require("wjson")

-- Encoded as an array
print(wjson.encode({10, 20, 30}))
-- Output: [10,20,30]

-- Encoded as an object
print(wjson.encode({x = 1, y = 2}))
-- Output: {"y":2,"x":1}

-- Force empty table to be an array
local empty_array = setmetatable({}, wjson.array_mt)
print(wjson.encode(empty_array))
-- Output: []
```

## Verification

Every push and pull request runs the full test suite on LuaJIT and Lua 5.2, 5.3,
and 5.4. The suite includes the JSONTestSuite and strict UTF-8 validation. The
rockspec is linted in CI as well.

## Development

To run the tests, you will need `busted` or `nix`. Then, run the test script:

```sh
./run_tests.sh
```

## Notes

- Decoder input is validated as UTF-8.
- Non-finite Lua numbers encode as `null` by policy.
- Performance-sensitive changes should be verified with `bench/bench.lua` and
  `./run_tests.sh`.
