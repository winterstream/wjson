local wjson = require("wjson")

describe("JSON UTF-8 Validation", function()
  local function test_rejection(name, input)
    it("should reject " .. name, function()
      local res, err = wjson.decode(input)
      assert.is_nil(res, "Expected rejection for: " .. name)
      assert.truthy(err:find("Invalid UTF%-8 sequence"))
    end)
  end

  describe("Invalid Lead Bytes", function()
    -- Bytes 0x80-0xBF are continuation bytes, never lead bytes
    test_rejection("unexpected continuation byte 0x80", '{"t": "\x80"}')
    test_rejection("unexpected continuation byte 0xBF", '{"t": "\xbf"}')

    -- Bytes 0xC0, 0xC1 are invalid (would be overlong)
    test_rejection("invalid lead byte 0xC0", '{"t": "\xc0\xaf"}')
    test_rejection("invalid lead byte 0xC1", '{"t": "\xc1\x80"}')

    -- Bytes 0xF5-0xFF are restricted
    test_rejection("invalid lead byte 0xF5", '{"t": "\xf5\x80\x80\x80"}')
    test_rejection("invalid lead byte 0xFF", '{"t": "\xff"}')
  end)

  describe("Truncated Sequences", function()
    test_rejection("truncated 2-byte sequence", '{"t": "\xc2"}')
    test_rejection("truncated 3-byte sequence (1 byte)", '{"t": "\xe2"}')
    test_rejection("truncated 3-byte sequence (2 bytes)", '{"t": "\xe2\x82"}')
    test_rejection("truncated 4-byte sequence (1 byte)", '{"t": "\xf0"}')
    test_rejection("truncated 4-byte sequence (2 bytes)", '{"t": "\xf0\x9f"}')
    test_rejection("truncated 4-byte sequence (3 bytes)", '{"t": "\xf0\x9f\x92"}')
  end)

  describe("Invalid Continuation Bytes", function()
    -- Continuation bytes must be 0x80-0xBF
    test_rejection("invalid 2nd byte in 2-byte sequence", '{"t": "\xc2\x20"}')
    test_rejection("invalid 2nd byte in 3-byte sequence", '{"t": "\xe2\x20\x80"}')
    test_rejection("invalid 3rd byte in 3-byte sequence", '{"t": "\xe2\x82\x20"}')
  end)

  describe("Overlong Encodings", function()
    -- ASCII '/' (0x2F) encoded as 2 bytes: 0xC0 0xAF
    test_rejection("overlong ASCII", '{"t": "\xc0\xaf"}')
  end)
end)
