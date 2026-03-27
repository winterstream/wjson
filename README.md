# wjson

A reasonably fast and very correct JSON library for Lua.

## About

`wjson` is a JSON library for Lua, designed with both speed and correctness in mind. It is written in pure Lua and works on a variety of Lua versions, including LuaJIT.

The library uses several optimization techniques, such as localizing functions, caching byte values, and a pointer-based scanner for decoding, to minimize string allocations and improve performance. It also includes comprehensive UTF-8 validation to ensure correct handling of Unicode characters.

## Features

- **Pure Lua:** No external dependencies, making it easy to integrate.
- **Correctness:** Includes UTF-8 validation and passes the JSONTestSuite.
- **Simple API:** A straightforward `encode` and `decode` API.
- **Array and Object Support:** Differentiates between Lua sequences (arrays) and tables (objects).

## Installation

You can install `wjson` using LuaRocks:

```sh
luarocks install wjson
```

## API

### `wjson.encode(value)`

Encodes a Lua value into a JSON string.

- Lua `nil`, `wjson.null`, `wjson.nan`, and `wjson.inf` are all encoded as `null`.
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
- JSON strings, numbers, booleans, arrays, and objects are decoded into their Lua equivalents.

**Example:**

```lua
local wjson = require("wjson")

local json_string = '{"name":"wjson","features":["fast","correct"]}'

local data = wjson.decode(json_string)

print(data.name) -- Output: wjson
print(data.features[1]) -- Output: fast
```

### `wjson.null`

A sentinel value used to represent `null` in JSON. This is useful to differentiate between a `null` value and a key that is not present in a table (`nil`).

### Arrays vs. Objects

`wjson` automatically detects whether a Lua table should be encoded as a JSON array or a JSON object.

- **Array:** A table is considered an array if it is a sequence (keys are integers from 1 to `n`). You can also force a table to be treated as an array by setting its metatable to `wjson.array_mt`. `wjson.empty_array()` returns a new empty array.
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

## Development

To run the tests, you will need `busted` or `nix`. Then, run the test script:

```sh
./run_tests.sh
```

## LLM Disclosure

This library was generated with the assistance of large language models. However, the author has spent considerable time reviewing the code. Furthermore, the author added the JSONTestSuite test cases to verify correctness and steered the LLM to generate various unit tests to verify correctness (which the author also reviewed).
