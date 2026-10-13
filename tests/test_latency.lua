-- The player's cast bar extras (#72): the latency estimate (key press to
-- SENT, median of the last 7), its block, the pushback text, and the
-- interrupt flash's lifecycle (once per cast, only the newest cast).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
-- The Quartz extras (#78) have their own test: off here, so these keep
-- testing the plain bar ("1.2s", the spell name alone, hidden on STOP).
GlassUF.Castbar.options.totalTime, GlassUF.Castbar.options.targetName, GlassUF.Castbar.options.complete = false, false, false
local Castbar = GlassUF.Castbar
local lat = Castbar._test.lat
local c = button("player").cast
local tc = button("target").cast

check(c.lag ~= nil, "the player's cast bar has a latency block")
-- OverlayBar places only its clip frame: an unanchored block is 0x0 in game.
check(c.lag._points[1] and c.lag._points[1][1] == "ALL" and c.lag._points[1][2] == c.bar,
      "the block covers the cast bar")
check(tc.lag == nil, "the target's has none (other units' timing is never read)")
local trackers = GlassUF.Engine._test.trackers
check(trackers.player.registered.UNIT_SPELLCAST_SENT, "SENT registered for the player")
check(trackers.player.registered.UNIT_SPELLCAST_SUCCEEDED, "SUCCEEDED registered for the player")
check(not trackers.target.registered.UNIT_SPELLCAST_SENT, "SENT not registered for the target")

local n = 0
local function newGUID() n = n + 1; return "Cast-3-6782-2991-248205-2052-" .. n end
local function advance(s) WoW.now = WoW.now + s end
local function keyPress(cancelled)
    if cancelled == nil then cancelled = false end
    WoW.fire("CURRENT_SPELL_CAST_CHANGED", cancelled)
end
local function casting(g, extra)
    local t = { name = "Smite", guid = g, spellID = 2052, total = 2, remaining = 1.23, startMs = WoW.now * 1000,
                endMs = (WoW.now + 2) * 1000, delayMs = 0 }
    for k, v in pairs(extra or {}) do t[k] = v end
    WoW.units.player.casting = t
    return t
end
-- SENT and START in one frame, as measured.
local function start(g, extra)
    casting(g, extra)
    WoW.fire("UNIT_SPELLCAST_SENT", "player", "Target", g, 2052)
    local ev = (extra and extra.channel) and "UNIT_SPELLCAST_CHANNEL_START" or "UNIT_SPELLCAST_START"
    WoW.fire(ev, "player", g, 2052, "CastBar-1")
end
local function finish(g)
    WoW.units.player.casting = nil
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, 2052, "CastBar-1")
    WoW.fire("UNIT_SPELLCAST_STOP", "player", g, 2052, "CastBar-1")
end
local function instant(g)
    WoW.fire("UNIT_SPELLCAST_SENT", "player", "Target", g, 139)
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, 139)
end
-- One clean sample of `s` seconds, from an instant, then time moves on.
local function sample(s)
    keyPress()
    advance(s)
    instant(newGUID())
    advance(2)
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end

-- No sample yet: the GetNetStats fallback (world 33 ms), marked approximate.
local est, approx = Castbar.Latency()
check(near(est, 0.033) and approx == true, "fallback before any sample: GetNetStats world latency")

-- A START with no key press stamp: no sample, the block from the fallback.
local g1 = newGUID()
start(g1)
eq(#lat.samples, 0, "no stamp: no sample")
check(c.lag._shown, "block shown on START")
check(near(c.lag._value, 0.033 / 2), "block = fallback / total")
eq(c.lag._reverse, true, "a cast's block sits at the right (reverse fill)")
finish(g1)
check(not c.lag._shown, "block hidden when the cast ends")
advance(1)

-- A clean hard cast: key press, 0.14 s later SENT + START in one frame.
keyPress()
advance(0.14)
local g2 = newGUID()
start(g2)
eq(#lat.samples, 1, "one sample")
check(near(lat.samples[1], 0.14), "sample = key press to SENT")
est, approx = Castbar.Latency()
check(near(est, 0.14) and approx == false, "the estimate is the sample, not approximate")
check(near(c.lag._value, 0.07), "block = 0.14 / 2")

-- A queued cast: the previous one ends, and the next is SENT/STARTed in the
-- same frame, after the handoff's CAST_CHANGED(false): a 0 sample, rejected.
keyPress()
advance(0.3)
finish(g2)
keyPress()   -- the handoff frame's CAST_CHANGED, as measured
local g3 = newGUID()
start(g3)
eq(#lat.samples, 1, "queued cast (same frame as the previous end): no sample")
-- ...and the stamp it consumed can't feed a later SENT.
advance(0.5)
finish(g3)
advance(0.5)
local g4 = newGUID()
start(g4)
eq(#lat.samples, 1, "a rejected SENT still consumed the stamp")
finish(g4)
advance(1)

-- An unrelated SUCCEEDED in the SENT frame (Auto Shot) keeps a real sample.
keyPress()
advance(0.15)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-6782-2991-248205-75-1", 75)
local gw = newGUID()
start(gw)
eq(#lat.samples, 2, "a stray SUCCEEDED in the SENT frame doesn't reject the sample")
check(near(lat.samples[2], 0.15), "the sample is the key press to SENT")
finish(gw)
table.remove(lat.samples)
advance(1)

-- A stale stamp (over 1 s old) is no sample.
keyPress()
advance(1.5)
instant(newGUID())
eq(#lat.samples, 1, "stale stamp: no sample")
advance(1)

-- CAST_CHANGED(true) and an unrelated FAILED_QUIET-like FAILED don't drop
-- a pending stamp; an instant's sample survives its own SUCCEEDED.
keyPress()
advance(0.05)
keyPress(true)
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0-2052-0000000008", 2052)
advance(0.05)
instant(newGUID())
eq(#lat.samples, 2, "CAST_CHANGED(true) / a stray FAILED keep the stamp")
check(near(lat.samples[2], 0.10), "sample measured from the false stamp")
advance(1)

-- The estimate is the median of the last 7: a key press that waited out a
-- global cooldown (0.35) or a short one (0.06) doesn't move it.
lat.samples = {}
sample(0.10); sample(0.20)
check(near(Castbar.Latency(), 0.15), "even count during start-up: the mean of the two middles")
lat.samples = {}
for _, s in ipairs({ 0.14, 0.13, 0.35, 0.15, 0.06, 0.14, 0.30, 0.12 }) do sample(s) end
eq(#lat.samples, 7, "only the last 7 are kept")
check(near(Castbar.Latency(), 0.14), "median of the last 7")

-- A channel's block sits at the left: it drains toward it.
local gc = newGUID()
keyPress(); advance(0.14)
start(gc, { channel = true, name = "Mind Flay", endMs = (WoW.now + 3) * 1000, total = 3 })
eq(c.lag._reverse, false, "a channel's block sits at the left")
check(c.lag._shown, "block shown on a channel")

-- Channel pushback: the end moves earlier, shown as -0.5.
WoW.units.player.casting.endMs = WoW.units.player.casting.endMs - 500
WoW.fire("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", gc, 15407)
check(near(c.delay, 0.5), "channel pushback = how much earlier it ends")
WoW.tick(0.1)
eq(textOf(c.time), "|cffff4040-0.5|r 1.2s", "channel pushback shown as -0.5")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", gc, 15407)
advance(1)

-- Cast pushback: delayTimeMs is cumulative (measured 1000, 1800, 2400):
-- assigned, never added up, and a repeat changes nothing.
local gp = newGUID()
start(gp)
check(c.delay == nil, "no pushback at START")
local cast = WoW.units.player.casting
cast.delayMs = 1000
WoW.fire("UNIT_SPELLCAST_DELAYED", "player", gp, 2052)
check(near(c.delay, 1.0), "first pushback 1.0")
cast.delayMs = 1800
WoW.fire("UNIT_SPELLCAST_DELAYED", "player", gp, 2052)
WoW.fire("UNIT_SPELLCAST_DELAYED", "player", gp, 2052)
check(near(c.delay, 1.8), "cumulative 1.8, not 2.8 or 4.6")
WoW.tick(0.1)
eq(textOf(c.time), "|cffff4040+1.8|r 1.2s", "pushback before the time")
-- A rejected attempt's FAILED while the cast carries on keeps the pushback.
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0-17-0000000012", 17)
check(near(c.delay, 1.8), "a stray FAILED keeps the pushback")
eq(textOf(c.spell), "Smite", "and the cast")
-- The option off: the plain time.
GlassUF.Settings.SetCastOption("pushback", false)
WoW.tick(0.1)
eq(textOf(c.time), "1.2s", "pushback text off")
eq(GlassUnitFramesDB.castPushback, false, "saved when off")
GlassUF.Settings.SetCastOption("pushback", true)
eq(GlassUnitFramesDB.castPushback, nil, "forgotten when back on")
finish(gp)
advance(1)
-- A new cast starts with no pushback.
local gq = newGUID()
start(gq)
check(c.delay == nil, "a new cast resets the pushback")
WoW.tick(0.1)
eq(textOf(c.time), "1.2s", "no pushback text on the new cast")
finish(gq)
advance(1)

-- A pushed-back cast's STOP forgets the pushback: a cast painted later
-- without a START (a full repaint) shows none.
local gr = newGUID()
start(gr)
WoW.units.player.casting.delayMs = 1000
WoW.fire("UNIT_SPELLCAST_DELAYED", "player", gr, 2052)
check(near(c.delay, 1.0), "pushed back")
-- A late STOP of an older cast leaves it.
WoW.fire("UNIT_SPELLCAST_STOP", "player", gq, 2052, "CastBar-1")
check(near(c.delay, 1.0), "an older cast's late STOP keeps the live pushback")
finish(gr)
check(c.delay == nil, "the newest cast's STOP clears the pushback")
casting(newGUID())
GlassUF.Engine.FullRepaint(button("player")); WoW.tick(0.1)
eq(textOf(c.time), "1.2s", "a cast seen only by a full repaint: no stale pushback")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player")
advance(1)

-- The latency option off hides the block, mid-cast.
local gl = newGUID()
start(gl)
check(c.lag._shown, "block shown")
GlassUF.Settings.SetCastOption("latency", false)
WoW.tick()
check(not c.lag._shown, "block hidden once the option is off")
eq(GlassUnitFramesDB.castLatency, false, "latency off saved")
GlassUF.Settings.SetCastOption("latency", true)
WoW.tick()
check(c.lag._shown, "block back")
finish(gl)
advance(1)

-- Secret timing (never measured for the player, but guarded): no block, no
-- pushback, no failure.
WoW.secretFields.castTimes = true
local gs = newGUID()
start(gs)
check(not c.lag._shown, "secret timing: no block")
WoW.units.player.casting.delayMs = 1000
WoW.fire("UNIT_SPELLCAST_DELAYED", "player", gs, 2052)
check(c.delay == nil, "secret delay: no pushback")
WoW.tick(0.1)
eq(textOf(c.time), "1.2s", "secret delay: plain time")
WoW.secretFields.castTimes = nil
finish(gs)
advance(1)

--------------------------------------------------------------------------------
-- The interrupt flash (measured: the first INTERRUPTED still has the cast
-- live, STOP follows, then repeats of the INTERRUPTED).
--------------------------------------------------------------------------------

-- Once per cast: the repeats don't restart it, nor bring it back.
local ga = newGUID()
start(ga)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", ga, 2052, nil, "CastBar-1")
eq(textOf(c.spell), "Smite", "first INTERRUPTED with the cast live: still the cast")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", ga, 2052, "CastBar-1")
check(not c.host._shown, "hidden on STOP")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", ga, 2052, nil, nil)
check(c.host._shown and textOf(c.spell) == "Interrupted", "the first repeat flashes")
local token = c.token
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", ga, 2052, nil, nil)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", ga, 2052, nil, nil)
eq(c.token, token, "later repeats leave the flash's token (and expiry) alone")
WoW.flushTimers()
check(not c.host._shown, "flash gone after its timer")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", ga, 2052, nil, nil)
check(not c.host._shown, "a late repeat doesn't bring it back")

-- A repeat while a newer cast is live: the newer cast stays.
local gb = newGUID()
start(gb)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", ga, 2052, nil, nil)
check(c.host._shown and textOf(c.spell) == "Smite", "an older cast's repeat leaves the live cast")
finish(gb)
check(not c.host._shown, "hidden after the newer cast")

-- The newer cast starts AND ends before the old repeat arrives: no flash.
local gx = newGUID()
start(gx)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", gx, 2052, nil, "CastBar-1")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", gx, 2052, "CastBar-1")
local gy = newGUID()
start(gy)
finish(gy)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", gx, 2052, nil, nil)
check(not c.host._shown, "a superseded cast's repeat can't flash")

-- A rejected attempt (client-side guid) with nothing casting: no flash.
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0-17-0000000013", 17)
check(not c.host._shown, "a rejected attempt doesn't flash")

-- An instant the server refuses after SENT (no START) still flashes.
local gi = newGUID()
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Target", gi, 139)
WoW.fire("UNIT_SPELLCAST_FAILED", "player", gi, 139)
check(c.host._shown and textOf(c.spell) == "Failed", "a SENT instant's FAILED flashes")
WoW.flushTimers()

-- FAILED at the end of the newest cast still flashes (once).
local gz = newGUID()
start(gz)
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_FAILED", "player", gz, 2052, "CastBar-1")
check(c.host._shown and textOf(c.spell) == "Failed", "the newest cast's FAILED flashes")
WoW.flushTimers()

-- The target: a new unit behind the token isn't held to the old one's guid.
local t1, t2 = newGUID(), newGUID()
WoW.units.target.casting = { name = "Fireball" }
WoW.fire("UNIT_SPELLCAST_START", "target", t1, 133)
eq(tc.latestGUID, t1, "the target's newest cast")
WoW.SetUnit("target", { name = "Mage", reaction = 2, casting = { name = "Frostbolt" } })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", t2, 116)
check(tc.host._shown and textOf(tc.spell) == "Interrupted",
      "a cast begun before the target change still flashes when kicked")
-- ...and its repeats don't restart it, though its newest guid is unknown.
local ttoken = tc.token
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", t2, 116)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", t2, 116)
eq(tc.token, ttoken, "repeats after a mid-cast target switch leave the flash alone")
WoW.flushTimers()

-- An ordinary full repaint (an option change) is no new unit: the target's
-- newest guid survives it, and an interrupt's repeats flash once.
local t3 = newGUID()
WoW.units.target.casting = { name = "Fireball" }
WoW.fire("UNIT_SPELLCAST_START", "target", t3, 133)
GlassUF.Settings.SetCastOption("pushback", false); WoW.tick()
GlassUF.Settings.SetCastOption("pushback", true); WoW.tick()
eq(tc.latestGUID, t3, "an ordinary repaint keeps the newest guid")
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "target", t3, 133)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", t3, 133)
ttoken = tc.token
check(tc.host._shown, "the first repeat flashes")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", t3, 133)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", t3, 133)
eq(tc.token, ttoken, "later repeats after an ordinary repaint don't restart it")
WoW.flushTimers()

eq(next(GlassUF.paintFailures), nil, "no paint failures")
done("test_latency")
