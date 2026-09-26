--!nocheck
-- Compile every Luau file under src/ (syntax check, same compiler as Roblox). Run from the project folder.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local bad = 0
local function walk(dir)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif string.match(entry, "%.luau?$") then
			local ok, err = pcall(luau.compile, fs.readFile(path))
			print((ok and "OK   " or "FAIL ") .. path .. (ok and "" or ("  " .. tostring(err))))
			if not ok then bad += 1 end
		end
	end
end
walk("src")
process.exit(bad == 0 and 0 or 1)
