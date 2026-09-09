local is_luajit = jit ~= nil
local warmup_iters = is_luajit and (tonumber(os.getenv("BENCH_WARMUP")) or 5) or 0
local min_iters = math.max(1, tonumber(os.getenv("BENCH_MIN_ITERS")) or 3)

local tag_pure = "[PURE LUA]"
local tag_cext = "[C EXT]"

-- Load the same library variants as docker/arena.lua when available.
local libs = {}

local ok_wjson, mod_wjson = pcall(require, "wjson")
if not ok_wjson then
  ok_wjson, mod_wjson = pcall(require, "src.wjson")
end
if ok_wjson and type(mod_wjson) == "table" and mod_wjson.encode and mod_wjson.decode then
  table.insert(libs, {
    id = "wjson",
    name = "wjson",
    category = "pure",
    tag = tag_pure,
    encode = mod_wjson.encode,
    decode = mod_wjson.decode,
  })
end

local function load_dkjson_pure()
  local previous_preload = package.preload["lpeg"]
  local previous_loaded = package.loaded["lpeg"]

  package.preload["lpeg"] = function()
    error("LPeg disabled for pure-Lua dkjson test")
  end
  package.loaded["lpeg"] = nil
  local ok, mod = pcall(dofile, "bench/dkjson.lua")
  package.preload["lpeg"] = previous_preload
  package.loaded["lpeg"] = previous_loaded

  return ok, mod
end

local ok_dk_pure, mod_dk_pure = load_dkjson_pure()
if ok_dk_pure and type(mod_dk_pure) == "table" and not mod_dk_pure.using_lpeg then
  table.insert(libs, {
    id = "dkjson_pure",
    name = "dkjson",
    category = "pure",
    tag = tag_pure,
    encode = mod_dk_pure.encode,
    decode = mod_dk_pure.decode,
  })
end

local function load_lunajson()
  local ok, mod = pcall(require, "lunajson")
  if ok then
    return ok, mod
  end

  -- Keep the benchmark self-contained when LuaRocks is unavailable.
  local previous_path = package.path
  package.path = "bench/?.lua;bench/?/init.lua;" .. previous_path
  ok, mod = pcall(require, "lunajson")
  package.path = previous_path
  return ok, mod
end

local ok_luna, mod_luna = load_lunajson()
if ok_luna and type(mod_luna) == "table" and mod_luna.encode and mod_luna.decode then
  table.insert(libs, {
    id = "lunajson",
    name = "lunajson",
    category = "pure",
    tag = tag_pure,
    encode = mod_luna.encode,
    decode = mod_luna.decode,
  })
end

local ok_rxi, mod_rxi = pcall(function()
  return dofile("bench/rxi_json.lua")
end)
if not ok_rxi then
  ok_rxi, mod_rxi = pcall(require, "json")
end
if ok_rxi and type(mod_rxi) == "table" and mod_rxi.decode and mod_rxi.encode then
  table.insert(libs, {
    id = "rxi_json",
    name = "rxi/json.lua",
    category = "pure",
    tag = tag_pure,
    encode = mod_rxi.encode,
    decode = mod_rxi.decode,
  })
end

local ok_dk_lpeg, mod_dk_lpeg = pcall(function()
  local mod = dofile("bench/dkjson.lua")
  if mod.use_lpeg then
    return mod.use_lpeg()
  end
  return mod
end)
if ok_dk_lpeg and type(mod_dk_lpeg) == "table" and mod_dk_lpeg.using_lpeg then
  table.insert(libs, {
    id = "dkjson_lpeg",
    name = "dkjson (LPeg)",
    category = "cext",
    tag = tag_cext,
    encode = mod_dk_lpeg.encode,
    decode = mod_dk_lpeg.decode,
  })
end

local ok_cjson, mod_cjson = pcall(require, "cjson")
if not ok_cjson then
  ok_cjson, mod_cjson = pcall(require, "cjson.safe")
end
if ok_cjson and type(mod_cjson) == "table" and mod_cjson.encode and mod_cjson.decode then
  table.insert(libs, {
    id = "cjson",
    name = "lua-cjson",
    category = "cext",
    tag = tag_cext,
    encode = mod_cjson.encode,
    decode = mod_cjson.decode,
  })
end

if #libs == 0 then
  error("No JSON libraries could be loaded")
end

local function reset_jit_and_gc()
  if is_luajit then
    jit.flush()
    jit.on()
  end
  collectgarbage("collect")
end

-- Random number generator seed
math.randomseed(42)

local function codepoint_to_utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(
      0xC0 + math.floor(cp / 64),
      0x80 + (cp % 64)
    )
  elseif cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 4096),
      0x80 + (math.floor(cp / 64) % 64),
      0x80 + (cp % 64)
    )
  else
    return string.char(
      0xF0 + math.floor(cp / 262144),
      0x80 + (math.floor(cp / 4096) % 64),
      0x80 + (math.floor(cp / 64) % 64),
      0x80 + (cp % 64)
    )
  end
end

local function random_string(min_len, max_len)
  local len = math.random(min_len, max_len)
  local chars = {}
  for i = 1, len do
    local r = math.random()
    if r < 0.05 then
      chars[i] = string.char(math.random(1, 31)) -- Control char to escape
    elseif r < 0.10 then
      chars[i] = '\\'
    elseif r < 0.15 then
      chars[i] = '"'
    elseif r < 0.25 then
      -- Arabic: 2-byte UTF-8
      chars[i] = codepoint_to_utf8(math.random(0x0600, 0x06FF))
    elseif r < 0.35 then
      -- Chinese: 3-byte UTF-8
      chars[i] = codepoint_to_utf8(math.random(0x4E00, 0x9FFF))
    elseif r < 0.45 then
      -- Emoji: 4-byte UTF-8
      chars[i] = codepoint_to_utf8(math.random(0x1F300, 0x1F9FF))
    else
      chars[i] = string.char(math.random(32, 126))
    end
  end
  return table.concat(chars)
end

local function generate_shallow_wide(min_len, max_len)
  local tbl = {}
  -- 200 fields per shallow object
  for i = 1, 200 do
    local key = "field_" .. i .. "_" .. random_string(5, 15)
    local val_type = math.random(1, 3)
    if val_type == 1 then
      tbl[key] = random_string(min_len, max_len)
    elseif val_type == 2 then
      tbl[key] = math.random() * 1000000
    else
      tbl[key] = math.random() > 0.5
    end
  end
  return tbl
end

local deep_table_count = 0
local function generate_deep_nested(depth, min_len, max_len)
  if depth == 0 then
    if math.random() > 0.5 then
      return random_string(min_len, max_len)
    else
      return math.random() * 1000
    end
  end

  local is_array = math.random() > 0.5
  local tbl = {}
  deep_table_count = deep_table_count + 1

  -- Each level has 2-4 children
  local children = math.random(2, 4)
  for i = 1, children do
    local val = generate_deep_nested(depth - 1, min_len, max_len)
    if is_array then
      table.insert(tbl, val)
    else
      local key = "nested_key_" .. random_string(5, 10)
      tbl[key] = val
    end
  end
  return tbl
end

local function measure(lib, tbl, iterations)
  local ok, str = pcall(lib.encode, tbl)
  if not ok or type(str) ~= "string" then
    return 0, 0, false
  end

  -- Warmup
  for _ = 1, warmup_iters do
    lib.encode(tbl)
    lib.decode(str)
  end

  local start = os.clock()
  for _ = 1, iterations do
    lib.encode(tbl)
  end
  local encode_time = os.clock() - start

  start = os.clock()
  for _ = 1, iterations do
    lib.decode(str)
  end
  local decode_time = os.clock() - start

  return encode_time, decode_time, true
end

local function print_benchmark_result(lib, label, encode_time, decode_time,
    can_encode, can_decode, denominator)
  local encode_result = can_encode
    and string.format("Encode: %6.2f ms", (encode_time / denominator) * 1000)
    or "Encode:    N/A"
  local decode_result = can_decode
    and string.format("Decode: %6.2f ms", (decode_time / denominator) * 1000)
    or "Decode:    N/A"

  print(string.format("%-12s | %-45s | %s | %s",
    lib.name, label, encode_result, decode_result))
end

local function run_benchmark(label, generator, sets, iters_per_set)
  local total_e = {}
  local total_d = {}
  local failed = {}

  for lib_index in ipairs(libs) do
    total_e[lib_index] = 0
    total_d[lib_index] = 0
    failed[lib_index] = false
  end

  -- Generate each payload once so every library sees the same input.
  for _ = 1, sets do
    local tbl = generator()
    for lib_index, lib in ipairs(libs) do
      reset_jit_and_gc()
      local e, d, ok = measure(lib, tbl, iters_per_set)
      if ok then
        total_e[lib_index] = total_e[lib_index] + e
        total_d[lib_index] = total_d[lib_index] + d
      else
        failed[lib_index] = true
      end
    end
  end

  local denominator = sets * iters_per_set
  for lib_index, lib in ipairs(libs) do
    print_benchmark_result(lib, label, total_e[lib_index], total_d[lib_index],
      not failed[lib_index], not failed[lib_index], denominator)
  end
end

print("=========================================================================")
print("JSON Benchmark Suite")
print("Libraries:")
for _, lib in ipairs(libs) do
  print(string.format("  * %-16s %s", lib.name, lib.tag))
end
if jit then
  print("VM: LuaJIT " .. jit.version)
else
  print("VM: Lua " .. _VERSION)
end
local sets = tonumber(os.getenv("BENCH_SETS")) or 20
local iters_per_set = tonumber(os.getenv("BENCH_ITERS")) or 20
local iters_per_big_set = math.max(1, math.floor(iters_per_set / 2))

print(string.format("Running benchmarks (%d data sets per type)...", sets))
print("=========================================================================")

run_benchmark("Shallow Wide (Short Strings, 200 fields)", function()
  return generate_shallow_wide(32, 256)
end, sets, iters_per_set)

run_benchmark("Shallow Wide (Long Strings, 200 fields)", function()
  return generate_shallow_wide(1024, 16384)
end, sets, iters_per_big_set)

run_benchmark("Deeply Nested (Short Strings, ~120 tables)", function()
  return generate_deep_nested(5, 32, 256)
end, sets, iters_per_set)

run_benchmark("Deeply Nested (Long Strings, ~160 tables)", function()
  return generate_deep_nested(5, 1024, 16384)
end, sets, iters_per_big_set)

local function read_file(path)
  local is_gz = path:match("%.gz$")
  local f
  if is_gz then
    f = io.popen("gzip -dc " .. path, "r")
  else
    f = io.open(path, "rb")
  end
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end



local datasets = {}
local synthetic_datasets = {}
local dataset_files = {
  "spec/datasets/github-gists.json.gz",
  "spec/datasets/historical-events-tr.json.gz",
  "spec/datasets/province-of-barcelona-universities.json.gz",
  "spec/datasets/wikipedia-movie-data.json.gz"
}

for _, file in ipairs(dataset_files) do
  local content = read_file(file)
  if content then
    table.insert(datasets, { name = file:match("([^/]+)%.json%.gz$"), raw = content, length = #content })
  end
end

-- Generate a synthetic dataset with lots of \uXXXX sequences to test the decoder's backslash logic
local function generate_unicode_escaped_json()
  local parts = { "{\"synthetic_unicode\": [" }
  for i = 1, 1000 do
    local r = math.random()
    if r < 0.3 then
      -- Arabic: \uXXXX
      table.insert(parts, string.format("\"\\u%04x\"", math.random(0x0600, 0x06FF)))
    elseif r < 0.6 then
      -- Chinese: \uXXXX
      table.insert(parts, string.format("\"\\u%04x\"", math.random(0x4E00, 0x9FFF)))
    else
      -- Emoji: surrogate pair
      local cp = math.random(0x1F300, 0x1F9FF)
      cp = cp - 0x10000
      local hi = 0xD800 + math.floor(cp / 1024)
      local lo = 0xDC00 + (cp % 1024)
      table.insert(parts, string.format("\"\\u%04x\\u%04x\"", hi, lo))
    end
    if i < 1000 then table.insert(parts, ",") end
  end
  table.insert(parts, "], \"mixed\": \"")
  for i = 1, 100 do
    table.insert(parts, string.format("hello \\u%04x world", math.random(0x0600, 0x06FF)))
  end
  table.insert(parts, "\"}")
  return table.concat(parts)
end

local function generate_complex_numbers_json()
  local parts = { "{\"synthetic_numbers\": [" }
  for i = 1, 3000 do
    local r = math.random()
    if r < 0.2 then
      -- standard integer
      table.insert(parts, tostring(math.random(-1000000, 1000000)))
    elseif r < 0.4 then
      -- Many decimal points
      table.insert(parts, string.format("%.15f", math.random() * 200 - 100))
    elseif r < 0.6 then
      -- Scientific with negative exponent
      table.insert(parts, string.format("%.5fe-%d", math.random() * 10, math.random(5, 50)))
    elseif r < 0.8 then
      -- Scientific with positive exponent
      table.insert(parts, string.format("%.5fe+%d", math.random() * 10, math.random(5, 50)))
    else
      -- Large decimal representations
      local sign = math.random() > 0.5 and "-" or ""
      table.insert(parts, sign .. "0." .. string.rep(tostring(math.random(0, 9)), math.random(10, 30)))
    end
    if i < 3000 then table.insert(parts, ",") end
  end
  table.insert(parts, "]}")
  return table.concat(parts)
end

local synthetic_json = generate_unicode_escaped_json()
table.insert(synthetic_datasets,
  { name = "synthetic-unicode-escapes", raw = synthetic_json, length = #synthetic_json })

local synthetic_numbers_json = generate_complex_numbers_json()
table.insert(synthetic_datasets,
  { name = "synthetic-complex-numbers", raw = synthetic_numbers_json, length = #synthetic_numbers_json })

local function run_dataset_benchmarks(ds_list)
  for _, ds in ipairs(ds_list) do
    local base_iters = 20
    if ds.length > 5000000 then    -- Size > ~5MB
      base_iters = 5
    elseif ds.length > 500000 then -- Size > ~500KB
      base_iters = 10
    end

    local iters = math.max(min_iters, math.floor(base_iters * sets / 20))

    -- Run each decoder on the original payload and encode its parsed table.
    for _, lib in ipairs(libs) do
      reset_jit_and_gc()
      local decode_ok, tbl = pcall(lib.decode, ds.raw)
      decode_ok = decode_ok and tbl ~= nil
      local encode_ok = false
      local decode_time = 0
      local encode_time = 0

      if decode_ok then
        -- Flush before warmup, not immediately before the timed section. This
        -- measures steady-state decoding rather than trace compilation.
        for _ = 1, warmup_iters do
          lib.decode(ds.raw)
        end
        if warmup_iters > 0 then
          collectgarbage("collect")
        end

        local decode_start = os.clock()
        for _ = 1, iters do
          lib.decode(ds.raw)
        end
        decode_time = os.clock() - decode_start

        local ok_encoded, encoded = pcall(lib.encode, tbl)
        encode_ok = ok_encoded and type(encoded) == "string"
        if encode_ok then
          for _ = 1, warmup_iters do
            lib.encode(tbl)
          end
          if warmup_iters > 0 then
            collectgarbage("collect")
          end

          local encode_start = os.clock()
          for _ = 1, iters do
            lib.encode(tbl)
          end
          encode_time = os.clock() - encode_start
        end
      end

      print_benchmark_result(lib, "Dataset: " .. ds.name, encode_time, decode_time,
        encode_ok, decode_ok, iters)
    end
  end
end

if #synthetic_datasets > 0 then
  print("=========================================================================")
  print("Synthetic Datasets")
  print("=========================================================================")
  run_dataset_benchmarks(synthetic_datasets)
end

if #datasets > 0 then
  print("=========================================================================")
  print("Real-world Datasets")
  print("=========================================================================")
  run_dataset_benchmarks(datasets)
end

print("=========================================================================")
