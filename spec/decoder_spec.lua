local wjson = require("wjson")

describe("decode_next", function()
  it("decodes multiple json values from a string", function()
    --                6      14             29
    --                |       |              |
    local str = '  [1]    true     {"a": "b"}    totally_invalid_json'
    local len = #str

    local val, next_idx = wjson.decode_next(str, len)
    assert.are_same({ 1 }, val)
    assert.are_equal(6, next_idx)

    val, next_idx = wjson.decode_next(str, len, next_idx)
    assert.are_same(true, val)
    assert.are_equal(14, next_idx)

    val, next_idx = wjson.decode_next(str, len, next_idx)
    assert.are_same({ a = "b" }, val)
    assert.are_equal(29, next_idx)
  end)


  it("fails to decode incomplete json", function()
    local str = '  [1'

    local val, next_idx, err = wjson.decode_next(str, 1024)
    assert.is_nil(val)
    assert.is_nil(next_idx)
    assert.is_not_nil(err)
  end)
end)
