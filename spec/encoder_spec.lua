local wjson = require("wjson")

describe("JSON Encoder", function()
  it("encodes null correctly", function()
    assert.is_equal("null", wjson.encode(wjson.null))
  end)

  it("handles null roundtripping", function()
    local encoded = wjson.encode({ a = wjson.null })
    local decoded = wjson.decode(encoded)
    assert.is_equal(wjson.null, decoded.a)
  end)

  it("encodes empty array correctly", function()
    assert.is_equal("[]", wjson.encode(wjson.empty_array()))
  end)

  it("handles empty array roundtripping", function()
    local encoded = wjson.encode({ a = wjson.empty_array() })
    local decoded = wjson.decode(encoded)
    -- Note: Since we use M.empty_array for decoding empty arrays, this should match
    assert.is_same(wjson.empty_array(), decoded.a)
    assert.is_equal("[]", wjson.encode(decoded.a))
  end)

  it("encodes basic types correctly", function()
    assert.is_equal("true", wjson.encode(true))
    assert.is_equal("false", wjson.encode(false))
    assert.is_equal("123", wjson.encode(123))
    assert.is_equal("1.5", wjson.encode(1.5))
    assert.is_equal('"hello"', wjson.encode("hello"))
  end)

  it("encodes objects correctly", function()
    local obj = { a = 1, b = "two" }
    local encoded = wjson.encode(obj)
    -- Order is not guaranteed in Lua tables
    assert.is_true(encoded == '{"a":1,"b":"two"}' or encoded == '{"b":"two","a":1}')
  end)

  it("encodes nested structures correctly", function()
    local data = {
      a = { 1, 2, 3 },
      b = { c = "d" },
      e = wjson.empty_array(),
      f = wjson.null
    }
    local encoded = wjson.encode(data)
    local decoded = wjson.decode(encoded)
    assert.is_same({ 1, 2, 3 }, decoded.a)
    assert.is_equal("d", decoded.b.c)
    assert.is_same(wjson.empty_array(), decoded.e)
    assert.is_equal(wjson.null, decoded.f)
  end)

  it("works with a custom buffer argument", function()
    local buffer = {}
    local data = { z = 3 }
    local encoded = wjson.encode(data, buffer)
    assert.is_equal('{"z":3}', encoded)
    -- Optional: verify buffer was used (it should be cleared after use)
    assert.is_nil(buffer[1])
  end)

  it("handles errors and clears buffer", function()
    local buffer = {}
    local res, err = wjson.encode({ true, false, "1", function() end }, buffer)
    assert.is_nil(res)
    assert.is_not_nil(err)
    assert.is_nil(buffer[1])
    -- After error, a subsequent call should still work correctly
    assert.is_equal("true", wjson.encode(true, buffer))
    assert.is_nil(buffer[1])
  end)

  describe("cycle detection", function()
    it("detects a self-referencing table", function()
      local t = { a = 1 }
      t.self = t
      local res, err = wjson.encode(t)
      assert.is_nil(res)
      assert.is_truthy(err:find("cyclic"))
    end)

    it("detects a self-referencing array", function()
      local t = { 1, 2, 3 }
      t[4] = t
      local res, err = wjson.encode(t)
      assert.is_nil(res)
      assert.is_truthy(err:find("cyclic"))
    end)

    it("detects an indirect cycle", function()
      local a = {}
      local b = {}
      a.child = b
      b.parent = a
      local res, err = wjson.encode(a)
      assert.is_nil(res)
      assert.is_truthy(err:find("cyclic"))
    end)

    it("allows a shared table in a DAG (no cycle)", function()
      local shared = { x = 1 }
      local data = { a = shared, b = shared }
      local res, err = wjson.encode(data)
      assert.is_not_nil(res)
      assert.is_nil(err)
      local decoded = wjson.decode(res)
      assert.is_equal(1, decoded.a.x)
      assert.is_equal(1, decoded.b.x)
    end)
  end)

  describe("__tojson metamethod", function()
    it("uses __tojson if present and returns a string", function()
      local t = setmetatable({ a = 1 }, {
        __tojson = function(val) return '{"custom":true}' end
      })
      local encoded = wjson.encode({ item = t })
      assert.is_equal('{"item":{"custom":true}}', encoded)
    end)

    it("errors if __tojson returns nil/false", function()
      local t = setmetatable({}, {
        __tojson = function() return false, "expected error" end
      })
      local res, err = wjson.encode({ item = t })
      assert.is_nil(res)
      assert.is_equal("expected error", err)
    end)

    it("does not trigger cycle error when simply utilizing __tojson correctly", function()
      local t = setmetatable({}, {
        __tojson = function() return '"hello"' end
      })
      assert.is_equal('"hello"', wjson.encode(t))
    end)
  end)
end)
