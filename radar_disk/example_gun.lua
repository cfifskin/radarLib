-- Example: aim a big cannon at the nearest structure seen by the radar.
package.path = "/lib/?.lua;" .. package.path -- works even if the startup loader is missing or old
local radar = require("radar")
local ballistics = require("ballistics")

local sensor = peripheral.find("entity_radar") or error("No entity_radar attached", 0)
local mount = peripheral.find("cannon_mount") or peripheral.find("cbc_cannon_mount")
    or error("No cannon mount attached (CC:CBC or CBC Peripheral)", 0)

-- Positions relative to this computer: block - computer block, counted along
-- the structure's own blocks when the computer is on a Sable structure.
radar.setOffset(sensor, 0, 1, 0)
local CANNON_OFFSET = { 2, 0, -3 } -- cannon mount block; another script may change it

local gun = ballistics.bigCannon({
    offset = CANNON_OFFSET,
    length = 8,                                -- cannon blocks in front of the breech
    muzzle = 5,                                -- block above the mount -> muzzle block
    charges = { "powder", "powder", "mk3" },   -- from the breech forward
    shell = "he_shell",
})
-- gun = ballistics.autocannon({ offset = CANNON_OFFSET, material = "steel", barrels = 4, muzzle = 3, round = "ap" })
-- gun = ballistics.heavyAutocannon({ offset = CANNON_OFFSET, material = "steel", barrels = 6, muzzle = 5, round = "apds", strong = true })
print(("muzzle speed %.2f blocks/tick"):format(gun.speed))

while true do
    local ok, targets = pcall(radar.scan, sensor, "sublevel", true)
    if not ok then
        printError(targets)
    elseif #targets > 0 then
        table.sort(targets, function(a, b) return a.distance < b.distance end)
        local solution = gun:aim(targets[1], { arc = "auto" })
        if solution.ok then
            ballistics.point(mount, solution)
            print(("yaw %.2f pitch %.2f  flight %.1f ticks"):format(solution.yaw, solution.pitch, solution.ticks))
        else
            print("no solution: " .. solution.reason)
        end
    end
    sleep(0.25)
end
