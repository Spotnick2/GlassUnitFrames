-- The secure buttons, their wiring, and plain-value painting.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()

for _, unit in ipairs({ "player", "target", "pet", "targettarget", "focus", "focustarget" }) do
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
    -- Unit buttons: up edge only, as SUF/DinoUF. The unit-button handler acts
    -- on every registered edge, so both edges could toggle the menu twice.
    eq(#(b._clicks or {}), 1, unit .. " registers one click spec")
    eq(b._clicks[1], "AnyUp", unit .. " clicks on the up edge")
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

-- Focus (#8): PLAYER_FOCUS_CHANGED repaints focus and focustarget; UNIT_TARGET
-- on focus repaints focustarget; focustarget (no unit events) ticks.
eq(textOf(button("focus").nameText), "Hogger", "focus painted")
eq(button("focus").health._value, 666, "focus health")
eq(button("focus").health._color[1], 0.85, "hostile focus is red")
check(button("focus").power ~= nil and button("focustarget").power == nil, "focus has power, focustarget does not")
WoW.SetUnit("focus", { name = "Mother Fang", reaction = 2, health = 50, maxHealth = 100 })
WoW.SetUnit("focustarget", { name = "Hathnos", reaction = 5, health = 400, maxHealth = 400 })
local sheenBefore = button("target").sheen._plays or 0
button("target").cast.flashing = true
WoW.fire("PLAYER_FOCUS_CHANGED"); WoW.tick()
eq(button("target").sheen._plays or 0, sheenBefore, "a focus change does not replay the target sheen")
check(button("target").cast.flashing, "a focus change does not cut off the target's cast flash")
button("target").cast.flashing = false
eq(textOf(button("focus").nameText), "Mother Fang", "focus repainted on PLAYER_FOCUS_CHANGED")
eq(textOf(button("focustarget").nameText), "Hathnos", "focustarget repainted on PLAYER_FOCUS_CHANGED")
WoW.SetUnit("focustarget", { name = "Morphisto", class = "WARLOCK", player = true })
GlassUF.Engine._test.ticker.elapsed = 0          -- prove the event path, not a ticker coincidence
WoW.fire("UNIT_TARGET", "focus"); WoW.tick()
eq(textOf(button("focustarget").nameText), "Morphisto", "UNIT_TARGET on focus repaints focustarget")
WoW.units.focustarget.health = 10
WoW.tick(0.6); WoW.tick()
eq(button("focustarget").health._value, 10, "focustarget ticker repaints")

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
