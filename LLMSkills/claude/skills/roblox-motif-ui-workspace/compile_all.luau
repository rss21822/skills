local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local failed = 0
for _, path in ipairs(process.args) do
	local ok, err = pcall(luau.compile, fs.readFile(path))
	print((ok and "OK   " or "FAIL ") .. path .. (ok and "" or (" " .. tostring(err))))
	if not ok then failed += 1 end
end
process.exit(failed == 0 and 0 or 1)
