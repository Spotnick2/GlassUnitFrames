-- #46: health text format per frame, and where the target's level goes.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function textOf(fs)
    local t = fs._text
    if type(t) == "table" then return "<formatted>" end
    return t
end

standardUnits()
WoW.SetUnit("target", { name = "Stormwind Guard", reaction = 5, level = 55, classification = "elite",
                        health = 830, maxHealth = 1317 })
loadAddon()
local p, t = button("player"), button("target")
local F = GlassUF.Frames

-- Health text: defaults from the layout, overridable per frame, live.
eq(F.HealthFormatOf("player"), "curmaxhp", "player defaults to cur/max")
eq(F.HealthFormatOf("target"), "curmaxhp_perhp", "target defaults to both")
check(GlassUF.Settings.SetHealthFormat("player", "perhp"), "player switched to percent")
WoW.tick()
eq(textOf(p.valueText), "80%", "player shows its percent now")
eq(GlassUnitFramesDB.healthText.player, "perhp", "saved per frame")
eq(textOf(t.valueText), "830/1.3K | 63%", "the target keeps its own format")
check(not GlassUF.Settings.SetHealthFormat("player", "bogus"), "unknown format rejected")
check(not GlassUF.Settings.SetHealthFormat("targettargettarget", "curhp"), "a name-only frame has no health text")
SlashCmdList.GLASSUNITFRAMES("text target curhp")
WoW.tick()
eq(textOf(t.valueText), "830", "/glass text target curhp")

-- Level placement: the power line by default.
eq(F.levelPos, "power", "level on the power line by default")
eq(textOf(t.levelText), "55 Elite", "level text on the power line")
eq(t.powerLeftText._points[1][2], t.levelText, "power percent follows the level")

-- Before the name: in the name line, the power line starts with the percent.
check(GlassUF.Settings.SetLevelPosition("name"), "level before the name")
WoW.tick()
eq(textOf(t.levelText), "", "power line level blanked")
eq(textOf(t.nameText), "55 Elite Stormwind Guard", "level before the name")
eq(t.powerLeftText._points[1][2], t.power, "power percent moves to the line's start")
eq(textOf(p.nameText), "Morphisto", "frames without a level text are untouched")
eq(GlassUnitFramesDB.level, "name", "saved")

-- On the portrait: its own label on the portrait tile.
SlashCmdList.GLASSUNITFRAMES("level portrait")
WoW.tick()
eq(textOf(t.levelOnTile), "55 Elite", "level on the portrait")
eq(textOf(t.levelText), "", "not on the power line")
eq(textOf(t.nameText), "Stormwind Guard", "not before the name")
eq(t.levelOnTile._points[1][2], t.tile, "anchored to the portrait tile")

-- Back to the power line.
GlassUF.Settings.SetLevelPosition("power"); WoW.tick()
eq(textOf(t.levelOnTile), "", "portrait label cleared")
eq(textOf(t.levelText), "55 Elite", "level back on the power line")
eq(t.powerLeftText._points[1][2], t.levelText, "percent follows it again")
check(not GlassUF.Settings.SetLevelPosition("sideways"), "unknown placement rejected")

-- Saved settings apply at build.
local saved = GlassUnitFramesDB
saved.level, saved.healthText = "name", { target = "perhp" }
WoW.reset(); standardUnits(); GlassUF = nil
WoW.SetUnit("target", { name = "Stormwind Guard", reaction = 5, level = 55, health = 830, maxHealth = 1317 })
loadAddon({ db = saved })
t = button("target")
eq(textOf(t.nameText), "55 Stormwind Guard", "saved level placement at build")
eq(textOf(t.valueText), "63%", "saved health format at build")
GlassUnitFramesDB = nil

done("test_text")
