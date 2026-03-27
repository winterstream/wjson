local wjson = require("wjson")
local lfs = require("lfs")

describe("JSONTestSuite Parsing Tests", function()
  local test_dir = "spec/JSONTestSuite/test_parsing"

  -- Use ls to get all files
  local files = {}
  for file in lfs.dir(test_dir) do
    if file:match("%.json$") then
      table.insert(files, file)
    end
  end

  for _, filename in ipairs(files) do
    local category = filename:sub(1, 1) -- y, n, or i
    local path = test_dir .. "/" .. filename

    it(filename, function()
      local f = io.open(path, "r")
      if not f then error("Could not open file: " .. path) end
      local content = f:read("*all")
      f:close()

      local status, res, err = pcall(wjson.decode, content)

      if category == "y" then
        -- Must accept
        assert.is_not_nil(res)
      elseif category == "n" then
        -- Must reject
        assert.is_not_nil(err)
      elseif category == "i" then
        -- Parsers are free to accept or reject.
        -- We just ensure it doesn't crash.
        assert.is_true(status)
      end
    end)
  end
end)
