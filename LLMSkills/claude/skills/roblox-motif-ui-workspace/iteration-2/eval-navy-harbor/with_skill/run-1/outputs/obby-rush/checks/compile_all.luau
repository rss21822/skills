--!nocheck
-- Compile every .luau under src/ (syntax check). Run from the project folder: lune run checks/compile_all.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local failed, count = 0, 0
local function walk(dir)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif string.match(entry, "%.luau?$") then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			print((ok and "OK   " or "FAIL ") .. path .. (ok and "" or (" :: " .. tostring(err))))
			if not ok then failed += 1 end
		end
	end
end
walk("src")
print(string.format("%s compile: %d files, %d failed", failed == 0 and "PASS" or "FAIL", count, failed))
process.exit(failed == 0 and 0 or 1)
