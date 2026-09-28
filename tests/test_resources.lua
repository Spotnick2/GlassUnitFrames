-- #29: combo points (rogue, cat druid) on the target frame, druid mana strip.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- A warlock (the standard units) gets neither.
standardUnits()
loadAddon()
check(button("target").combo == nil, "no combo pips for a warlock")
check(button("player").druidMana == nil, "no druid mana strip for a warlock")

-- A rogue: five pips on the target, alphas from the client's curves.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class, WoW.units.player.powerToken = "ROGUE", "ENERGY"
WoW.units.player.combo = 0
loadAddon()
local t = button("target")
local c = t.combo
check(c and #c.pips == 5, "five combo pips on the target frame")
check(c.holder._shown, "shown with a target")
for i = 1, 5 do eq(c.pips[i]._alpha, 0, "0 points: pip " .. i .. " empty") end
WoW.units.player.combo = 3
WoW.fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS"); WoW.tick()
eq(c.pips[3]._alpha, 1, "3 points: pip 3 lit (the player's event repaints the TARGET frame)")
eq(c.pips[4]._alpha, 0, "pip 4 still empty")
WoW.units.player.combo = 5
WoW.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS"); WoW.tick()
eq(c.pips[5]._alpha, 1, "5 points: all lit")

-- Secret combo points: the (secret) alpha goes straight to the pips.
WoW.secretFields.combo = true
WoW.fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS"); WoW.tick()
check(WoW.IsSecret(c.pips[1]._alpha), "secret points: secret alpha passed straight on")
eq(next(GlassUF.paintFailures), nil, "no failures on the secret path")
WoW.secretFields.combo = nil

-- No target: the pips hide with it.
WoW.SetUnit("target", nil)
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(not c.holder._shown, "no target: no pips")

-- A druid: pips only in cat form; the mana strip only out of caster form.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class, WoW.units.player.powerToken = "DRUID", "MANA"
WoW.units.player.combo, WoW.units.player.mana, WoW.units.player.maxMana = 2, 800, 1000
loadAddon()
c = button("target").combo
local dm = button("player").druidMana
check(c ~= nil and dm ~= nil, "a druid gets both")
check(not c.holder._shown, "caster form: no combo pips")
check(not dm.host._shown, "caster form: no mana strip (the main bar is mana)")
WoW.units.player.powerToken = "ENERGY"          -- cat form
WoW.fire("UNIT_DISPLAYPOWER", "player"); WoW.tick()
check(c.holder._shown, "cat form: combo pips (UNIT_DISPLAYPOWER, no power type, still repaints)")
eq(c.pips[2]._alpha, 1, "2 points lit")
check(dm.host._shown, "cat form: the mana strip shows")
eq(dm.bar._value, 800, "mana value straight to the bar")
eq(dm.bar._max, 1000, "max mana straight to the bar")
WoW.units.player.mana = 850
WoW.fire("UNIT_POWER_FREQUENT", "player", "MANA"); WoW.tick()
eq(dm.bar._value, 850, "inactive mana regeneration updates the strip")
WoW.units.player.powerToken = "RAGE"            -- bear form
WoW.fire("UNIT_DISPLAYPOWER", "player"); WoW.tick()
check(not c.holder._shown, "bear form: no combo pips")
check(dm.host._shown, "bear form: the mana strip stays")
WoW.secretFields.mana = true
WoW.fire("UNIT_POWER_FREQUENT", "player", "MANA"); WoW.tick()
check(WoW.IsSecret(dm.bar._value), "secret mana straight to the bar")
eq(next(GlassUF.paintFailures), nil, "no failures")

-- Blizzard's ComboFrame is hidden once ours exists.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class = "ROGUE"
local cf = CreateFrame("Frame", "ComboFrame", UIParent)
loadAddon()
check(not cf._shown, "Blizzard's ComboFrame hidden for a rogue")
rawset(_G, "ComboFrame", nil)

done("test_resources")
