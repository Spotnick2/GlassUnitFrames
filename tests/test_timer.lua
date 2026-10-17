-- The combat timer (#120): a glass pill counting up from combat start, a bar
-- of the cast family (Castbar.bars.timer), detached by default at the top
-- centre. What shows: off -> nothing; preview -> its clock; unlock -> 00:42;
-- combat -> its clock; else nothing, with combat recorded whatever shows.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local Timer, Castbar, S = GlassUF.Timer, GlassUF.Castbar, GlassUF.Settings
local pl = button("player")
local t = Castbar.bars.timer
check(t ~= nil, "built on the player frame through the normal build")
local host, text = t.host, t.text

local function fight(on)
    WoW.combat = on
    WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
local function after(s) WoW.now = WoW.now + s; WoW.tick(0.25) end

-- Format.
eq(Timer.Format(0), "00:00", "zero")
eq(Timer.Format(65.9), "01:05", "whole seconds, mm:ss")
eq(Timer.Format(3605), "1:00:05", "past an hour")

-- Out of combat: hidden. A fight: counts up, then hides.
check(not host:IsShown(), "hidden out of combat")
fight(true)
check(host:IsShown(), "shown when combat starts")
eq(textOf(text), "00:00", "from 00:00")
after(65)
eq(textOf(text), "01:05", "counts up")
after(3540)
eq(textOf(text), "1:00:05", "past an hour")
fight(false)
check(not host:IsShown(), "hidden when combat ends")
check(not t.ticker:IsShown(), "and its clock stops")

-- Placement: detached by default at the top centre.
check(Castbar.IsDetached("timer"), "detached by default")
eq(GlassUnitFramesDB.castBars, nil, "the default isn't saved")
eq(host._points[1][1], "CENTER", "CENTER")
eq(host._points[1][2], UIParent, "on the screen")
eq(host._points[1][5], 180, "at the top centre")
eq(host._width, 80, "80 wide")
eq(host._height, 22, "22 tall")
-- Attach saves false; detach again prunes; junk is the default.
check(S.SetCastDetached("timer", false), "attach")
eq(GlassUnitFramesDB.castBars.timer.detached, false, "attaching saves false")
check(not Castbar.IsDetached("timer"), "docked")
eq(host._points[1][1], "BOTTOMLEFT", "docked above the player frame")
eq(host._points[1][2], pl, "on the player button")
eq(host._points[1][3], "TOPLEFT", "its top-left")
eq(host._points[1][5], 10, "clear of the leader crown")
S.SetCastDetached("timer", true)
eq(GlassUnitFramesDB.castBars, nil, "detaching again is the default: nothing saved")
GlassUnitFramesDB.castBars = { timer = { detached = "yes" } }
check(Castbar.IsDetached("timer"), "junk is the default (detached)")
GlassUnitFramesDB.castBars = { player = { detached = "yes" } }
check(not Castbar.IsDetached("player"), "and for an ordinary bar its default (docked)")
GlassUnitFramesDB.castBars = nil
S.SetCastDetached("player", true)
eq(GlassUnitFramesDB.castBars.player.detached, true, "an ordinary bar still saves true")
S.SetCastDetached("player", false)
eq(GlassUnitFramesDB.castBars, nil, "and nothing when docked")

-- The colours: the cast bars' time text.
S.SetCastColor("time", 1, 0, 0, 1)
eq(text._textColor and text._textColor[2], 0, "the time text colour reaches it")
S.ResetCastColors()

-- Option off: hidden, no events, saved; on: nil saved.
fight(true)
after(65)
check(S.SetCombatTimer(true), "a repeated on is accepted")
eq(textOf(text), "01:05", "and keeps counting (no reset to 00:00)")
SlashCmdList.GLASSUNITFRAMES("timer off")
eq(GlassUnitFramesDB.combatTimer, false, "off is saved")
check(not host:IsShown(), "off hides it mid-fight")
eq(Timer._test.live(), nil, "and forgets the fight")
after(10)
SlashCmdList.GLASSUNITFRAMES("timer on")
eq(GlassUnitFramesDB.combatTimer, nil, "on is the default: not saved")
check(host:IsShown(), "on in a fight shows it at once")
eq(textOf(text), "00:00", "counting from now (the start was missed)")
fight(false)
SlashCmdList.GLASSUNITFRAMES("timer maybe")
check(WoW.chat[#WoW.chat]:find("timer on|off", 1, true), "a wrong word gets the usage")

-- World entry: a /reload mid-fight counts from now; a loading screen inside a
-- timed fight keeps its start; out of combat, nothing.
WoW.combat = true
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(host:IsShown(), "entering the world in combat starts it")
after(65)
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(textOf(text), "01:05", "a loading screen in the same fight keeps the count")
WoW.combat = false
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(not host:IsShown(), "out of combat: hidden")

-- Unlock: the sample to place, a mover; lock hides it.
check(S.Unlock(), "unlock")
check(host:IsShown(), "unlocked: shown")
eq(textOf(text), "00:42", "the sample")
check(GlassUF.Movers._test and GlassUF.Movers._test.movers and GlassUF.Movers._test.movers["cast:timer"],
      "a cast:timer mover")
SlashCmdList.GLASSUNITFRAMES("lock")
check(not host:IsShown(), "locked: hidden again")

-- Preview: counts from 00:00; stopped while unlocked, the sample comes back.
check(S.SetPreview(true), "preview")
eq(textOf(text), "00:00", "the preview counts from 00:00")
after(3)
eq(textOf(text), "00:03", "and runs")
S.Unlock()
eq(textOf(text), "00:03", "the preview wins over the sample")
S.SetPreview(false)
eq(textOf(text), "00:42", "preview off while unlocked: the sample")
SlashCmdList.GLASSUNITFRAMES("lock")

-- Off while unlocked, then on: the sample again.
S.Unlock()
S.SetCombatTimer(false)
check(not host:IsShown(), "off hides the sample")
S.SetCombatTimer(true)
eq(textOf(text), "00:42", "on again: the sample")
SlashCmdList.GLASSUNITFRAMES("lock")

-- Both combat orders: the timer's handler before and after the dispatcher's
-- preview stop and lock, during a preview and while unlocked.
local onEvent = Timer._test.onEvent
for _, timerFirst in ipairs({ true, false }) do
    for _, setup in ipairs({ "preview", "unlock" }) do
        WoW.combat = false
        if setup == "preview" then S.SetPreview(true) else S.Unlock() end
        if timerFirst then onEvent(nil, "PLAYER_REGEN_DISABLED") end
        GlassUF.Preview.OnCombat()
        GlassUF.Movers.OnCombat()
        if not timerFirst then onEvent(nil, "PLAYER_REGEN_DISABLED") end
        WoW.combat = true
        local label = setup .. (timerFirst and ", timer first" or ", timer last")
        check(host:IsShown(), "combat during " .. label .. ": shown")
        eq(textOf(text), "00:00", "the live clock (" .. label .. ")")
        after(2)
        eq(textOf(text), "00:02", "running (" .. label .. ")")
        onEvent(nil, "PLAYER_REGEN_ENABLED")
        check(not host:IsShown(), "combat ends (" .. label .. "): hidden")
    end
end
WoW.combat = false

-- In combat: placing, showing and moving it touches nothing protected.
WoW.blocked = {}
fight(true)
S.SetCastDetached("timer", false)
S.SetCastDetached("timer", true)
GlassUF.Castbar.SetPosition("timer", 10, 150)
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
fight(false)
Castbar.ResetPosition("timer")

-- Options: "Timer" on its own picker row; no spell icon for it; the switch.
local O = GlassUF.Options
O._test.castPage:Show()
local c = O._test.controls
check(c.castBarRow2 and #c.castBarRow2 == 1, "a second picker row with Timer")
c.castBarRow2[1]._scripts.OnClick(c.castBarRow2[1])
check(c.castBarRow2[1]:GetChecked(), "Timer checked")
for _, rb in ipairs(c.castBarRow) do check(not rb:GetChecked(), "and none of the others") end
for _, rb in ipairs(c.castIcon) do check(rb._enabled == false, "no spell icon for the timer") end
c.combatTimer:SetChecked(false)
c.combatTimer._scripts.OnClick(c.combatTimer)
eq(GlassUnitFramesDB.combatTimer, false, "the switch turns it off")
c.combatTimer:SetChecked(true)
c.combatTimer._scripts.OnClick(c.combatTimer)
eq(GlassUnitFramesDB.combatTimer, nil, "and on")
c.castBarRow[1]._scripts.OnClick(c.castBarRow[1])
check(not c.castBarRow2[1]:GetChecked(), "picking You unchecks Timer")

-- Saved off at load: built, hidden, no events; turning it on works.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = { combatTimer = false } })
local t2 = GlassUF.Castbar.bars.timer
check(t2 ~= nil and not GlassUF.Timer.enabled, "saved off: built, off")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(not t2.host:IsShown(), "and a fight doesn't show it")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")

eq(next(GlassUF.paintFailures), nil, "no failures")
done("test_timer")
