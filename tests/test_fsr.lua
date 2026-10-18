-- The five-second rule (#94): a 2 px red strip on the player's mana bar,
-- draining for 5 s after a spell that costs mana. No tick timer (regen on
-- Forever is continuous). Mana is never read: the spend comes from the
-- spell's cost, full mana from a client curve.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local MANA_SPELL, FREE, RAGE_SPELL, NO_TABLE = 686, 100, 78, 836
local function costs()
    WoW.spellCosts[MANA_SPELL] = { { type = 0, cost = 25, minCost = 25 } }
    WoW.spellCosts[FREE] = { { type = 0, cost = 0, minCost = 0 } }
    WoW.spellCosts[RAGE_SPELL] = { { type = 1, cost = 15, minCost = 15 } }
end

-- A warlock (the standard units): mana 920 / 1270.
standardUnits()
costs()
loadAddon()
local F = GlassUF.FiveSecond
local T = F._test
local st = T.state
local pl = button("player")
local strips = T.strips()
check(strips and strips.power, "a mana user gets the strip on the power bar")
check(strips.druid == nil, "no druid strip for a warlock")
local strip = strips.power
local bar, clip = strip.bar, strip.clip
eq(bar:GetHeight(), 2, "2 px tall")
eq(bar._points[1][1], "BOTTOMLEFT", "along the bottom edge")
eq(bar._points[1][2], pl.power, "of the power bar")
check(not clip._shown, "hidden while idle")

local function adv(s) WoW.now = WoW.now + s; WoW.runDue() end
local function cast(id) WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", id) end
local function mana() WoW.fire("UNIT_POWER_UPDATE", "player", "MANA") end
local function combat(on)
    WoW.combat = on
    WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
local function dur() return T.dur() end
local REMAINING = Enum.StatusBarTimerDirection.RemainingTime
local function settle() adv(30); T.reset() end   -- let every timer lapse

-- The cost test: what counts as a spend.
check(T.costsMana(MANA_SPELL), "a mana cost is a spend")
check(not T.costsMana(FREE), "a plain 0 mana cost isn't")
check(not T.costsMana(RAGE_SPELL), "a rage cost isn't")
check(not T.costsMana(NO_TABLE), "no cost table isn't")
WoW.spellCosts[901] = { { type = 0, cost = 0, costPerSec = 12 } }
check(T.costsMana(901), "a channel's mana per second is a spend")
WoW.spellCosts[902] = { { type = 0, cost = WoW.Secret("cost") } }
check(T.costsMana(902), "a secret amount in a mana entry counts")
WoW.spellCosts[903] = WoW.Secret("costs")
check(not T.costsMana(903), "a secret cost table is unknown: no spend")
WoW.spellCosts[904] = { WoW.Secret("entry") }
check(not T.costsMana(904), "a secret entry is unknown: no spend")
WoW.spellCosts[905] = { { type = WoW.Secret("type"), cost = 25 } }
check(not T.costsMana(905), "a secret power type isn't read as mana")
WoW.spellCosts[906] = "error"
check(not T.costsMana(906), "a throwing GetSpellPowerCost is no spend")
check(not T.costsMana(WoW.Secret("spellID")), "a secret spellID is no spend")
WoW.spellCosts[907] = { { type = 1, cost = 10 }, { type = 0, cost = 30 } }
check(T.costsMana(907), "a mana entry after another type counts")

-- Combat only (the default): out of combat nothing shows.
cast(MANA_SPELL)
eq(st.state, "window", "a mana spend starts the window")
check(not clip._shown, "but out of combat (combat only) it isn't shown")
settle()

-- In combat: red, draining 5 s.
combat(true)
local t0 = WoW.now
cast(MANA_SPELL)
eq(st.state, "window", "a spend in combat: the window")
check(clip._shown, "shown in combat")
eq(bar._color[1], 1.00, "red")
eq(bar._timer.dir, REMAINING, "draining (RemainingTime)")
eq(bar._timer.duration, dur(), "the window's duration object")
eq(dur()._start, t0, "from the spend")
eq(dur()._dur, 5, "5 seconds")

-- Mana updates (the spend's own, regen, a potion) never restart or end it.
mana()
adv(0.115); mana()
eq(st.state, "window", "mana updates leave the window")
eq(dur()._start, t0, "and don't restart it")

-- A free instant and a rage spell don't touch it.
cast(FREE); cast(RAGE_SPELL)
eq(dur()._start, t0, "free and non-mana casts leave the window alone")

-- A re-spend restarts it; the first window's timer can't end the second.
adv(2.885)                     -- 3 s in
local t1 = WoW.now
cast(MANA_SPELL)
eq(dur()._start, t1, "a second spend restarts the window")
adv(2)                         -- the first window's 5 s
eq(st.state, "window", "the superseded window's timer does nothing")
check(clip._shown, "still shown")
adv(3)                         -- the second window's 5 s
eq(st.state, "idle", "after 5 s: done (no tick timer: regen is continuous)")
check(not clip._shown, "hidden when it runs out")
mana()
eq(st.state, "idle", "a regen update after it starts nothing")
check(not clip._shown, "still hidden")
settle()

-- Combat ending inside the window ends it (measured twice).
combat(true)
cast(MANA_SPELL)
adv(0.98)
GlassUF.Settings.SetFiveSecondCombatOnly(false)
combat(false)
eq(st.state, "idle", "combat exit inside the window: done")
check(not clip._shown, "hidden, even with combat only off")
GlassUF.Settings.SetFiveSecondCombatOnly(true)
settle()

-- Combat only off: a spend out of combat shows it.
GlassUF.Settings.SetFiveSecondCombatOnly(false)
eq(GlassUnitFramesDB.fsrCombatOnly, false, "saved when off")
cast(MANA_SPELL)
check(clip._shown, "combat only off: shown out of combat")
GlassUF.Settings.SetFiveSecondCombatOnly(true)
eq(GlassUnitFramesDB.fsrCombatOnly, nil, "on is the default: not saved")
check(not clip._shown, "combat only again: hidden out of combat")
combat(true)
check(clip._shown, "a fight starting mid-window shows it")
settle()

-- Full mana hides the strip through the client's curve, never a Lua read.
combat(true)
cast(MANA_SPELL)
eq(clip._alpha, 1, "below full: visible")
WoW.units.player.power = WoW.units.player.maxPower
adv(1); mana()
eq(clip._alpha, 0, "full mana (a potion): alpha 0")
WoW.units.player.power = 400
WoW.secretFields.power = true
adv(0.13); mana()
check(WoW.IsSecret(clip._alpha), "a secret alpha goes straight to SetAlpha")
WoW.secretFields.power = nil
settle()

-- Payload guards: a secret or other power token is ignored, without error.
combat(true)
WoW.fire("UNIT_POWER_UPDATE", "player", WoW.Secret("powerType"))
WoW.fire("UNIT_POWER_UPDATE", "player", "ENERGY")
eq(st.state, "idle", "a secret or non-mana power update is ignored")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-2", WoW.Secret("spellID"))
eq(st.state, "idle", "a secret spellID is no spend")

-- Death goes idle.
cast(MANA_SPELL)
WoW.fire("PLAYER_DEAD")
eq(st.state, "idle", "death: idle")
check(not clip._shown, "and hidden")

-- The option off, the regen segment (#118) still on: hidden, but the window
-- is still tracked (the segment needs it), with its own expiry; saved only
-- when off.
cast(MANA_SPELL)
local gen = st.gen
GlassUF.Settings.SetFiveSecond(false)
eq(st.state, "window", "off, the segment on: the window is kept")
eq(st.gen, gen, "the same window")
check(not clip._shown, "off: hidden")
eq(GlassUnitFramesDB.fiveSecondRule, false, "saved when off")
GlassUF.Settings.SetFiveSecond(true)
eq(GlassUnitFramesDB.fiveSecondRule, nil, "on: not saved")
check(clip._shown, "on again mid-window: shown")
eq(bar._timer.duration, dur(), "the same duration: only its remaining time")
adv(5.1)
eq(st.state, "idle", "it ends on its original timer")
settle()

-- Both off: idle, hidden, no events.
cast(MANA_SPELL)
GlassUF.Settings.SetFiveSecond(false)
GlassUF.Settings.SetManaRegen(false)
eq(st.state, "idle", "both off: idle")
check(not clip._shown, "both off: hidden")
cast(MANA_SPELL)
eq(st.state, "idle", "both off: a spend does nothing")
GlassUF.Settings.SetFiveSecond(true)
cast(MANA_SPELL)
eq(st.state, "window", "back on: spends count again")
check(clip._shown, "and show")
settle()

-- Combat changing while nothing's tracked (no events): turning one on
-- re-reads combat.
GlassUF.Settings.SetFiveSecond(false)
combat(true)
GlassUF.Settings.SetFiveSecond(true)
cast(MANA_SPELL)
check(clip._shown, "off out of combat, on in combat: shown (combat re-read)")
settle()
combat(true)                   -- seen while on
GlassUF.Settings.SetFiveSecond(false)
combat(false)
GlassUF.Settings.SetFiveSecond(true)
cast(MANA_SPELL)
check(not clip._shown, "off in combat, on out of combat: hidden (combat only)")
settle()
GlassUF.Settings.SetManaRegen(true)

-- The options page offers both switches to a mana user.
local O = GlassUF.Options
O._test.panel:Show()
local c = O._test.controls
check(c.fsr and c.fsrCombat, "the main page has the five-second rule switches")
c.fsr:SetChecked(false); c.fsr._scripts.OnClick(c.fsr)
eq(GlassUnitFramesDB.fiveSecondRule, false, "the checkbox saves through Settings")
c.fsr:SetChecked(true); c.fsr._scripts.OnClick(c.fsr)
eq(F.enabled, true, "and turns it back on")

eq(next(GlassUF.paintFailures), nil, "no paint failures")

-- A druid: in a form the strip is on the druid mana strip, its alpha from MANA.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class, WoW.units.player.powerToken = "DRUID", "RAGE"
WoW.units.player.power, WoW.units.player.maxPower = 100, 100   -- rage full
WoW.units.player.mana, WoW.units.player.maxMana = 150, 300
costs()
loadAddon()
F, T = GlassUF.FiveSecond, GlassUF.FiveSecond._test
local ds = T.strips()
check(ds.druid ~= nil, "a druid gets a strip on the druid mana strip too")
eq(ds.druid.bar._points[1][2], button("player").druidMana.bar, "along the druid mana bar")
adv(0); combat(true)
cast(MANA_SPELL)
check(ds.druid.clip._shown and not ds.power.clip._shown, "in a form: on the druid mana strip")
eq(ds.druid.clip._alpha, 1, "half mana: visible although rage is full (mana alpha, not the bar's)")
WoW.units.player.powerToken = "MANA"
WoW.fire("UNIT_DISPLAYPOWER", "player")
check(ds.power.clip._shown and not ds.druid.clip._shown, "caster form: back on the power bar")
eq(ds.power.bar._timer.duration, T.dur(), "carrying the running window")
WoW.units.player.mana = 300
WoW.fire("UNIT_DISPLAYPOWER", "player")
eq(ds.power.clip._alpha, 0, "full mana: hidden")
eq(next(GlassUF.paintFailures), nil, "no paint failures (druid)")

-- A warrior builds nothing, and the options page has no switches.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class, WoW.units.player.powerToken = "WARRIOR", "RAGE"
loadAddon()
check(not GlassUF.FiveSecond.Built(), "a warrior gets no strip")
GlassUF.Options._test.panel:Show()
check(GlassUF.Options._test.controls.fsr == nil, "no switches for a warrior")

GlassUnitFramesDB = nil
done("test_fsr")
