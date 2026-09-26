--!nocheck
-- Compile every .luau under src/ and tools/ (syntax check, same compiler family as Roblox Luau).
--   lune run tools/compile_all.luau
local fs, luau, process = require("@lune/fs"), require("@lune/luau"), require("@lune/process")
local bad = 0
local function walk(dir)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif string.match(entry, "%.luau$") then
			local ok, err = pcall(luau.compile, fs.readFile(path))
			print((ok and "OK   " or "FAIL ") .. path .. (ok and "" or ("  " .. tostring(err))))
			if not ok then bad += 1 end
		end
	end
end
walk("src")
walk("tools")
process.exit(bad == 0 and 0 or 1)
