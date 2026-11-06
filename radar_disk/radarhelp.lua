-- Help for the radar library, right on the computer.
--   radarhelp          list of topics
--   radarhelp <topic>  one topic
-- The full manual is the README of the repository.

local TOPICS = {
    { "scan", "radar.scan and what it returns", [[
local radar = require("radar")
local sensor = peripheral.find("entity_radar")
local targets, info = radar.scan(sensor, filter, global)

sensor: wrapped peripheral or its name.
filter: type name, list of names or nil for all targets:
  "sublevel", "object_large", "minecraft:pig", "pig"
global: true = world coordinates (see: position),
  false/nil = offset from the sensor block.

Each target: uuid, type, name, subLevelName, subLevelUUID,
x, y, z, distance, velocity {x, y, z} in blocks/tick,
speed, samples, tracked (ticks followed; velocity is 0
while tracked == 0).

info: sensor, tick, total, scans, global, mode, origin,
range, orientation, addon, filter, matched, maxTargets,
truncated.

radar.reset(sensor) forgets tracked targets.]] },

    { "position", "world coordinates: GPS and offset", [[
global = true needs the world position of the sensor.

radar.setOffset(sensor, dx, dy, dz)
  sensor block minus computer block. On a Sable structure
  these are the structure's own axes. Needs GPS once.
radar.setOrigin(sensor, x, y, z)
  sensor block from F3, ground only, no GPS.
radar.setHost(x, y, z)
  computer block by hand, ground only, no GPS.

radar.getOrigin(sensor) returns {x, y, z}, mode.
Compare it with F3 to check the setup.
mode: "ground", "structure" or "manual".

radar.calibrate() measures the computer again, for example
after moving it or after "structure calibration failed":
slow the structure down first.]] },

    { "screen", "radar picture on a monitor or a terminal", [[
local ui = require("radarui")
local monitor = peripheral.find("monitor")

ui.draw(device, targets, info, front, showInfo, touch,
        textScale)

device: monitor, its name, term.current() or a window.
front: axis at the top: "x", "-x", "z", "-z".
showInfo: true = panel with the selected target.
touch: true = touching a target selects it.
textScale: 0.5..5, nil = picked by the monitor size.
Returns the selected target or nil.

Touch needs ui.listen running next to your loop:
parallel.waitForAny(radarLoop, ui.listen)

ui.select(device, target or uuid), nil clears it.
local uuid, target = ui.getSelected(device)]] },

    { "hud", "radar on HUD glasses", [[
Mod CC: HUD Glasses. Put a HUD Modem next to the computer,
bind the glasses: hold them, right-click the modem.

local glasses = peripheral.find("hud_glasses")
local hud = ui.hud(glasses, { scale = 2, position = "top_right" })
ui.draw(hud, targets, info, "-z")

scale: any positive number, the radar takes 40*scale x
  30*scale cells: 1 = 40x30, 2 = 80x60, 0.5 = 20x15.
  At most 3.2 on the default grid.
position: top_left, top, top_right, left, center, right,
  bottom_left, bottom, bottom_right or {x, y}, the top left
  cell, counted from 1.
margin: cells from the edge for named positions (2).
background: true = black, default is see-through.
grid: {width, height}, default {256, 96} for 16:9.
  false = keep it. Changing the grid clears the whole HUD.

On the fly, shown by the next ui.draw:
hud.setScale(2.3)
hud.setPosition("center")
hud.setPosition(100, 50)
hud.clear()]] },

    { "addon", "CC Optical Filters addon", [[
The addon is found by itself (getScanStats on the sensor).

With it radar.scan filters inside the sensor, so filtered
entities do not use up the limit of 72 targets per scan.

info.addon: addon found.
info.filter: "server", "local" or nil.
info.matched, info.maxTargets, info.truncated: truncated =
  true means only the nearest maxTargets of matched came
  back.

The filter lives in the sensor block and is shared by all
programs using it. Two programs with different filters
slow each other down; radar.config.serverFilter = false
filters in the library instead.]] },

    { "config", "settings", [[
radar.config: decimals, velocityDecimals, scans,
  velocityWindow, maxGapTicks, gpsTimeout, structureCheck,
  serverFilter.
  More scans = better position, more server load.
  Shorter velocityWindow = faster but noisier velocity.

ui.config: textScale, minWidth, minHeight, infoWidth,
  touchRadius, velocitySeconds, hudSize, hudGrid,
  hudMargin, colors.]] },
}

local args = { ... }
local name = args[1]

local function list()
    print("radarhelp <topic>")
    for _, topic in ipairs(TOPICS) do
        print(("  %-9s %s"):format(topic[1], topic[2]))
    end
    print("Examples: radar_example, radar_ui_example, radar_hud_example")
end

if not name then
    list()
    return
end

for _, topic in ipairs(TOPICS) do
    if topic[1] == name:lower() then
        textutils.pagedPrint(topic[3])
        return
    end
end
printError(("No topic '%s'"):format(name))
list()
