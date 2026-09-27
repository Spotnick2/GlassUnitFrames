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
eq(tocFiles()[1], "Compat.lua", "Compat loads first")

-- Two places that must agree, never derived from each other (porting guide §0).
loadAddon()
eq(GlassUF.MEASURED_ON_BUILD, "1.60.1.70009", "MEASURED_ON_BUILD")

-- Every texture the material names exists in Media/.
for size, S in pairs(GlassUF.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = "Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2" }) do
    check(io.open("Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end

done("test_toc")
