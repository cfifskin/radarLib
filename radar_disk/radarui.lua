--[[
radarui - radar screen for monitors, terminals and windows.

    local radar = require("radar")
    local ui = require("radarui")
    local sensor = peripheral.find("entity_radar")
    local monitor = peripheral.find("monitor")

    while true do
        local targets, info = radar.scan(sensor, nil, true)
        ui.draw(monitor, targets, info, "-z", true, true)
        sleep(0.25)
    end

The left part is a top-down view: the centre is the sensor, the circle is the
scan range, the top of the screen is the chosen front axis (of the structure
when the computer is on a Sable structure). The right part shows the selected
target. Select a target with ui.select(device, uuid) or, on an advanced monitor,
by touching it (needs ui.listen() running, see the README).
]]

local ui = { version = "1.0.0" }

ui.config = {
    textScale = nil,     -- fixed monitor text scale; nil = pick by monitor size
    minWidth = 50,       -- auto scale picks the largest scale that still gives
    minHeight = 20,      -- at least this many columns and rows
    infoWidth = 18,      -- minimum width of the info panel, in characters
    touchRadius = 4,     -- touch tolerance in radar pixels (a character is 2x3)
    velocitySeconds = 1, -- length of the selected target's velocity line
    colors = {
        background = colors.black,
        ring = colors.green,
        grid = colors.gray,
        center = colors.white,
        front = colors.lime,
        selected = colors.white,
        velocity = colors.cyan,
        title = colors.lime,
        label = colors.lightGray,
        text = colors.white,
        warning = colors.red,
        player = colors.lightBlue, -- targets with a name
        default = colors.white,    -- types missing below
        types = {
            sublevel = colors.orange,
            object_large = colors.red,
            object_mid = colors.yellow,
            object_small = colors.lime,
        },
    },
}

-- Front axes in structure (or world) coordinates.
local FRONT = {
    x = { 1, 0, 0 }, ["+x"] = { 1, 0, 0 }, ["-x"] = { -1, 0, 0 },
    z = { 0, 0, 1 }, ["+z"] = { 0, 0, 1 }, ["-z"] = { 0, 0, -1 },
}

local HEX = {}
for i = 0, 15 do HEX[i] = ("0123456789abcdef"):sub(i + 1, i + 1) end

-- Colour bitmask (colors.red) -> palette index 0..15.
local function index(color)
    local i = 0
    while color > 1 do color, i = color / 2, i + 1 end
    return i
end

-- Per-device state, keyed by peripheral name (monitors) or by the object.
local states = {}

local function resolve(device)
    if type(device) == "string" then
        local wrapped = peripheral.wrap(device)
        if not wrapped then
            error(("radarui: no peripheral named '%s'"):format(device), 3)
        end
        device = wrapped
    end
    if type(device) ~= "table" or type(device.getSize) ~= "function" or type(device.blit) ~= "function" then
        error("radarui: bad argument #1 (monitor, terminal or window expected)", 3)
    end
    local ok, name = pcall(peripheral.getName, device)
    if not ok then name = nil end
    local key = name or device
    local state = states[key]
    if not state then
        state = { name = name }
        states[key] = state
    end
    state.device = device
    return state
end

-- Largest text scale that keeps at least minWidth x minHeight characters, so
-- the picture looks the same on a 3x2 monitor and on a 6x4 one.
local function chooseScale(device)
    if type(device.setTextScale) ~= "function" then return end
    local cfg = ui.config
    if cfg.textScale then
        device.setTextScale(cfg.textScale)
        return
    end
    for s = 5, 0.5, -0.5 do
        device.setTextScale(s)
        local w, h = device.getSize()
        if w >= cfg.minWidth and h >= cfg.minHeight then return end
    end
end

local function setPixel(pix, L, x, y, color)
    if x >= 0 and y >= 0 and x < L.ZW and y < L.PH then pix[y * L.ZW + x + 1] = color end
end

local function inCircle(L, x, y, margin)
    local dx, dy, r = x + 0.5 - L.cx, y + 0.5 - L.cy, L.R - margin
    return dx * dx + dy * dy <= r * r
end

-- The radar is drawn on a pixel canvas with teletext characters: every
-- character holds 2x3 square pixels. The canvas covers the radar zone only.
local function buildLayout(state, showInfo)
    local device = state.device
    if not state.scaled then
        chooseScale(device)
        state.scaled = true
    end
    local w, h = device.getSize()
    local key = ("%dx%d%s"):format(w, h, showInfo and "i" or "")
    if state.layout and state.layout.key == key then return state.layout end
    if state.layout and type(device.setTextScale) == "function" then
        chooseScale(device) -- the monitor was resized
        w, h = device.getSize()
        key = ("%dx%d%s"):format(w, h, showInfo and "i" or "")
    end

    local L = { key = key, W = w, H = h, PH = h * 3 }
    local rw = w
    if showInfo then
        rw = math.min(math.ceil(h * 3 / 2), w - ui.config.infoWidth - 1)
        if rw < 4 then rw, showInfo = w, false end -- no room for the panel
    end
    L.RW, L.ZW, L.info = rw, rw * 2, showInfo
    if showInfo then L.infoW = w - rw - 1 end
    L.cx = math.floor((L.ZW - 1) / 2) + 0.5
    L.cy = math.floor((L.PH - 1) / 2) + 0.5
    L.R = math.min(L.cx, L.cy, L.ZW - L.cx, L.PH - L.cy)

    -- Static background: range circle, half-range ring, cross, front mark.
    local c = ui.config.colors
    local bg, ring, grid = index(c.background), index(c.ring), index(c.grid)
    local pix, R = {}, L.R
    for py = 0, L.PH - 1 do
        local dy = py + 0.5 - L.cy
        for px = 0, L.ZW - 1 do
            local dx = px + 0.5 - L.cx
            local d = math.sqrt(dx * dx + dy * dy)
            local col = bg
            if d <= R then
                if d > R - 1 then
                    col = ring
                elseif math.abs(d - R / 2) <= 0.5 or dx == 0 or dy == 0 then
                    col = grid
                end
            end
            pix[py * L.ZW + px + 1] = col
        end
    end
    local top = math.floor(L.cy - R)
    for py = top, top + 2 do setPixel(pix, L, math.floor(L.cx), py, index(c.front)) end
    setPixel(pix, L, math.floor(L.cx), math.floor(L.cy), index(c.center))
    L.base = pix

    state.layout = L
    return L
end

-- Quaternion rotation (same as in radar.lua).
local function rotate(q, v)
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w
    local x, y, z = v[1], v[2], v[3]
    local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
    return {
        x + qw * tx + (qy * tz - qz * ty),
        y + qw * ty + (qz * tx - qx * tz),
        z + qw * tz + (qx * ty - qy * tx),
    }
end

-- Structure orientation: from radar.scan's info, or straight from CC: Sable.
local function orientation(info)
    if type(info.orientation) == "table" then return info.orientation end
    if type(sublevel) == "table" and type(sublevel.isInPlotGrid) == "function" and sublevel.isInPlotGrid() then
        local q = sublevel.getLogicalPose().orientation
        if q.v then return { x = q.v.x, y = q.v.y, z = q.v.z, w = q.a } end
        return { x = q.x, y = q.y, z = q.z, w = q.w }
    end
end

-- World-space horizontal direction of the front axis, normalised.
local function heading(state, front, info)
    local f = FRONT[front]
    local q = orientation(info)
    if q then f = rotate(q, f) end
    local len = math.sqrt(f[1] * f[1] + f[3] * f[3])
    if len < 0.1 then -- front axis points up or down: keep the last heading
        return state.heading or { FRONT[front][1], FRONT[front][3] }
    end
    state.heading = { f[1] / len, f[3] / len }
    return state.heading
end

local function targetColor(t)
    local c = ui.config.colors
    if t.name then return c.player end
    return c.types[t.type] or c.default
end

local function findTarget(targets, uuid)
    if not uuid then return nil end
    for _, t in ipairs(targets) do
        if t.uuid == uuid then return t end
    end
end

-- Builds the info panel lines: { text, color }.
local function panelLines(state, L, targets, info, front, range, selected)
    local c = ui.config.colors
    local width = L.infoW
    local lines = {}
    local function add(text, color) lines[#lines + 1] = { text = text, color = color or c.text } end
    local function wrap(text, color)
        for i = 1, #text, width do add(text:sub(i, i + width - 1), color) end
    end

    add("RADAR", c.title)
    add(("Range %.0f"):format(range), c.label)
    add(("Targets %d"):format(#targets), c.label)
    add(("Up %s%s"):format(front:sub(1, 1) == "-" and "" or "+", front:upper()), c.label)
    add(("-"):rep(width), c.grid)

    if not state.selected then
        add("No target", c.label)
        if state.touch then add("Tap a target", c.label) end
        return lines
    end

    local t = selected
    add(t and "TARGET" or "TARGET LOST", t and c.title or c.warning)
    add("UUID", c.label)
    wrap(state.selected)
    if not t then return lines end

    add("Name", c.label)
    add(t.name or t.subLevelName or "-", targetColor(t))
    add("Type " .. tostring(t.type))
    add(info.global and "Position" or "Offset", c.label)
    add(("X %.2f"):format(t.x))
    add(("Y %.2f"):format(t.y))
    add(("Z %.2f"):format(t.z))
    add(("Dist %.2f"):format(t.distance))
    add("Speed", c.label)
    add(("%.3f b/t"):format(t.speed or 0))
    add(("%.2f b/s"):format((t.speed or 0) * 20))
    return lines
end

-- Converts the canvas to teletext characters and blits every row together
-- with the info panel. Each character can show only two colours, so a cell
-- keeps its most common colour and its most important other colour.
local function render(state, L, pix, prio, lines)
    local device = state.device
    local ZW = L.ZW
    local bg = HEX[index(ui.config.colors.background)]
    local cell, count = {}, {}
    for row = 0, L.H - 1 do
        local text, fg, bk = {}, {}, {}
        for col = 0, L.RW - 1 do
            local i = row * 3 * ZW + col * 2 + 1
            cell[1], cell[2] = pix[i], pix[i + 1]
            cell[3], cell[4] = pix[i + ZW], pix[i + ZW + 1]
            cell[5], cell[6] = pix[i + 2 * ZW], pix[i + 2 * ZW + 1]

            for k = 1, 6 do count[cell[k]] = (count[cell[k]] or 0) + 1 end
            local a, an = cell[6], 0
            for k = 1, 6 do
                if count[cell[k]] > an then a, an = cell[k], count[cell[k]] end
            end
            local b, bp = nil, -1
            for k = 1, 6 do
                local p = cell[k]
                if p ~= a and prio[p] > bp then b, bp = p, prio[p] end
            end
            for k = 1, 6 do count[cell[k]] = nil end

            -- The bottom-right pixel is always the background of the character.
            local code, back, fore = 128, a, a
            if b then
                back = cell[6] == b and b or a
                fore = back == a and b or a
                local bit = 1
                for k = 1, 5 do
                    local p = cell[k] == b and b or a
                    if p ~= back then code = code + bit end
                    bit = bit * 2
                end
            end
            text[#text + 1] = string.char(code)
            fg[#fg + 1] = HEX[fore]
            bk[#bk + 1] = HEX[back]
        end

        if L.info then
            local line = lines[row + 1]
            local s = line and line.text:gsub("[^\32-\126]", "?") or ""
            s = s:sub(1, L.infoW)
            local pad = L.infoW - #s
            text[#text + 1] = " " .. s .. (" "):rep(pad)
            local f = HEX[index(line and line.color or ui.config.colors.text)]
            fg[#fg + 1] = f:rep(L.infoW + 1)
            bk[#bk + 1] = bg:rep(L.infoW + 1)
        end

        device.setCursorPos(1, row + 1)
        device.blit(table.concat(text), table.concat(fg), table.concat(bk))
    end
end

local function drawLine(pix, L, x0, y0, x1, y1, color)
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
    local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
        if inCircle(L, x0, y0, 1) then setPixel(pix, L, x0, y0, color) end
        if x0 == x1 and y0 == y1 then break end
        local e2 = 2 * err
        if e2 >= dy then err, x0 = err + dy, x0 + sx end
        if e2 <= dx then err, y0 = err + dx, y0 + sy end
    end
end

local function paint(state)
    local last = state.last
    local targets, info, front = last.targets, last.info, last.front
    local L = buildLayout(state, last.showInfo)
    local c = ui.config.colors

    -- Drawing priority of colours inside one character.
    local prio = {}
    for i = 0, 15 do prio[i] = 0 end
    local function rank(color, p) local i = index(color) if p > prio[i] then prio[i] = p end end
    rank(c.grid, 1) rank(c.ring, 2) rank(c.front, 3) rank(c.center, 3) rank(c.velocity, 4)
    rank(c.player, 5) rank(c.default, 5)
    for _, col in pairs(c.types) do rank(col, 5) end
    rank(c.selected, 6)

    local pix = {}
    for i = 1, #L.base do pix[i] = L.base[i] end

    local range = tonumber(info.range)
    if not range or range <= 0 then
        range = 1
        for _, t in ipairs(targets) do range = math.max(range, t.distance or 0) end
    end
    local h = heading(state, front, info)
    local fx, fz = h[1], h[2]
    local k = L.R / range
    local ox, oz = 0, 0
    if info.global then
        if not info.origin then error("radarui: info.origin is missing for global coordinates", 3) end
        ox, oz = info.origin.x, info.origin.z
    end

    -- World vector (dx, dz) -> canvas point. Up = front, right = front turned
    -- 90 degrees clockwise when looking down.
    local function project(dx, dz)
        local up = dx * fx + dz * fz
        local right = -dx * fz + dz * fx
        return L.cx + right * k, L.cy - up * k
    end

    local markers, selected = {}, findTarget(targets, state.selected)
    local function marker(t)
        local px, py = project(t.x - ox, t.z - oz)
        local ddx, ddy = px - L.cx, py - L.cy
        local d, max = math.sqrt(ddx * ddx + ddy * ddy), L.R - 1.5
        if d > max then px, py = L.cx + ddx * max / d, L.cy + ddy * max / d end
        local x0, y0 = math.floor(px - 0.5), math.floor(py - 0.5)
        local col = index(targetColor(t))
        for yy = y0, y0 + 1 do
            for xx = x0, x0 + 1 do setPixel(pix, L, xx, yy, col) end
        end
        markers[#markers + 1] = { uuid = t.uuid, x = px, y = py }
        return x0, y0, px, py
    end

    for _, t in ipairs(targets) do
        if t ~= selected then marker(t) end
    end
    if selected then
        local v = selected.velocity
        if v and selected.speed and selected.speed > 0 then
            local ticks = 20 * ui.config.velocitySeconds
            local x0, y0 = project(selected.x - ox, selected.z - oz)
            local x1, y1 = project(selected.x - ox + v.x * ticks, selected.z - oz + v.z * ticks)
            drawLine(pix, L, x0, y0, x1, y1, index(c.velocity))
        end
        local x0, y0 = marker(selected)
        local col = index(c.selected)
        for i = -2, 3 do
            setPixel(pix, L, x0 + i, y0 - 2, col)
            setPixel(pix, L, x0 + i, y0 + 3, col)
            setPixel(pix, L, x0 - 2, y0 + i, col)
            setPixel(pix, L, x0 + 3, y0 + i, col)
        end
    end
    state.markers = markers

    local lines = L.info and panelLines(state, L, targets, info, front, range, selected) or nil
    render(state, L, pix, prio, lines)
    return selected
end

--- Draw the radar screen.
-- @param device    monitor (wrapped or its name), term.current() or a window
-- @param targets   targets from radar.scan
-- @param info      info from radar.scan
-- @param front     axis shown at the top: "x", "-x", "z" or "-z"; on a Sable
--                  structure these are the structure's own axes
-- @param showInfo  true = info panel on the right
-- @param touch     true = touching a target on an advanced monitor selects it
-- @return the selected target from targets, or nil
function ui.draw(device, targets, info, front, showInfo, touch)
    local state = resolve(device)
    if type(targets) ~= "table" then
        error("radarui: bad argument #2 (targets table expected, got " .. type(targets) .. ")", 2)
    end
    if type(info) ~= "table" then
        error("radarui: bad argument #3 (info table expected, got " .. type(info) .. ")", 2)
    end
    front = type(front) == "string" and front:lower() or nil
    if not FRONT[front] then
        error('radarui: bad argument #4 (front must be "x", "-x", "z" or "-z")', 2)
    end
    if front == "+x" then front = "x" elseif front == "+z" then front = "z" end
    state.last = { targets = targets, info = info, front = front, showInfo = showInfo == true }
    state.touch = touch == true
    return paint(state)
end

--- Select a target by uuid (or pass a target table). nil clears the selection.
-- The selection survives between draws; a target that left the radar is shown
-- as "TARGET LOST" until another one is selected.
function ui.select(device, target)
    local state = resolve(device)
    if type(target) == "table" then target = target.uuid end
    if target ~= nil and type(target) ~= "string" then
        error("radarui: bad argument #2 (uuid string, target table or nil expected)", 2)
    end
    state.selected = target
    if state.last then paint(state) end
end

--- Returns the selected uuid and the target table from the last draw (nil if
-- the target is not on the radar now).
function ui.getSelected(device)
    local state = resolve(device)
    return state.selected, state.last and findTarget(state.last.targets, state.selected)
end

-- Touch at character (x, y): uuid of the nearest marker, nil for empty space
-- inside the circle, false outside the radar zone.
local function hitTest(state, x, y)
    local L = state.layout
    if not L or x < 1 or y < 1 or x > L.RW or y > L.H then return false end
    local tx, ty = (x - 0.5) * 2, (y - 0.5) * 3
    local best, bestD = nil, ui.config.touchRadius
    for _, m in ipairs(state.markers or {}) do
        local d = math.sqrt((m.x - tx) ^ 2 + (m.y - ty) ^ 2)
        if d <= bestD then best, bestD = m.uuid, d end
    end
    if best then return best end
    if inCircle(L, tx, ty, 0) then return nil end
    return false
end

--- Process one event. Call it from your own event loop, or run ui.listen().
-- Handles monitor_touch (advanced monitors), mouse_click (computer screen)
-- and monitor_resize. Returns true if a selection changed.
function ui.handleEvent(event, a, b, c)
    if event == "monitor_resize" then
        for _, s in pairs(states) do
            if s.name == a and s.last then
                s.layout = nil
                chooseScale(s.device)
                paint(s)
            end
        end
        return false
    end
    if event ~= "monitor_touch" and event ~= "mouse_click" then return false end

    local changed = false
    for _, s in pairs(states) do
        local mine
        if event == "monitor_touch" then mine = s.name == a else mine = s.name == nil end
        if mine and s.touch and s.last then
            local x, y = b, c
            if event == "mouse_click" and type(s.device.getPosition) == "function" then
                local wx, wy = s.device.getPosition()
                x, y = x - wx + 1, y - wy + 1
            end
            local hit = hitTest(s, x, y)
            if hit ~= false and hit ~= s.selected then
                s.selected = hit
                paint(s)
                changed = true
            end
        end
    end
    return changed
end

--- Endless event loop for touch selection. Run it next to your radar loop:
--   parallel.waitForAny(radarLoop, ui.listen)
function ui.listen()
    while true do
        ui.handleEvent(os.pullEvent())
    end
end

return ui
