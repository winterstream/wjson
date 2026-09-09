#!/usr/bin/env lua
-- tools/render_rockspec.lua
-- Renders README.md into plain-text ASCII format and updates the rockspec
-- description.detailed field.

-- Read file contents or raise an error.
local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then
    error("failed to open " .. path .. ": " .. tostring(err))
  end
  local content = f:read("*a")
  f:close()
  return content
end

-- Write file contents or raise an error.
local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    error("failed to open " .. path .. " for writing: " .. tostring(err))
  end
  f:write(content)
  f:close()
end

-- Normalize Unicode punctuation to ASCII equivalents for monospaced alignment.
local function normalize_ascii(s)
  s = s:gsub("\226\128\147", "-")   -- en-dash –
  s = s:gsub("\226\128\148", "--")  -- em-dash —
  s = s:gsub("\226\128\153", "'")   -- right single quote ’
  s = s:gsub("\226\128\152", "'")   -- left single quote ‘
  s = s:gsub("\226\128\156", "\"")  -- left double quote “
  s = s:gsub("\226\128\157", "\"")  -- right double quote ”
  s = s:gsub("\195\151", "x")       -- multiplication sign ×
  return s
end

-- Clean cell content for table rendering.
local function clean_cell(s)
  s = s:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  s = s:gsub("%*%*([^*]+)%*%*", "%1")
  s = s:gsub("`", "")
  s = s:gsub("\\%*", "*")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Render Markdown table lines as an ASCII-bordered box table.
local function render_table(table_lines)
  local rows = {}

  for _, line in ipairs(table_lines) do
    if not line:match("^%s*|%s*:?%-+") then
      local row = {}
      local l = line:gsub("^%s*|", ""):gsub("|%s*$", "")
      for cell in (l .. "|"):gmatch("([^|]*)|") do
        table.insert(row, clean_cell(cell))
      end
      if #row > 0 then
        table.insert(rows, row)
      end
    end
  end

  if #rows == 0 then
    return ""
  end

  -- Calculate maximum column widths.
  local widths = {}
  for _, row in ipairs(rows) do
    for i, cell in ipairs(row) do
      widths[i] = math.max(widths[i] or 0, #cell)
    end
  end

  local function make_border()
    local parts = {}
    for _, w in ipairs(widths) do
      table.insert(parts, string.rep("-", w + 2))
    end
    return "+" .. table.concat(parts, "+") .. "+"
  end

  local border = make_border()
  local out = {}
  table.insert(out, border)

  for i, row in ipairs(rows) do
    local line_cells = {}
    for c, cell in ipairs(row) do
      table.insert(line_cells, " " .. cell .. string.rep(" ", widths[c] - #cell) .. " ")
    end
    table.insert(out, "|" .. table.concat(line_cells, "|") .. "|")
    if i == 1 then
      table.insert(out, border)
    end
  end

  table.insert(out, border)
  return table.concat(out, "\n")
end

-- Clean inline Markdown links, bold markers, and escapes in regular lines.
local function clean_line(line)
  line = line:gsub("%[([^%]]+)%]%(([^%)]+)%)", function(text, url)
    text = text:gsub("`", "")
    if url:match("^#") or url == "LICENSE" then
      return text
    end
    if text == url then
      return url
    end
    return text .. " (" .. url .. ")"
  end)
  line = line:gsub("%*%*([^*]+)%*%*", "%1")
  line = line:gsub("\\%*", "*")
  return line
end

-- Convert full Markdown text into plain ASCII text.
local function render_markdown(md)
  md = normalize_ascii(md)
  md = md:gsub("<!%-%-.-%-%->\n?", "")

  local in_lines = {}
  for line in (md .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    table.insert(in_lines, line)
  end

  local out_lines = {}
  local i = 1
  local in_code_block = false

  while i <= #in_lines do
    local line = in_lines[i]

    if line:match("^```") then
      in_code_block = not in_code_block
      i = i + 1
    elseif in_code_block then
      if line == "" then
        table.insert(out_lines, "")
      else
        table.insert(out_lines, "    " .. line)
      end
      i = i + 1
    elseif line:match("^%s*|.*|%s*$") then
      local tbl_lines = {}
      while i <= #in_lines and in_lines[i]:match("^%s*|.*|%s*$") do
        table.insert(tbl_lines, in_lines[i])
        i = i + 1
      end
      table.insert(out_lines, render_table(tbl_lines))
    elseif line:match("^%s*%[%s*!%[") or line:match("^%s*!%[") then
      -- Skip badge links and images
      i = i + 1
    elseif line:match("^#%s+(.+)$") then
      local title = line:match("^#%s+(.+)$")
      title = clean_line(title):gsub("`([^`]+)`", "%1")
      table.insert(out_lines, title)
      table.insert(out_lines, string.rep("=", #title))
      i = i + 1
    elseif line:match("^##%s+(.+)$") then
      local heading = line:match("^##%s+(.+)$")
      heading = clean_line(heading):gsub("`([^`]+)`", "%1")
      table.insert(out_lines, heading)
      table.insert(out_lines, string.rep("-", #heading))
      i = i + 1
    elseif line:match("^###%s+(.+)$") then
      local sub = line:match("^###%s+(.+)$")
      sub = clean_line(sub):gsub("`([^`]+)`", "%1")
      table.insert(out_lines, sub)
      table.insert(out_lines, string.rep("~", #sub))
      i = i + 1
    elseif line:match("^>%s*%[!NOTE%]") then
      table.insert(out_lines, "Note:")
      i = i + 1
    elseif line:match("^>%s*(.*)$") then
      local quote = line:match("^>%s*(.*)$")
      table.insert(out_lines, "  " .. clean_line(quote))
      i = i + 1
    else
      table.insert(out_lines, clean_line(line))
      i = i + 1
    end
  end

  local res = table.concat(out_lines, "\n")
  res = res:gsub("\n\n\n+", "\n\n")
  res = res:gsub("^%s+", ""):gsub("%s+$", "")
  return res
end

-- Find default rockspec filename from Makefile if available.
local function find_rockspec()
  local mf = io.open("Makefile", "r")
  if mf then
    local content = mf:read("*a")
    mf:close()
    local name = content:match("ROCKSPEC%s*=%s*([^\r\n]+)")
    if name and name ~= "" then
      return (name:gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end
  return "wjson-0.9-4.rockspec"
end

-- Replace description.detailed in rockspec text with rendered string.
local function update_rockspec(rockspec, rendered)
  local new_detailed = "detailed = [==[\n" .. rendered .. "\n   ]==],"
  local s, e = rockspec:find("detailed%s*=%s*%[([=]*)%[.-%]%1%]%s*,?")
  if s then
    return rockspec:sub(1, s - 1) .. new_detailed .. rockspec:sub(e + 1)
  end
  error("could not locate description.detailed in rockspec")
end

-- Extract existing description.detailed from rockspec.
local function extract_detailed(rockspec)
  local _, content = rockspec:match("detailed%s*=%s*%[([=]*)%[\r?\n?(.-)%]%1%]")
  if content then
    return (content:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  return nil
end

-- Main entry point.
local function main(args)
  local mode = "update"
  local rockspec_path = nil

  for _, arg in ipairs(args) do
    if arg == "--check" then
      mode = "check"
    elseif arg == "--dump" then
      mode = "dump"
    elseif not rockspec_path and not arg:match("^%-") then
      rockspec_path = arg
    end
  end

  rockspec_path = rockspec_path or find_rockspec()

  local md = read_file("README.md")
  local rendered = render_markdown(md)

  if mode == "dump" then
    io.write(rendered, "\n")
    return 0
  end

  local rockspec = read_file(rockspec_path)

  if mode == "check" then
    local current = extract_detailed(rockspec)
    if current ~= rendered then
      io.stderr:write("Error: " .. rockspec_path .. " detailed description is out of date.\n")
      io.stderr:write("Run 'make rockspec' to update it.\n")
      return 1
    end
    print(rockspec_path .. " detailed description is up to date.")
    return 0
  end

  local updated = update_rockspec(rockspec, rendered)
  write_file(rockspec_path, updated)
  print("Updated " .. rockspec_path .. " description.detailed from README.md")
  return 0
end

local code = main(arg)
os.exit(code)
