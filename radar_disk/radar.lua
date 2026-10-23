--[[
radar - helper library for CC Optical (ccoptical) entity sensors.

    local radar = require("radar")
    local sensor = peripheral.find("entity_radar")
    local targets, info = radar.scan(sensor, { "sublevel", "object_large" }, true)

Every call to radar.scan runs several sensor scans at once (they land in the
same game tick, each with its own random noise), puts every sample on the
sphere of the exact distance the sensor reports and averages them. The
position therefore has no lag. Velocity is a least-squares fit over the
positions of the last config.velocityWindow ticks.
]]

local radar = { version = "1.5.0" }

radar.config = {
    decimals = 2,         -- rounding of x/y/z and distance (2 = 0.01 block)
    velocityDecimals = 3, -- rounding of velocity and speed (blocks per tick)
    scans = 4,            -- sensor scans averaged per radar.scan call (1 = no averaging)
    velocityWindow = 20,  -- ticks of position history used for velocity
    maxGapTicks = 60,     -- forget a target that was not seen for this many ticks
    gpsTimeout = 2,       -- seconds to wait for gps.locate
    structureCheck = 2,   -- seconds between checks whether the computer is on a structure
}

-- Per-sensor state, keyed by peripheral name.
local sensors = {}

-- Position of this computer, shared by all sensors:
-- host.ground = world block; host.structure = { uuid, block } in structure coordinates.
local host = {}

local function round(value, decimals)
    local m = 10 ^ decimals
    local r = math.floor(value * m + 0.5) / m
    if r == 0 then return 0 end -- avoid -0
    return r
end

local function getState(name)
    local state = sensors[name]
    if not state then
        state = { offset = { 0, 0, 0 }, tracks = { [false] = {}, [true] = {} } }
        sensors[name] = state
    end
    return state
end

-- Accepts a wrapped peripheral or a peripheral name. Errors point at the caller
-- of the public function.
local function resolveSensor(sensor)
    if type(sensor) == "string" then
        local wrapped = peripheral.wrap(sensor)
        if not wrapped then
            error(("radar: no peripheral named '%s'"):format(sensor), 3)
        end
        sensor = wrapped
    end
    local ok, name = pcall(peripheral.getName, sensor)
    if type(sensor) ~= "table" or not ok or not peripheral.hasType(sensor, "entity_sensor") then
        error("radar: bad argument #1 (entity_sensor peripheral expected)", 3)
    end
    return sensor, name
end

-- nil or {} = no filter, otherwise a set of lowercase type names.
local function makeFilter(filter)
    if filter == nil then return nil end
    if type(filter) == "string" then return { [filter:lower()] = true } end
    if type(filter) ~= "table" then
        error("radar: bad argument #2 (string, table or nil expected, got " .. type(filter) .. ")", 3)
    end
    local set = {}
    for i, v in ipairs(filter) do
        if type(v) ~= "string" then
            error(("radar: bad argument #2 (filter[%d] is %s, string expected)"):format(i, type(v)), 3)
        end
        set[v:lower()] = true
    end
    if next(set) == nil then return nil end
    return set
end

local function checkNumbers(fn, x, y, z)
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        error(("radar.%s: x, y, z must be numbers"):format(fn), 3)
    end
end

-- GPS returns the lower corner of the block the wireless modem is attached to,
-- i.e. the computer block. On a Sable structure the point is already in world
-- space (Sable patches wireless distances).
local function locate()
    local x, y, z = gps.locate(radar.config.gpsTimeout)
    if not x then
        error("radar: GPS unavailable - set up GPS hosts or use radar.setOrigin", 0)
    end
    return { x, y, z }
end

-- CC: Sable calls run on the server thread and cost a game tick each, so
-- whether the computer is on a structure (and which one) is cached for
-- config.structureCheck seconds.
local structureCache = { time = -math.huge }

local function onStructure()
    if os.clock() - structureCache.time < radar.config.structureCheck then
        return structureCache.value
    end
    local value = type(sublevel) == "table" and type(sublevel.isInPlotGrid) == "function"
        and sublevel.isInPlotGrid() or false
    structureCache.value = value
    structureCache.uuid = value and sublevel.getUniqueId() or nil
    structureCache.time = os.clock()
    return value
end

-- Reads the structure pose. CC: Sable wraps orientation into a quaternion
-- object ({ v, a }); the raw table has x/y/z/w, so accept both.
local function readPose()
    local p = sublevel.getLogicalPose()
    local q = p.orientation
    local qx, qy, qz, qw
    if q.v then
        qx, qy, qz, qw = q.v.x, q.v.y, q.v.z, q.a
    else
        qx, qy, qz, qw = q.x, q.y, q.z, q.w
    end
    return {
        position = { p.position.x, p.position.y, p.position.z },
        q = { qx, qy, qz, qw },
        scale = { p.scale.x, p.scale.y, p.scale.z },
        pivot = { p.rotationPoint.x, p.rotationPoint.y, p.rotationPoint.z },
    }
end

local function rotate(q, v, inverse)
    local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
    if inverse then qx, qy, qz = -qx, -qy, -qz end
    local x, y, z = v[1], v[2], v[3]
    local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
    return {
        x + qw * tx + (qy * tz - qz * ty),
        y + qw * ty + (qz * tx - qx * tz),
        z + qw * tz + (qx * ty - qy * tx),
    }
end

-- Same maths as Sable's Pose3d.transformPosition / transformPositionInverse.
local function toWorld(pose, p)
    local s, c = pose.scale, pose.pivot
    local r = rotate(pose.q, { (p[1] - c[1]) * s[1], (p[2] - c[2]) * s[2], (p[3] - c[3]) * s[3] })
    return { r[1] + pose.position[1], r[2] + pose.position[2], r[3] + pose.position[3] }
end

local function toStructure(pose, g)
    local o = pose.position
    local r = rotate(pose.q, { g[1] - o[1], g[2] - o[2], g[3] - o[3] }, true)
    local s, c = pose.scale, pose.pivot
    return { r[1] / s[1] + c[1], r[2] / s[2] + c[2], r[3] / s[3] + c[3] }
end

local function nearest(v) return math.floor(v + 0.5) end

-- Finds the computer block in structure coordinates. The structure keeps moving
-- while GPS waits for replies, so the result is accepted only if poses read
-- before and after GPS agree and the point lands on a block corner.
local function calibrateStructure()
    local uuid = sublevel.getUniqueId()
    for _ = 1, 3 do
        local before = readPose()
        local g = locate()
        local after = readPose()
        local a, b = toStructure(before, g), toStructure(after, g)
        local block, ok = {}, true
        for i = 1, 3 do
            local mid = (a[i] + b[i]) / 2
            block[i] = nearest(mid)
            if math.abs(a[i] - b[i]) > 0.3 or math.abs(mid - block[i]) > 0.3 then ok = false end
        end
        if ok then
            host.structure = { uuid = uuid, block = block }
            return
        end
    end
    error("radar: structure calibration failed - slow the structure down and call radar.calibrate()", 0)
end

local function calibrateGround()
    local g = locate()
    host.ground = { nearest(g[1]), nearest(g[2]), nearest(g[3]) }
end

-- Makes sure the computer position is known (GPS calibration when needed).
local function ensureHost(state)
    if onStructure() then
        if state.origin then
            error("radar: setOrigin is for ground sensors, on a structure use radar.setOffset", 0)
        end
        if not host.structure or host.structure.uuid ~= structureCache.uuid then
            calibrateStructure()
        end
    elseif not state.origin and not host.ground then
        calibrateGround()
    end
end

-- World position of the sensor block centre (the point ccoptical measures from).
-- state.offset = sensor block - computer block, in structure axes on a structure.
-- pose: structure pose read together with the scans (nil = read now).
local function sensorOrigin(state, pose)
    ensureHost(state)
    local d = state.offset
    if onStructure() then
        local b = host.structure.block
        return toWorld(pose or readPose(), { b[1] + d[1] + 0.5, b[2] + d[2] + 0.5, b[3] + d[3] + 0.5 }), "structure"
    end
    if state.origin then return state.origin, "manual" end
    local b = host.ground
    return { b[1] + d[1] + 0.5, b[2] + d[2] + 0.5, b[3] + d[3] + 0.5 }, "ground"
end

-- Runs config.scans sensor scans and (on a structure) a pose read as parallel
-- coroutines. Each call is a server-thread task; queued together they are
-- executed in the same game tick, so the samples differ only by noise.
local function multiScan(sensor, count, wantPose)
    local raws, pose, failure = {}, nil, nil
    local jobs = {}
    for i = 1, count do
        jobs[i] = function()
            local ok, raw = pcall(sensor.scan)
            if ok then raws[#raws + 1] = raw else failure = raw end
        end
    end
    if wantPose then
        jobs[#jobs + 1] = function()
            local ok, p = pcall(readPose)
            if ok then pose = p end
        end
    end
    if #jobs == 1 then jobs[1]() else parallel.waitForAll(table.unpack(jobs)) end
    if #raws == 0 then error("radar: scan failed: " .. tostring(failure), 0) end
    return raws, pose
end

-- Track = position history of one target: { {tick, x, y, z, weight}, ... }.
-- Velocity is the weighted least-squares slope over the last velocityWindow
-- ticks. Exact (optical) sensors use the last two points.
local function trackVelocity(points, exact)
    local n = #points
    if n < 2 then return { 0, 0, 0 } end
    if exact then
        local a, b = points[n - 1], points[n]
        local dt = b[1] - a[1]
        return { (b[2] - a[2]) / dt, (b[3] - a[3]) / dt, (b[4] - a[4]) / dt }
    end
    local sw, st = 0, 0
    for _, p in ipairs(points) do sw, st = sw + p[5], st + p[5] * p[1] end
    local tm = st / sw
    local stt, v = 0, { 0, 0, 0 }
    for _, p in ipairs(points) do
        local dt = p[1] - tm
        stt = stt + p[5] * dt * dt
        for i = 1, 3 do v[i] = v[i] + p[5] * dt * p[i + 1] end
    end
    if stt <= 0 then return { 0, 0, 0 } end
    return { v[1] / stt, v[2] / stt, v[3] / stt }
end

local function updateTrack(tracks, id, point, exact)
    local cfg = radar.config
    local track = tracks[id]
    if track and point[1] - track.tick > cfg.maxGapTicks then track = nil end
    if not track then
        track = { points = {}, first = point[1] }
        tracks[id] = track
    end
    local points = track.points
    if points[#points] and points[#points][1] == point[1] then
        points[#points] = point -- same tick again: keep the newer batch
    else
        points[#points + 1] = point
    end
    while #points > 2 and point[1] - points[1][1] > cfg.velocityWindow do
        table.remove(points, 1)
    end
    track.tick = point[1]
    track.velocity = trackVelocity(points, exact)
    return track
end

--- Scan with a sensor.
-- @param sensor  wrapped entity_sensor peripheral or its name
-- @param filter  type name, list of type names, or nil for all targets
-- @param global  true = world coordinates, false/nil = offset from the sensor
-- @return list of targets, info table
function radar.scan(sensor, filter, global)
    local name
    sensor, name = resolveSensor(sensor)
    local types = makeFilter(filter)
    if global ~= nil and type(global) ~= "boolean" then
        error("radar: bad argument #3 (boolean or nil expected, got " .. type(global) .. ")", 2)
    end
    global = global == true

    local state = getState(name)
    if state.exact == nil then state.exact = sensor.isOptical() end

    local cfg = radar.config
    local count = state.exact and 1 or math.max(1, math.floor(cfg.scans))
    if global then ensureHost(state) end -- GPS calibration before the timed scans
    local structure = onStructure()
    local raws, pose = multiScan(sensor, count, structure)

    local origin, mode
    if global then origin, mode = sensorOrigin(state, pose) end
    local orientation
    if pose then
        local q = pose.q
        orientation = { x = q[1], y = q[2], z = q[3], w = q[4] }
    end

    -- Group the samples of all scans by target.
    local groups, order, tick = {}, {}, -math.huge
    for _, raw in ipairs(raws) do
        local t = raw.lastScanTick
        if t > tick then tick = t end
        for _, d in ipairs(raw.detections) do
            local g = groups[d.id]
            if not g then
                g = { samples = {}, meta = d, tick = t }
                groups[d.id] = g
                order[#order + 1] = d.id
            elseif t >= g.tick then
                g.meta, g.tick = d, t
            end
            g.samples[#g.samples + 1] = { t, d.x, d.y, d.z }
        end
    end

    local tracks = state.tracks[global]
    local targets = {}
    for _, id in ipairs(order) do
        local g = groups[id]
        local d = g.meta
        -- Average the samples. Scans that landed in an earlier tick (server
        -- busy) are moved forward with the previous velocity estimate.
        local old = tracks[id]
        local v0 = old and old.velocity or { 0, 0, 0 }
        local p = { 0, 0, 0 }
        for _, s in ipairs(g.samples) do
            local dt = g.tick - s[1]
            for i = 1, 3 do p[i] = p[i] + s[i + 1] + v0[i] * dt end
        end
        local n = #g.samples
        for i = 1, 3 do
            p[i] = p[i] / n
            if origin then p[i] = p[i] + origin[i] end
        end
        -- Every target updates its track, so changing the filter between calls
        -- does not break velocity estimation.
        local track = updateTrack(tracks, id, { g.tick, p[1], p[2], p[3], n }, state.exact)

        if not types or types[string.lower(d.type)] then
            local target = {}
            for k, v in pairs(d) do target[k] = v end
            -- One identifier: for a structure ccoptical repeats its UUID in id and
            -- subLevelUUID. subLevelUUID stays only for an entity aboard a structure.
            target.uuid, target.id = d.id, nil
            if target.subLevelUUID == d.id then target.subLevelUUID = nil end
            target.x = round(p[1], cfg.decimals)
            target.y = round(p[2], cfg.decimals)
            target.z = round(p[3], cfg.decimals)
            target.distance = round(d.distance, cfg.decimals)
            local vx, vy, vz = track.velocity[1], track.velocity[2], track.velocity[3]
            target.velocity = {
                x = round(vx, cfg.velocityDecimals),
                y = round(vy, cfg.velocityDecimals),
                z = round(vz, cfg.velocityDecimals),
            }
            target.speed = round(math.sqrt(vx * vx + vy * vy + vz * vz), cfg.velocityDecimals)
            target.samples = n
            target.tracked = g.tick - track.first
            targets[#targets + 1] = target
        end
    end

    for id, t in pairs(tracks) do
        if tick - t.tick > cfg.maxGapTicks then tracks[id] = nil end
    end

    return targets, {
        sensor = name,
        tick = tick,
        total = #order,
        scans = #raws,
        global = global,
        mode = mode,
        origin = origin and { x = origin[1], y = origin[2], z = origin[3] } or nil,
        range = sensor.getRange and sensor.getRange() or nil,
        orientation = orientation,
    }
end

--- World position of the sensor block centre and how it was found:
-- "manual" (setOrigin), "ground" (GPS) or "structure" (GPS calibration + pose).
function radar.getOrigin(sensor)
    local _, name = resolveSensor(sensor)
    local origin, mode = sensorOrigin(getState(name))
    return { x = origin[1], y = origin[2], z = origin[3] }, mode
end

--- Fix the position of a sensor on the ground (block coordinates as shown by
-- F3). nil clears it, after which GPS and the offset are used.
function radar.setOrigin(sensor, x, y, z)
    local _, name = resolveSensor(sensor)
    local state = getState(name)
    if x == nil then
        state.origin = nil
    else
        checkNumbers("setOrigin", x, y, z)
        state.origin = { x + 0.5, y + 0.5, z + 0.5 }
    end
    state.tracks[true] = {}
end

--- Sensor position relative to the computer: sensor block - computer block,
-- in blocks. On the ground the axes are world axes; on a Sable structure they
-- are the structure's own block grid, so the offset stays valid however the
-- structure moves or rotates.
function radar.setOffset(sensor, dx, dy, dz)
    local _, name = resolveSensor(sensor)
    checkNumbers("setOffset", dx, dy, dz)
    local state = getState(name)
    state.offset = { dx, dy, dz }
    state.tracks[true] = {}
end

--- Re-measure the computer position with GPS (after moving the computer, or
-- if calibration on a structure failed). Shared by all sensors.
function radar.calibrate()
    host.ground, host.structure = nil, nil
    structureCache.time = -math.huge
    if onStructure() then calibrateStructure() else calibrateGround() end
    for _, state in pairs(sensors) do state.tracks[true] = {} end
end

--- Set the computer block position by hand (ground only, replaces GPS).
-- nil returns to GPS.
function radar.setHost(x, y, z)
    if x == nil then
        host.ground = nil
        return
    end
    checkNumbers("setHost", x, y, z)
    host.ground = { x, y, z }
end

--- World position of the centre of the block at (dx, dy, dz) from the computer
-- block (structure axes on a Sable structure, world axes on the ground).
-- Returns {x, y, z}, the structure orientation {x, y, z, w} (nil on the
-- ground) and the mode ("structure" or "ground").
function radar.blockToWorld(dx, dy, dz)
    checkNumbers("blockToWorld", dx, dy, dz)
    if onStructure() then
        if not host.structure or host.structure.uuid ~= structureCache.uuid then
            calibrateStructure()
        end
        local b = host.structure.block
        local pose = readPose()
        local p = toWorld(pose, { b[1] + dx + 0.5, b[2] + dy + 0.5, b[3] + dz + 0.5 })
        local q = pose.q
        return { x = p[1], y = p[2], z = p[3] }, { x = q[1], y = q[2], z = q[3], w = q[4] }, "structure"
    end
    if not host.ground then calibrateGround() end
    local b = host.ground
    return { x = b[1] + dx + 0.5, y = b[2] + dy + 0.5, z = b[3] + dz + 0.5 }, nil, "ground"
end

--- Drop all tracked targets of a sensor (velocity starts from scratch).
function radar.reset(sensor)
    local _, name = resolveSensor(sensor)
    local state = getState(name)
    state.tracks = { [false] = {}, [true] = {} }
end

return radar
