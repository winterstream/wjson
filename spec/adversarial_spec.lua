local wjson = require("wjson")

describe("Adversarial Inputs", function()
  describe("Unicode: Invalid Byte Sequences (Decoder)", function()
    local function test_reject(name, input)
      it("rejects " .. name, function()
        local res, err = wjson.decode(input)
        assert.is_nil(res)
        assert.is_string(err)
      end)
    end

    -- Overlong encodings
    test_reject("overlong 2-byte NUL (C0 80)", '{"k": "\xc0\x80"}')
    test_reject("overlong 3-byte slash (E0 80 AF)", '{"k": "\xe0\x80\xaf"}')
    test_reject("overlong 4-byte NUL (F0 80 80 80)", '{"k": "\xf0\x80\x80\x80"}')
    test_reject("max overlong 2-byte (C1 BF)", '{"k": "\xc1\xbf"}')

    -- Surrogate halves as raw UTF-8 (forbidden in UTF-8)
    test_reject("raw UTF-8 high surrogate (ED A0 80)", '{"k": "\xed\xa0\x80"}')
    test_reject("raw UTF-8 low surrogate (ED BF BF)", '{"k": "\xed\xbf\xbf"}')

    -- Out of range
    test_reject("above U+10FFFF (F4 90 80 80)", '{"k": "\xf4\x90\x80\x80"}')
    test_reject("5-byte sequence (F8...)", '{"k": "\xf8\x80\x80\x80\x80"}')
    test_reject("6-byte sequence (FC...)", '{"k": "\xfc\x80\x80\x80\x80\x80"}')
    test_reject("byte FE", '{"k": "\xfe"}')
    test_reject("byte FF", '{"k": "\xff"}')

    -- Truncation
    test_reject("truncated 3nd byte of 3-byte sequence", '{"k": "hello\xe2\x82"}')
  end)

  describe("Unicode: Escape Sequence Attacks (Decoder)", function()
    it("accepts \\u0000 and produces a NUL byte", function()
      local res, err = wjson.decode('"\\u0000"')
      assert.is_nil(err)
      assert.is_equal("\0", res)
    end)

    local function test_reject_escape(name, input)
      it("rejects " .. name, function()
        local res, err = wjson.decode(input)
        assert.is_nil(res)
        assert.truthy(err:find("Invalid unicode escape") or err:find("Unpaired surrogate") or
          err:find("Invalid escape sequence"))
      end)
    end

    test_reject_escape("partial \\u", '"\\u"')
    test_reject_escape("partial \\u1", '"\\u1"')
    test_reject_escape("partial \\u12", '"\\u12"')
    test_reject_escape("partial \\u123", '"\\u123"')
    test_reject_escape("non-hex after \\u", '"\\uGGGG"')
    test_reject_escape("lone high surrogate", '"\\uD800"')
    test_reject_escape("high surrogate then non-surrogate \\u", '"\\uD800\\u0041"')
    test_reject_escape("high surrogate then junk", '"\\uD800abc"')
    test_reject_escape("two high surrogates", '"\\uD800\\uD800"')
    test_reject_escape("lone low surrogate", '"\\uDC00"')
  end)

  describe("Control Characters (Decoder)", function()
    -- RFC 8259: All control characters U+0000–U+001F must be escaped.
    for i = 0, 31 do
      local char = string.char(i)
      it("rejects unescaped control character 0x" .. string.format("%02X", i), function()
        local res, err = wjson.decode('{"k": "' .. char .. '"}')
        assert.is_nil(res)
        assert.truthy(err:find("Unescaped control character") or err:find("Invalid UTF%-8 sequence"))
      end)

      it("accepts escaped control character \\u" .. string.format("%04X", i), function()
        local input = string.format('"\\u%04x"', i)
        local res, err = wjson.decode(input)
        assert.is_nil(err)
        assert.is_equal(char, res)
      end)
    end

    it("accepts DEL (U+007F)", function()
      local res, err = wjson.decode('"\\u007F"')
      assert.is_nil(err)
      assert.is_equal("\127", res)

      -- Raw DEL is also allowed in JSON strings (it's not < 0x20)
      res, err = wjson.decode('"\127"')
      assert.is_nil(err)
      assert.is_equal("\127", res)
    end)
  end)

  describe("Resource Exhaustion / Denial of Service", function()
    it("rejects depth beyond 20 (failing at level 22)", function()
      -- Level 1 (depth 0) to Level 21 (depth 20) are OK.
      -- Level 22 (depth 21) should fail.
      local deep = string.rep("[", 22) .. string.rep("]", 22)
      local res, err = wjson.decode(deep)
      assert.is_nil(res)
      assert.truthy(err:find("depth limit exceeded"))
    end)

    it("accepts depth at exactly 21 levels (max depth 20 reached)", function()
      local deep = string.rep("[", 21) .. string.rep("]", 21)
      local res, err = wjson.decode(deep)
      assert.is_not_nil(res)
    end)

    it("handles large string values without crashing", function()
      local large = '"' .. string.rep("a", 1000000) .. '"'
      local status, res = pcall(wjson.decode, large)
      assert.is_true(status)
      assert.is_equal(1000000, #res)
    end)

    it("handles infinity/NaN in numbers by producing null", function()
      local res, err = wjson.decode("Infinity")
      assert.is_nil(res)
      assert.truthy(err:find("Unexpected character"))

      res, err = wjson.decode("NaN")
      assert.is_nil(res)
      assert.truthy(err:find("Unexpected character"))
    end)
  end)

  describe("Number Parsing Edge Cases", function()
    local function test_reject_num(name, input)
      it("rejects " .. name, function()
        local res, err = wjson.decode(input)
        assert.is_nil(res)
      end)
    end

    test_reject_num("leading zero (01)", "01")
    test_reject_num("leading zero float (00.1)", "00.1")
    test_reject_num("bare minus", "-")
    test_reject_num("bare dot", ".5")
    test_reject_num("trailing dot", "1.")
    test_reject_num("bare exponent", "e5")
    test_reject_num("plus sign", "+1")
    test_reject_num("hex", "0x1A")

    it("handles negative zero", function()
      local res = wjson.decode("-0")
      assert.is_equal(0, res)
    end)
  end)

  describe("Structural Confusion", function()
    it("strips UTF-8 BOM", function()
      local input = "\xEF\xBB\xBF" .. '{"a": 1}'
      local res, err = wjson.decode(input)
      assert.is_nil(err)
      assert.is_equal(1, res.a)
    end)

    it("fails on truncated UTF-8 BOM", function()
      local input = "\xEF\xBB" .. '{"a": 1}'
      local res, err = wjson.decode(input)
      assert.is_equal("Unexpected character at 1: \xEF", err)
      assert.is_nil(res)

      input = "\xEF" .. '{"a": 1}'
      res, err = wjson.decode(input)
      assert.is_equal("Unexpected character at 1: \xEF", err)
      assert.is_nil(res)
    end)

    local function test_reject_struct(name, input)
      it("rejects " .. name, function()
        local res, err = wjson.decode(input)
        assert.is_nil(res)
      end)
    end

    test_reject_struct("mismatched [}", "[}")
    test_reject_struct("unclosed array", "[1, 2")
    test_reject_struct("trailing comma array", "[1,]")
    test_reject_struct("trailing comma object", '{"a":1,}')
    test_reject_struct("multiple roots", "1 2")
    test_reject_struct("empty input", "")
    test_reject_struct("whitespace only", "   ")
  end)

  describe("Null Byte Injection", function()
    it("rejects unescaped null byte in string", function()
      local res, err = wjson.decode('{"k": "a\0b"}')
      assert.is_nil(res)
      assert.truthy(err:find("Unescaped control character") or err:find("Invalid UTF%-8 sequence"))
    end)

    it("accepts \\u0000 and roundtrips correctly", function()
      local input = '{"k": "\\u0000"}'
      local res, err = wjson.decode(input)
      assert.is_nil(err)
      assert.is_equal("\0", res.k)

      local encoded = wjson.encode(res)
      assert.truthy(encoded:find("\\u0000", 1, true))
      local res2 = wjson.decode(encoded)
      assert.is_equal("\0", res2.k)
    end)
  end)

  describe("Lua-Specific Metatable Key Poisoning", function()
    it("treats metamethod keys as plain data", function()
      local input = '{"__index": "evil", "__gc": 1, "__tojson": true}'
      local res, err = wjson.decode(input)
      assert.is_nil(err)
      assert.is_equal("evil", res.__index)
      assert.is_equal(1, res.__gc)
      assert.is_equal(true, res.__tojson)

      -- Verify they don't affect encoding of other objects
      assert.is_equal('{"a":1}', wjson.encode({ a = 1 }))
    end)
  end)

  describe("Shared State Corruption", function()
    it("survives error and encodes correctly afterwards", function()
      -- Trigger an error (function cannot be encoded)
      local res, err = wjson.encode({ function() end })
      assert.is_nil(res)
      assert.is_not_nil(err)

      -- Next encode should be clean
      local res2 = wjson.encode({ a = 1 })
      assert.is_equal('{"a":1}', res2)
    end)

    it("survives re-entrant __tojson and error in it", function()
      local t = setmetatable({}, {
        __tojson = function()
          -- Re-entrant call
          wjson.encode({ nested = true })
          error("boom")
        end
      })
      local status, res = pcall(wjson.encode, { item = t })
      assert.is_false(status)

      -- Next encode should be clean
      local res2 = wjson.encode({ safe = true })
      assert.is_equal('{"safe":true}', res2)
    end)

    it("does not leak large buffer content to small encodes", function()
      local large = {}
      for i = 1, 1000 do large[i] = i end
      wjson.encode(large)

      local res = wjson.encode({ short = true })
      assert.is_equal('{"short":true}', res)
    end)
  end)
end)
