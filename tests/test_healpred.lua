-- Incoming heal prediction (#13).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

Enum.UnitIncomingHealClampMode = { MaximumHealth = 1 }
standardUnits()
loadAddon()
local p, t = button("player"), button("target")

check(p.healPred and t.healPred and button("focus").healPred, "player, target and focus predict heals")
check(button("pet").healPred == nil and button("targettarget").healPred == nil, "small chained frames do not")
eq(p.healCalc.clamp, 1, "calculator clamped to maximum health")

-- Geometry: full health-bar width, anchored to the fill's moving edge, clipped.
local pred = p.healPred
eq(pred._width, 300 - 2 * GlassUF.Glass.Inset("large"), "prediction spans the full health bar width")
eq(pred._points[1][2], p.health:GetStatusBarTexture(), "anchored to the health fill's edge")
check(pred._parent._clips == true, "clipped at the health bar's boundary")

-- Values go straight through, snapped (never eased).
Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
WoW.units.player.incoming = 300
WoW.fire("UNIT_HEAL_PREDICTION", "player"); WoW.tick()
eq(pred._value, 300, "incoming heals reach the bar")
eq(pred._max, 1550, "scaled to maximum health")
eq(pred._interp, nil, "prediction snaps")
WoW.units.player.incoming = 0
WoW.fire("UNIT_HEAL_PREDICTION", "player"); WoW.tick()
eq(pred._value, 0, "a finished heal clears")
Enum.StatusBarInterpolation = nil

-- A damage cast must not refresh prediction: spellcast events don't touch it.
WoW.units.player.incoming = 999
WoW.units.player.casting = { name = "Fireball" }
WoW.fire("UNIT_SPELLCAST_START", "player"); WoW.tick()
eq(pred._value, 0, "spellcast events do not refresh heal prediction")
WoW.units.player.casting = nil
WoW.units.player.incoming = 0

-- Secret values pass through untouched.
WoW.secretFields.incoming, WoW.secretFields.maxHealth = true, true
WoW.units.target.incoming = 120
WoW.fire("UNIT_HEAL_PREDICTION", "target"); WoW.tick()
check(WoW.IsSecret(t.healPred._value) and WoW.IsSecret(t.healPred._max), "secret heals handed to the bar untouched")
eq(next(GlassUF.paintFailures), nil, "no paint failures")

-- No calculator API: no prediction bar, nothing breaks.
WoW.reset()
standardUnits()
GlassUF = nil
local realCreate = CreateUnitHealPredictionCalculator
CreateUnitHealPredictionCalculator = nil
loadAddon()
check(button("player").healPred == nil and button("player").health ~= nil, "no API: no prediction, frame fine")
CreateUnitHealPredictionCalculator = realCreate

done("test_healpred")
