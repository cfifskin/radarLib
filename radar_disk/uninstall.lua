-- Removes the radar library from this computer.
--   uninstall        remove the libraries and the startup loader
--   uninstall all    also remove the example programs
-- One command without a disk:
--   wget run https://raw.githubusercontent.com/cfifskin/radarLib/main/radar_disk/uninstall.lua
local args = { ... }
local all = args[1] == "all"

local FILES = {
    "lib/radar.lua", "lib/radarui.lua", "lib/ballistics.lua",
    "startup/00_radarlib.lua",
    ".radarlib_tmp", -- left over by an interrupted download
}
local EXAMPLES = { "radar_example.lua", "radar_ui_example.lua", "gun_example.lua" }
local MODULES = { "radar", "radarui", "ballistics" }

local removed = 0
local function remove(path)
    if fs.exists(path) then
        fs.delete(path)
        print("  removed /" .. path)
        removed = removed + 1
    end
end

-- Delete a directory only if nothing else is left in it.
local function removeIfEmpty(dir)
    if fs.isDir(dir) and #fs.list(dir) == 0 then remove(dir) end
end

print("Removing radar library:")
for _, path in ipairs(FILES) do remove(path) end
if all then
    for _, path in ipairs(EXAMPLES) do remove(path) end
end
removeIfEmpty("lib")
removeIfEmpty("startup")

-- Unregister the modules, so new programs no longer find them without a reboot.
local registry = debug and debug.getregistry and debug.getregistry()
if type(registry) == "table" and type(registry._LOADED) == "table" then
    for _, name in ipairs(MODULES) do registry._LOADED[name] = nil end
end

if removed == 0 then
    print("  nothing to remove")
else
    print("Done. Programs that are already running keep the library until a reboot.")
end
if not all then
    for _, path in ipairs(EXAMPLES) do
        if fs.exists(path) then
            print('Examples are kept, "uninstall all" removes them too.')
            break
        end
    end
end
