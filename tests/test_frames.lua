-- The secure buttons, their wiring, and plain-value painting.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()

local EDGES = { "LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp" }

for _, unit in ipairs({ "player", "target", "pet", "targettarget" }) do
    local b = button(unit)
    check(b ~= nil, unit .. " frame built")
    eq(b._template, "SecureUnitButtonTemplate", unit .. " template")
    eq(b._name, "GlassUF_" .. unit, unit .. " global name")
    eq(b._attrs.unit, unit, unit .. " unit attribute")
    eq(b._attrs["*type1"], "target", unit .. " left click targets")
    eq(b._attrs["*type2"], "togglemenu", unit .. " right click menu")
    for k in pairs(b._attrs) do
        check(not k:find("typerelease"), unit .. " never sets typerelease (double-acts): " .. k)
    end
    eq(#(b._clicks or {}), 4, unit .. " registers both mouse edges")
    for i, e in ipairs(EDGES) do eq(b._clicks[i], e, unit .. " click edge " .. i) end
    check(WoW.unitWatch[b], unit .. " is under RegisterUnitWatch")
end

-- Plain values reach the bars and text.
local p = button("player")
eq(p.health._max, 1550, "player health max")
eq(p.health._value, 1240, "player health value")
eq(textOf(p.nameText), "Morphisto", "player name")
eq(textOf(p.valueText), "1.2K | 80%", "player value text")
eq(textOf(p.powerText), "920", "player power text")
eq(p.power._value, 920, "player power value")
eq(p.health._color[3], 0.93, "player coloured by class")
eq(button("target").health._color[1], 0.85, "hostile target is red")
eq(button("pet").power._color[1], 1.00, "pet focus coloured")
eq(textOf(button("pet").valueText), "100%", "small frame shows percent only")
eq(button("player").model._modelUnit, "player", "3D portrait set to the unit")

-- A unit event repaints on the next rendered frame, once.
WoW.units.player.health = 775
WoW.fire("UNIT_HEALTH", "player")
WoW.fire("UNIT_HEALTH", "player")
eq(p.health._value, 1240, "not painted before the flush")
WoW.tick()
eq(p.health._value, 775, "painted after the flush")
eq(textOf(p.valueText), "775 | 50%", "value text after damage")

-- Dead and offline read as words.
WoW.units.target.dead = true
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()
eq(textOf(button("target").valueText), "Dead", "dead target")
WoW.units.target.dead = false
WoW.units.target.connected = false
WoW.fire("UNIT_CONNECTION", "target"); WoW.tick()
eq(textOf(button("target").valueText), "Offline", "offline target")
eq(button("target").health._color[1], 0.50, "offline target is grey")

-- Target change repaints target and targettarget and sweeps the sheen.
WoW.SetUnit("target", { name = "Defias Bandit", reaction = 2, health = 77, maxHealth = 100 })
local plays = button("target").sheen._plays or 0
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(textOf(button("target").nameText), "Defias Bandit", "new target painted")
eq(button("target").sheen._plays, plays + 1, "sheen plays on a new target")

-- targettarget has no unit events: the ticker repaints it while shown.
WoW.units.targettarget.health = 155
WoW.tick(0.3); WoW.tick()
eq(button("targettarget").health._value, 1240, "no repaint before 0.5s")
WoW.tick(0.3); WoW.tick()
eq(button("targettarget").health._value, 155, "ticker repainted targettarget")

-- Pet replaced: UNIT_PET on player repaints the pet frame.
WoW.SetUnit("pet", { name = "Grunthok", reaction = 5 })
WoW.fire("UNIT_PET", "player"); WoW.tick()
eq(textOf(button("pet").nameText), "Grunthok", "pet repainted after UNIT_PET")

-- Every registered event runs for every unit without a Lua error. Casters
-- are mid-cast so START events have a cast to find, as they would in game.
WoW.units.player.casting = { name = "Shadow Bolt" }
WoW.units.target.casting = { name = "Fireball" }
local seen = WoW.fireAllRegistered()
WoW.tick()
check(seen.UNIT_HEALTH and seen.UNIT_SPELLCAST_START and seen.PLAYER_TARGET_CHANGED, "core events registered")
eq(next(GlassUF.eventFailures), nil, "no event registration failures")
eq(next(GlassUF.paintFailures), nil, "no paint failures with plain values")

-- Slash commands run.
SlashCmdList.GLASSUNITFRAMES("")
SlashCmdList.GLASSUNITFRAMES("secrets")
SlashCmdList.GLASSUNITFRAMES("font friz")
eq(GlassUnitFramesDB.font, "friz", "font saved")
eq(p.nameText._font[1], "Fonts\\FRIZQT__.TTF", "font applied to existing text")
SlashCmdList.GLASSUNITFRAMES("font comic")
eq(GlassUnitFramesDB.font, "friz", "unknown font rejected")

done("test_frames")
