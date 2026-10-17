-- The combat timer (#120): a glass pill over the player's portrait, opening
-- (a circle growing into the pill, fading in) when combat starts and closing
-- when it ends, frozen on the fight's final time. What shows: off -> closed;
-- preview -> its clock; combat -> its clock; else closed, with combat recorded
-- whatever shows.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local Timer, S = GlassUF.Timer, GlassUF.Settings
local pl = button("player")
local t = Timer._test.bar()
check(t ~= nil, "built on the player frame through the normal build")
local host, text = t.host, t.text

local function fight(on)
    WoW.combat = on
    WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
local function after(s) WoW.now = WoW.now + s; WoW.tick(0.25) end
local function settle() after(0.3) end   -- past the opening or closing animation

-- Format.
eq(Timer.Format(0), "00:00", "zero")
eq(Timer.Format(65.9), "01:05", "whole seconds, mm:ss")
eq(Timer.Format(3605), "1:00:05", "past an hour")

-- Over the portrait tile.
eq(host._points[1][1], "BOTTOM", "its bottom")
eq(host._points[1][2], pl.tile, "on the portrait tile")
eq(host._points[1][3], "TOP", "over its top")
eq(host._points[1][5], 4, "4 above")

-- Out of combat: closed. A fight opens it, counts, and closes it.
check(not host:IsShown(), "hidden out of combat")
fight(true)
check(host:IsShown(), "combat starts: it opens")
eq(host._alpha, 0, "from transparent")
eq(host._width, 18, "and a circle")
eq(textOf(text), "00:00", "at 00:00")
WoW.now = WoW.now + 0.125; WoW.tick(0.125)
check(host._alpha > 0.5 and host._alpha < 1, "half way: fading in (ease-out)")
check(host._width > 18 and host._width < 52, "and growing")
settle()
eq(host._alpha, 1, "open: opaque")
eq(host._width, 52, "and the full pill")
after(65)
eq(textOf(text), "01:05", "counts up")
fight(false)
check(host:IsShown(), "combat ends: it closes, still shown")
WoW.now = WoW.now + 0.125; WoW.tick(0.125)
check(host._alpha < 0.5 and host._alpha > 0, "fading out")
eq(textOf(text), "01:05", "frozen on the fight's time")
settle()
check(not host:IsShown(), "closed: hidden")
check(not t.ticker:IsShown(), "and its clock stops")
-- A fight starting while it closes reopens it from where it was.
fight(true)
settle()
fight(false)
WoW.now = WoW.now + 0.125; WoW.tick(0.125)
local mid = host._alpha
fight(true)
WoW.now = WoW.now + 0.01; WoW.tick(0.01)
check(host._alpha >= mid, "a fight mid-close reopens from where it was")
settle()
eq(host._alpha, 1, "fully open again")
eq(textOf(text), "00:00", "a new fight, from 00:00")
fight(false); settle()
-- Past an hour.
fight(true); settle(); after(3605)
eq(textOf(text), "1:00:05", "past an hour")
fight(false); settle()

-- The portrait set to "none": over the frame's left edge, clear of the crown.
check(S.SetPortraitMode("player", "none"), "portrait none")
eq(host._points[1][1], "BOTTOMLEFT", "no tile: its bottom-left")
eq(host._points[1][2], pl, "on the player button")
eq(host._points[1][3], "TOPLEFT", "over its top-left")
eq(host._points[1][5], 10, "10 above: clear of the leader crown")
S.SetPortraitMode("player", "3d")
eq(host._points[1][2], pl.tile, "the portrait back: over the tile again")

-- Option off: closes, no events, saved; on: nil saved.
fight(true); settle(); after(65)
check(S.SetCombatTimer(true), "a repeated on is accepted")
eq(textOf(text), "01:05", "and keeps counting (no reset to 00:00)")
SlashCmdList.GLASSUNITFRAMES("timer off")
eq(GlassUnitFramesDB.combatTimer, false, "off is saved")
settle()
check(not host:IsShown(), "off closes it mid-fight")
eq(Timer._test.live(), nil, "and forgets the fight")
after(10)
SlashCmdList.GLASSUNITFRAMES("timer on")
eq(GlassUnitFramesDB.combatTimer, nil, "on is the default: not saved")
check(host:IsShown(), "on in a fight opens it at once")
eq(textOf(text), "00:00", "counting from now (the start was missed)")
fight(false); settle()
SlashCmdList.GLASSUNITFRAMES("timer maybe")
check(WoW.chat[#WoW.chat]:find("timer on|off", 1, true), "a wrong word gets the usage")

-- World entry: a /reload mid-fight counts from now; a loading screen inside a
-- timed fight keeps its start; out of combat, closed.
WoW.combat = true
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(host:IsShown(), "entering the world in combat opens it")
settle(); after(65)
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(textOf(text), "01:05", "a loading screen in the same fight keeps the count")
WoW.combat = false
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
settle()
check(not host:IsShown(), "out of combat: closed")

-- Preview: counts from 00:00, and closes when it stops.
check(S.SetPreview(true), "preview")
check(host:IsShown(), "the preview opens it")
eq(textOf(text), "00:00", "from 00:00")
settle(); after(3)
eq(textOf(text), "00:03", "and runs")
S.SetPreview(false)
settle()
check(not host:IsShown(), "preview off: closed")

-- Both combat orders: the timer's handler before and after the dispatcher's
-- preview stop.
local onEvent = Timer._test.onEvent
for _, timerFirst in ipairs({ true, false }) do
    WoW.combat = false
    S.SetPreview(true)
    settle()
    if timerFirst then onEvent(nil, "PLAYER_REGEN_DISABLED") end
    GlassUF.Preview.OnCombat()
    if not timerFirst then onEvent(nil, "PLAYER_REGEN_DISABLED") end
    WoW.combat = true
    local label = timerFirst and "timer first" or "timer last"
    settle()
    check(host:IsShown() and host._alpha == 1, "combat during a preview (" .. label .. "): open")
    eq(textOf(text), "00:00", "the live clock (" .. label .. ")")
    after(2)
    eq(textOf(text), "00:02", "running (" .. label .. ")")
    onEvent(nil, "PLAYER_REGEN_ENABLED")
    settle()
    check(not host:IsShown(), "combat ends (" .. label .. "): closed")
end
WoW.combat = false

-- In combat: opening and closing touch nothing protected.
WoW.blocked = {}
fight(true); settle()
eq(#WoW.blocked, 0, "nothing blocked in combat")
-- The player frame hidden (the stub refuses that to us in combat, as the
-- client would; the unit watch does it): the timer goes with it, and is
-- right when it's back.
after(5)
WoW.combat = false; pl:Hide(); WoW.combat = true
check(not host:IsVisible(), "hidden with the player frame")
after(60)
WoW.combat = false; pl:Show(); WoW.combat = true
after(0)
eq(textOf(text), "01:05", "the right time when it's back")
fight(false); settle()

-- Options: the switch on the main page (it scrolls; the Cast bars page doesn't).
local O = GlassUF.Options
O._test.panel:Show()
local c = O._test.controls
check(c.combatTimer ~= nil, "a Combat timer switch")
c.combatTimer:SetChecked(false)
c.combatTimer._scripts.OnClick(c.combatTimer)
eq(GlassUnitFramesDB.combatTimer, false, "the switch turns it off")
c.combatTimer:SetChecked(true)
c.combatTimer._scripts.OnClick(c.combatTimer)
eq(GlassUnitFramesDB.combatTimer, nil, "and on")

-- Saved off at load: built, closed, no events; turning it on works.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = { combatTimer = false } })
local t2 = GlassUF.Timer._test.bar()
check(t2 ~= nil and not GlassUF.Timer.enabled, "saved off: built, off")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(not t2.host:IsShown(), "and a fight doesn't open it")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")

eq(next(GlassUF.paintFailures), nil, "no failures")
done("test_timer")
