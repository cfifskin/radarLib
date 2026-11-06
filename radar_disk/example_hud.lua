-- Example: radar screen on HUD glasses (mod CC: HUD Glasses).
-- Put a HUD Modem next to the computer and bind the glasses to it: hold them
-- and right-click the modem. A pocket computer with the HUD upgrade works too.
package.path = "/lib/?.lua;" .. package.path -- works even if the startup loader is missing or old
local radar = require("radar")
local ui = require("radarui")

local sensor = peripheral.find("entity_radar") or error("No entity_radar attached", 0)
local glasses = peripheral.find("hud_glasses") or error("No HUD Modem attached", 0)

local SCALE = 1              -- size: 1 = 40x30 cells, 2 = 80x60, also 0.5, 2.3... (at most 3.2)
local POSITION = "top_right" -- top_left, top, top_right, left, center, right,
                             -- bottom_left, bottom, bottom_right or { x, y }, cell of the
                             -- top left corner (the screen is 256x96 cells)
local FILTER = nil           -- all targets; or "sublevel", { "sublevel", "player" }
local FRONT = "-z"           -- axis at the top of the radar: "x", "-x", "z", "-z"

local hud = ui.hud(glasses, { scale = SCALE, position = POSITION })

while true do
    local ok, targets, info = pcall(radar.scan, sensor, FILTER, false)
    if ok then
        ui.draw(hud, targets, info, FRONT)
    else
        printError(targets)
    end
    sleep(0.25)
end
