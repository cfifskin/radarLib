-- Example: radar screen on a monitor (advanced monitor: touch a target to select it).
package.path = "/lib/?.lua;" .. package.path -- works even if the startup loader is missing or old
local radar = require("radar")
local ui = require("radarui")

local sensor = peripheral.find("entity_radar") or error("No entity_radar attached", 0)
local monitor = peripheral.find("monitor") or term.current()

-- World coordinates need the radar position, see radar_example.lua.
-- radar.setOffset(sensor, 0, 1, 0)
local USE_GLOBAL = false
local FILTER = nil  -- all targets; or "sublevel", { "sublevel", "player" }
local FRONT = "-z"  -- axis at the top of the screen: "x", "-x", "z", "-z"
local TEXT_SCALE = nil -- monitor font size 0.5..5 (step 0.5), nil = by monitor size

local function radarLoop()
    while true do
        local ok, targets, info = pcall(radar.scan, sensor, FILTER, USE_GLOBAL)
        if ok then
            local target = ui.draw(monitor, targets, info, FRONT, true, true, TEXT_SCALE)
            -- target is the selected target (or nil): use it for guns, logs...
        else
            printError(targets)
        end
        sleep(0.25)
    end
end

-- ui.listen handles touches while radarLoop sleeps or scans.
parallel.waitForAny(radarLoop, ui.listen)
