-- Health-loss segment (#40): a red bar that follows health late, clipped to
-- the part beyond the current fill.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }   -- measured in game (#14)
loadAddon()
local p = button("player")
local loss = p.lossBar
check(loss ~= nil, "player has a health-loss bar")
check(button("target").lossBar ~= nil, "target too")
check(button("targettarget").lossBar == nil, "not on the small chained frames")

-- Geometry: clipped from the health fill's moving edge to the bar's end.
local clip = loss:GetParent()
eq(clip._points[1][2], p.health:GetStatusBarTexture(), "clip starts at the fill's edge")
eq(clip._points[1][3], "TOPRIGHT", "at the fill's right edge")
eq(clip._points[2][2], p.health, "and ends with the health bar")
eq(loss._points[1][2], p.health, "the loss bar has the health bar's geometry")

WoW.flushTimers()
eq(loss._value, 1240, "starts at current health (first paint snaps)")

-- Damage: health drops at once, the red bar holds the old value, then eases.
WoW.units.player.health = 600
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(p.health._value, 600, "health bar follows at once")
eq(loss._value, 1240, "red segment holds the lost health")
WoW.flushTimers()
eq(loss._value, 600, "then catches up")
eq(loss._interp, Enum.StatusBarInterpolation.ExponentialEaseOut, "eased, not snapped")

-- Two hits in a row: only the latest update lands.
WoW.units.player.health = 500
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
WoW.units.player.health = 400
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
WoW.flushTimers()
eq(loss._value, 400, "the latest value wins")

-- A new target snaps: no red segment carried over from the previous unit.
local t = button("target")
WoW.SetUnit("target", { health = 300, maxHealth = 1000, guid = "other" })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(t.lossBar._value, 300, "new target: loss bar snaps with the health bar")

-- Secret health goes straight through.
WoW.secretFields.health = true
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
WoW.flushTimers()
eq(next(GlassUF.paintFailures), nil, "secret health: no failures")

done("test_healthloss")
