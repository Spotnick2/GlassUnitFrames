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
eq(host._points[1][2], pl.body, "on the player's body (it rides the group layout's glide, #132)")
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
check(WoW.chat[#WoW.chat]:find("timer on||off", 1, true), "a wrong word gets the usage")

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

-- The alert at a fight's start (#186): the glow (on by default) and the sound
-- (off by default).
local glowing = Timer._test.glowing
local g = t.glow
check(Timer.glow and not Timer.sound, "defaults: glow on, sound off")
-- Long brackets: the expected paths can't lose their backslashes to escaping
-- the way a quoted string can (Codex, #187).
eq(g.outer._file, [[Interface\SpellActivationOverlay\IconAlert]], "Blizzard's proc glow")
eq(g.ants._file, [[Interface\SpellActivationOverlay\IconAlertAnts]], "and its ants")
local sounds = {}
rawset(_G, "PlaySound", function(kit, channel) sounds[#sounds + 1] = { kit, channel }; return true, 1 end)
fight(true)
check(glowing() and g.frame:IsShown(), "a fight's start: it glows")
eq(g.flash._alpha, 1, "a white flash first")
eq(g.outer._width, 18 * 1.4 * 2, "the ring at twice its size, round the opening circle")
eq(g.ants._alpha, 0, "no ants yet")
eq(#sounds, 0, "no sound: off by default")
settle()
eq(g.outer._width, 52 * 1.4, "the burst done: the ring round the open pill")
eq(g.outer._height, 18 * 1.4, "and its height")
eq(g.flash._alpha, 0, "the flash gone")
after(0.25)
eq(g.ants._alpha, 1, "the ants march")
local function antCell() return table.concat(g.ants._texCoord, ",") end
local cell = antCell()
WoW.now = WoW.now + 0.05; WoW.tick(0.05)
check(antCell() ~= cell, "the ants step their flipbook")
eq(#g.ants._texCoord, 4, "one 48 px cell of it")
eq(g.ants._texCoord[2] - g.ants._texCoord[1], 48 / 256, "48 px wide")
after(2.8)   -- 3.4 s in: inside the fade (3.3 to 3.7)
check(glowing() and g.outer._alpha < 1 and g.outer._alpha > 0, "then it fades")
after(0.35)
check(not glowing() and not g.frame:IsShown(), "and goes after its hold")
check(host:IsShown() and host._alpha == 1, "the pill stays")
fight(false); settle()
-- Combat ending mid-glow: it fades with the pill and is gone when it closes.
fight(true); settle()
fight(false); settle()
check(not glowing() and not g.frame:IsShown(), "combat ends mid-glow: gone with the pill")
-- The sound, on: one kit on Master at each fight's start.
SlashCmdList.GLASSUNITFRAMES("timer sound on")
eq(GlassUnitFramesDB.timerSound, true, "sound on is saved")
fight(true)
eq(#sounds, 1, "a fight's start plays it")
eq(sounds[1][1], Timer.SOUND_KIT, "the kit")
eq(sounds[1][2], "Master", "on Master")
settle(); after(1)
eq(#sounds, 1, "once a fight")
fight(false); settle()
SlashCmdList.GLASSUNITFRAMES("timer sound test")
eq(#sounds, 2, "test plays it")
check(WoW.chat[#WoW.chat]:find("playing", 1, true), "and says so")
-- A refused kit (willPlay false) is recorded, once per failure, not thrown.
rawset(_G, "PlaySound", function() return false end)
fight(true)
check(GlassUF.paintFailures["timer sound"] ~= nil, "a refused kit is recorded")
fight(false); settle()
GlassUF.paintFailures["timer sound"] = nil
SlashCmdList.GLASSUNITFRAMES("timer sound test")
check(WoW.chat[#WoW.chat]:find("refused", 1, true), "test says a refusal")
rawset(_G, "PlaySound", function(kit, channel) sounds[#sounds + 1] = { kit, channel }; return true, 1 end)
SlashCmdList.GLASSUNITFRAMES("timer sound off")
eq(GlassUnitFramesDB.timerSound, nil, "sound off is the default: not saved")
local n = #sounds
fight(true); fight(false); settle()
eq(#sounds, n, "off: no sound")
-- The glow off: saved, none at a fight's start; off mid-glow stops it.
fight(true)
check(glowing(), "glowing")
SlashCmdList.GLASSUNITFRAMES("timer glow off")
eq(GlassUnitFramesDB.timerGlow, false, "glow off is saved")
check(not glowing() and not g.frame:IsShown(), "off mid-glow: gone")
fight(false); settle()
fight(true)
check(not glowing(), "off: no glow at a fight's start")
fight(false); settle()
SlashCmdList.GLASSUNITFRAMES("timer glow on")
eq(GlassUnitFramesDB.timerGlow, nil, "glow on is the default: not saved")
SlashCmdList.GLASSUNITFRAMES("timer glow maybe")
check(WoW.chat[#WoW.chat]:find("glow on||off", 1, true), "a wrong word gets the usage")
-- The timer off: no glow, no sound (its events are off).
S.SetTimerSound(true)
S.SetCombatTimer(false)
n = #sounds
fight(true)
check(not glowing() and #sounds == n, "timer off: neither")
fight(false); settle()
S.SetCombatTimer(true)
S.SetTimerSound(false)
-- A preview glows too, without the sound.
S.SetTimerSound(true)
n = #sounds
S.SetPreview(true)
check(glowing(), "a preview glows")
eq(#sounds, n, "without the sound")
S.SetPreview(false); settle()
check(not glowing(), "preview off: gone with the pill")
S.SetTimerSound(false)
rawset(_G, "PlaySound", nil)

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
check(c.timerGlow ~= nil and c.timerSound ~= nil, "glow and sound switches")
c.timerGlow:SetChecked(false)
c.timerGlow._scripts.OnClick(c.timerGlow)
eq(GlassUnitFramesDB.timerGlow, false, "the glow switch turns it off")
c.timerGlow:SetChecked(true)
c.timerGlow._scripts.OnClick(c.timerGlow)
eq(GlassUnitFramesDB.timerGlow, nil, "and on")
c.timerSound:SetChecked(true)
c.timerSound._scripts.OnClick(c.timerSound)
eq(GlassUnitFramesDB.timerSound, true, "the sound switch turns it on")
c.timerSound:SetChecked(false)
c.timerSound._scripts.OnClick(c.timerSound)
eq(GlassUnitFramesDB.timerSound, nil, "and off")

-- Saved off at load: built, closed, no events; turning it on works.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = { combatTimer = false, timerGlow = false, timerSound = true } })
local t2 = GlassUF.Timer._test.bar()
check(t2 ~= nil and not GlassUF.Timer.enabled, "saved off: built, off")
check(not GlassUF.Timer.glow and GlassUF.Timer.sound, "the alert's saves read at load")
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(not t2.host:IsShown(), "and a fight doesn't open it")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")

eq(next(GlassUF.paintFailures), nil, "no failures")
done("test_timer")
