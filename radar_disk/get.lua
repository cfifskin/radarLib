-- One-command installer, downloads the library from GitHub:
--   wget run https://raw.githubusercontent.com/cfifskin/radarLib/main/radar_disk/get.lua
-- With a directory argument the files are kept there, e.g. to make an
-- installer floppy:
--   wget run https://raw.githubusercontent.com/cfifskin/radarLib/main/radar_disk/get.lua disk
local BASE = "https://raw.githubusercontent.com/cfifskin/radarLib/main/radar_disk/"
local FILES = {
    "radar.lua", "radarui.lua", "ballistics.lua", "install.lua", "loader.lua", "startup.lua",
    "example.lua", "example_ui.lua", "example_gun.lua",
}

local args = { ... }
local keep = args[1]
local dir
if keep then
    dir = fs.combine(keep, "")
    if not fs.isDir(dir) then
        printError(("No directory '%s' (is the disk inserted?)"):format(keep))
        return
    end
else
    dir = ".radarlib_tmp"
    fs.delete(dir)
    fs.makeDir(dir)
end

for _, name in ipairs(FILES) do
    write("Downloading " .. name .. "... ")
    local response, err = http.get(BASE .. name, nil, true)
    if not response then
        printError(err or "failed")
        if not keep then fs.delete(dir) end
        return
    end
    local data = response.readAll()
    response.close()
    local file = fs.open(fs.combine(dir, name), "wb")
    file.write(data)
    file.close()
    print("OK")
end

shell.run("/" .. fs.combine(dir, "install.lua"))
if not keep then fs.delete(dir) end

if not fs.exists("lib/radar.lua") then
    printError("Installation failed.")
elseif keep then
    print("Installer kept in /" .. dir)
end
