local wjson = require("wjson")

describe("JSON Unicode Handling", function()
  it("correctly handles surrogate pairs by combining them into a single UTF-8 character", function()
    -- G Clef: U+1D11E -> \uD834\uDD1E
    -- UTF-8: F0 9D 84 9E (\240\157\132\158)
    local input = '"\\uD834\\uDD1E"'
    local res, err = wjson.decode(input)
    assert.is_nil(err)
    assert.is_equal("\240\157\132\158", res)
  end)

  it("rejects unpaired surrogates", function()
    -- Lone high surrogate
    local res1, err1 = wjson.decode('"\\uD800"')
    assert.is_nil(res1, "Should reject lone high surrogate")
    assert.match("Unpaired surrogate", err1)

    -- Lone low surrogate
    local res2, err2 = wjson.decode('"\\uDC00"')
    assert.is_nil(res2, "Should reject lone low surrogate")
    assert.match("Unpaired surrogate", err2)
  end)

  it("rejects non-standard \\U escapes", function()
    -- \U0001D11E is not standard JSON
    local input = '"\\U0001D11E"'
    local res, err = wjson.decode(input)
    assert.is_nil(res)
    assert.match("Invalid escape sequence", err)
  end)

  it("handles standard 4-byte UTF-8 sequences (non-surrogate)", function()
    -- Emoji 𝄞 can also be passed directly if the file is UTF-8, but testing escapes here.
    -- Let's test a BMP character just to be sure regular stuff still works.
    -- Euro sign: € -> U+20AC -> \u20AC
    local input = '"\\u20AC"'
    local res, err = wjson.decode(input)
    assert.is_nil(err)
    assert.is_equal("€", res)
  end)

  it("rejects valid JavaScript escapes that are invalid JSON", function()
    -- \' is valid in JavaScript strings, but invalid in JSON.
    -- Strict parsers must reject it.
    local res, err = wjson.decode('"\\\'"')
    assert.is_nil(res)
    assert.match("Invalid escape sequence", err)
  end)

  describe("rejects non-standard escape formats", function()
    local attempts = {
      { fmt = "Lua/ES6 style",   val = '"\\u{0041}"' },
      { fmt = "Perl/PCRE style", val = '"\\x{41}"' },
      { fmt = "Hex style",       val = '"\\x41"' },
      { fmt = "Octal style",     val = '"\\101"' },
      { fmt = "CSS style",       val = '"\\0041"' }, -- Usually not in strings like this, but ensures numbering isn't parsed
    }

    for _, attempt in ipairs(attempts) do
      it("rejects " .. attempt.fmt .. ": " .. attempt.val, function()
        local res, err = wjson.decode(attempt.val)
        assert.is_nil(res)
        assert.match("Invalid", err)
      end)
    end
  end)

  describe("treats other formats as literals (not escapes)", function()
    -- HTML Entities, Percent Encoding, etc. are NOT JSON escapes.
    -- If they appear in a string, they should be treated as literal characters.
    -- They should NOT be decoded into their referenced character.
    local literals = {
      { name = "HTML Entity",      input = '"&#x41;"', expected = "&#x41;" },
      { name = "Percent encoding", input = '"%u0041"', expected = "%u0041" },
      { name = "U+ notation",      input = '"U+0041"', expected = "U+0041" },
      { name = "0x notation",      input = '"0x41"',   expected = "0x41" },
    }

    for _, case in ipairs(literals) do
      it("reads " .. case.name .. " as entry string literal", function()
        local res, err = wjson.decode(case.input)
        assert.is_not_nil(res)
        assert.is_equal(case.expected, res)
      end)
    end
  end)
end)
