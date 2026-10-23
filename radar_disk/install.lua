-- Installs the radar library from this disk.
-- Usage: install              install or update
--        install remove       uninstall (same as uninstall)
--        install remove all   uninstall together with the examples
local args = { ... }
local here = fs.getDir(shell.getRunningProgram())

local LIB = "lib/radar.lua"
local UI = "lib/radarui.lua"
local BALLISTICS = "lib/ballistics.lua"
local LOADER = "startup/00_radarlib.lua"
local EXAMPLE = "radar_example.lua"
local UI_EXAMPLE = "radar_ui_example.lua"
local GUN_EXAMPLE = "gun_example.lua"

if args[1] == "remove" then
    shell.run("/" .. fs.combine(here, "uninstall.lua"), args[2] or "")
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
copy("radarui.lua", UI)
copy("ballistics.lua", BALLISTICS)
copy("loader.lua", LOADER)
if not fs.exists(EXAMPLE) then copy("example.lua", EXAMPLE) end
if not fs.exists(UI_EXAMPLE) then copy("example_ui.lua", UI_EXAMPLE) end
if not fs.exists(GUN_EXAMPLE) then copy("example_gun.lua", GUN_EXAMPLE) end

-- Register right away, so no reboot is needed.
shell.run("/" .. LOADER)

print("radar library installed:")
print("  /" .. LIB)
print("  /" .. UI)
print("  /" .. BALLISTICS)
print("  /" .. LOADER)
print("  /" .. EXAMPLE .. ", /" .. UI_EXAMPLE .. ", /" .. GUN_EXAMPLE .. " (examples)")
print('Use: local radar = require("radar")')
print('     local ui = require("radarui")')
print('     local ballistics = require("ballistics")')
print("You can remove the disk now.")
