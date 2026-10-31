-- The mirror timers (#151): breath, fatigue and feign death as glass rows on
-- an always-detached pill, the custom-timer hook, Blizzard's container hidden
-- without a reparent, the option, the unlock and preview samples. Built
-- offline; the client's values may be secret (unmeasured), so they must only
-- ever reach the client.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local Castbar, Mirror, S = GlassUF.Castbar, GlassUF.Mirror, GlassUF.Settings
local T = Mirror._test
local c = Castbar.bars.mirror
local rows = T.rows
local function rowOf(label)
    for _, r in ipairs(rows) do if r.timer and r.bar._shown and textOf(r.label) == label then return r end end
end
local function start(name, value, max, paused, label)
    WoW.mirror[name] = { index = 1, value = value, max = max, paused = paused or 0, label = label or name }
    WoW.fire("MIRROR_TIMER_START", name, value, max, -1, paused or 0, label or name)
end

check(c ~= nil, "the mirror pill is a bar of Castbar's")
check(not c.host._shown, "hidden with no timer")
check(Castbar.IsDetached("mirror"), "always detached")
eq(Castbar.SetDetached("mirror", false), false, "it can't be attached")
eq(Castbar.MoverSource("mirror").attach, nil, "its mover has no Attach")
local x, y, w = Castbar.EffectiveGeometry("mirror")
eq(x, 0, "default spot: centred")
eq(y, 270, "near the top, where Blizzard's sit")
eq(w, 220, "default width")

-- Blizzard's container: silenced and hidden, never reparented (an Edit Mode system).
local mc = rawget(_G, "MirrorTimerContainer")
check(not mc._shown, "Blizzard's mirror timers hidden")
check(mc._events.MIRROR_TIMER_START == nil, "and silenced")
eq(mc:GetParent(), UIParent, "and left under its parent")

-- Breath: the client's values straight to the bar, the seconds when plain.
start("BREATH", 60000, 60000, 0, "Breath")
check(c.host._shown, "a timer shows the pill")
local br = rowOf("Breath")
check(br ~= nil, "a Breath row")
eq(br.bar._max, 60000, "maxValue to SetMinMaxValues as is")
eq(br.bar._color[1], Mirror.COLORS.BREATH[1], "breath's colour")
WoW.mirror.BREATH.value = 39500
WoW.tick(0.1)
eq(br.bar._value, 39500, "GetMirrorTimerProgress to SetValue")
eq(textOf(br.time), "40", "the seconds left")
-- Paused: no updates; resumed: again.
WoW.fire("MIRROR_TIMER_PAUSE", "BREATH", 1)
WoW.mirror.BREATH.value = 20000
WoW.tick(0.1)
eq(br.bar._value, 39500, "paused: the bar holds")
WoW.fire("MIRROR_TIMER_PAUSE", "BREATH", 0)
WoW.tick(0.1)
eq(br.bar._value, 20000, "resumed: it moves again")

-- A second timer stacks under the first; the pill grows.
local h1 = c.host._height
start("EXHAUSTION", 30000, 60000, 0, "Fatigue")
local ex = rowOf("Fatigue")
check(ex ~= nil and ex ~= br, "a second row")
check(c.host._height > h1, "the pill grows")
-- Breath stops: fatigue moves up, the pill shrinks back; then nothing.
WoW.mirror.BREATH = nil
WoW.fire("MIRROR_TIMER_STOP", "BREATH")
check(rows[1].timer and textOf(rows[1].label) == "Fatigue", "the first row is fatigue now")
eq(c.host._height, h1, "one row's height again")
WoW.mirror.EXHAUSTION = nil
WoW.fire("MIRROR_TIMER_STOP", "EXHAUSTION")
check(not c.host._shown, "no timer: hidden")

-- Secret values: still to the client, no seconds, no failure.
WoW.secretFields.mirror = true
WoW.mirror.BREATH = { index = 1, value = 60000, max = 60000 }
WoW.fire("MIRROR_TIMER_START", "BREATH", WoW.Secret("value"), WoW.Secret("max"), -1, WoW.Secret("paused"), "Breath")
br = rowOf("Breath")
check(br ~= nil, "secret values: the row shows")
check(GlassUF.API.IsSecret(br.bar._max), "the secret max handed to the client")
WoW.tick(0.1)
check(GlassUF.API.IsSecret(br.bar._value), "the secret progress handed to the client")
eq(textOf(br.time), "", "no seconds from a secret")
WoW.secretFields.mirror = nil
WoW.mirror.BREATH = nil
WoW.fire("MIRROR_TIMER_STOP", "BREATH")
eq(next(GlassUF.paintFailures), nil, "no failures on the secret path")
-- A name we can't read can't key a row: skipped and recorded.
WoW.fire("MIRROR_TIMER_START", WoW.Secret("name"), 1, 1, -1, 0, "Breath")
check(not c.host._shown, "a secret name: no row")
check(GlassUF.paintFailures["mirror timer"] ~= nil, "recorded for /glass secrets")
GlassUF.paintFailures["mirror timer"] = nil

-- A loading screen or /reload: the live timers rebuilt from GetMirrorTimerInfo.
WoW.mirror.FEIGNDEATH = { index = 2, value = 300000, max = 360000, label = "Feign Death" }
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(rowOf("Feign Death") ~= nil, "rebuilt at world entry")
WoW.mirror.FEIGNDEATH = nil
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(not c.host._shown, "and gone when the client has none")

-- The custom-timer hook.
eq(Mirror.Start("pull", "Pull", 10), true, "a custom timer starts")
local pull = rowOf("Pull")
check(pull ~= nil, "on the same pill")
check(pull.bar._timer and pull.bar._timer.duration:GetTotalDuration() == 10, "a duration we own, to the client")
eq(pull.bar._timer.dir, Enum.StatusBarTimerDirection.RemainingTime, "it drains")
WoW.tick(0.1)
eq(textOf(pull.time), "10", "its seconds")
WoW.now = WoW.now + 10.1
WoW.tick(0.1)
check(not c.host._shown, "it ends on its own")
Mirror.Start("pull", "Pull", 10)
eq(Mirror.Stop("pull"), true, "and stops on request")
check(not c.host._shown, "stopped: hidden")
for _, bad in ipairs({ { nil, "x", 5 }, { "a", "", 5 }, { "a", "x", 0 }, { "a", "x", WoW.Secret("s") }, { "a", "x", 1e9 } }) do
    eq(Mirror.Start(bad[1], bad[2], bad[3]), false, "bad arguments refused")
end
eq(Mirror.Stop("nothing"), false, "stopping an unknown id: false")

-- Rows shift: each bar is bound again to the timer it now shows (Codex, #163).
-- Two custom timers, the first stopped: row 1 shows B's own duration.
Mirror.Start("a", "A", 30)
Mirror.Start("b", "B", 12)
local bDur = rowOf("B").bar._timer.duration
Mirror.Stop("a")
eq(textOf(rows[1].label), "B", "B moved up to row 1")
eq(rows[1].bar._timer.duration, bDur, "row 1's fill is B's duration, not A's")
eq(rows[1].bar._timer.duration:GetTotalDuration(), 12, "B's length")
-- A paused mirror timer moving into a row that held a custom timer: its own max and held value.
start("BREATH", 60000, 60000, 0, "Breath")      -- row 2, under B
WoW.mirror.BREATH.value = 41000
WoW.tick(0.1)
WoW.fire("MIRROR_TIMER_PAUSE", "BREATH", 1)
WoW.mirror.BREATH.value = 5000                    -- the client moves on; a paused row doesn't
Mirror.Stop("b")
local moved = rows[1]
eq(moved.timer and moved.timer.mirror, "BREATH", "breath moved up to row 1")
eq(moved.bar._max, 60000, "its own max on the bar")
eq(moved.bar._value, 41000, "its held value, not B's fill")
eq(textOf(moved.time), "41", "and its seconds")
WoW.fire("MIRROR_TIMER_PAUSE", "BREATH", 0)
WoW.tick(0.1)
eq(moved.bar._value, 5000, "resumed: live again")
-- A custom timer moving into a row that held a mirror timer: timer-bound again.
Mirror.Start("c", "C", 20)                        -- row 2
WoW.mirror.BREATH = nil
WoW.fire("MIRROR_TIMER_STOP", "BREATH")
eq(textOf(rows[1].label), "C", "C moved up to row 1")
eq(rows[1].bar._timer.duration:GetTotalDuration(), 20, "row 1 bound to C's duration")
Mirror.Stop("c")
check(not c.host._shown, "all stopped: hidden")

-- The option: off drops the rows and the events, saved; on rebuilds.
start("BREATH", 60000, 60000, 0, "Breath")
S.SetMirrorTimers(false)
check(not c.host._shown, "off: hidden")
eq(GlassUnitFramesDB.mirrorTimers, false, "off is saved")
check(c.events._events.MIRROR_TIMER_START == nil, "off: unregistered")
eq(Mirror.Start("pull", "Pull", 10), false, "off: no custom timer either")
S.SetMirrorTimers(true)
eq(GlassUnitFramesDB.mirrorTimers, nil, "on: nothing saved")
check(rowOf("Breath") ~= nil, "on: the live timer comes back")
WoW.mirror.BREATH = nil
WoW.fire("MIRROR_TIMER_STOP", "BREATH")

-- Unlocked: a sample so the pill has a size to drag, and a mover.
check(GlassUF.Movers.Unlock(), "unlocked")
check(c.host._shown and rows[1].timer == T.SAMPLE, "the sample row while unlocked")
check(GlassUF.Movers._test.sources["cast:mirror"] ~= nil, "a mover for it")
GlassUF.Movers.Lock()
check(not c.host._shown, "locked: hidden again")
-- Preview: the sample too.
GlassUF.Preview.Start()
check(c.host._shown and rows[1].timer == T.SAMPLE, "the sample row in a preview")
GlassUF.Preview.Stop()
check(not c.host._shown, "the preview over: hidden")
-- A live timer beats the sample.
GlassUF.Preview.Start()
start("BREATH", 60000, 60000, 0, "Breath")
check(rows[1].timer ~= T.SAMPLE and rows[1].timer.mirror == "BREATH", "a live timer replaces the sample")
GlassUF.Preview.Stop()
eq(next(GlassUF.paintFailures), nil, "no paint failures")

done("test_mirror")
