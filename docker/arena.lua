--[==[
LUA JSON BENCHMARK ARENA
Pitting wjson against dkjson (Pure Lua), lunajson (Pure Lua),
dkjson (LPeg C Extension), and lua-cjson (C Extension).
]==]

local is_luajit = (jit ~= nil)
local vm_name = is_luajit and ("LuaJIT " .. jit.version) or _VERSION

-- Parse arguments
local opt_quick = false
local opt_no_color = false
local opt_datasets_only = false
local opt_synthetic_only = false

for _, arg_val in ipairs(arg or {}) do
  if arg_val == "--quick" or arg_val == "-q" then
    opt_quick = true
  elseif arg_val == "--no-color" then
    opt_no_color = true
  elseif arg_val == "--datasets-only" then
    opt_datasets_only = true
  elseif arg_val == "--synthetic-only" then
    opt_synthetic_only = true
  end
end

-- Terminal colors
local c_reset  = opt_no_color and "" or "\27[0m"
local c_bold   = opt_no_color and "" or "\27[1m"
local c_dim    = opt_no_color and "" or "\27[2m"
local c_red    = opt_no_color and "" or "\27[31m"
local c_green  = opt_no_color and "" or "\27[32m"
local c_yellow = opt_no_color and "" or "\27[33m"
local c_blue   = opt_no_color and "" or "\27[34m"
local c_cyan   = opt_no_color and "" or "\27[36m"
local c_white  = opt_no_color and "" or "\27[37m"

local tag_pure = opt_no_color and "[PURE LUA]" or (c_green .. c_bold .. "[PURE LUA]" .. c_reset)
local tag_cext = opt_no_color and "[C EXT]   " or (c_yellow .. c_bold .. "[C EXT]   " .. c_reset)

-- Print header banner
print(c_cyan .. c_bold .. "================================================================================" .. c_reset)
print(c_white .. c_bold .. "                     LUA JSON BENCHMARK ARENA                                   " .. c_reset)
print(c_cyan .. c_bold .. "================================================================================" .. c_reset)
print(string.format("%sRuntime:%s %s%s%s", c_bold, c_reset, c_yellow, vm_name, c_reset))
print(string.format("%sMode:%s    %s", c_bold, c_reset, opt_quick and (c_yellow .. "Quick (reduced iterations)" .. c_reset) or "Standard"))
print()
print(c_bold .. "Libraries under test:" .. c_reset)
print(string.format("  * %s%-16s%s %s (Pure Lua, zero dependencies)", c_green, "wjson", c_reset, tag_pure))
print(string.format("  * %s%-16s%s %s (dkjson in pure-Lua scanner mode)", c_green, "dkjson", c_reset, tag_pure))
print(string.format("  * %s%-16s%s %s (lunajson pure-Lua parser)", c_green, "lunajson", c_reset, tag_pure))
print(string.format("  * %s%-16s%s %s (rxi/json.lua pure-Lua parser)", c_green, "rxi/json.lua", c_reset, tag_pure))
print(string.format("  * %s%-16s%s %s (dkjson using C LPeg grammar)", c_yellow, "dkjson (LPeg)", c_reset, tag_cext))
print(string.format("  * %s%-16s%s %s (OpenResty lua-cjson native C module)", c_yellow, "lua-cjson", c_reset, tag_cext))
print(c_cyan .. "--------------------------------------------------------------------------------" .. c_reset)

-- Load libraries
local libs = {}

-- 1. wjson
local ok_wjson, mod_wjson = pcall(require, "wjson")
if not ok_wjson then
  ok_wjson, mod_wjson = pcall(require, "src.wjson")
end
if ok_wjson and mod_wjson then
  table.insert(libs, {
    id = "wjson",
    name = "wjson",
    category = "pure",
    tag = tag_pure,
    encode = mod_wjson.encode,
    decode = mod_wjson.decode,
  })
else
  print(c_red .. "Warning: wjson could not be loaded: " .. tostring(mod_wjson) .. c_reset)
end

-- 2. dkjson (Pure Lua mode)
package.preload["lpeg"] = function() error("LPeg disabled for pure-Lua dkjson test") end
package.loaded["lpeg"] = nil
local ok_dk_pure, mod_dk_pure = pcall(function()
  return dofile("bench/dkjson.lua")
end)
if not ok_dk_pure then
  ok_dk_pure, mod_dk_pure = pcall(require, "dkjson")
end
package.preload["lpeg"] = nil
package.loaded["lpeg"] = nil

if ok_dk_pure and mod_dk_pure and not mod_dk_pure.using_lpeg then
  table.insert(libs, {
    id = "dkjson_pure",
    name = "dkjson",
    category = "pure",
    tag = tag_pure,
    encode = mod_dk_pure.encode,
    decode = mod_dk_pure.decode,
  })
end

-- 3. lunajson (Pure Lua)
local ok_luna, mod_luna = pcall(require, "lunajson")
if ok_luna and mod_luna then
  table.insert(libs, {
    id = "lunajson",
    name = "lunajson",
    category = "pure",
    tag = tag_pure,
    encode = mod_luna.encode,
    decode = mod_luna.decode,
  })
end

-- 4. rxi/json.lua (Pure Lua)
local ok_rxi, mod_rxi = pcall(function()
  return dofile("bench/rxi_json.lua")
end)
if not ok_rxi then
  ok_rxi, mod_rxi = pcall(require, "json")
end
if ok_rxi and mod_rxi and mod_rxi.decode and mod_rxi.encode then
  table.insert(libs, {
    id = "rxi_json",
    name = "rxi/json.lua",
    category = "pure",
    tag = tag_pure,
    encode = mod_rxi.encode,
    decode = mod_rxi.decode,
  })
end

-- 5. dkjson (LPeg mode)
local ok_dk_lpeg, mod_dk_lpeg = pcall(function()
  local d = dofile("bench/dkjson.lua")
  if d.use_lpeg then
    return d.use_lpeg()
  end
  return d
end)
if ok_dk_lpeg and mod_dk_lpeg and mod_dk_lpeg.using_lpeg then
  table.insert(libs, {
    id = "dkjson_lpeg",
    name = "dkjson (LPeg)",
    category = "cext",
    tag = tag_cext,
    encode = mod_dk_lpeg.encode,
    decode = mod_dk_lpeg.decode,
  })
end

-- 5. lua-cjson (C Extension)
local ok_cjson, mod_cjson = pcall(require, "cjson")
if not ok_cjson then
  ok_cjson, mod_cjson = pcall(require, "cjson.safe")
end
if ok_cjson and mod_cjson then
  table.insert(libs, {
    id = "cjson",
    name = "lua-cjson",
    category = "cext",
    tag = tag_cext,
    encode = mod_cjson.encode,
    decode = mod_cjson.decode,
  })
end

local function reset_jit_and_gc()
  if is_luajit then
    jit.flush()
    jit.on()
  end
  collectgarbage("collect")
end

math.randomseed(42)

local function codepoint_to_utf8(cp)
  if cp >= 0xD800 and cp <= 0xDFFF then cp = 0x2020 end
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64))
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + (math.floor(cp / 64) % 64), 0x80 + (cp % 64))
  else
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + (math.floor(cp / 4096) % 64), 0x80 + (math.floor(cp / 64) % 64), 0x80 + (cp % 64))
  end
end

local function random_string(min_len, max_len)
  local len = math.random(min_len, max_len)
  local t = {}
  for i = 1, len do
    local r = math.random()
    if r < 0.85 then
      t[i] = string.char(math.random(32, 126))
    elseif r < 0.95 then
      t[i] = codepoint_to_utf8(math.random(0x0080, 0x07FF))
    else
      t[i] = codepoint_to_utf8(math.random(0x0800, 0xD7FF))
    end
  end
  return table.concat(t)
end

local function generate_shallow_wide(min_s, max_s)
  local t = {}
  for i = 1, 200 do
    t["key_" .. i] = random_string(min_s, max_s)
  end
  return t
end

local function generate_deep_nested(depth, min_s, max_s)
  local root = {}
  local current = root
  for d = 1, depth do
    current.meta = { level = d, desc = random_string(min_s, max_s) }
    current.items = {}
    for i = 1, 5 do
      table.insert(current.items, { id = i, name = random_string(min_s, max_s) })
    end
    current.next = {}
    current = current.next
  end
  current.terminal = true
  return root
end

local function generate_unicode_escaped_json()
  local parts = { "{\"synthetic_unicode\": [" }
  for i = 1, 800 do
    local r = math.random()
    if r < 0.3 then
      table.insert(parts, string.format("\"\\u%04x\"", math.random(0x0600, 0x06FF)))
    elseif r < 0.6 then
      table.insert(parts, string.format("\"\\u%04x\"", math.random(0x4E00, 0x9FFF)))
    else
      local cp = math.random(0x1F300, 0x1F9FF) - 0x10000
      local hi = 0xD800 + math.floor(cp / 1024)
      local lo = 0xDC00 + (cp % 1024)
      table.insert(parts, string.format("\"\\u%04x\\u%04x\"", hi, lo))
    end
    if i < 800 then table.insert(parts, ",") end
  end
  table.insert(parts, "], \"mixed\": \"")
  for _ = 1, 80 do
    table.insert(parts, string.format("hello \\u%04x world", math.random(0x0600, 0x06FF)))
  end
  table.insert(parts, "\"}")
  return table.concat(parts)
end

local function generate_complex_numbers_json()
  local parts = { "{\"synthetic_numbers\": [" }
  for i = 1, 2500 do
    local r = math.random()
    if r < 0.2 then
      table.insert(parts, tostring(math.random(-1000000, 1000000)))
    elseif r < 0.4 then
      table.insert(parts, string.format("%.15f", math.random() * 200 - 100))
    elseif r < 0.6 then
      table.insert(parts, string.format("%.5fe-%d", math.random() * 10, math.random(5, 50)))
    elseif r < 0.8 then
      table.insert(parts, string.format("%.5fe+%d", math.random() * 10, math.random(5, 50)))
    else
      local sign = math.random() > 0.5 and "-" or ""
      table.insert(parts, sign .. "0." .. string.rep(tostring(math.random(0, 9)), math.random(10, 25)))
    end
    if i < 2500 then table.insert(parts, ",") end
  end
  table.insert(parts, "]}")
  return table.concat(parts)
end

local function read_file(path)
  local is_gz = path:match("%.gz$")
  local f = is_gz and io.popen("gzip -dc " .. path, "r") or io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

-- Assemble benchmark targets
local targets = {}

if not opt_datasets_only then
  local sw_short = generate_shallow_wide(16, 64)
  local sw_short_json = mod_wjson.encode(sw_short)
  table.insert(targets, { name = "Shallow Wide (Short Strings, 200 keys)", json = sw_short_json, size = #sw_short_json, iters = opt_quick and 10 or 30 })

  local sw_long = generate_shallow_wide(512, 4096)
  local sw_long_json = mod_wjson.encode(sw_long)
  table.insert(targets, { name = "Shallow Wide (Long Strings, 200 keys)", json = sw_long_json, size = #sw_long_json, iters = opt_quick and 3 or 8 })

  local dn_short = generate_deep_nested(5, 16, 64)
  local dn_short_json = mod_wjson.encode(dn_short)
  table.insert(targets, { name = "Deeply Nested (Short Strings, ~120 tables)", json = dn_short_json, size = #dn_short_json, iters = opt_quick and 10 or 25 })

  local uni_json = generate_unicode_escaped_json()
  table.insert(targets, { name = "Synthetic Unicode Escapes (\\uXXXX)", json = uni_json, size = #uni_json, iters = opt_quick and 5 or 15 })

  local num_json = generate_complex_numbers_json()
  table.insert(targets, { name = "Synthetic Complex Numbers (2500 nums)", json = num_json, size = #num_json, iters = opt_quick and 5 or 15 })
end

if not opt_synthetic_only then
  local dataset_paths = {
    "spec/datasets/github-gists.json.gz",
    "spec/datasets/historical-events-tr.json.gz",
    "spec/datasets/province-of-barcelona-universities.json.gz",
    "spec/datasets/wikipedia-movie-data.json.gz"
  }

  for _, path in ipairs(dataset_paths) do
    local raw = read_file(path)
    if raw and #raw > 0 then
      local base_name = path:match("([^/]+)%.json%.gz$")
      local iters
      if #raw > 5000000 then
        iters = opt_quick and 2 or 5
      elseif #raw > 500000 then
        iters = opt_quick and 3 or 8
      else
        iters = opt_quick and 5 or 15
      end
      table.insert(targets, { name = "Dataset: " .. base_name, json = raw, size = #raw, iters = iters })
    end
  end
end

-- Benchmark execution and reporting

for t_idx, target in ipairs(targets) do
  local size_kb = target.size / 1024
  local size_str = size_kb >= 1024 and string.format("%.2f MB", size_kb / 1024) or string.format("%.1f KB", size_kb)
  print()
  print(string.format("%s[%d/%d] %s%s (%s, %d iters)%s", c_bold, t_idx, #targets, c_white, target.name, size_str, target.iters, c_reset))
  print(c_dim .. string.rep("-", 80) .. c_reset)

  local results = {}
  local wjson_decode_time = nil

  for _, lib in ipairs(libs) do
    -- Warmup & pre-decode to obtain Lua table for encode benchmark
    local ok_dec, parsed_val = pcall(lib.decode, target.json)
    local can_decode = ok_dec and (parsed_val ~= nil)
    local can_encode = false

    if can_decode then
      local ok_enc = pcall(lib.encode, parsed_val)
      can_encode = ok_enc
    end

    local d_total = 0
    local e_total = 0

    if can_decode and target.iters > 0 then
      -- 1. Benchmark Decode
      for _ = 1, (is_luajit and 2 or 0) do pcall(lib.decode, target.json) end
      reset_jit_and_gc()
      local t0 = os.clock()
      for _ = 1, target.iters do
        lib.decode(target.json)
      end
      d_total = (os.clock() - t0)

      -- 2. Benchmark Encode
      if can_encode then
        for _ = 1, (is_luajit and 2 or 0) do pcall(lib.encode, parsed_val) end
        reset_jit_and_gc()
        local t1 = os.clock()
        for _ = 1, target.iters do
          lib.encode(parsed_val)
        end
        e_total = (os.clock() - t1)
      end
    end

    local d_avg_ms = (d_total / target.iters) * 1000
    local e_avg_ms = (e_total / target.iters) * 1000
    local throughput_mb = (d_avg_ms > 0) and ((target.size / (1024 * 1024)) / (d_avg_ms / 1000)) or 0

    if lib.id == "wjson" and can_decode then
      wjson_decode_time = d_avg_ms
    end

    local res = {
      lib = lib,
      can_decode = can_decode,
      can_encode = can_encode,
      d_ms = d_avg_ms,
      e_ms = e_avg_ms,
      mb_s = throughput_mb,
    }
    table.insert(results, res)
  end

  -- Print results grouped by Pure Lua vs C Extension
  for _, category in ipairs({ "pure", "cext" }) do
    local is_pure = (category == "pure")
    local cat_label = is_pure and (c_green .. c_bold .. "=== PURE LUA IMPLEMENTATIONS ===" .. c_reset)
                               or (c_yellow .. c_bold .. "=== C EXTENSIONS / HYBRID ===" .. c_reset)
    print("  " .. cat_label)

    for _, res in ipairs(results) do
      if res.lib.category == category then
        local ratio_str = ""
        if res.can_decode and wjson_decode_time and wjson_decode_time > 0 then
          local ratio = res.d_ms / wjson_decode_time
          if math.abs(ratio - 1.0) < 0.05 then
            ratio_str = c_cyan .. " [baseline]" .. c_reset
          elseif ratio < 1.0 then
            ratio_str = string.format("%s [%.1fx faster]%s", c_yellow, 1.0 / ratio, c_reset)
          else
            ratio_str = string.format("%s [%.1fx slower]%s", c_dim, ratio, c_reset)
          end
        end

        local speed_str = res.mb_s > 0 and string.format("%6.1f MB/s", res.mb_s) or "   N/A   "
        local enc_str = res.can_encode and string.format("Encode: %7.2f ms", res.e_ms) or "Encode:     N/A  "
        local dec_str = res.can_decode and string.format("Decode: %7.2f ms", res.d_ms) or "Decode:     N/A  "

        local name_col = (res.lib.id == "wjson")
          and (c_bold .. c_green .. string.format("%-14s", res.lib.name) .. c_reset)
          or string.format("%-14s", res.lib.name)

        print(string.format("    %s %s | %s | %s | Speed: %s%s",
          res.lib.tag, name_col, dec_str, enc_str, speed_str, ratio_str))
      end
    end
  end
end

print()
print(c_cyan .. "================================================================================" .. c_reset)
print(c_dim .. "Note: wjson provides 100% pure Lua execution with zero C dependencies." .. c_reset)
print()
