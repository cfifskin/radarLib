-- Installed as /startup/00_radarlib.lua.
-- CC:Tweaked gives every program its own package.path, but copies
-- debug.getregistry()._LOADED into each program's package.loaded. Registering
-- the library there makes require("radar") work from any directory.
local path = "/lib/radar.lua"
if not fs.exists(path) then return end

local registry = debug and debug.getregistry and debug.getregistry()
if type(registry) ~= "table" then
    printError("radarlib: debug.getregistry is unavailable.")
    printError('Use: package.path = "/lib/?.lua;" .. package.path')
    return
end
if type(registry._LOADED) ~= "table" then registry._LOADED = {} end

local fn, err = loadfile(path, nil, setmetatable({}, { __index = _G }))
if not fn then
    printError("radarlib: " .. err)
    return
end
local ok, lib = pcall(fn, "radar")
if not ok then
    printError("radarlib: " .. tostring(lib))
    return
end
registry._LOADED.radar = lib
