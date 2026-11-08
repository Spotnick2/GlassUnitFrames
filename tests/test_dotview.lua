-- test_dotview.lua: the DoT kill estimate on the target and focus frames
-- (#175, docs/DOT-KILL-PLAN.md section 7). Health only ever reaches
-- StatusBars; the kill icon's comparator is the client's, not Lua's.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local sp = 0
UnitCanAttack = function(_, u) local un = WoW.units[u]; return un ~= nil and un.reaction <= 4 end
GetSpellBonusDamage = function() return sp end
standardUnits()
WoW.units.player.level = 60
loadAddon()
local DotView, Dots = GlassUF.DotView, GlassUF.Dots
local t, f = button("target"), button("focus")
local CORRUPTION = 172

local n = 0
local function cast(spellID, name)
    n = n + 1
    local g = "Cast-3-" .. n
    WoW.fire("UNIT_SPELLCAST_SENT", "player", name or "Defias Pillager", g, spellID or CORRUPTION)
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, spellID or CORRUPTION)
end
local function wait(dt)
    for _ = 1, math.floor(dt / 0.05 + 0.5) do WoW.now = WoW.now + 0.05; WoW.tick(0.05) end
end
local function hit(unit) WoW.fire("UNIT_COMBAT", unit or "target", "WOUND", "", WoW.Secret("amount"), 32) end
local function shownLines(b)
    local c = 0
    for _, bar in ipairs(b.dotLines) do if bar:IsShown() then c = c + 1 end end
    return c
end

-- Built on target and focus only.
check(t.dotMarker and f.dotMarker, "target and focus have the marker")
check(button("pet").dotMarker == nil and button("player").dotMarker == nil, "no other frame does")
check(t.channels.dots and f.channels.dots, "the dots channel on both")
eq(#t.dotLines, Dots.MAX_TICKS, "a tick line per upcoming tick")

-- The marker: the health bar's width, reverse fill, its right end on the
-- health fill's moving edge, inside a clip that is the whole health bar.
local m = t.dotMarker
eq(m._width, t.healthWidth, "the full health-bar width")
check(m._reverse, "fills leftward from its right end")
eq(m._points[1][1], "TOPRIGHT", "its right end")
eq(m._points[1][2], t.health:GetStatusBarTexture(), "on the health fill")
eq(m._points[1][3], "TOPRIGHT", "at the fill's moving edge")
eq(m._points[2][1], "BOTTOMRIGHT", "the bar's full height")
check(t.dotClip._clips, "clipped")
eq(t.dotClip._points[1][1], "ALL", "at the health bar's bounds")
eq(t.dotClip._level, t.health:GetFrameLevel() + 3, "over the fill, under the glass overlay")
local line = t.dotLines[1]
check(line._reverse and line._points[1][2] == t.health:GetStatusBarTexture(), "tick lines share the edge")

-- The kill icon: a clipped window over the portrait tile, a 10,000 px bar
-- whose right end is the window's, the skull's right edge on the fill's.
local icon = t.dotIcon
check(icon.window._clips, "the icon's window clips")
eq(icon.bar._width, DotView.BAR_LENGTH, "the comparator bar's length")
eq(icon.bar._points[1][1], "RIGHT", "its right end")
eq(icon.bar._points[1][2], icon.window, "on the window's")
check(not icon.bar._reverse, "normal fill")
eq(icon.skull._points[1][1], "RIGHT", "the skull's right edge")
eq(icon.skull._points[1][2], icon.bar:GetStatusBarTexture(), "rides the fill's right edge")
eq(icon.window._points[1][2], t.tile, "centred on the portrait tile")
check(f.dotIcon.window._points[1][3] == "LEFT" and f.dotIcon.window._points[1][2] == f.body,
    "focus (no tile): left of the frame")

-- Nothing tracked: nothing drawn.
WoW.tick()
eq(m._value, 0, "an empty marker")
eq(icon.window:GetAlpha(), 0, "no kill icon")

-- A DoT on the target (plain health 830 / 1317): the marker, then the icon
-- once committed. Corruption + 100 spell power: 4 ticks of 30.
sp = 100
cast()
wait(0.5)
WoW.tick()
eq(m._max, 1317, "the marker's scale is max health")
eq(m._value, 120, "its value is the estimate")
eq(shownLines(t), 3, "three lines: between the four ticks")
eq(t.dotLines[1]._value, 30, "the first line after the next tick")
eq(icon.window:GetAlpha(), 0, "no icon before a tick is seen")
wait(2.5)
hit()
WoW.tick()
eq(m._value, 90, "three ticks left")
eq(icon.window:GetAlpha(), 1, "the icon's window shows once committed")
eq(icon.bar._max, 830, "its scale is current health")
check(math.abs(icon.bar._value - 90 * (1 - icon.size / DotView.BAR_LENGTH)) < 1e-9,
    "its value is committed * (1 - S/L): the skull enters only past lethal")

-- Secret health: straight to the bars, nothing compared, no failure.
WoW.secretFields.health, WoW.secretFields.maxHealth = true, true
WoW.fire("UNIT_HEALTH", "target")
WoW.tick()
check(issecretvalue(m._max), "max health reaches the marker as the secret it is")
check(issecretvalue(icon.bar._max), "health reaches the comparator as a secret")
eq(next(GlassUF.paintFailures), nil, "no paint failures with secret health")
WoW.secretFields = {}

-- A failed paint clears everything (never a stale skull).
local saved = UnitHealth
UnitHealth = function() error("boom") end
WoW.fire("UNIT_HEALTH", "target")
WoW.tick()
UnitHealth = saved
eq(icon.window:GetAlpha(), 0, "a failed paint hides the icon")
eq(m._value, 0, "and empties the marker")
GlassUF.paintFailures = {}
WoW.fire("UNIT_HEALTH", "target")
WoW.tick()
eq(icon.window:GetAlpha(), 1, "the next paint draws again")

-- Dead, friendly or gone: cleared.
WoW.units.target.reaction = 5
WoW.fire("UNIT_FACTION", "target")
WoW.tick()
eq(m._value, 0, "a unit we can't attack shows nothing")
WoW.units.target.reaction = 2
WoW.fire("UNIT_FACTION", "target")
WoW.tick()
eq(m._value, 90, "back when attackable")

-- The options.
local db = GlassUnitFramesDB
GlassUF.Settings.SetDots("icon", false)
WoW.tick()
eq(icon.window:GetAlpha(), 0, "icon off")
eq(db.dots and db.dots.icon, false, "saved off")
GlassUF.Settings.SetDots("icon", true)
eq(db.dots, nil, "back on: nothing saved")
GlassUF.Settings.SetDots("ticks", false)
WoW.tick()
eq(shownLines(t), 0, "tick lines off")
GlassUF.Settings.SetDots("ticks", true)
GlassUF.Settings.SetDots("marker", false)
WoW.tick()
eq(m._value, 0, "marker off")
eq(icon.window:GetAlpha(), 1, "the icon on its own")
GlassUF.Settings.SetDots("marker", true)
check(not GlassUF.Settings.SetDots("nonsense", false), "an unknown part is refused")
SlashCmdList.GLASSUNITFRAMES("dots off")
check(not DotView.options.marker and not DotView.options.icon and not DotView.options.focus, "/glass dots off")
check(not Dots.enabled, "the tracker stops")
eq((Dots.Estimate("target")), 0, "and forgets")
SlashCmdList.GLASSUNITFRAMES("dots on")
eq(db.dots, nil, "/glass dots on: nothing saved")
SlashCmdList.GLASSUNITFRAMES("dots focus off")
eq(db.dots and db.dots.focus, false, "/glass dots focus off")
SlashCmdList.GLASSUNITFRAMES("dots focus on")

-- Placement: with the portrait off, the icon sits where the tile would be;
-- in combat it waits.
WoW.combat = true
GlassUF.Frames.SetPortraitMode("target", "none")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
local p = t.dotIcon.window._points[1]
check(p[2] == t.body and (p[1] == "LEFT" or p[1] == "RIGHT"), "no tile: beside the body")
GlassUF.Frames.SetPortraitMode("target", "3d")
eq(t.dotIcon.window._points[1][2], t.tile, "back on the tile")

-- The preview: a sample marker on the target, a kill icon on the focus.
Dots.SetEnabled(true)
GlassUF.Preview.Start()
WoW.tick()
local s = GlassUF.Frames.SAMPLES.target
eq(m._value, s.maxHp * 0.35, "the target's sample marker")
eq(shownLines(t), 3, "with its tick lines")
eq(f.dotIcon.window:GetAlpha(), 1, "the focus's sample kill icon")
GlassUF.Preview.Stop()
WoW.tick()
eq(f.dotIcon.window:GetAlpha(), 0, "the real state again after the preview")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
done("test_dotview")
