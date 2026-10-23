-- Runs when the computer boots with this disk inserted.
local here = fs.getDir(shell.getRunningProgram())
shell.run("/" .. fs.combine(here, "install.lua"))

-- A disk startup replaces the computer's own startup files, so run them too
-- (the library loader has already been run by the installer).
local LOADER = "startup/00_radarlib.lua"

local function run(path)
    if fs.exists(path) and not fs.isDir(path) then shell.run("/" .. path) end
end

run("startup.lua")
if fs.isDir("startup") then
    for _, file in ipairs(fs.list("startup")) do
        local path = fs.combine("startup", file)
        if path ~= LOADER then run(path) end
    end
end
