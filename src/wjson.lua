--[==[
wjson is a pure lua json library.

# API
- `encode`: Serialize Lua values to JSON. A buffer can be provided to reduce
  memory allocations (useful when calling encode multiple times).
- `decode`: Parse JSON strings into Lua values.

# Usage Notes
- `null`: Use `wjson.null` to represent a JSON `null` (however, if you have a
   custom table that returns nil values, it will be encoded as `null`.)
- `empty_array()`: Use `wjson.empty_array()` or an empty table with the
  `wjson.array_mt` metatable to ensure it encodes as an empty JSON array `[]`.

# Implementation Details
- Strict UTF-8 validation on input strings. This results in a 2x performance
  penalty relative to dkjson when parsing strings in PUC Lua.
- Focuses on reducing memory allocations.
- Acceptance of repetitive code when it avoids function calls that are expensive
  on PUC Lua.
- Reliance on `bench.lua` to verify that code changes really improve performance
  across PUC Lua 5.2, PUC Lua 5.3, PUC Lua 5.4, and LuaJIT.

# LLM Disclosure

This library was generated with the assistance of large language models.
However, the author has spent considerable time reviewing the code. Furthermore,
the author added the JSONTestSuite test cases to verify correctness and steered
the LLM to generate various unit tests to verify correctness (which the author
also reviewed).

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
local str_byte        = string.byte
local str_sub         = string.sub
local str_char        = string.char
local str_format      = string.format
local str_gsub        = string.gsub
local str_find        = string.find
local tbl_concat      = table.concat
local tostring        = tostring
local tonumber        = tonumber
local type            = type
local getmetatable    = getmetatable
local next            = next
local math_huge       = math.huge

local BYTE_LBRACKET   = str_byte("[")
local BYTE_RBRACKET   = str_byte("]")
local BYTE_LBRACE     = str_byte("{")
local BYTE_RBRACE     = str_byte("}")
local BYTE_COLON      = str_byte(":")
local BYTE_COMMA      = str_byte(",")
local BYTE_QUOTE      = str_byte('"')
local BYTE_BACKSLASH  = str_byte("\\")
local BYTE_SLASH      = str_byte("/")
local BYTE_B          = str_byte("b")
local BYTE_F          = str_byte("f")
local BYTE_N          = str_byte("n")
local BYTE_R          = str_byte("r")
local BYTE_T          = str_byte("t")
local BYTE_U          = str_byte("u")

--- Sentinel for null values, compatible with ngx.null if available
local null            = setmetatable({}, {
  __tostring = function() return "null" end,
  __tojson = function() return "null" end,
})

local SMALL_INTS      = {
  [0] = "0", [1] = "1", [2] = "2", [3] = "3", [4] = "4",
  [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9",
  [10] = "10", [11] = "11", [12] = "12", [13] = "13", [14] = "14",
  [15] = "15", [16] = "16", [17] = "17", [18] = "18", [19] = "19",
  [20] = "20", [21] = "21", [22] = "22", [23] = "23", [24] = "24",
  [25] = "25", [26] = "26", [27] = "27", [28] = "28", [29] = "29",
  [30] = "30", [31] = "31", [32] = "32", [33] = "33", [34] = "34",
  [35] = "35", [36] = "36", [37] = "37", [38] = "38", [39] = "39",
  [40] = "40", [41] = "41", [42] = "42", [43] = "43", [44] = "44",
  [45] = "45", [46] = "46", [47] = "47", [48] = "48", [49] = "49",
  [50] = "50", [51] = "51", [52] = "52", [53] = "53", [54] = "54",
  [55] = "55", [56] = "56", [57] = "57", [58] = "58", [59] = "59",
  [60] = "60", [61] = "61", [62] = "62", [63] = "63", [64] = "64",
  [65] = "65", [66] = "66", [67] = "67", [68] = "68", [69] = "69",
  [70] = "70", [71] = "71", [72] = "72", [73] = "73", [74] = "74",
  [75] = "75", [76] = "76", [77] = "77", [78] = "78", [79] = "79",
  [80] = "80", [81] = "81", [82] = "82", [83] = "83", [84] = "84",
  [85] = "85", [86] = "86", [87] = "87", [88] = "88", [89] = "89",
  [90] = "90", [91] = "91", [92] = "92", [93] = "93", [94] = "94",
  [95] = "95", [96] = "96", [97] = "97", [98] = "98", [99] = "99",
}

local array_mt        = {}

local ok, tab_new_req = pcall(require, "table.new")
---@type fun(narr: integer, nrec: integer): table
local tab_new         = ok and tab_new_req or function() return {} end

-- Bitwise compatibility check
local bit             = _G.bit32
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

local utf8_len = (type(_G.utf8) == "table" and type(_G.utf8.len) == "function") and _G.utf8.len or nil

local skip_whitespace
if _G.jit then
  skip_whitespace = function(str, pos)
    local b = str_byte(str, pos)
    while b == 32 or b == 10 or b == 13 or b == 9 do
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

local escapes = {}
for i = 0, 255 do
  local c = str_char(i)
  if i < 32 then
    if c == "\b" then
      escapes[c] = "\\b"
    elseif c == "\f" then
      escapes[c] = "\\f"
    elseif c == "\n" then
      escapes[c] = "\\n"
    elseif c == "\r" then
      escapes[c] = "\\r"
    elseif c == "\t" then
      escapes[c] = "\\t"
    else
      escapes[c] = str_format("\\u%04x", i)
    end
  elseif c == '"' then
    escapes[c] = '\\"'
  elseif c == "\\" then
    escapes[c] = "\\\\"
  else
    escapes[c] = c
  end
end

local shared_encode_parts = tab_new(32, 0)

-- LuaJIT-optimized escape: byte-indexed table + manual scanning
-- (str_gsub is C-optimized in PUC Lua and beats manual scanning there)
local escape_string
if _G.jit then
  local ESCAPE_STRINGS = {}
  for i = 0, 255 do
    if i < 32 then
      if i == 8 then
        ESCAPE_STRINGS[i] = "\\b"
      elseif i == 12 then
        ESCAPE_STRINGS[i] = "\\f"
      elseif i == 10 then
        ESCAPE_STRINGS[i] = "\\n"
      elseif i == 13 then
        ESCAPE_STRINGS[i] = "\\r"
      elseif i == 9 then
        ESCAPE_STRINGS[i] = "\\t"
      else
        ESCAPE_STRINGS[i] = str_format("\\u%04x", i)
      end
    elseif i == 34 then -- '"'
      ESCAPE_STRINGS[i] = '\\"'
    elseif i == 92 then -- '\\'
      ESCAPE_STRINGS[i] = "\\\\"
    else
      ESCAPE_STRINGS[i] = nil
    end
  end

  escape_string = function(str)
    local len = #str
    local i = 1
    while i <= len do
      local b = str_byte(str, i)
      if b < 32 or b == 34 or b == 92 then
        -- Build escaped string using concatenation for small part counts,
        -- tbl_concat for large counts
        local n = 0
        local start = 1
        -- First pass: count parts
        local j = i
        while j <= len do
          local b2 = str_byte(str, j)
          if b2 < 32 or b2 == 34 or b2 == 92 then
            n = n + 2 -- escaped char + preceding chunk
            j = j + 1
          else
            j = j + 1
          end
        end
        n = n + 1 -- final chunk

        if n <= 8 then
          -- Use string concatenation (avoids table allocation)
          local result = ""
          start = 1
          j = i
          while j <= len do
            local b2 = str_byte(str, j)
            local esc = ESCAPE_STRINGS[b2]
            if esc then
              if start < j then
                result = result .. str_sub(str, start, j - 1)
              end
              result = result .. esc
              start = j + 1
            end
            j = j + 1
          end
          if start <= len then
            result = result .. str_sub(str, start, len)
          end
          return result
        else
          -- Use shared table (avoids O(n^2) concatenation and table allocation)
          local parts = shared_encode_parts
          local pn = 0
          start = 1
          j = i
          while j <= len do
            local b2 = str_byte(str, j)
            local esc = ESCAPE_STRINGS[b2]
            if esc then
              if start < j then
                pn = pn + 1
                parts[pn] = str_sub(str, start, j - 1)
              end
              pn = pn + 1
              parts[pn] = esc
              start = j + 1
            end
            j = j + 1
          end
          if start <= len then
            pn = pn + 1
            parts[pn] = str_sub(str, start, len)
          end
          local result = tbl_concat(parts, "", 1, pn)
          for k = 1, pn do parts[k] = nil end
          return result
        end
      end
      i = i + 1
    end
    return nil
  end
else
  escape_string = nil -- PUC Lua uses str_gsub directly
end

local ESCAPE_PATTERN = '[%z\1-\31\\"]'

-- Decode escape lookup table (keyed by byte value for O(1) lookup)
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
for i = 48, 57 do HEX_VALUES[i] = i - 48 end  -- 0-9
for i = 65, 70 do HEX_VALUES[i] = i - 55 end  -- A-F
for i = 97, 102 do HEX_VALUES[i] = i - 87 end -- a-f


---@param val any
---@param buf string[]
---@param buf_len integer
---@return integer buf_len, string? error
local function encode_value(val, buf, buf_len)
  if val == nil or val == null then
    buf_len = buf_len + 1
    buf[buf_len] = "null"
    return buf_len
  end

  local t = type(val)
  if t == "string" then
    buf[buf_len + 1] = '"'
    if escape_string then
      -- LuaJIT: manual byte scanning
      local escaped = escape_string(val)
      if escaped then
        buf[buf_len + 2] = escaped
      else
        buf[buf_len + 2] = val
      end
    else
      -- PUC Lua: str_gsub (C-optimized)
      if not str_find(val, ESCAPE_PATTERN) then
        buf[buf_len + 2] = val
      else
        buf[buf_len + 2] = str_gsub(val, ESCAPE_PATTERN, escapes)
      end
    end
    buf[buf_len + 3] = '"'
    return buf_len + 3
  end

  if t == "number" then
    if val ~= val then
      buf_len = buf_len + 1
      buf[buf_len] = "null" -- JSON doesn't support NaN
      return buf_len
    elseif val == math_huge or val == -math_huge then
      buf_len = buf_len + 1
      buf[buf_len] = "null" -- JSON doesn't support Infinity
      return buf_len
    end
    local s = SMALL_INTS[val]
    if s then
      buf_len = buf_len + 1
      buf[buf_len] = s
      return buf_len
    end
    buf_len = buf_len + 1
    buf[buf_len] = tostring(val)
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

  local len = #val
  if getmetatable(val) == array_mt or len > 0 then
    -- Array encoding
    buf_len = buf_len + 1
    buf[buf_len] = "["
    if len > 0 then
      local new_buf_len, err = encode_value(val[1], buf, buf_len)
      if err then return new_buf_len, err end
      buf_len = new_buf_len --[[@as integer]]

      for i = 2, len do
        buf_len = buf_len + 1
        buf[buf_len] = ","
        new_buf_len, err = encode_value(val[i], buf, buf_len)
        if err then return new_buf_len, err end
        buf_len = new_buf_len --[[@as integer]]
      end
    end
    buf_len = buf_len + 1
    buf[buf_len] = "]"
    return buf_len
  end

  local k, v = next(val)
  if k == nil then
    buf_len = buf_len + 1
    buf[buf_len] = "{}"
    return buf_len
  end

  -- Object encoding
  buf_len = buf_len + 1
  buf[buf_len] = "{"
  local first = true
  while k ~= nil do
    if not first then
      buf_len = buf_len + 1
      buf[buf_len] = ","
    end
    first = false

    local key_str = (type(k) == "string") and k or tostring(k)
    buf[buf_len + 1] = '"'
    if escape_string then
      -- LuaJIT: manual byte scanning
      local escaped = escape_string(key_str)
      if escaped then
        buf[buf_len + 2] = escaped
      else
        buf[buf_len + 2] = key_str
      end
    else
      -- PUC Lua: str_gsub (C-optimized)
      if not str_find(key_str, ESCAPE_PATTERN) then
        buf[buf_len + 2] = key_str
      else
        buf[buf_len + 2] = str_gsub(key_str, ESCAPE_PATTERN, escapes)
      end
    end
    buf[buf_len + 3] = '":'
    buf_len = buf_len + 3

    local new_buf_len, err = encode_value(v, buf, buf_len)
    if err then return new_buf_len, err end
    buf_len = new_buf_len --[[@as integer]]

    k, v = next(val, k)
  end
  buf_len = buf_len + 1
  buf[buf_len] = "}"
  return buf_len
end

local shared_encode_buf = tab_new(16384, 0)

---@param buffer any[]
---@param buf_len integer
local function clear_buffer(buffer, buf_len)
  for i = 1, buf_len do buffer[i] = nil end
end

---@param buffer any[]
---@param buf_len integer
local function drain_buffer(buffer, buf_len)
  local str = tbl_concat(buffer, "", 1, buf_len)
  clear_buffer(buffer, buf_len)
  return str
end

---@param val any
---@param buffer any[]
---@return string?, string?
local function encode(val, buffer)
  local buf = buffer or shared_encode_buf
  local buf_len, err = encode_value(val, buf, 0)
  if err then
    clear_buffer(buf, buf_len)
    return nil, tostring(err)
  end
  return drain_buffer(buf, buf_len)
end

---@type fun(str: string, pos: integer, depth: integer, len: integer, b?: integer): any, integer|nil
local decode_value -- forward declaration

---@type fun(str: string, pos: integer, len: integer): string|nil, integer|nil
local parse_string

local shared_string_parts = tab_new(32, 0)

if _G.jit then
  parse_string = function(str, pos, len)
    -- pos matches the opening quote
    local i = pos + 1
    local start = i
    while i <= len do
      local b = str_byte(str, i)
      if b == BYTE_QUOTE then
        return str_sub(str, start, i - 1), i + 1
      end
      if b < 32 or b == BYTE_BACKSLASH or b >= 128 then break end
      i = i + 1
    end
    if i > len then
      return "Unterminated string at position " .. pos, nil
    end

    local parts = shared_string_parts
    local n = 0
    if i > start then
      n = n + 1
      parts[n] = str_sub(str, start, i - 1)
    end
    local chunk_start = i

    while i <= len do
      local b = str_byte(str, i)
      if b == BYTE_QUOTE then
        if chunk_start <= i - 1 then
          n = n + 1
          parts[n] = str_sub(str, chunk_start, i - 1)
        end
        local result = tbl_concat(parts, "", 1, n)
        for j = 1, n do parts[j] = nil end
        return result, i + 1
      end

      if b ~= BYTE_BACKSLASH then
        if b < 32 then -- control character
          for j = 1, n do parts[j] = nil end
          return "Unescaped control character at position " .. i, nil
        end
        -- UTF-8 validation
        if b >= 0x80 then
          if b >= 0xC2 and b < 0xE0 then -- 2-byte sequence
            local b2 = str_byte(str, i + 1)
            if not b2 or b2 < 0x80 or b2 >= 0xC0 then
              for j = 1, n do parts[j] = nil end
              return "Invalid UTF-8 sequence at position " .. i, nil
            end
            i = i + 2
          elseif b >= 0xE0 and b < 0xF0 then -- 3-byte sequence
            local b2 = str_byte(str, i + 1)
            local b3 = str_byte(str, i + 2)
            if not b3 or b2 < 0x80 or b2 >= 0xC0 or b3 < 0x80 or b3 >= 0xC0 then
              for j = 1, n do parts[j] = nil end
              return "Invalid UTF-8 sequence at position " .. i, nil
            end
            i = i + 3
          elseif b >= 0xF0 and b < 0xF5 then -- 4-byte sequence
            local b2 = str_byte(str, i + 1)
            local b3 = str_byte(str, i + 2)
            local b4 = str_byte(str, i + 3)
            if not b4 or b2 < 0x80 or b2 >= 0xC0 or b3 < 0x80 or b3 >= 0xC0 or b4 < 0x80 or b4 >= 0xC0 then
              for j = 1, n do parts[j] = nil end
              return "Invalid UTF-8 sequence at position " .. i, nil
            end
            i = i + 4
          else
            for j = 1, n do parts[j] = nil end
            return "Invalid UTF-8 sequence at position " .. i, nil
          end
        else
          i = i + 1
        end
        goto continue
      end

      if chunk_start < i then
        n = n + 1
        parts[n] = str_sub(str, chunk_start, i - 1)
      end
      i = i + 1 -- skip backslash
      local c = str_byte(str, i)
      local escaped = DECODE_ESCAPES[c]
      if escaped then
        n = n + 1
        parts[n] = escaped
      elseif c == BYTE_U then
        -- unicode \uXXXX
        local h1 = HEX_VALUES[str_byte(str, i + 1)]
        local h2 = HEX_VALUES[str_byte(str, i + 2)]
        local h3 = HEX_VALUES[str_byte(str, i + 3)]
        local h4 = HEX_VALUES[str_byte(str, i + 4)]

        if not (h1 and h2 and h3 and h4) then
          for j = 1, n do parts[j] = nil end
          return "Invalid unicode escape at " .. i, nil
        end

        local code = h1 * 4096 + h2 * 256 + h3 * 16 + h4

        -- Basic UTF-8 conversion (Happy paths for 1, 2, 3 byte characters)
        if code < 0x80 then
          n = n + 1
          parts[n] = str_char(code)
          i = i + 4
          goto continue_loop
        end

        if code < 0x800 then
          n = n + 1
          parts[n] = str_char(0xC0 + rshift(code, 6), 0x80 + (code % 0x40))
          i = i + 4
          goto continue_loop
        end

        if code < 0xD800 or code > 0xDFFF then
          -- Normal 3-byte sequence (BMP), excluding surrogates
          n = n + 1
          parts[n] = str_char(0xE0 + rshift(code, 12),
            0x80 + (band(rshift(code, 6), 0x3F)),
            0x80 + (code % 0x40))
          i = i + 4
          goto continue_loop
        end

        -- Surrogate pair handling
        if code < 0xD800 or code > 0xDBFF then
          for j = 1, n do parts[j] = nil end
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        if str_byte(str, i + 5) ~= BYTE_BACKSLASH or str_byte(str, i + 6) ~= BYTE_U then
          for j = 1, n do parts[j] = nil end
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        local l1 = HEX_VALUES[str_byte(str, i + 7)]
        local l2 = HEX_VALUES[str_byte(str, i + 8)]
        local l3 = HEX_VALUES[str_byte(str, i + 9)]
        local l4 = HEX_VALUES[str_byte(str, i + 10)]

        if not (l1 and l2 and l3 and l4) then
          for j = 1, n do parts[j] = nil end
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        local low_code = l1 * 4096 + l2 * 256 + l3 * 16 + l4
        if low_code < 0xDC00 or low_code > 0xDFFF then
          for j = 1, n do parts[j] = nil end
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        -- Valid surrogate pair found
        local combined = 0x10000 + ((code - 0xD800) * 1024) + (low_code - 0xDC00)
        n = n + 1
        parts[n] = str_char(
          0xF0 + rshift(combined, 18),
          0x80 + band(rshift(combined, 12), 0x3F),
          0x80 + band(rshift(combined, 6), 0x3F),
          0x80 + band(combined, 0x3F)
        )
        i = i + 10 -- Skip both \uXXXX sequences (6 + 4)
        goto continue_loop
      else
        for j = 1, n do parts[j] = nil end
        return "Invalid escape sequence \\\\" .. str_char(c or 0) .. " at position " .. i, nil
      end
      ::continue_loop::
      i = i + 1
      chunk_start = i
      ::continue::
    end

    for j = 1, n do parts[j] = nil end
    return "Unterminated string", nil
  end
else
  local STRING_PATTERN = utf8_len and '["\\\1-\31%z]' or '["\\\1-\31%z\128-\255]'

  parse_string = function(str, pos, len)
    -- PUC Lua: use pattern matching to find the first quote or special character
    local start = pos + 1
    local special_pos = str_find(str, STRING_PATTERN, start)
    if not special_pos then
      return "Unterminated string at position " .. pos, nil
    end
    if str_byte(str, special_pos) == BYTE_QUOTE then
      return str_sub(str, start, special_pos - 1), special_pos + 1
    end

    local i = special_pos
    local parts = {}
    local n = 0
    if i > start then
      n = n + 1
      parts[n] = str_sub(str, start, i - 1)
    end
    local chunk_start = i

    -- PUC Lua slow path loop with chunked search
    while i <= len do
      local special_pos_chunk = str_find(str, STRING_PATTERN, i)
      if not special_pos_chunk then return "Unterminated string", nil end
      i = special_pos_chunk

      local b = str_byte(str, i)
      if b == BYTE_QUOTE then
        if chunk_start <= i - 1 then
          n = n + 1
          parts[n] = str_sub(str, chunk_start, i - 1)
        end
        return tbl_concat(parts), i + 1
      end

      if b ~= BYTE_BACKSLASH then
        if b < 32 then -- control character
          return "Unescaped control character at position " .. i, nil
        end
        -- UTF-8 validation
        if b >= 0x80 then
          if b < 0xC2 or b >= 0xF5 then
            return "Invalid UTF-8 sequence at position " .. i, nil
          end
          local expected = (b >= 0xF0 and 3) or (b >= 0xE0 and 2) or 1
          for _ = 1, expected do
            i = i + 1
            local b2 = str_byte(str, i)
            if not b2 or b2 < 0x80 or b2 >= 0xC0 then
              return "Invalid UTF-8 sequence at position " .. i, nil
            end
          end
        end
        i = i + 1
        goto continue
      end

      if chunk_start < i then
        n = n + 1
        parts[n] = str_sub(str, chunk_start, i - 1)
      end
      i = i + 1 -- skip backslash
      local c = str_byte(str, i)
      local escaped = DECODE_ESCAPES[c]
      if escaped then
        n = n + 1
        parts[n] = escaped
      elseif c == BYTE_U then
        -- unicode \uXXXX
        local h1 = HEX_VALUES[str_byte(str, i + 1)]
        local h2 = HEX_VALUES[str_byte(str, i + 2)]
        local h3 = HEX_VALUES[str_byte(str, i + 3)]
        local h4 = HEX_VALUES[str_byte(str, i + 4)]

        if not (h1 and h2 and h3 and h4) then
          return "Invalid unicode escape at " .. i, nil
        end

        local code = h1 * 4096 + h2 * 256 + h3 * 16 + h4

        -- Basic UTF-8 conversion (Happy paths for 1, 2, 3 byte characters)
        if code < 0x80 then
          n = n + 1
          parts[n] = str_char(code)
          i = i + 4
          goto continue_loop
        end

        if code < 0x800 then
          n = n + 1
          parts[n] = str_char(0xC0 + rshift(code, 6), 0x80 + (code % 0x40))
          i = i + 4
          goto continue_loop
        end

        if code < 0xD800 or code > 0xDFFF then
          -- Normal 3-byte sequence (BMP), excluding surrogates
          n = n + 1
          parts[n] = str_char(0xE0 + rshift(code, 12),
            0x80 + (band(rshift(code, 6), 0x3F)),
            0x80 + (code % 0x40))
          i = i + 4
          goto continue_loop
        end

        -- Surrogate pair handling
        if code < 0xD800 or code > 0xDBFF then
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        if str_byte(str, i + 5) ~= BYTE_BACKSLASH or str_byte(str, i + 6) ~= BYTE_U then
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        local l1 = HEX_VALUES[str_byte(str, i + 7)]
        local l2 = HEX_VALUES[str_byte(str, i + 8)]
        local l3 = HEX_VALUES[str_byte(str, i + 9)]
        local l4 = HEX_VALUES[str_byte(str, i + 10)]

        if not (l1 and l2 and l3 and l4) then
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        local low_code = l1 * 4096 + l2 * 256 + l3 * 16 + l4
        if low_code < 0xDC00 or low_code > 0xDFFF then
          return "Unpaired surrogate or invalid unicode sequence at " .. i, nil
        end

        -- Valid surrogate pair found
        local combined = 0x10000 + ((code - 0xD800) * 1024) + (low_code - 0xDC00)
        n = n + 1
        parts[n] = str_char(
          0xF0 + rshift(combined, 18),
          0x80 + band(rshift(combined, 12), 0x3F),
          0x80 + band(rshift(combined, 6), 0x3F),
          0x80 + band(combined, 0x3F)
        )
        i = i + 10 -- Skip both \uXXXX sequences (6 + 4)
        goto continue_loop
      else
        return "Invalid escape sequence \\\\" .. str_char(c or 0) .. " at position " .. i, nil
      end
      ::continue_loop::
      i = i + 1
      chunk_start = i
      ::continue::
    end

    return "Unterminated string", nil
  end
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
  if b == 45 then -- '-'
    negative = true
    pos = pos + 1
    b = str_byte(str, pos)
  end

  if not (b and b >= 48 and b <= 57) then -- 0-9
    return "Invalid number at position " .. start_pos, nil
  end

  -- Fast path: compute small integers directly from byte values
  -- Avoids str_sub + tonumber allocation for the common case
  if b == 48 then -- '0'
    -- Check for leading zero followed by digit (invalid: 01, 023)
    local after_zero = str_byte(str, pos + 1)
    if after_zero and after_zero >= 48 and after_zero <= 57 then
      return "Invalid number: leading zero at position " .. start_pos, nil
    end
    pos = pos + 1
    -- Check if followed by '.', 'e', 'E' (slow path)
    local next_b = str_byte(str, pos)
    if next_b == 46 or next_b == 101 or next_b == 69 then -- '.', 'e', 'E'
      -- Fall through to slow path
    else
      return negative and -0 or 0, pos
    end
  else
    -- Non-zero first digit: try to accumulate integer directly
    local num = b - 48
    pos = pos + 1
    while pos <= len do
      b = str_byte(str, pos)
      if b and b >= 48 and b <= 57 then -- 0-9
        num = num * 10 + (b - 48)
        pos = pos + 1
      elseif b == 46 or b == 101 or b == 69 then -- '.', 'e', 'E'
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
    if b and b >= 48 and b <= 57 then
      pos = pos + 1
    elseif b == 46 or b == 101 or b == 69 then
      break
    else
      break
    end
  end

  -- Check for decimal part
  if b == 46 then -- '.'
    pos = pos + 1
    local next_b = str_byte(str, pos)
    if not (next_b and next_b >= 48 and next_b <= 57) then
      return "Invalid number: dot must be followed by digits at position " .. start_pos, nil
    end
    while pos <= len do
      b = str_byte(str, pos)
      if b and b >= 48 and b <= 57 then
        pos = pos + 1
      elseif b == 101 or b == 69 then
        break
      else
        break
      end
    end
  end

  -- Check for exponent
  if b == 101 or b == 69 then
    pos = pos + 1
    b = str_byte(str, pos)
    if b == 43 or b == 45 then -- '+', '-'
      pos = pos + 1
      b = str_byte(str, pos)
    end
    if not (b and b >= 48 and b <= 57) then
      return "Invalid number: exponent must have digits at position " .. start_pos, nil
    end
    while pos <= len do
      b = str_byte(str, pos)
      if b and b >= 48 and b <= 57 then
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


---@param str string
---@param pos integer
---@param depth integer
---@param len integer
---@return any val_or_err, integer|nil pos
local function parse_array(str, pos, depth, len)
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

    -- skip whitespace
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
  return setmetatable(arr, array_mt), pos + 1
end

---@param str string
---@param pos integer
---@param depth integer
---@param len integer
---@return any val_or_err, integer|nil pos
local function parse_object(str, pos, depth, len)
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
    -- skip whitespace
    pos, b = skip_whitespace(str, pos)
    if b ~= BYTE_COLON then
      return "Expected : after key at " .. pos, nil
    end
    pos = pos + 1

    -- Value
    -- skip whitespace
    pos, b = skip_whitespace(str, pos)
    local val, val_pos = decode_value(str, pos, depth + 1, len, b)
    if not val_pos then return val, nil end
    pos = val_pos
    obj[key] = val

    -- Comma or End
    -- skip whitespace
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

---@param str string
---@param pos integer
---@param depth integer
---@param len integer
---@param b? integer
decode_value = function(str, pos, depth, len, b)
  if depth > 20 then return "JSON recursion depth limit exceeded", nil end

  b = b or str_byte(str, pos)
  if not b then return "Unexpected EOF", nil end

  if (b >= 48 and b <= 57) or b == 45 then -- 0-9 or -
    return parse_number(str, pos, len)
  end

  if b == BYTE_QUOTE then return parse_string(str, pos, len) end
  if b == BYTE_LBRACKET then return parse_array(str, pos, depth, len) end
  if b == BYTE_LBRACE then return parse_object(str, pos, depth, len) end

  if b == BYTE_T and str_byte(str, pos + 1) == 114 and str_byte(str, pos + 2) == 117 and str_byte(str, pos + 3) == 101 then -- true
    return true, pos + 4
  end

  if b == BYTE_F and str_byte(str, pos + 1) == 97 and str_byte(str, pos + 2) == 108 and str_byte(str, pos + 3) == 115 and str_byte(str, pos + 4) == 101 then -- false
    return false, pos + 5
  end

  if b == BYTE_N and str_byte(str, pos + 1) == 117 and str_byte(str, pos + 2) == 108 and str_byte(str, pos + 3) == 108 then -- null
    return null, pos + 4
  end

  return "Unexpected character at " .. pos .. ": " .. str_char(b or 0), nil
end

---@param str string
---@return any?, string?
local function decode(str, max_size)
  if not str or str == "" then return nil, "Empty JSON" end

  if utf8_len then
    local count, pos = utf8_len(str)
    if not count then
      return nil, "Invalid UTF-8 sequence at position " .. (pos or "?")
    end
  end

  -- Size Check
  local len = #str
  if max_size and len > max_size then
    return nil, str_format("JSON size limit exceeded (%d bytes > %d bytes)", len, max_size)
  end

  local pos, b = skip_whitespace(str, 1)
  if not b then return nil, "Empty or whitespace-only JSON" end

  local val, end_pos = decode_value(str, pos, 0, len, b)
  if not end_pos then return nil, tostring(val) end

  end_pos, b = skip_whitespace(str, end_pos)
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
  clear_buffer = clear_buffer,
  drain_buffer = drain_buffer,
  encode = encode,
  decode = decode,
  empty_array = empty_array,
}
