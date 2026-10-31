-- The cast bar's roadmap extras, built offline before their in-game check:
-- who interrupted a cast (#150), the out-of-range colour (#152) and the
-- global cooldown line (#149). Each must stay quiet (the old look) whenever
-- the client's answer is absent, secret or unknown.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
-- Docked bars: the player's 14 px row, the target's pill.
loadAddon({ db = { castBars = { player = { detached = false }, target = { detached = false } } } })
local Castbar, S = GlassUF.Castbar, GlassUF.Settings
local T = Castbar._test
local pc, tc = button("player").cast, button("target").cast
local CAST = Castbar.DEFAULT_COLORS.cast
local n = 0
local function guid() n = n + 1; return "Cast-3-1-1-1-2061-" .. n end
local function cast(unit, g, extra)
    local t = { name = "Greater Heal", guid = g, spellID = 2061, total = 2.5, remaining = 1.2,
                startMs = WoW.now * 1000, endMs = (WoW.now + 2.5) * 1000, delayMs = 0 }
    for k, v in pairs(extra or {}) do t[k] = v end
    WoW.units[unit].casting = t
    if unit == "player" then WoW.fire("UNIT_SPELLCAST_SENT", "player", (extra and extra.sentTo) or "", g, 2061) end
    WoW.fire(t.channel and "UNIT_SPELLCAST_CHANNEL_START" or "UNIT_SPELLCAST_START", unit, g, 2061, "CastBar-1")
end
local function sameColor(bar, col) return bar._color[1] == col[1] and bar._color[2] == col[2] and bar._color[3] == col[3] end

--------------------------------------------------------------------------------
-- #150: "Interrupted by <name>"
--------------------------------------------------------------------------------

-- A visible unit: its token's name. The flash starts on a repeat after the STOP.
local g1 = guid()
cast("target", g1)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g1, 2061, "GUID-Morphisto", "CastBar-1")   -- cast still live
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "target", g1, 2061, "CastBar-1")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g1, 2061, nil, nil)                      -- a repeat
eq(textOf(tc.spell), "Interrupted by Morphisto", "the interrupter seen by a token (the player)")
WoW.flushTimers()

-- Not on any token: GetPlayerInfoByGUID's name.
WoW.players["Player-1-0042"] = { name = "Karuzo" }
local g2 = guid()
cast("target", g2)
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g2, 2061, "Player-1-0042", "CastBar-1")
eq(textOf(tc.spell), "Interrupted by Karuzo", "a player's name from the GUID")
WoW.flushTimers()

-- An NPC nobody targets, nil, empty or secret: the plain text, as before.
for _, by in ipairs({ "Creature-0-1-1-1-2000-1", "", WoW.Secret("interruptedBy") }) do
    local g = guid()
    cast("target", g)
    WoW.units.target.casting = nil
    WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g, 2061, by, "CastBar-1")
    eq(textOf(tc.spell), "Interrupted", "no name to give: plain Interrupted")
    WoW.flushTimers()
end
local g3 = guid()
cast("target", g3)
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g3, 2061)
eq(textOf(tc.spell), "Interrupted", "no interruptedBy at all (the 70338 trace)")
WoW.flushTimers()

-- A channel: the name can come with its CHANNEL_STOP, after the flash began.
local g4 = guid()
cast("target", g4, { channel = true })
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g4, 2061, nil, "CastBar-1")
eq(textOf(tc.spell), "Interrupted", "the flash before the name is known")
WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "target", g4, 2061, "GUID-Morphisto", "CastBar-1")
eq(textOf(tc.spell), "Interrupted by Morphisto", "the flash up for that cast gets the name")
WoW.flushTimers()

-- An older cast's interrupter never names a newer cast's flash.
local g5, g6 = guid(), guid()
cast("target", g5)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g5, 2061, "GUID-Morphisto", "CastBar-1")
cast("target", g6)
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", g6, 2061, nil, "CastBar-1")
eq(textOf(tc.spell), "Interrupted", "a new START forgets the last interrupter")
WoW.flushTimers()
eq(next(GlassUF.paintFailures), nil, "no paint failures on the interrupter paths")

--------------------------------------------------------------------------------
-- #152: the out-of-range colour
--------------------------------------------------------------------------------

local RANGE = T.RANGE_COLOR
local function settle() WoW.tick(T.RANGE_EVERY + 0.05) end
local function stopPlayer(g)
    WoW.units.player.casting = nil
    WoW.fire("UNIT_SPELLCAST_STOP", "player", g, 2061, "CastBar-1")
    WoW.flushTimers()
end

-- Cast at the target (SENT names it): out of range dims the bar, back in restores it.
WoW.inRange.target = false
local r1 = guid()
cast("player", r1, { sentTo = "Defias Pillager" })
check(sameColor(pc.bar, CAST), "the cast colour at START")
settle()
check(sameColor(pc.bar, RANGE), "out of range: dimmed")
eq(WoW.rangeAsked[#WoW.rangeAsked][1], 2061, "asked about the cast's spell")
eq(WoW.rangeAsked[#WoW.rangeAsked][2], "target", "for the unit SENT named")
WoW.inRange.target = true
settle()
check(sameColor(pc.bar, CAST), "back in range: the cast colour")
-- Unknown is never out of range; neither is a secret or a throw.
for _, v in ipairs({ "secret", "error" }) do
    WoW.inRange.target = false; settle()
    WoW.inRange.target = v; settle()
    check(sameColor(pc.bar, CAST), "IsSpellInRange " .. v .. ": not out of range")
end
WoW.inRange.target = nil; settle()
check(sameColor(pc.bar, CAST), "nil: not out of range")
-- A full repaint mid-cast keeps the dimmed colour.
WoW.inRange.target = false; settle()
GlassUF.Engine.FullRepaint(button("player")); WoW.tick()
check(sameColor(pc.bar, RANGE), "a repaint keeps the out-of-range colour")
-- The target changes mid-cast: the new one is never tested.
WoW.SetUnit("target", { name = "Kobold", guid = "GUID-Kobold", reaction = 2 })
local asked = #WoW.rangeAsked
settle()
check(sameColor(pc.bar, CAST), "another unit behind the token: the cast colour")
eq(#WoW.rangeAsked, asked, "and it isn't asked about")
stopPlayer(r1)
standardUnits()

-- The focus as the recipient.
WoW.inRange.focus = false
local r2 = guid()
cast("player", r2, { sentTo = "Hogger" })
settle()
eq(WoW.rangeAsked[#WoW.rangeAsked][2], "focus", "the focus when SENT named it")
check(sameColor(pc.bar, RANGE), "the focus out of range: dimmed")
stopPlayer(r2)

-- A self-cast, or a name that is neither target nor focus: never asked.
WoW.inRange.target, WoW.inRange.focus = false, false
asked = #WoW.rangeAsked
for _, to in ipairs({ "", "Morphisto", "Someone Else" }) do
    local r = guid()
    cast("player", r, { sentTo = to })
    settle()
    check(sameColor(pc.bar, CAST), "no recipient (" .. to .. "): the cast colour")
    stopPlayer(r)
end
eq(#WoW.rangeAsked, asked, "no recipient: IsSpellInRange never asked")

-- The option: off restores the colour at once and is saved; on again dims.
local r3 = guid()
cast("player", r3, { sentTo = "Defias Pillager" })
settle()
check(sameColor(pc.bar, RANGE), "dimmed before the option goes off")
S.SetCastOption("range", false); WoW.tick()
check(sameColor(pc.bar, CAST), "off: the cast colour on the next repaint")
eq(GlassUnitFramesDB.castRange, false, "off is saved")
settle()
check(sameColor(pc.bar, CAST), "off: stays the cast colour")
S.SetCastOption("range", true)
eq(GlassUnitFramesDB.castRange, nil, "on: nothing saved")
settle()
check(sameColor(pc.bar, RANGE), "on again: dimmed")
stopPlayer(r3)
WoW.inRange.target, WoW.inRange.focus = nil, nil
eq(next(GlassUF.paintFailures), nil, "no paint failures on the range paths")

--------------------------------------------------------------------------------
-- #149: the GCD line
--------------------------------------------------------------------------------

local g = pc.gcd
check(g ~= nil, "the player's bar has a GCD line")
check(tc.gcd == nil, "no other bar has one")
check(T.gcdFrame._events.SPELL_UPDATE_COOLDOWN, "SPELL_UPDATE_COOLDOWN registered while the option is on")
check(not g._shown, "hidden with no GCD")
eq(g._points[1][2], button("player").power, "docked: along the power bar")
eq(g._points[1][1], "TOPLEFT", "its top edge (the five-second rule owns the bottom)")

-- An instant on the GCD: the spell just sent answers.
WoW.cooldowns[2061] = { isActive = true, isOnGCD = true, start = WoW.now, duration = 1.5 }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 2061)
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(g._shown, "shown for the GCD, with no cast")
eq(g._timer.dir, Enum.StatusBarTimerDirection.ElapsedTime, "it fills as the GCD runs")
eq(g._timer.duration:GetTotalDuration(), 1.5, "the spell's GCD duration, straight to the client")
WoW.now = WoW.now + 1.49; WoW.runDue()
check(g._shown, "still shown before the GCD ends")
WoW.now = WoW.now + 0.02; WoW.runDue()
check(not g._shown, "hidden when it ends")

-- A spell with a cooldown of its own (isOnGCD false), a stale SENT, no answer: nothing.
WoW.cooldowns[8092] = { isActive = true, isOnGCD = false, start = WoW.now, duration = 8 }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 8092)
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(not g._shown, "a spell on its own cooldown: no GCD line")
WoW.cooldowns[2061] = { isActive = true, isOnGCD = true, start = WoW.now, duration = 1.5 }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 2061)
WoW.now = WoW.now + 0.6
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(not g._shown, "an update long after the SENT: not that spell's GCD")
WoW.cooldowns[2061] = "error"
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 2061)
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(not g._shown, "GetSpellCooldown throwing: nothing")

-- The GCD spell (61304), should it ever read active: no SENT needed.
WoW.cooldowns[2061] = nil
WoW.cooldowns[GlassUF.API.GCD_SPELL] = { isActive = true, start = WoW.now, duration = 1.5 }
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(g._shown, "the GCD spell active: shown")
WoW.now = WoW.now + 2; WoW.runDue()
WoW.cooldowns[GlassUF.API.GCD_SPELL] = nil

-- A secret remaining time: still drawn by the client, hidden after Vanilla's GCD.
WoW.cooldowns[2061] = { isActive = true, isOnGCD = true, start = WoW.now, duration = 1.5, secret = true }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 2061)
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(g._shown, "a secret duration still shows")
WoW.now = WoW.now + T.GCD_MAX + 0.01; WoW.runDue()
check(not g._shown, "and hides after the GCD's length")

-- A new GCD while one shows: the old one's hide never lands early.
WoW.cooldowns[2061] = { isActive = true, isOnGCD = true, start = WoW.now, duration = 1.5 }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 2061)
WoW.fire("SPELL_UPDATE_COOLDOWN")
WoW.now = WoW.now + 1.0
WoW.cooldowns[2061] = { isActive = true, isOnGCD = true, start = WoW.now, duration = 1.5 }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 2061)
WoW.fire("SPELL_UPDATE_COOLDOWN")
WoW.now = WoW.now + 0.6; WoW.runDue()
check(g._shown, "the first GCD's hide doesn't end the second")
WoW.now = WoW.now + 1; WoW.runDue()
check(not g._shown, "the second ends on its own time")

-- Detached: along the bar's bottom.
S.SetCastDetached("player", true)
eq(g._points[1][2], pc.bar, "detached: on the bar")
eq(g._points[1][1], "BOTTOMLEFT", "along its bottom")
S.SetCastDetached("player", false)

-- The option off: unregistered, hidden, saved.
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", guid(), 2061)
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(g._shown, "shown before the option goes off")
S.SetCastOption("gcd", false)
check(not g._shown, "off: hidden at once")
check(not T.gcdFrame._events.SPELL_UPDATE_COOLDOWN, "off: the event is unregistered")
eq(GlassUnitFramesDB.castGCD, false, "off is saved")
S.SetCastOption("gcd", true)
check(T.gcdFrame._events.SPELL_UPDATE_COOLDOWN, "on: registered again")
eq(GlassUnitFramesDB.castGCD, nil, "on: nothing saved")
eq(next(GlassUF.paintFailures), nil, "no paint failures on the GCD paths")

done("test_castextras")
