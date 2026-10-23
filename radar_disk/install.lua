-- Installs the radar library from this disk.
-- Usage: install          install or update
--        install remove   uninstall
local args = { ... }
local here = fs.getDir(shell.getRunningProgram())

local LIB = "lib/radar.lua"
local LOADER = "startup/00_radarlib.lua"
local EXAMPLE = "radar_example.lua"

if args[1] == "remove" then
    fs.delete(LIB)
    fs.delete(LOADER)
    print("radar library removed. Reboot to unload it.")
    return
end

if fs.exists("startup") and not fs.isDir("startup") then
    printError("/startup is a file. Rename it to /startup.lua and run install again.")
    return
end

local function copy(from, to)
    if fs.exists(to) then fs.delete(to) end
    local dir = fs.getDir(to)
    if dir ~= "" then fs.makeDir(dir) end
    fs.copy(fs.combine(here, from), to)
end

copy("radar.lua", LIB)
copy("loader.lua", LOADER)
if not fs.exists(EXAMPLE) then copy("example.lua", EXAMPLE) end

-- Register right away, so no reboot is needed.
shell.run("/" .. LOADER)

print("radar library installed:")
print("  /" .. LIB)
print("  /" .. LOADER)
print("  /" .. EXAMPLE .. " (example)")
print('Use: local radar = require("radar")')
print("You can remove the disk now.")
