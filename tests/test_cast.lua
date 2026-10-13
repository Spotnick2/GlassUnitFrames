-- Cast bar: DurationObject timing, directions, stop, interrupt flash.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
-- The Quartz extras (#78) have their own test: off here, so these keep
-- testing the plain bar ("1.2s", the spell name alone, hidden on STOP).
GlassUF.Castbar.options.totalTime, GlassUF.Castbar.options.targetName, GlassUF.Castbar.options.complete = false, false, false
local c = button("target").cast
check(not c.host._shown, "cast pill hidden with no cast")

WoW.units.target.casting = { name = "Fireball", remaining = 1.23 }
WoW.fire("UNIT_SPELLCAST_START", "target")
check(c.host._shown, "cast pill shown on START")
eq(c.bar._timer.dir, Enum.StatusBarTimerDirection.ElapsedTime, "cast fills with elapsed time")
eq(textOf(c.spell), "Fireball", "spell name")
eq(c.bar._color[1], 0.95, "cast colour")
WoW.tick(0.1)
eq(textOf(c.time), "1.2s", "time text from GetRemainingDuration")

WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "target")
check(not c.host._shown, "hidden on STOP")

WoW.units.target.casting = { name = "Arcane Missiles", channel = true }
WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "target")
eq(c.bar._timer.dir, Enum.StatusBarTimerDirection.RemainingTime, "channel drains with remaining time")
eq(c.bar._color[1], 0.40, "channel colour")

-- Interrupt: red flash that survives the STOP that follows, gone after the timer.
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target")
WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "target")
check(c.host._shown, "interrupt flash survives the following STOP")
eq(textOf(c.spell), "Interrupted", "interrupt text")
eq(c.bar._color[1], 0.85, "interrupt colour")
WoW.flushTimers()
check(not c.host._shown, "flash hidden after the timer")

-- A new cast during the flash is not hidden by the old timer.
WoW.fire("UNIT_SPELLCAST_FAILED", "target")
WoW.units.target.casting = { name = "Fireball" }
WoW.fire("UNIT_SPELLCAST_START", "target")
WoW.flushTimers()
check(c.host._shown, "a new cast outlives the previous flash's timer")

-- Switching target mid-cast shows the new target's cast (or none).
WoW.SetUnit("target", { name = "Kobold", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(not c.host._shown, "new target not casting: pill hidden")
WoW.SetUnit("target", { name = "Mage", reaction = 2, casting = { name = "Frostbolt" } })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(c.host._shown, "new target already casting: pill shown")
eq(textOf(c.spell), "Frostbolt", "new target's spell")

-- Review regressions (PR #2, Codex):
-- A FAILED for a rejected attempt must not replace a cast that carries on.
WoW.SetUnit("target", { name = "Mage", reaction = 2, casting = { name = "Frostbolt" } })
WoW.fire("UNIT_SPELLCAST_START", "target")
WoW.fire("UNIT_SPELLCAST_FAILED", "target")
eq(textOf(c.spell), "Frostbolt", "FAILED during an ongoing cast keeps the cast")
WoW.flushTimers()
check(c.host._shown, "ongoing cast still shown after the old timer")

-- A queued full repaint must not erase an interrupt flash.
WoW.units.target.casting = nil
GlassUF.Engine.FullRepaint(button("target"))
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target")
WoW.tick()                                   -- the queued repaint flushes now
check(c.host._shown, "flash survives a queued full repaint")
eq(textOf(c.spell), "Interrupted", "flash text intact")
WoW.flushTimers()
check(not c.host._shown, "flash gone after its timer")

-- Colour is applied after the timer is attached.
WoW.units.target.casting = { name = "Fireball" }
local order = {}
local bar = c.bar
local realTimer, realColor = bar.SetTimerDuration, bar.SetStatusBarColor
rawset(bar, "SetTimerDuration", function(self, ...) order[#order + 1] = "timer"; return realTimer(self, ...) end)
rawset(bar, "SetStatusBarColor", function(self, ...) order[#order + 1] = "color"; return realColor(self, ...) end)
WoW.fire("UNIT_SPELLCAST_START", "target")
eq(table.concat(order, ","), "timer,color", "colour re-applied after SetTimerDuration")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
done("test_cast")
