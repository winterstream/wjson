--[==[
wjson is a pure Lua JSON library.

# API
- `encode(val[, buffer])`: Serialize Lua values to JSON. Pass a reusable buffer
  when you want to avoid allocations across repeated calls.
- `decode(str)`: Parse exactly one JSON value from a string.
- `decode_next(str[, len[, pos]])`: Parse the next JSON value and return the
  value plus the position immediately after it.
- `empty_array()`: Return a fresh table that always encodes as `[]`.
- `array_mt`: Metatable that forces a table to encode as a JSON array.

# Behavior notes
- `wjson.null` represents JSON `null`.
- NaN and +/-Infinity encode as `null`.
- Input strings are validated as UTF-8.

# Performance design
The main hot paths are string escaping, number parsing, and table traversal.
This file keeps a few measured optimizations (localized globals, cached byte
constants, small-integer string caching, and separate JIT/PUC scanning where it
materially changes performance), but the parsing and encoding logic is shared as
much as possible so the tricky JSON and Unicode rules stay in one place.

# License

Copyright (c) 2026, Wynand Winterbach All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]==]

-- Localize frequently used functions for performance
local str_byte                   = string.byte
local str_sub                    = string.sub
local str_char                   = string.char
local str_format                 = string.format
local str_gsub                   = string.gsub
local str_find                   = string.find
local tbl_concat                 = table.concat
local tostring                   = tostring
local tonumber                   = tonumber
local type                       = type
local getmetatable               = getmetatable
local next                       = next
local math_huge                  = math.huge

local JIT                        = _G['jit']

local BYTE_LBRACKET              = str_byte("[")
local BYTE_RBRACKET              = str_byte("]")
local BYTE_LBRACE                = str_byte("{")
local BYTE_RBRACE                = str_byte("}")
local BYTE_COLON                 = str_byte(":")
local BYTE_COMMA                 = str_byte(",")
local BYTE_QUOTE                 = str_byte('"')
local BYTE_BACKSLASH             = str_byte("\\")
local BYTE_SLASH                 = str_byte("/")
local BYTE_DOT                   = str_byte(".")
local BYTE_MINUS                 = str_byte("-")
local BYTE_PLUS                  = str_byte("+")
local BYTE_0                     = str_byte("0")
local BYTE_9                     = str_byte("9")
local BYTE_A                     = str_byte("a")
local BYTE_B                     = str_byte("b")
local BYTE_E                     = str_byte("e")
local BYTE_F                     = str_byte("f")
local BYTE_L                     = str_byte("l")
local BYTE_N                     = str_byte("n")
local BYTE_R                     = str_byte("r")
local BYTE_S                     = str_byte("s")
local BYTE_T                     = str_byte("t")
local BYTE_U                     = str_byte("u")
local BYTE_UPPER_A               = str_byte("A")
local BYTE_UPPER_E               = str_byte("E")
local BYTE_UPPER_F               = str_byte("F")
local BYTE_SPACE                 = str_byte(" ")
local BYTE_LF                    = str_byte("\n")
local BYTE_CR                    = str_byte("\r")
local BYTE_TAB                   = str_byte("\t")

local UTF8_1BYTE_LIMIT           = 0x80
local UTF8_2BYTE_LIMIT           = 0x800
local UTF8_3BYTE_LIMIT           = 0x10000
local MAX_DECODE_DEPTH           = 20

local DEFAULT_PARTS_CAPACITY     = 32
local DEFAULT_ENCODE_BUF_CAP     = 16384

local UTF8_CONTINUATION_MARK     = 0x80
local UTF8_2BYTE_MARK            = 0xC0
local UTF8_3BYTE_MARK            = 0xE0
local UTF8_4BYTE_MARK            = 0xF0

local UTF8_2BYTE_MIN             = 0xC2
local UTF8_4BYTE_MAX             = 0xF4

local UNICODE_SURROGATE_HIGH_MIN = 0xD800
local UNICODE_SURROGATE_HIGH_MAX = 0xDBFF
local UNICODE_SURROGATE_LOW_MIN  = 0xDC00
local UNICODE_SURROGATE_LOW_MAX  = 0xDFFF

local BOM_BYTE_1                 = 0xEF
local BOM_BYTE_2                 = 0xBB
local BOM_BYTE_3                 = 0xBF

local HEX_WEIGHT_NIBBLE_4        = 4096
local HEX_WEIGHT_NIBBLE_3        = 256
local HEX_WEIGHT_NIBBLE_2        = 16

--- Sentinel for null values, compatible with ngx.null if available
local null                       = setmetatable({}, {
  __tostring = function() return "null" end,
  __tojson = function() return "null" end,
})

local SMALL_INTS                 = {}
for i = 0, 999 do
  SMALL_INTS[i] = tostring(i)
end

local array_mt        = {}

local ok, tab_new_req = pcall(require, "table.new")
---@type fun(narr: integer, nrec: integer): table
local tab_new         = ok and tab_new_req or function() return {} end

-- Bitwise compatibility check
local bit             = _G['bit32']
if not bit then
  pcall(function() bit = require("bit") end)
end

local rshift, band
if bit then
  rshift = bit.rshift
  band = bit.band
else
  -- Optimistic load for Lua 5.3+ operators to avoid syntax errors in Lua 5.1
  -- This chunk will only be interpreted if loaded
  local chunk = load([[
    return {
      rshift = function(n, bits) return n >> bits end,
      band = function(a, b) return a & b end
    }
  ]])
  if chunk then
    local ops = chunk()
    rshift = ops.rshift
    band = ops.band
  else
    error("Bitwise operations not available")
  end
end

---@type fun(str: string, pos: integer): integer, integer?
local skip_whitespace
if JIT then
  skip_whitespace = function(str, pos)
    local b = str_byte(str, pos)
    while b == BYTE_SPACE or b == BYTE_LF or b == BYTE_CR or b == BYTE_TAB do
      pos = pos + 1
      b = str_byte(str, pos)
    end
    return pos, b
  end
else
  skip_whitespace = function(str, pos)
    local new_pos = str_find(str, '[^ \n\r\t]', pos)
    if new_pos then
      return new_pos, str_byte(str, new_pos)
    end
    return #str + 1, nil
  end
end

---@type table<string, string>
local ESCAPES = {}
for i = 0, 255 do
  local c = str_char(i)
  if i < BYTE_SPACE then
    ESCAPES[c] = str_format("\\u%04x", i)
  else
    ESCAPES[c] = c
  end
end

ESCAPES["\b"] = "\\b"
ESCAPES["\f"] = "\\f"
ESCAPES["\n"] = "\\n"
ESCAPES["\r"] = "\\r"
ESCAPES['"'] = '\\"'
ESCAPES["\\"] = '\\\\'

local ESCAPES_BYTE = {}
for i = 0, 255 do
  local c = str_char(i)
  ESCAPES_BYTE[i] = ESCAPES[c]
end

local escape_string
if JIT then
  escape_string = function(str)
    local len = #str
    for i = 1, len do
      local b = str_byte(str, i)
      if b < BYTE_SPACE or b == BYTE_QUOTE or b == BYTE_BACKSLASH then
        local parts = tab_new(DEFAULT_PARTS_CAPACITY, 0)
        local parts_len = 1
        local start = 1

        for j = i, len do
          local esc = ESCAPES_BYTE[str_byte(str, j)]
          if esc then
            if start < j then
              parts[parts_len] = str_sub(str, start, j - 1)
              parts_len = parts_len + 1
            end
            parts[parts_len] = esc
            parts_len = parts_len + 1
            start = j + 1
          end
        end

        if start <= len then
          parts[parts_len] = str_sub(str, start, len)
        else
          parts_len = parts_len - 1
        end

        return tbl_concat(parts, "", 1, parts_len)
      end
    end
    return nil
  end
else
  escape_string = function() error("escape_string called on PUC Lua") end
end

local ESCAPE_PATTERN = '[%z\1-\31\\"]'
local DECODE_ESCAPES = {
  [BYTE_QUOTE] = '"',
  [BYTE_BACKSLASH] = "\\",
  [BYTE_SLASH] = "/",
  [BYTE_B] = "\b",
  [BYTE_F] = "\f",
  [BYTE_N] = "\n",
  [BYTE_R] = "\r",
  [BYTE_T] = "\t",
}

local HEX_VALUES = {}
for i = 0, 255 do HEX_VALUES[i] = nil end
for i = BYTE_0, BYTE_9 do HEX_VALUES[i] = i - BYTE_0 end
for i = BYTE_UPPER_A, BYTE_UPPER_F do HEX_VALUES[i] = i - BYTE_UPPER_A + 10 end
for i = BYTE_A, BYTE_F do HEX_VALUES[i] = i - BYTE_A + 10 end

local ESCAPED_KEY_CACHE = setmetatable({}, { __mode = "kv" })

local function encode_string_contents(str)
  if JIT then
    return escape_string(str) or str
  end
  if not str_find(str, ESCAPE_PATTERN) then
    return str
  end
  return str_gsub(str, ESCAPE_PATTERN, ESCAPES)
end

local function encode_key_string(key)
  local key_str = (type(key) == "string") and key or tostring(key)
  if JIT then
    return encode_string_contents(key_str)
  end

  local escaped_key = ESCAPED_KEY_CACHE[key_str]
  if not escaped_key then
    escaped_key = encode_string_contents(key_str)
    ESCAPED_KEY_CACHE[key_str] = escaped_key
  end
  return escaped_key
end

local function append_encoded_key(key, buf, buf_len)
  buf[buf_len + 1] = '"'
  buf[buf_len + 2] = encode_key_string(key)
  buf[buf_len + 3] = '":'
  return buf_len + 3
end

local encode_value

local function encode_array(val, buf, buf_len, visited)
  buf_len = buf_len + 1
  buf[buf_len] = "["

  local len = #val
  for i = 1, len do
    if i > 1 then
      buf_len = buf_len + 1
      buf[buf_len] = ","
    end
    local new_buf_len, err = encode_value(val[i], buf, buf_len, visited)
    if err then return new_buf_len, err end
    buf_len = new_buf_len
  end

  buf_len = buf_len + 1
  buf[buf_len] = "]"
  visited[val] = nil
  return buf_len
end

local function encode_object(val, buf, buf_len, visited)
  local k, v = next(val)
  if k == nil then
    buf_len = buf_len + 1
    buf[buf_len] = "{}"
    visited[val] = nil
    return buf_len
  end

  buf_len = buf_len + 1
  buf[buf_len] = "{"

  local first = true
  while k ~= nil do
    if first then
      first = false
    else
      buf_len = buf_len + 1
      buf[buf_len] = ","
    end

    buf_len = append_encoded_key(k, buf, buf_len)
    local new_buf_len, err = encode_value(v, buf, buf_len, visited)
    if err then return new_buf_len, err end
    buf_len = new_buf_len
    k, v = next(val, k)
  end

  buf_len = buf_len + 1
  buf[buf_len] = "}"
  visited[val] = nil
  return buf_len
end

encode_value = function(val, buf, buf_len, visited)
  if val == nil or val == null then
    buf_len = buf_len + 1
    buf[buf_len] = "null"
    return buf_len
  end

  local t = type(val)
  if t == "string" then
    buf[buf_len + 1] = '"'
    buf[buf_len + 2] = encode_string_contents(val)
    buf[buf_len + 3] = '"'
    return buf_len + 3
  end

  if t == "number" then
    if val ~= val or val == math_huge or val == -math_huge then
      buf_len = buf_len + 1
      buf[buf_len] = "null"
      return buf_len
    end

    local s = SMALL_INTS[val]
    buf_len = buf_len + 1
    buf[buf_len] = s or tostring(val)
    return buf_len
  end

  if t == "boolean" then
    buf_len = buf_len + 1
    buf[buf_len] = val and "true" or "false"
    return buf_len
  end

  if t ~= "table" then
    return buf_len, "cannot serialize type: " .. t
  end

  local mt = getmetatable(val)
  if mt and mt ~= array_mt then
    local tojson = mt.__tojson
    if tojson then
      if visited[val] then
        return buf_len, "cannot serialize cyclic data structure"
      end
      visited[val] = true
      local ret, err = tojson(val)
      visited[val] = nil
      if type(ret) == "string" then
        buf_len = buf_len + 1
        buf[buf_len] = ret
        return buf_len
      end
      if not ret then
        return buf_len, err or "custom encoder failed"
      end
    end
  end

  if visited[val] then
    return buf_len, "cannot serialize cyclic data structure"
  end
  visited[val] = true

  if mt == array_mt or #val > 0 then
    return encode_array(val, buf, buf_len, visited)
  end

  return encode_object(val, buf, buf_len, visited)
end

local function clear_buffer(buffer, buf_len)
  for i = 1, buf_len do buffer[i] = nil end
end

local function drain_buffer(buffer, buf_len)
  local str = tbl_concat(buffer, "", 1, buf_len)
  clear_buffer(buffer, buf_len)
  return str
end

local function encode(val, buffer)
  local buf = buffer or tab_new(DEFAULT_ENCODE_BUF_CAP, 0)
  local buf_len, err = encode_value(val, buf, 0, {})
  if err then
    clear_buffer(buf, buf_len)
    return nil, tostring(err)
  end
  return drain_buffer(buf, buf_len)
end

local decode_value
local parse_string

local STRING_PATTERN = '["\\\1-\31%z\128-\255]'
-- PUC 5.3+: special bytes that are NOT valid multibyte UTF-8 starts. A scan
-- for this class stops a multibyte run before any byte utf8.len would accept
-- but strict UTF-8 (and this library) must reject (F5-FF out-of-range starts).
local NON_HIGH_SPECIAL = '["\\\1-\31%z\245-\255]'
local utf8_len = utf8 and utf8.len
-- Lua 5.3's utf8.len accepts surrogate encodings (ED A0-BF). When we detect
-- that leniency, spans also stop at ED (surrogate lead byte) so ED sequences
-- always go through strict per-character validation instead.
if utf8_len and utf8_len("\xED\xA0\x80") then
  NON_HIGH_SPECIAL = '["\\\1-\31%z\237\245-\255]'
end

local function clear_parts(parts, parts_len)
  for i = 1, parts_len do parts[i] = nil end
end

local function find_string_boundary(str, pos, len)
  if JIT then
    local i = pos
    while i <= len do
      local b = str_byte(str, i)
      if b == BYTE_QUOTE or b == BYTE_BACKSLASH or b < BYTE_SPACE or b >= UTF8_1BYTE_LIMIT then
        return i, b
      end
      i = i + 1
    end
    return nil, nil
  end

  local special_pos = str_find(str, STRING_PATTERN, pos)
  if not special_pos then
    return nil, nil
  end
  return special_pos, str_byte(str, special_pos)
end

local function continuation_byte(b)
  return b and b >= UTF8_CONTINUATION_MARK and b < UTF8_2BYTE_MARK
end

local function validate_utf8_at(str, i, len, b)
  if b < BYTE_SPACE then
    return nil, "Unescaped control character at position " .. i
  end
  if b < UTF8_1BYTE_LIMIT then
    return i + 1
  end
  if b < UTF8_2BYTE_MIN or b > UTF8_4BYTE_MAX then
    return nil, "Invalid UTF-8 sequence at position " .. i
  end

  local b2 = str_byte(str, i + 1)
  if not continuation_byte(b2) then
    return nil, "Invalid UTF-8 sequence at position " .. i
  end

  if b < UTF8_3BYTE_MARK then
    return i + 2
  end

  local b3 = str_byte(str, i + 2)
  if not continuation_byte(b3) then
    return nil, "Invalid UTF-8 sequence at position " .. i
  end

  if b < UTF8_4BYTE_MARK then
    if b == UTF8_3BYTE_MARK and b2 < 0xA0 then
      return nil, "Invalid UTF-8 sequence (overlong) at position " .. i
    end
    if b == 0xED and b2 > 0x9F then
      return nil, "Invalid UTF-8 sequence (surrogate) at position " .. i
    end
    return i + 3
  end

  local b4 = str_byte(str, i + 3)
  if not continuation_byte(b4) then
    return nil, "Invalid UTF-8 sequence at position " .. i
  end
  if b == UTF8_4BYTE_MARK and b2 < 0x90 then
    return nil, "Invalid UTF-8 sequence (overlong) at position " .. i
  end
  if b == UTF8_4BYTE_MAX and b2 > 0x8F then
    return nil, "Invalid UTF-8 sequence (out of range) at position " .. i
  end
  return i + 4
end

local function decode_hex_quad(str, pos)
  local b1, b2, b3, b4 = str_byte(str, pos, pos + 3)
  local h1 = HEX_VALUES[b1]
  local h2 = HEX_VALUES[b2]
  local h3 = HEX_VALUES[b3]
  local h4 = HEX_VALUES[b4]
  if h1 == nil or h2 == nil or h3 == nil or h4 == nil then
    return nil
  end
  return h1 * HEX_WEIGHT_NIBBLE_4 + h2 * HEX_WEIGHT_NIBBLE_3 + h3 * HEX_WEIGHT_NIBBLE_2 + h4
end

local function append_codepoint_utf8(parts, parts_len, code)
  parts_len = parts_len + 1
  if code < UTF8_1BYTE_LIMIT then
    parts[parts_len] = str_char(code)
  elseif code < UTF8_2BYTE_LIMIT then
    parts[parts_len] = str_char(
      UTF8_2BYTE_MARK + rshift(code, 6),
      UTF8_CONTINUATION_MARK + (code % 0x40)
    )
  elseif code < UTF8_3BYTE_LIMIT then
    parts[parts_len] = str_char(
      UTF8_3BYTE_MARK + rshift(code, 12),
      UTF8_CONTINUATION_MARK + band(rshift(code, 6), 0x3F),
      UTF8_CONTINUATION_MARK + (code % 0x40)
    )
  else
    parts[parts_len] = str_char(
      UTF8_4BYTE_MARK + rshift(code, 18),
      UTF8_CONTINUATION_MARK + band(rshift(code, 12), 0x3F),
      UTF8_CONTINUATION_MARK + band(rshift(code, 6), 0x3F),
      UTF8_CONTINUATION_MARK + band(code, 0x3F)
    )
  end
  return parts_len
end

local function decode_unicode_escape(str, i, parts, parts_len)
  local code = decode_hex_quad(str, i + 1)
  if code == nil then
    return parts_len, nil, "Invalid unicode escape at " .. i
  end

  if code < UNICODE_SURROGATE_HIGH_MIN or code > UNICODE_SURROGATE_LOW_MAX then
    return append_codepoint_utf8(parts, parts_len, code), i + 4
  end

  if code > UNICODE_SURROGATE_HIGH_MAX then
    return parts_len, nil, "Unpaired surrogate or invalid unicode sequence at " .. i
  end
  if str_byte(str, i + 5) ~= BYTE_BACKSLASH or str_byte(str, i + 6) ~= BYTE_U then
    return parts_len, nil, "Unpaired surrogate or invalid unicode sequence at " .. i
  end

  local low_code = decode_hex_quad(str, i + 7)
  if low_code == nil or low_code < UNICODE_SURROGATE_LOW_MIN or low_code > UNICODE_SURROGATE_LOW_MAX then
    return parts_len, nil, "Unpaired surrogate or invalid unicode sequence at " .. i
  end

  local combined = UTF8_3BYTE_LIMIT
    + ((code - UNICODE_SURROGATE_HIGH_MIN) * 1024)
    + (low_code - UNICODE_SURROGATE_LOW_MIN)
  return append_codepoint_utf8(parts, parts_len, combined), i + 10
end

parse_string = function(str, pos, len)
  local start = pos + 1
  local i, b = find_string_boundary(str, start, len)
  if not i then
    return "Unterminated string at position " .. pos, nil
  end
  if b == BYTE_QUOTE then
    return str_sub(str, start, i - 1), i + 1
  end

  -- The parts table is created lazily on the first backslash. Strings whose
  -- only specials are UTF-8 high bytes (the common escape-free slow path)
  -- keep their original bytes and need just one str_sub at the end.
  local parts = nil
  local parts_len = 0
  local chunk_start = start

  while i and i <= len do
    if b == BYTE_QUOTE then
      if chunk_start <= i - 1 then
        local chunk = str_sub(str, chunk_start, i - 1)
        if parts then
          parts_len = parts_len + 1
          parts[parts_len] = chunk
        else
          return chunk, i + 1
        end
      end
      if not parts then
        return "", i + 1
      end
      local result = tbl_concat(parts, "", 1, parts_len)
      clear_parts(parts, parts_len)
      return result, i + 1
    end

    if b == BYTE_BACKSLASH then
      if not parts then
        parts = tab_new(DEFAULT_PARTS_CAPACITY, 0)
      end
      if chunk_start < i then
        parts_len = parts_len + 1
        parts[parts_len] = str_sub(str, chunk_start, i - 1)
      end

      i = i + 1
      local c = str_byte(str, i)
      local escaped = DECODE_ESCAPES[c]
      if escaped then
        parts_len = parts_len + 1
        parts[parts_len] = escaped
      elseif c == BYTE_U then
        local err
        parts_len, i, err = decode_unicode_escape(str, i, parts, parts_len)
        if err then
          if parts then clear_parts(parts, parts_len) end
          return err, nil
        end
      else
        if parts then clear_parts(parts, parts_len) end
        return "Invalid escape sequence \\\\" .. str_char(c or 0) .. " at position " .. i, nil
      end

      i = i + 1
      chunk_start = i
    else
      -- PUC 5.3+ only (utf8_len is nil elsewhere): batch-validate the whole
      -- multibyte run in one utf8.len call instead of per-character
      -- validate_utf8_at + boundary-scan restarts.
      local skip_validate = false
      if utf8_len and b >= UTF8_1BYTE_LIMIT then
        local nxt = str_find(str, NON_HIGH_SPECIAL, i)
        if not nxt then
          if utf8_len(str, i, len) then
            -- No closing quote ahead and the rest is valid UTF-8: unterminated.
            skip_validate = true
            i = len + 1
          end
        elseif nxt > i and utf8_len(str, i, nxt - 1) then
          i = nxt
          b = str_byte(str, nxt)
          skip_validate = true
        end
      end
      if not skip_validate then
        local err
        i, err = validate_utf8_at(str, i, len, b)
        if err then
          if parts then clear_parts(parts, parts_len) end
          return err, nil
        end
      end
    end

    i, b = find_string_boundary(str, i, len)
  end

  if parts then clear_parts(parts, parts_len) end
  return "Unterminated string at position " .. pos, nil
end

---@param str string
---@param pos integer
---@param len integer
---@return number|string val_or_err, integer|nil pos
local function parse_number(str, pos, len)
  local start_pos = pos
  local b = str_byte(str, pos)
  local negative = false

  -- Handle optional minus sign
  if b == BYTE_MINUS then
    negative = true
    pos = pos + 1
    b = str_byte(str, pos)
  end

  if not (b and b >= BYTE_0 and b <= BYTE_9) then
    return "Invalid number at position " .. start_pos, nil
  end

  -- Fast path: compute small integers directly from byte values
  -- Avoids str_sub + tonumber allocation for the common case
  if b == BYTE_0 then
    -- Check for leading zero followed by digit (invalid: 01, 023)
    local after_zero = str_byte(str, pos + 1)
    if after_zero and after_zero >= BYTE_0 and after_zero <= BYTE_9 then
      return "Invalid number: leading zero at position " .. start_pos, nil
    end
    pos = pos + 1
    -- Check if followed by '.', 'e', 'E' (slow path)
    local next_b = str_byte(str, pos)
    if next_b == BYTE_DOT or next_b == BYTE_E or next_b == BYTE_UPPER_E then
      -- Fall through to slow path
    else
      return negative and -0 or 0, pos
    end
  else
    -- Non-zero first digit: try to accumulate integer directly
    local num = b - BYTE_0
    pos = pos + 1
    while pos <= len do
      b = str_byte(str, pos)
      if b and b >= BYTE_0 and b <= BYTE_9 then
        num = num * 10 + (b - BYTE_0)
        pos = pos + 1
      elseif b == BYTE_DOT or b == BYTE_E or b == BYTE_UPPER_E then
        break
      else
        if negative then num = -num end
        return num, pos
      end
    end
  end

  -- Slow path: handle decimals and exponents via tonumber(str_sub(...))
  -- Re-scan from start_pos since we need the full string for tonumber
  pos = start_pos + (negative and 1 or 0)
  b = str_byte(str, pos)
  -- Skip digits before decimal/exponent
  while pos <= len do
    b = str_byte(str, pos)
    if b and b >= BYTE_0 and b <= BYTE_9 then
      pos = pos + 1
    elseif b == BYTE_DOT or b == BYTE_E or b == BYTE_UPPER_E then
      break
    else
      break
    end
  end

  -- Check for decimal part
  if b == BYTE_DOT then
    pos = pos + 1
    local next_b = str_byte(str, pos)
    if not (next_b and next_b >= BYTE_0 and next_b <= BYTE_9) then
      return "Invalid number: dot must be followed by digits at position " .. start_pos, nil
    end
    while pos <= len do
      b = str_byte(str, pos)
      if b and b >= BYTE_0 and b <= BYTE_9 then
        pos = pos + 1
      elseif b == BYTE_E or b == BYTE_UPPER_E then
        break
      else
        break
      end
    end
  end

  -- Check for exponent
  if b == BYTE_E or b == BYTE_UPPER_E then
    pos = pos + 1
    b = str_byte(str, pos)
    if b == BYTE_PLUS or b == BYTE_MINUS then
      pos = pos + 1
      b = str_byte(str, pos)
    end
    if not (b and b >= BYTE_0 and b <= BYTE_9) then
      return "Invalid number: exponent must have digits at position " .. start_pos, nil
    end
    while pos <= len do
      b = str_byte(str, pos)
      if b and b >= BYTE_0 and b <= BYTE_9 then
        pos = pos + 1
      else
        break
      end
    end
  end

  local num_str = str_sub(str, start_pos, pos - 1)
  local num = tonumber(num_str)
  if not num then
    return "Invalid number value at " .. start_pos, nil
  end
  return num, pos
end


---@type fun(str: string, pos: number, depth: number, len: number): any?, number?
local parse_array

---@type fun(str: string, pos: number, depth: number, len: number): any?, number?
local parse_object

if JIT then
  parse_array = function(str, pos, depth, len)
    local arr = tab_new(8, 0)
    local n = 0
    pos = pos + 1 -- skip [

    local b, new_pos
    pos, b = skip_whitespace(str, pos)
    while b ~= BYTE_RBRACKET do
      local val, npos = decode_value(str, pos, depth + 1, len, b)
      if not npos then return val, nil end
      pos = npos
      n = n + 1
      arr[n] = val

      pos, b = skip_whitespace(str, pos)
      if b == BYTE_COMMA then
        local comma_pos = pos
        pos = pos + 1
        pos, b = skip_whitespace(str, pos)
        if b == BYTE_RBRACKET then
          return "Trailing comma in array at " .. comma_pos, nil
        end
      elseif b ~= BYTE_RBRACKET then
        return "Expected ] or , at " .. pos, nil
      end
    end
    return setmetatable(arr, array_mt), pos + 1
  end

  parse_object = function(str, pos, depth, len)
    local obj = tab_new(0, 8)
    pos = pos + 1 -- skip {

    local b, new_pos
    pos, b = skip_whitespace(str, pos)
    while b ~= BYTE_RBRACE do
      if b ~= BYTE_QUOTE then
        return "Expected string key for object at " .. (pos or "?"), nil
      end
      local key, npos = parse_string(str, pos, len)
      if not npos or not key then return key, nil end
      pos = npos

      pos, b = skip_whitespace(str, pos)
      if b ~= BYTE_COLON then
        return "Expected : after key at " .. pos, nil
      end
      pos = pos + 1

      pos, b = skip_whitespace(str, pos)
      local val, val_pos = decode_value(str, pos, depth + 1, len, b)
      if not val_pos then return val, nil end
      pos = val_pos
      obj[key] = val

      pos, b = skip_whitespace(str, pos)
      if b == BYTE_COMMA then
        local comma_pos = pos
        pos = pos + 1
        pos, b = skip_whitespace(str, pos)
        if b == BYTE_RBRACE then
          return "Trailing comma in object at " .. comma_pos, nil
        end
      elseif b ~= BYTE_RBRACE then
        return "Expected } or , at " .. pos, nil
      end
    end
    return obj, pos + 1
  end
else
  parse_array = function(str, pos, depth, len)
    local arr = tab_new(8, 0)
    local n = 0
    pos = pos + 1 -- skip [

    local b
    pos, b = skip_whitespace(str, pos)
    while b ~= BYTE_RBRACKET do
      local val, new_pos = decode_value(str, pos, depth + 1, len, b)
      if not new_pos then return val, nil end
      pos = new_pos
      n = n + 1
      arr[n] = val

      -- skip whitespace or peek comma/bracket
      b = str_byte(str, pos)
      if b == BYTE_COMMA then
        local comma_pos = pos
        pos = pos + 1
        pos, b = skip_whitespace(str, pos)
        if b == BYTE_RBRACKET then
          return "Trailing comma in array at " .. comma_pos, nil
        end
      elseif b == BYTE_RBRACKET then
        -- proceed to end of while loop
      else
        pos, b = skip_whitespace(str, pos)
        if b == BYTE_COMMA then
          local comma_pos = pos
          pos = pos + 1
          -- Check for trailing comma
          pos, b = skip_whitespace(str, pos)
          if b == BYTE_RBRACKET then
            return "Trailing comma in array at " .. comma_pos, nil
          end
        elseif b ~= BYTE_RBRACKET then
          return "Expected ] or , at " .. pos, nil
        end
      end
    end
    return setmetatable(arr, array_mt), pos + 1
  end

  parse_object = function(str, pos, depth, len)
    local obj = tab_new(0, 8)
    pos = pos + 1 -- skip {

    local b
    pos, b = skip_whitespace(str, pos)
    while b ~= BYTE_RBRACE do
      -- Parse Key
      if b ~= BYTE_QUOTE then
        return "Expected string key for object at " .. (pos or "?"), nil
      end
      local key, new_pos = parse_string(str, pos, len)
      if not new_pos or not key then return key, nil end
      pos = new_pos

      -- Colon
      -- skip whitespace / peek colon
      b = str_byte(str, pos)
      if b == BYTE_COLON then
        pos = pos + 1
      else
        pos, b = skip_whitespace(str, pos)
        if b ~= BYTE_COLON then
          return "Expected : after key at " .. pos, nil
        end
        pos = pos + 1
      end

      -- Value
      -- skip whitespace / peek value
      pos, b = skip_whitespace(str, pos)
      local val, val_pos = decode_value(str, pos, depth + 1, len, b)
      if not val_pos then return val, nil end
      pos = val_pos
      obj[key] = val

      -- Comma or End
      -- skip whitespace / peek comma/brace
      b = str_byte(str, pos)
      if b == BYTE_COMMA then
        local comma_pos = pos
        pos = pos + 1
        pos, b = skip_whitespace(str, pos)
        if b == BYTE_RBRACE then
          return "Trailing comma in object at " .. comma_pos, nil
        end
      elseif b == BYTE_RBRACE then
        -- proceed
      else
        pos, b = skip_whitespace(str, pos)
        if b == BYTE_COMMA then
          local comma_pos = pos
          pos = pos + 1
          pos, b = skip_whitespace(str, pos)
          if b == BYTE_RBRACE then
            return "Trailing comma in object at " .. comma_pos, nil
          end
        elseif b ~= BYTE_RBRACE then
          return "Expected } or , at " .. pos, nil
        end
      end
    end
    return obj, pos + 1
  end
end

-- Internal decode helpers return either (value, next_pos) or (error_message, nil).
decode_value = function(str, pos, depth, len, b)
  if depth > MAX_DECODE_DEPTH then return "JSON recursion depth limit exceeded", nil end

  b = b or str_byte(str, pos)
  if not b then
    return "Unexpected EOF", nil
  elseif b == BYTE_QUOTE then
    return parse_string(str, pos, len)
  elseif (b >= BYTE_0 and b <= BYTE_9) or b == BYTE_MINUS then
    return parse_number(str, pos, len)
  elseif b == BYTE_LBRACKET then
    return parse_array(str, pos, depth, len)
  elseif b == BYTE_LBRACE then
    return parse_object(str, pos, depth, len)
  elseif b == BYTE_T then
    local b2, b3, b4 = str_byte(str, pos + 1, pos + 3)
    if b2 == BYTE_R and b3 == BYTE_U and b4 == BYTE_E then -- true
      return true, pos + 4
    end
  elseif b == BYTE_F then
    local b2, b3, b4, b5 = str_byte(str, pos + 1, pos + 4)
    if b2 == BYTE_A and b3 == BYTE_L and b4 == BYTE_S and b5 == BYTE_E then -- false
      return false, pos + 5
    end
  elseif b == BYTE_N then
    local b2, b3, b4 = str_byte(str, pos + 1, pos + 3)
    if b2 == BYTE_U and b3 == BYTE_L and b4 == BYTE_L then -- null
      return null, pos + 4
    end
  else
    return "Unexpected character at " .. pos .. ": " .. str_char(b or 0), nil
  end
end

---@param str string
---@param pos? integer
---@param len? integer
---@return any?, integer?, string?
local function decode_next(str, len, pos)
  local b
  len = len or #str
  pos = pos or 1

  local bb1, bb2, bb3 = str_byte(str, pos, pos + 3)
  if pos > 1 or bb1 ~= BOM_BYTE_1 or bb2 ~= BOM_BYTE_2 or bb3 ~= BOM_BYTE_3 then
    pos, b = skip_whitespace(str, pos)
  else
    pos, b = skip_whitespace(str, 4)
  end

  if not b then return nil, nil, "Empty or whitespace-only JSON" end

  local val, end_pos = decode_value(str, pos, 0, len, b)
  if not end_pos then return nil, nil, tostring(val) end
  return val, end_pos, nil
end

---@param str string
---@return any?, string?
local function decode(str)
  local len = #str
  local val, end_pos, err = decode_next(str, len, 1)
  if not end_pos then return nil, err end

  end_pos = skip_whitespace(str, end_pos)
  if end_pos <= len then
    return nil, "Trailing characters after JSON data at " .. end_pos
  end

  return val
end

local function empty_array()
  return setmetatable(tab_new(0, 0), array_mt)
end

return {
  null = null,
  array_mt = array_mt,
  clear_buffer = clear_buffer,
  drain_buffer = drain_buffer,
  encode = encode,
  decode = decode,
  decode_next = decode_next,
  empty_array = empty_array,
}
