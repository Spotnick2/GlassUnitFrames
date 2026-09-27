-- Health-loss segment (#40): a bar that follows health late, clipped to the
-- part beyond the current fill; throttled, range immediate, snaps on death.
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

-- Levels: loss +1, heal +2, both under the glass overlay (+3).
local hl = p.health:GetFrameLevel()
eq(loss:GetFrameLevel(), hl + 1, "loss bar at health + 1")
eq(p.healPred:GetFrameLevel(), hl + 2, "heal prediction above it, at health + 2")
eq(p.health.overlay:GetFrameLevel(), hl + 3, "glass overlay above both")

WoW.flushTimers()
eq(loss._value, 1240, "starts at current health (first paint snaps)")

-- Damage: health drops at once, the loss bar holds the old value, then eases.
WoW.units.player.health = 600
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(p.health._value, 600, "health bar follows at once")
eq(loss._value, 1240, "loss segment holds the lost health")
WoW.flushTimers()
eq(loss._value, 600, "then catches up")
eq(loss._interp, Enum.StatusBarInterpolation.ExponentialEaseOut, "eased, not snapped")

-- Steady damage: one timer at a time, and it applies the LATEST value, so the
-- segment keeps catching up instead of growing for the whole fight.
local before = #WoW.timers
for _, h in ipairs({ 550, 500, 450 }) do
    WoW.units.player.health = h
    WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
end
eq(#WoW.timers - before, 1, "one pending timer under steady damage")
WoW.flushTimers()
eq(loss._value, 450, "the timer applies the latest value")
WoW.units.player.health = 400
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(#WoW.timers, 1, "a new hit after the catch-up schedules again")
WoW.flushTimers()
eq(loss._value, 400, "and catches up again")

-- A max-health increase (buff, level) is not a loss: the range follows at once.
WoW.units.player.maxHealth = 2000
WoW.fire("UNIT_MAXHEALTH", "player"); WoW.tick()
eq(loss._max, 2000, "loss range follows max health immediately")
eq(p.health._max, 2000, "same range as the health bar")
WoW.flushTimers()

-- Death snaps: no red segment across a greyed-out frame.
WoW.units.player.health = 0
WoW.units.player.dead = true
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(loss._value, 0, "dead: loss bar snaps to the current value")
eq(#WoW.timers, 0, "no pending catch-up after death")
WoW.units.player.dead = false
WoW.units.player.health = 400

-- A new target snaps: nothing carried over from the previous unit.
local t = button("target")
WoW.units.target.health = 200
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()        -- a pending catch-up on the old target
WoW.SetUnit("target", { health = 300, maxHealth = 1000, guid = "other" })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(t.lossBar._value, 300, "new target: loss bar snaps with the health bar")
WoW.flushTimers()
eq(t.lossBar._value, 300, "the old target's pending value never lands")

-- Secret health goes straight through to the bar.
WoW.secretFields.health = true
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
WoW.flushTimers()
check(WoW.IsSecret(loss._value), "the loss bar received the secret value")
eq(next(GlassUF.paintFailures), nil, "secret health: no failures")

done("test_healthloss")
