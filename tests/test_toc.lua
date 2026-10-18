-- The manifest and the pinned build.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open("GlassUnitFrames.toc"):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassUnitFramesDB", 1, true), "saved variables declared")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- Two places that must agree, never derived from each other (porting guide §0).
loadAddon()
eq(GlassUF.MEASURED_ON_BUILD, "1.60.1.70450", "MEASURED_ON_BUILD")

-- The packager replaces its version keyword in every shipped file, so a
-- literal one in Lua would turn into the release tag (AltStable's bug).
for _, f in ipairs(tocFiles()) do
    check(not io.open(f):read("*a"):find("@project-version@", 1, true), "no literal version keyword in " .. f)
end

-- The newer-build warning is for dev copies only; a release stays quiet.
local function warned(version, build)
    WoW.reset()
    WoW.addonVersion = version
    local real = GetBuildInfo
    GetBuildInfo = function() return "1.60.1", build, "Sep 23 2026", 16001 end
    loadAddon()
    GetBuildInfo = real
    for _, line in ipairs(WoW.chat) do
        if line:find("is newer than", 1, true) then return true end
    end
    return false
end
check(warned("dev", "99999"), "dev copy warns on a newer build")
check(warned("@" .. "project-version" .. "@", "99999"), "unpackaged checkout warns on a newer build")
check(warned(nil, "99999"), "unreadable version counts as dev")
check(not warned("v1.2.0", "99999"), "release does not warn on a newer build")
check(not warned("dev", "70450"), "no warning on the measured build")

-- Every texture the material names ships with the library (Libs\LibGlass-1.0\Media
-- in the package; the checkout's Media/ here). GlassUnitFrames has no Media/ of its own.
local root = libGlassRoot()
for size, S in pairs(GlassUF.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2", "track_fade" }) do
    check(io.open(root .. "/Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end
-- Glass.MEDIA points into the embedded copy, where the packager puts it.
eq(GlassUF.Glass.MEDIA, "Interface\\AddOns\\GlassUnitFrames\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")

done("test_toc")
