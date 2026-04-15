local use_dkjson = os.getenv("USE_DKJSON") == "1"
for _, v in ipairs(arg or {}) do
  if v == "--dkjson" then
    use_dkjson = true
    break
  end
end

local json_lib
local lib_name

if use_dkjson then
  json_lib = require("bench.dkjson")
  lib_name = "dkjson"
else
  json_lib = require("wjson")
  lib_name = "wjson"
end

local wjson = json_lib -- Keep variable name for compatibility or refactor; let's refactor to json_lib

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
    local val_type = math.random(1, 4)
    if val_type == 1 then
      tbl[key] = random_string(min_len, max_len)
    elseif val_type == 2 then
      tbl[key] = math.random() * 1000000
    elseif val_type == 3 then
      tbl[key] = math.random() > 0.5
    else
      tbl[key] = json_lib.null
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
  -- dkjson doesn't use array_mt, so we only apply it for wjson
  local tbl = (is_array and json_lib.array_mt) and setmetatable({}, json_lib.array_mt) or {}
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

local function measure(tbl, iterations)
  collectgarbage("collect")
  local ok, str = pcall(json_lib.encode, tbl)
  if not ok then return 0, 0 end

  -- Warmup
  for i = 1, 10 do
    json_lib.encode(tbl)
    json_lib.decode(str)
  end

  local start = os.clock()
  for i = 1, iterations do
    json_lib.encode(tbl)
  end
  local encode_time = os.clock() - start

  start = os.clock()
  for i = 1, iterations do
    json_lib.decode(str)
  end
  local decode_time = os.clock() - start

  return encode_time, decode_time
end

local function run_benchmark(label, generator, sets, iters_per_set)
  local total_e, total_d = 0, 0
  for _ = 1, sets do
    local tbl = generator()
    local e, d = measure(tbl, iters_per_set)
    total_e = total_e + e
    total_d = total_d + d
  end
  local avg_e = (total_e / (sets * iters_per_set)) * 1000
  local avg_d = (total_d / (sets * iters_per_set)) * 1000
  print(string.format("%-45s | Encode: %6.2f ms | Decode: %6.2f ms", label, avg_e, avg_d))
end

print("=========================================================================")
print("JSON Benchmark Suite")
print("Library: " .. lib_name)
if jit then
  print("VM: LuaJIT " .. jit.version)
else
  print("VM: Lua " .. _VERSION)
end
print("Running benchmarks (20 data sets per type)...")
print("=========================================================================")

local sets = 20
local iters_per_set = 20
local iters_per_big_set = 10

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

local function measure_dataset(raw_string, iterations)
  collectgarbage("collect")
  local ok, tbl = pcall(json_lib.decode, raw_string)
  if not ok then return 0, 0 end

  -- Warmup
  for i = 1, math.min(3, iterations) do
    json_lib.decode(raw_string)
    pcall(json_lib.encode, tbl)
  end

  local start = os.clock()
  for i = 1, iterations do
    json_lib.encode(tbl)
  end
  local encode_time = os.clock() - start

  start = os.clock()
  for i = 1, iterations do
    json_lib.decode(raw_string)
  end
  local decode_time = os.clock() - start

  return encode_time, decode_time
end

local datasets = {}
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
      table.insert(parts, sign .. "0." .. string.rep(tostring(math.random(0,9)), math.random(10, 30)))
    end
    if i < 3000 then table.insert(parts, ",") end
  end
  table.insert(parts, "]}")
  return table.concat(parts)
end

local synthetic_json = generate_unicode_escaped_json()
table.insert(datasets, { name = "synthetic-unicode-escapes", raw = synthetic_json, length = #synthetic_json })

local synthetic_numbers_json = generate_complex_numbers_json()
table.insert(datasets, { name = "synthetic-complex-numbers", raw = synthetic_numbers_json, length = #synthetic_numbers_json })

if #datasets > 0 then
  print("=========================================================================")
  print("Real-world Datasets")
  print("=========================================================================")
  for _, ds in ipairs(datasets) do
    local iters = 20
    if ds.length > 5000000 then    -- Size > ~5MB
      iters = 5
    elseif ds.length > 500000 then -- Size > ~500KB
      iters = 10
    end

    local e, d = measure_dataset(ds.raw, iters)
    local avg_e = (e / iters) * 1000
    local avg_d = (d / iters) * 1000

    print(string.format("%-45s | Encode: %6.2f ms | Decode: %6.2f ms", "Dataset: " .. ds.name, avg_e, avg_d))
  end
end

print("=========================================================================")
