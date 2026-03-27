local wjson = require("wjson")
local lfs = require("lfs")

describe("JSONTestSuite Transform Tests", function()
  local test_dir = "spec/JSONTestSuite/test_transform"

  -- Use ls to get all files
  local files = {}
  for file in lfs.dir(test_dir) do
    if file:match("%.json$") then
      table.insert(files, file)
    end
  end

  for _, filename in ipairs(files) do
    local path = test_dir .. "/" .. filename

    it(filename, function()
      local f = io.open(path, "r")
      if not f then error("Could not open file: " .. path) end
      local content = f:read("*all")
      f:close()

      -- We use pcall to ensure we catch any crashes during decoding
      local status, res, err = pcall(wjson.decode, content)
      assert.is_true(status)

      -- For transform tests, they might be valid or invalid JSON according to strict RFC,
      -- but they are often used to see how parsers handle edge cases.
      -- We don't necessarily assert res.ok for all of them unless we know they should be valid.

      if filename == "object_same_key_different_values.json" then
        assert.is_nil(err)
        assert.is_equal(2, res.a)
      elseif filename == "object_same_key_same_value.json" then
        assert.is_nil(err)
        assert.is_equal(1, res.a)
      elseif filename == "number_1.0.json" then
        assert.is_nil(err)
        -- Lua numbers are doubles, so 1.0 is just 1
        assert.is_equal(1, res[1])
      end
    end)
  end
end)
