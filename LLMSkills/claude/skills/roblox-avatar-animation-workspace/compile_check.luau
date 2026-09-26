local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
for _, p in process.args do
  local ok, err = pcall(luau.compile, fs.readFile(p))
  print(ok and "OK" or "FAIL", p, ok and "" or tostring(err))
end
