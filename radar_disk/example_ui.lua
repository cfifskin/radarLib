-- Example: radar screen on a monitor (advanced monitor: touch a target to select it).
local radar = require("radar")
local ui = require("radarui")

local sensor = peripheral.find("entity_radar") or error("No entity_radar attached", 0)
local monitor = peripheral.find("monitor") or term.current()

-- World coordinates need the radar position, see radar_example.lua.
-- radar.setOffset(sensor, 0, 1, 0)
local USE_GLOBAL = false
local FILTER = nil  -- all targets; or "sublevel", { "sublevel", "player" }
local FRONT = "-z"  -- axis at the top of the screen: "x", "-x", "z", "-z"

local function radarLoop()
    while true do
        local ok, targets, info = pcall(radar.scan, sensor, FILTER, USE_GLOBAL)
        if ok then
            local target = ui.draw(monitor, targets, info, FRONT, true, true)
            -- target is the selected target (or nil): use it for guns, logs...
        else
            printError(targets)
        end
        sleep(0.25)
    end
end

-- ui.listen handles touches while radarLoop sleeps or scans.
parallel.waitForAny(radarLoop, ui.listen)
