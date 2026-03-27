package = "wjson"
version = "0.1-1"
source = {
   url = "git+https://github.com/wynand/wjson.git"
}
description = {
   summary = "A fast and small JSON library for Lua and LuaJIT",
   detailed = [[
      wjson is a minimalist JSON encoder/decoder for Lua. 
      It supports Lua 5.2+, LuaJIT, and provides a simple API for conversion.
   ]],
   homepage = "https://github.com/wynand/wjson",
   license = "MIT"
}
dependencies = {
   "lua >= 5.2"
}
build = {
   type = "builtin",
   modules = {
      wjson = "src/wjson.lua"
   }
}
