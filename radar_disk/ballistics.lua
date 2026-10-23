--[[
ballistics - fire control for Create Big Cannons mounts (CBC, CBC: Enhanced
Shells, CBC: Advanced Technology).

    local radar = require("radar")
    local ballistics = require("ballistics")

    local gun = ballistics.bigCannon({
        offset = { 2, 0, -3 },          -- cannon mount block - computer block
        length = 8,                     -- cannon blocks in front of the breech
        muzzle = 5,                     -- pivot block -> muzzle block, in blocks
        charges = { "powder", "powder", "mk3" },
        shell = "he_shell",
    })
    local solution = gun:aim(target)    -- target from radar.scan(..., true)
    if solution.ok then ballistics.point(mount, solution) end

The physics is a copy of the mods' code: every tick the projectile moves by
v + a/2 and v grows by a, where a = gravity - drag * v (|v| * v for quadratic
drag). The muzzle speed, spawn point and inherited structure velocity follow
the cannon contraptions of CBC and CBC: AT.
]]

local ballistics = { version = "1.0.0" }

ballistics.config = {
    -- createbigcannons-server.toml: compat.sableProjectilesInheritPhysicsObjectVelocity
    inheritVelocity = true,
    -- cbc_at server config: bigCannons.disablePhysicRework = false means true here
    physicsRework = true,
    -- dimension munition properties: overworld 1/1, nether 1.1/1.1, end 0.8/0
    gravityMultiplier = 1,
    dragMultiplier = 1,
    maxTicks = 1200,  -- longest flight considered for big cannon shells
    latency = 0,      -- ticks between the solution and the shot (target lead)
}

-- Charge power of one propellant block (createbigcannons and cbc_enhanced_shells
-- block_propellant "strength"). A big cartridge gives 2 per power level:
-- "cartridge4" = 8. Numbers are used as they are.
ballistics.charges = {
    powder = 2, powder_charge = 2,
    mk1 = 2.5, mk2 = 3.0, mk3 = 3.5, mk4 = 4.0, mk5 = 4.5,
    powder_charge_mk1 = 2.5, powder_charge_mk2 = 3.0, powder_charge_mk3 = 3.5,
    powder_charge_mk4 = 4.0, powder_charge_mk5 = 4.5,
}

-- Big cannon shells. Mk.1-Mk.5 variants of CBC: Enhanced Shells have the same
-- flight data as the base shell, so "he_shell_mk3" works too.
local STANDARD = { gravity = -0.05, drag = 0.01 }
ballistics.shells = {
    ap_shell = STANDARD, ap_shot = STANDARD, he_shell = STANDARD, shot = STANDARD,
    solid_shot = STANDARD, shrapnel_shell = STANDARD, smoke_shell = STANDARD,
    fluid_shell = STANDARD, traffic_cone = STANDARD,
    mortar_stone = { gravity = -0.025, drag = 0.01 },
    -- CBC: Enhanced Shells
    bunker_buster_shell = { gravity = -0.04, drag = 0.008 },
    cluster_shell = STANDARD, disintegration_shell = STANDARD, gravitational_shell = STANDARD,
    plasma_shell = STANDARD, prototype_shell = STANDARD, shell_holder = STANDARD,
    singularity_shell = STANDARD, vortex_shell = STANDARD, h_bomb_shell = STANDARD,
    h_bomb_mini_shell = STANDARD, nuke_shell = STANDARD,
}

-- Autocannon rounds (CBC and CBC: AT).
ballistics.autocannonRounds = {
    ap = { gravity = -0.025, drag = 0.01 },
    flak = { gravity = -0.025, drag = 0.01 },
    machine_gun = { gravity = -0.025, drag = 0.01 },
    apds = { gravity = -0.02, drag = 0.01 },
    apdsfs = { gravity = -0.016, drag = 0.00825 },
    he = { gravity = -0.025, drag = 0.01 },
    hei = { gravity = -0.025, drag = 0.01 },
}

-- Heavy autocannon rounds (CBC: AT), all with quadratic drag.
ballistics.heavyRounds = {
    ap = { gravity = -0.03, drag = 0.013, quadratic = true },
    apds = { gravity = -0.02, drag = 0.011, quadratic = true },
    apdsfs = { gravity = -0.0175, drag = 0.008, quadratic = true },
    he = { gravity = -0.03, drag = 0.013, quadratic = true },
    hef = { gravity = -0.033, drag = 0.013, quadratic = true },
    heat = { gravity = -0.035, drag = 0.012, quadratic = true },
    smoke = { gravity = -0.035, drag = 0.005, quadratic = true },
}

-- Autocannon materials (CBCAutocannonMaterials), also used by heavy autocannons.
ballistics.materials = {
    cast_iron = { baseSpeed = 5, perBarrel = 2, maxIncreases = 2, lifetime = 11, maxBarrels = 3 },
    bronze = { baseSpeed = 3, perBarrel = 1.5, maxIncreases = 3, lifetime = 25, maxBarrels = 5 },
    steel = { baseSpeed = 3, perBarrel = 1.5, maxIncreases = 4, lifetime = 60, maxBarrels = 7 },
}

-- Pitch limits of a standard cannon mount (cannon on top of the mount).
local LIMITS = {
    big = { -30, 60 },
    auto = { -45, 90 },
}

---------------------------------------------------------------------------
-- Vector helpers (arrays {x, y, z})

local function vec(t)
    if t == nil then return nil end
    if t[1] then return { t[1], t[2], t[3] } end
    return { t.x, t.y, t.z }
end

local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
local function len(a) return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end
local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function unit(a)
    local l = len(a)
    if l < 1e-12 then return { 0, 0, 1 } end
    return scale(a, 1 / l)
end

local function rotate(q, v, inverse)
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w
    if inverse then qx, qy, qz = -qx, -qy, -qz end
    local x, y, z = v[1], v[2], v[3]
    local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
    return {
        x + qw * tx + (qy * tz - qz * ty),
        y + qw * ty + (qz * tx - qx * tz),
        z + qw * tz + (qx * ty - qy * tx),
    }
end

-- Minecraft angles: yaw 0 = +Z (south), 90 = -X (west); pitch > 0 = up.
-- CBC cannon mounts use the same convention for cannonYaw/cannonPitch.
local function fromAngles(yaw, pitch)
    local cp = math.cos(pitch)
    return { -math.sin(yaw) * cp, math.sin(pitch), math.cos(yaw) * cp }
end

local function toAngles(d)
    local yaw = math.atan2(-d[1], d[3])
    local pitch = math.asin(math.max(-1, math.min(1, d[2])))
    return yaw, pitch
end

local function wrap180(deg)
    deg = deg % 360
    if deg >= 180 then deg = deg - 360 end
    return deg
end

---------------------------------------------------------------------------
-- Flight model

-- Linear drag has a closed form for the mod's integrator:
-- p(n) = p0 + c(n) * v0 + B(n) * up, with r = 1 - k and S = (1 - r^n) / k.
local function linearCoeffs(n, g, k)
    if k < 1e-9 then return n, g * n * n / 2 end
    local s = (1 - (1 - k) ^ n) / k
    local h = 1 - k / 2
    return h * s, h * (n - s) * g / k + g * n / 2
end

-- Launch for linear drag: finds flight times n where the needed launch
-- velocity (relative to the carrier) has exactly the muzzle speed.
local function solveLinear(p0, u, speed, g, k, t0, w, maxTicks, arc)
    local function required(n)
        local c, b = linearCoeffs(n, g, k)
        local rx = (t0[1] + w[1] * n - p0[1]) / c - u[1]
        local ry = (t0[2] + w[2] * n - p0[2] - b) / c - u[2]
        local rz = (t0[3] + w[3] * n - p0[3]) / c - u[3]
        return math.sqrt(rx * rx + ry * ry + rz * rz) - speed, { rx, ry, rz }
    end

    local roots = {}
    local n = 0.05
    local f = required(n)
    while n < maxTicks do
        local n1 = math.min(n + math.max(0.25, n * 0.02), maxTicks)
        local f1 = required(n1)
        if (f > 0) ~= (f1 > 0) then
            local lo, hi, flo = n, n1, f
            for _ = 1, 40 do
                local mid = (lo + hi) / 2
                local fm = required(mid)
                if (fm > 0) == (flo > 0) then lo, flo = mid, fm else hi = mid end
            end
            roots[#roots + 1] = (lo + hi) / 2
            if arc == "low" or #roots == 2 then break end
        end
        n, f = n1, f1
    end

    local root = arc == "high" and roots[2] or roots[1]
    if not root then return nil end
    local _, v = required(root)
    return unit(v), root
end

-- Simulates a shot and returns the miss (sideways, vertical) where the
-- projectile passes the (moving) target, plus the flight time. reached =
-- false when the shell never gets that far.
local function simulate(p0, d, speed, u, g, k, quadratic, t0, w, maxTicks)
    local vx, vy, vz = d[1] * speed + u[1], d[2] * speed + u[2], d[3] * speed + u[3]
    local px, py, pz = p0[1], p0[2], p0[3]
    local bx, bz = t0[1] - px, t0[3] - pz
    local bl = math.sqrt(bx * bx + bz * bz)
    if bl < 1e-6 then bx, bz, bl = d[1], d[3], math.sqrt(d[1] * d[1] + d[3] * d[3]) + 1e-12 end
    bx, bz = bx / bl, bz / bl
    local sx, sz = -bz, bx
    local ex, ey, ez = px - t0[1], py - t0[2], pz - t0[3]
    local along = ex * bx + ez * bz
    for n = 1, maxTicks do
        local sp = math.sqrt(vx * vx + vy * vy + vz * vz)
        local drag = k * sp
        if quadratic then drag = drag * sp end
        if drag > sp then drag = sp end
        local ax, ay, az = 0, g, 0
        if sp > 1e-10 then
            ax, ay, az = -vx / sp * drag, g - vy / sp * drag, -vz / sp * drag
        end
        px, py, pz = px + vx + ax / 2, py + vy + ay / 2, pz + vz + az / 2
        vx, vy, vz = vx + ax, vy + ay, vz + az

        local nx, ny, nz = px - t0[1] - w[1] * n, py - t0[2] - w[2] * n, pz - t0[3] - w[3] * n
        local nAlong = nx * bx + nz * bz
        if nAlong >= 0 then
            local t = along / (along - nAlong)
            local mx, my, mz = ex + (nx - ex) * t, ey + (ny - ey) * t, ez + (nz - ez) * t
            return mx * sx + mz * sz, my, n - 1 + t, true
        end
        ex, ey, ez, along = nx, ny, nz, nAlong
        if vy < 0 and ey < -512 then break end
    end
    -- Never reached: count the missing distance as being low.
    return ex * sx + ez * sz, ey + along, maxTicks, false
end

-- Newton iteration on world yaw/pitch with a numeric Jacobian. Works for any
-- drag law; used for quadratic drag, starting from a linear-drag guess.
local function solveNumeric(p0, d, speed, u, g, k, quadratic, t0, w, maxTicks)
    local yaw, pitch = toAngles(d)
    local eps = 1e-3
    local miss, time, reached
    for _ = 1, 20 do
        local lat, vert, t, ok = simulate(p0, fromAngles(yaw, pitch), speed, u, g, k, quadratic, t0, w, maxTicks)
        miss, time, reached = math.sqrt(lat * lat + vert * vert), t, ok
        if ok and miss < 0.01 then break end
        local la, va = simulate(p0, fromAngles(yaw + eps, pitch), speed, u, g, k, quadratic, t0, w, maxTicks)
        local lb, vb = simulate(p0, fromAngles(yaw, pitch + eps), speed, u, g, k, quadratic, t0, w, maxTicks)
        local j11, j21 = (la - lat) / eps, (va - vert) / eps
        local j12, j22 = (lb - lat) / eps, (vb - vert) / eps
        local det = j11 * j22 - j12 * j21
        if math.abs(det) < 1e-12 then break end
        local dyaw = -(j22 * lat - j12 * vert) / det
        local dpitch = -(-j21 * lat + j11 * vert) / det
        local step = math.sqrt(dyaw * dyaw + dpitch * dpitch)
        local maxStep = math.rad(10)
        if step > maxStep then dyaw, dpitch = dyaw * maxStep / step, dpitch * maxStep / step end
        yaw = yaw + dyaw
        pitch = math.max(-math.pi / 2, math.min(math.pi / 2, pitch + dpitch))
    end
    if not reached or miss > 0.5 then return nil end
    return fromAngles(yaw, pitch), time
end

---------------------------------------------------------------------------
-- Guns

local Gun = {}
Gun.__index = Gun

local function getRadar()
    local ok, radar = pcall(require, "radar")
    if not ok or type(radar) ~= "table" or not radar.blockToWorld then
        error("ballistics: the radar library (1.4.0+) is required for the gun position", 0)
    end
    return radar
end

-- Velocity a projectile inherits from the structure at point p (blocks/tick).
local function carrierVelocity(p, computer, q)
    if not ballistics.config.inheritVelocity or not q then return { 0, 0, 0 } end
    if type(sublevel) ~= "table" or type(sublevel.getVelocity) ~= "function" then return { 0, 0, 0 } end
    local v = vec(sublevel.getVelocity())                  -- blocks/s at the computer
    local okW, w = pcall(sublevel.getAngularVelocity)      -- rad/s, structure axes
    if okW and type(w) == "table" then
        local omega = rotate(q, vec(w))
        v = add(v, cross(omega, sub(p, computer)))
    end
    return scale(v, 0.05)
end

--- Change the cannon mount position (mount block - computer block; structure
-- axes on a Sable structure). Same as changing gun.offset.
function Gun:setOffset(dx, dy, dz)
    self.offset = { dx, dy, dz }
end

--- Pivot of the cannon in world space: the centre of the block above the
-- mount, i.e. the point the barrel turns around.
function Gun:pivot()
    local o = vec(self.offset)
    if not o or type(o[1]) ~= "number" or type(o[2]) ~= "number" or type(o[3]) ~= "number" then
        error("ballistics: gun.offset must be {dx, dy, dz} (mount block - computer block)", 0)
    end
    local p = vec(self.pivotOffset)
    local radar = getRadar()
    local pos, q, mode = radar.blockToWorld(o[1] + p[1], o[2] + p[2], o[3] + p[3])
    return vec(pos), q, mode, radar
end

--- Firing solution for a target {x, y, z[, velocity = {x, y, z}]} in world
-- coordinates (radar.scan with global = true). Options: arc = "low" | "high"
-- | "auto" (low, or high if low is out of the pitch limits), latency (ticks).
function Gun:aim(target, opts)
    opts = opts or {}
    local cfg = ballistics.config
    local t0 = vec(target)
    if type(target) ~= "table" or type(t0[1]) ~= "number" then
        error("ballistics: bad argument #1 (target with x, y, z expected)", 2)
    end
    local w = vec(target.velocity) or { 0, 0, 0 }
    local latency = opts.latency or cfg.latency
    t0 = add(t0, scale(w, latency))

    local pivot, q, mode, radar = self:pivot()
    local computer = q and vec((radar.blockToWorld(0, 0, 0))) or pivot
    local g = self.gravity * cfg.gravityMultiplier
    local k = self.drag * cfg.dragMultiplier
    local speed, maxTicks = self.speed, self.maxTicks

    local function solve(arc)
        local d = unit(sub(t0, pivot))
        local time, u
        for _ = 1, 4 do -- spawn point and carrier velocity depend on the direction
            local p0 = add(pivot, scale(d, self.muzzle))
            u = carrierVelocity(p0, computer, q)
            local guess, t
            if self.quadratic then
                guess = solveLinear(p0, u, speed, g, math.min(0.5, k * speed * 0.6), t0, w, maxTicks, arc)
                guess, t = solveNumeric(p0, guess or d, speed, u, g, k, true, t0, w, maxTicks)
            else
                guess, t = solveLinear(p0, u, speed, g, k, t0, w, maxTicks, arc)
            end
            if not guess then return nil end
            d, time = guess, t
        end
        return d, time, u
    end

    local arc = opts.arc or "low"
    local d, time, u = solve(arc == "high" and "high" or "low")
    local result = { muzzleSpeed = speed, mode = mode }
    if not d then
        result.ok, result.reason = false, "out of range"
        return result
    end

    local function fill(dir, t, vel)
        local local_ = q and rotate(q, dir, true) or dir
        local yaw, pitch = toAngles(local_)
        result.direction = { x = dir[1], y = dir[2], z = dir[3] }
        result.yaw = wrap180(math.deg(yaw))
        result.pitch = math.deg(pitch)
        local wy, wp = toAngles(dir)
        result.worldYaw, result.worldPitch = wrap180(math.deg(wy)), math.deg(wp)
        result.ticks = t
        local aim = add(t0, scale(w, t))
        result.aimPoint = { x = aim[1], y = aim[2], z = aim[3] }
        local m = add(pivot, scale(dir, self.muzzle))
        result.muzzle = { x = m[1], y = m[2], z = m[3] }
        result.carrierVelocity = { x = vel[1], y = vel[2], z = vel[3] }
    end
    fill(d, time, u)
    result.arc = arc == "high" and "high" or "low"

    local lo, hi = self.limits[1], self.limits[2]
    if (result.pitch < lo or result.pitch > hi) and arc == "auto" then
        local d2, time2, u2 = solve("high")
        if d2 then
            fill(d2, time2, u2)
            result.arc = "high"
        end
    end
    if result.pitch < lo or result.pitch > hi then
        result.ok, result.reason = false, ("pitch %.1f outside %g..%g"):format(result.pitch, lo, hi)
    elseif result.ticks > self.maxTicks then
        result.ok, result.reason = false, "projectile expires before reaching the target"
    else
        result.ok = true
    end
    return result
end

--- Where the shell would be after following a solution, tick by tick
-- (for checks and displays). Returns a list of {x, y, z}.
function Gun:trajectory(solution, ticks)
    local cfg = ballistics.config
    local d = vec(solution.direction)
    local u = vec(solution.carrierVelocity) or { 0, 0, 0 }
    local p = vec(solution.muzzle)
    local g, k = self.gravity * cfg.gravityMultiplier, self.drag * cfg.dragMultiplier
    local v = add(scale(d, self.speed), u)
    local out = {}
    for n = 1, math.min(ticks or math.ceil(solution.ticks or 0) + 1, self.maxTicks) do
        local sp = len(v)
        local drag = k * sp
        if self.quadratic then drag = drag * sp end
        drag = math.min(drag, sp)
        local a = { 0, g, 0 }
        if sp > 1e-10 then a = add(a, scale(v, -drag / sp)) end
        p = add(add(p, v), scale(a, 0.5))
        v = add(v, a)
        out[n] = { x = p[1], y = p[2], z = p[3] }
    end
    return out
end

local function newGun(spec, fields)
    local gun = setmetatable(fields, Gun)
    gun.offset = spec.offset
    gun.pivotOffset = spec.pivotOffset or { 0, 1, 0 }
    gun.limits = spec.limits or gun.limits
    return gun
end

local function lookup(tbl, name, what)
    if type(name) == "table" then
        if type(name.gravity) ~= "number" or type(name.drag) ~= "number" then
            error(("ballistics: custom %s needs gravity and drag"):format(what), 3)
        end
        return name
    end
    if type(name) ~= "string" then error(("ballistics: %s name expected"):format(what), 3) end
    local key = name:lower():gsub("^.*:", ""):gsub("_mk%d$", "")
    local data = tbl[key]
    if not data then error(("ballistics: unknown %s '%s'"):format(what, name), 3) end
    return data
end

local function chargePower(c)
    if type(c) == "number" then return c end
    if type(c) ~= "string" then error("ballistics: charge must be a name or a number", 4) end
    local key = c:lower():gsub("^.*:", "")
    local level = key:match("^big_cartridge(%d)$") or key:match("^cartridge(%d)$")
    if level then return 2 * tonumber(level) end
    local power = ballistics.charges[key]
    if not power then error(("ballistics: unknown charge '%s'"):format(c), 4) end
    return power
end

--- Muzzle speed of a big cannon (blocks/tick).
-- spec.charges: list from the breech forward; spec.length: cannon blocks in
-- front of the breech up to the muzzle; spec.shellLength (1), spec.muzzleBrakes
-- (0, CBC: AT muzzle brakes at the end of the barrel).
function ballistics.bigCannonSpeed(spec)
    local charges = spec.charges or {}
    local shell = lookup(ballistics.shells, spec.shell or "he_shell", "shell")
    local addedCharge = shell.addedCharge or 0
    if not ballistics.config.physicsRework then
        local total = addedCharge
        for _, c in ipairs(charges) do total = total + chargePower(c) end
        return total
    end

    -- CBC: AT CustomPropellantContext, block by block from the breech.
    local length = spec.length or (#charges + (spec.shellLength or 1))
    local brakes = spec.muzzleBrakes or 0
    local used, drag, gas, velocity = 0, 0, 0, 0
    local function current() return math.max(0, velocity + used - drag) end
    for i = 1, length do
        if i <= #charges then
            local power = math.max(0, chargePower(charges[i]))
            used = used + power
            gas = gas + 0.8 * power
        elseif i == #charges + 1 then
            used = used + addedCharge
        end
        local v = current()
        if i > length - brakes then
            gas = (gas - 0.32) * 0.45
            drag = drag + 2.5e-4 * v * v
        else
            gas = gas - 0.32
            drag = drag + 0.08 * v * v
        end
        velocity = velocity + math.max(0, gas)
    end
    return current()
end

--- Big cannon. spec: offset, length, muzzle, charges, shell, shellLength,
-- muzzleBrakes, limits = {minPitch, maxPitch}, pivotOffset.
-- muzzle = blocks from the block above the mount to the muzzle block along
-- the barrel (the shell appears in the centre of the muzzle block).
function ballistics.bigCannon(spec)
    local shell = lookup(ballistics.shells, spec.shell or "he_shell", "shell")
    local speed = spec.speed or ballistics.bigCannonSpeed(spec)
    if speed <= 0 then error("ballistics: no muzzle speed (no charges?)", 2) end
    return newGun(spec, {
        kind = "big_cannon",
        speed = speed,
        gravity = shell.gravity,
        drag = shell.drag,
        quadratic = shell.quadratic or false,
        muzzle = spec.muzzle or 0,
        maxTicks = ballistics.config.maxTicks,
        limits = LIMITS.big,
    })
end

local function itemCannon(spec, rounds, heavy)
    local material = ballistics.materials[(spec.material or "steel"):lower()]
    if not material then error(("ballistics: unknown material '%s'"):format(tostring(spec.material)), 3) end
    local round = lookup(rounds, spec.round or "ap", "round")
    local barrels = spec.barrels
    if type(barrels) ~= "number" or barrels < 0 then
        error("ballistics: barrels (blocks in front of the breech) expected", 3)
    end
    local maxBarrels = heavy and math.floor(material.maxBarrels * 1.5) or material.maxBarrels
    if barrels > maxBarrels then
        error(("ballistics: %d barrels - rounds get stuck after %d"):format(barrels, maxBarrels), 3)
    end
    local speed = material.baseSpeed + material.perBarrel * math.min(barrels, material.maxIncreases)
    local lifetime = material.lifetime
    if heavy then
        lifetime = lifetime * 3
        if spec.strong then speed = speed * 1.5 end
    end
    return newGun(spec, {
        kind = heavy and "heavy_autocannon" or "autocannon",
        speed = spec.speed or speed,
        gravity = round.gravity,
        drag = round.drag,
        quadratic = round.quadratic or false,
        -- the round appears at the front face of the last barrel block
        muzzle = (spec.muzzle or 0) + 0.5,
        maxTicks = lifetime,
        limits = LIMITS.auto,
    })
end

--- Autocannon. spec: offset, material ("cast_iron" | "bronze" | "steel"),
-- barrels (autocannon blocks in front of the breech), muzzle, round, limits.
function ballistics.autocannon(spec)
    return itemCannon(spec, ballistics.autocannonRounds, false)
end

--- Heavy autocannon (CBC: AT). Same as autocannon plus strong = true for
-- strong cartridges (x1.5 speed).
function ballistics.heavyAutocannon(spec)
    return itemCannon(spec, ballistics.heavyRounds, true)
end

--- Turn a cannon mount to a solution. Supports "cannon_mount" (CC:CBC) and
-- "cbc_cannon_mount" (CBC Peripheral).
function ballistics.point(mount, solution)
    if type(mount) == "string" then mount = peripheral.wrap(mount) end
    if type(mount) ~= "table" then error("ballistics: bad argument #1 (cannon mount expected)", 2) end
    if not solution or not solution.yaw then error("ballistics: bad argument #2 (solution expected)", 2) end
    if peripheral.hasType(mount, "cannon_mount") and mount.setTargetAngles then
        if not mount.isComputerControl() then mount.setComputerControl(true) end
        mount.setTargetAngles(solution.yaw, solution.pitch)
    elseif mount.setYaw and mount.setPitch then
        mount.setYaw(solution.yaw)
        mount.setPitch(solution.pitch)
    else
        error("ballistics: unsupported mount peripheral", 2)
    end
end

return ballistics
