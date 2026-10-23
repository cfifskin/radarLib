-- Example: show ships (sublevels) seen by the radar.
local radar = require("radar")

local sensor = peripheral.find("entity_radar") or error("No entity_radar attached", 0)
local monitor = peripheral.find("monitor")

-- World coordinates need the radar position (then set USE_GLOBAL = true).
-- With GPS (ground or Sable structure): radar block - computer block.
-- On a structure count it along the structure's own blocks.
-- radar.setOffset(sensor, 0, 1, 0)
-- Without GPS, ground only: radar block coordinates from F3.
-- radar.setOrigin(sensor, 100, 64, -200)
local USE_GLOBAL = false
local FILTER = "sublevel" -- or { "sublevel", "object_large" }, or nil for all

local out = monitor or term.current()
if monitor then monitor.setTextScale(0.5) end

while true do
    local ok, targets, info = pcall(radar.scan, sensor, FILTER, USE_GLOBAL)

    local old = term.redirect(out)
    term.clear()
    term.setCursorPos(1, 1)
    if not ok then
        printError(targets)
    else
        print(("tick %d  targets %d/%d  %s"):format(
            info.tick, #targets, info.total, info.mode or "local"))
        for i, t in ipairs(targets) do
            print(("%d) %s"):format(i, t.subLevelName or t.name or t.type))
            print(("  pos %.2f %.2f %.2f  d=%.2f"):format(t.x, t.y, t.z, t.distance))
            print(("  vel %.3f %.3f %.3f  |v|=%.3f b/t  n=%d"):format(
                t.velocity.x, t.velocity.y, t.velocity.z, t.speed, t.samples))
        end
    end
    term.redirect(old)

    sleep(0.25)
end
