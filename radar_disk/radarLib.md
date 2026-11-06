# radarLib

Radar library for CC Optical sensors.
Scroll with up/down, jump between sections with left/right, press Q to exit.

    local radar = require("radar")
    local sensor = peripheral.find("entity_radar")
    local targets, info = radar.scan(sensor)
    print(#targets, "targets")

Examples on this computer: `radar_example`, `radar_ui_example`, `radar_hud_example`.

## Scan

    radar.scan(sensor, filter, global)

Returns `targets, info`.

* `sensor`: wrapped peripheral or its name.
* `filter`: type name, list of names or nil for all targets: "sublevel", "object_large", "minecraft:pig", "pig".
* `global`: true = world coordinates (see Position), false or nil = offset from the sensor block.

Each target has:

* `uuid`, `type`, `name`, `subLevelName`, `subLevelUUID`
* `x`, `y`, `z`, `distance`
* `velocity` as {x, y, z} in blocks per tick, `speed`
* `samples`: scans averaged
* `tracked`: ticks followed, velocity is 0 while it is 0

`info` has: `sensor`, `tick`, `total`, `scans`, `global`, `mode`, `origin`, `range`, `orientation`, `addon`, `filter`, `matched`, `maxTargets`, `truncated`.

`radar.reset(sensor)` forgets tracked targets.

## Position

`global = true` needs the world position of the sensor.

    radar.setOffset(sensor, dx, dy, dz)

Sensor block minus computer block. On a Sable structure these are the structure's own axes. Needs GPS once.

    radar.setOrigin(sensor, x, y, z)

Sensor block from F3, ground only, no GPS.

    radar.setHost(x, y, z)

Computer block by hand, ground only, no GPS.

    local pos, mode = radar.getOrigin(sensor)

Compare it with F3 to check the setup. `mode` is "ground", "structure" or "manual".

`radar.calibrate()` measures the computer again, for example after moving it. After "structure calibration failed" slow the structure down and call it.

## Screen

Radar picture on a monitor, a terminal or a window.

    local ui = require("radarui")
    local monitor = peripheral.find("monitor")
    ui.draw(monitor, targets, info, "-z",
        true, true)

Arguments: `device, targets, info, front, showInfo, touch, textScale`.

* `front`: axis at the top: "x", "-x", "z", "-z".
* `showInfo`: true = panel with the selected target.
* `touch`: true = touching a target selects it.
* `textScale`: 0.5 to 5, nil = picked by monitor size.

Returns the selected target or nil.

Touch needs `ui.listen` next to your loop:

    parallel.waitForAny(radarLoop, ui.listen)

Selecting from code:

    ui.select(monitor, target)
    local uuid, target = ui.getSelected(monitor)

## HUD glasses

Mod CC: HUD Glasses. Put a HUD Modem next to the computer, then hold the glasses and right-click the modem.

    local glasses = peripheral.find("hud_glasses")
    local hud = ui.hud(glasses, {
        scale = 2,
        position = "top_right",
    })
    ui.draw(hud, targets, info, "-z")

Options:

* `scale`: any positive number, the radar takes 40*scale by 30*scale cells: 1 = 40x30, 2 = 80x60, 0.5 = 20x15. At most 3.2 on the default grid.
* `position`: top_left, top, top_right, left, center, right, bottom_left, bottom, bottom_right, or {x, y}: the top left cell, counted from 1.
* `margin`: cells from the edge for named positions, 2 by default.
* `background`: true = black, see-through by default.
* `grid`: {width, height}, {256, 96} by default, fits 16:9. false keeps the grid as it is. Changing the grid clears the whole HUD.

Changes on the fly, shown by the next `ui.draw`:

    hud.setScale(2.3)
    hud.setPosition("center")
    hud.setPosition(100, 50)
    hud.clear()

## CC Optical Filters

The addon is found by itself. With it `radar.scan` filters inside the sensor, so other entities do not use up the limit of 72 targets per scan.

* `info.addon`: addon found.
* `info.filter`: "server", "local" or nil.
* `info.truncated`: true = only the nearest `info.maxTargets` of `info.matched` came back.

The filter lives in the sensor block and is shared by all programs. Two programs with different filters slow each other down; `radar.config.serverFilter = false` filters in the library instead.

## Settings

`radar.config`: `decimals`, `velocityDecimals`, `scans`, `velocityWindow`, `maxGapTicks`, `gpsTimeout`, `structureCheck`, `serverFilter`.

More `scans` give a better position and more server load. A shorter `velocityWindow` gives a faster but noisier velocity.

`ui.config`: `textScale`, `minWidth`, `minHeight`, `infoWidth`, `touchRadius`, `velocitySeconds`, `hudSize`, `hudGrid`, `hudMargin`, `colors`.

Full manual: github.com/cfifskin/radarLib
