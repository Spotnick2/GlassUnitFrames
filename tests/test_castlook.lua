-- Quartz's look and options on the cast bars (#78): the spell icon, "Spell ->
-- Target", "remaining / total", the precision, the spark, the complete flash,
-- the colours (validated, saved, applied; the picker), the ms figure inside
-- the block.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local Castbar, S = GlassUF.Castbar, GlassUF.Settings
local pl, tg = button("player"), button("target")
local pc, tc = pl.cast, tg.cast
local n = 0
local function guid() n = n + 1; return "Cast-3-1-1-1-2061-" .. n end
local function cast(unit, g, name, extra)
    local t = { name = name or "Greater Heal", guid = g, spellID = 2061, total = 2.5, remaining = 1.234,
                startMs = WoW.now * 1000, endMs = (WoW.now + 2.5) * 1000, delayMs = 0 }
    for k, v in pairs(extra or {}) do t[k] = v end
    WoW.units[unit].casting = t
    if unit == "player" then WoW.fire("UNIT_SPELLCAST_SENT", "player", (extra and extra.sentTo) or "", g, 2061) end
    WoW.fire(t.channel and "UNIT_SPELLCAST_CHANNEL_START" or "UNIT_SPELLCAST_START", unit, g, 2061, "CastBar-1")
    WoW.tick(0.1)
end
local function stop(unit, g, channel)
    WoW.units[unit].casting = nil
    WoW.fire(channel and "UNIT_SPELLCAST_CHANNEL_STOP" or "UNIT_SPELLCAST_STOP", unit, g, 2061, "CastBar-1")
end

-- The icon: yours on the left, the target's on the right (Quartz's mirrored
-- pair); the bar shortened by the icon's room.
eq(Castbar.IconSide("player"), "left", "your icon: left by default")
eq(Castbar.IconSide("target"), "right", "the target's: right")
local g1 = guid()
cast("player", g1)
check(pc.icon._shown, "the icon shows while casting")
eq(pc.icon._file, 136243, "the cast's own icon (UnitCastingInfo's texture, straight to the client)")
eq(pc.bar._points[1][4], 14 + 2, "the bar starts after the icon (14 px row + 2)")
eq(pc.icon._points[1][1], "TOPLEFT", "the icon at the left end")
-- Spell -> Target from SENT's target name; and remaining / total.
stop("player", g1); WoW.flushTimers()
local g2 = guid()
cast("player", g2, nil, { sentTo = "Karuzo Macphisto" })
eq(textOf(pc.spell), "Greater Heal -> Karuzo Macphisto", "Spell -> Target on your bar")
eq(textOf(pc.time), "1.2 / 2.5", "remaining / total")
-- Precision.
S.SetCastPrecision(2); WoW.tick(0.1)
eq(textOf(pc.time), "1.23 / 2.50", "precision 2")
eq(GlassUnitFramesDB.castPrecision, 2, "saved")
S.SetCastPrecision(9)
eq(Castbar.precision, 3, "clamped to 3")
S.SetCastPrecision(1)
eq(GlassUnitFramesDB.castPrecision, nil, "back to 1: nothing saved")
S.SetCastOption("totalTime", false); WoW.tick(0.1)
eq(textOf(pc.time), "1.2s", "total off: the remaining time alone")
S.SetCastOption("totalTime", true)
-- The spark rides the fill's moving edge.
check(pc.spark._shown, "the spark shows while casting")
eq(pc.spark._points[1][2], pc.bar:GetStatusBarTexture(), "anchored to the fill's edge (no Lua geometry)")

-- A cast that completes: the short "complete" flash, the name kept.
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", g2, 2061, "CastBar-1")
stop("player", g2)
check(pc.host._shown, "a completed cast flashes")
eq(pc.bar._color[1], Castbar.colors.complete[1], "in the complete colour")
eq(textOf(pc.spell), "Greater Heal -> Karuzo Macphisto", "the name kept")
check(not pc.spark._shown, "no spark on a flash")
WoW.flushTimers()
check(not pc.host._shown, "gone after its timer")
-- Self-cast: no arrow.
local g3 = guid()
cast("player", g3, nil, { sentTo = GetUnitName("player", false) })
eq(textOf(pc.spell), "Greater Heal", "a self-cast: no -> target")
-- An interrupt: no green, one red.
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", g3, 2061, nil, "CastBar-1")   -- the cast still live
stop("player", g3)
check(not pc.host._shown, "an interrupted cast's STOP: no complete flash")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", g3, 2061, nil, nil)
check(pc.host._shown and textOf(pc.spell) == "Interrupted", "the repeat: the red flash")
eq(pc.bar._color[1], Castbar.colors.failed[1], "in the failed colour")
WoW.flushTimers()
-- A channel ends without a complete flash; the option off, none at all.
local g4 = guid()
cast("player", g4, "Mind Flay", { channel = true })
stop("player", g4, true)
check(not pc.host._shown, "a channel's end: no complete flash")
S.SetCastOption("complete", false)
local g5 = guid()
cast("player", g5)
stop("player", g5)
check(not pc.host._shown, "complete flash off: hidden on STOP")
S.SetCastOption("complete", true)
eq(GlassUnitFramesDB.castComplete, nil, "on again: nothing saved")
-- The target's completed cast flashes too (its STOP, no SUCCEEDED for others).
local t1 = guid()
cast("target", t1, "Fireball")
eq(tc.icon._points[1][1], "TOPRIGHT", "the target's icon at the right end")
eq(textOf(tc.time), "1.2 / 2.5", "remaining / total on the target too")
stop("target", t1)
check(tc.host._shown, "the target's completed cast flashes")
WoW.flushTimers()

-- Icon side: none frees the bar's full width; saved only when not the default.
S.SetCastIcon("player", "none")
eq(GlassUnitFramesDB.castBars.player.icon, "none", "saved")
eq(pc.bar._points[1][4], 0, "no icon: the bar from the row's edge")
local g6 = guid()
cast("player", g6)
check(not pc.icon._shown, "no icon shown")
stop("player", g6); WoW.flushTimers()
S.SetCastIcon("player", "left")
eq(GlassUnitFramesDB.castBars, nil, "the default again: nothing saved")
check(not S.SetCastIcon("player", "middle"), "an unknown side is refused")

-- Colours: validated, saved, applied; reset.
check(S.SetCastColor("cast", 1, 0.5, 0, 1), "casting colour set")
eq(GlassUnitFramesDB.castColors.cast[2], 0.5, "saved")
local g7 = guid()
cast("player", g7)
eq(pc.bar._color[2], 0.5, "the next cast in the new colour")
stop("player", g7); WoW.flushTimers()
check(not S.SetCastColor("cast", 2, 0, 0, 1), "out of range refused")
check(not S.SetCastColor("nonsense", 1, 1, 1, 1), "an unknown key refused")
S.SetCastColor("spell", 1, 0.8, 0, 1)
eq(pc.spell._textColor and pc.spell._textColor[2] or select(2, pc.spell:GetTextColor()), 0.8, "spell text colour applied at once")
-- Background: the pill's own glass tint, through LibGlass.
local tints = {}
local realTint = GlassUF.Glass.SetSurfaceTint
GlassUF.Glass.SetSurfaceTint = function(g, ...) tints[#tints + 1] = { g, ... }; return realTint(g, ...) end
S.SetCastColor("background", 0.1, 0.1, 0.2, 0.9)
local hit = false
for _, t in ipairs(tints) do if t[1] == tc.glass and t[3] == 0.1 and t[5] == 0.9 then hit = true end end
check(hit, "background: SetSurfaceTint on each pill")
tints = {}
S.ResetCastColors()
hit = false
for _, t in ipairs(tints) do if t[1] == tc.glass and t[2] == nil then hit = true end end
check(hit, "reset: SetSurfaceTint(g), the pill's own tint back")
GlassUF.Glass.SetSurfaceTint = realTint
eq(GlassUnitFramesDB.castColors, nil, "reset: nothing saved")
-- A transparent spark is no spark.
S.SetCastColor("spark", 1, 1, 1, 0)
local g8 = guid()
cast("player", g8)
check(not pc.spark._shown, "spark alpha 0: hidden")
stop("player", g8); WoW.flushTimers()
S.SetCastColor("spark", nil)

-- The colour picker: the client's ColorPickerFrame; cancel puts it back.
local picker = CreateFrame("Frame", "ColorPickerFrame", UIParent)
local info
rawset(picker, "SetupColorPickerAndShow", function(self, i) info = i end)
rawset(picker, "GetColorRGB", function() return 0.2, 0.4, 0.6 end)
rawset(picker, "GetColorAlpha", function() return 0.5 end)
local O = GlassUF.Options
O._test.castPage._scripts.OnShow(O._test.castPage)
local sw = O._test.controls.castSwatches.channel
sw._scripts.OnClick(sw)
check(info and info.swatchFunc, "the swatch opens the picker")
eq(info.hasOpacity, false, "no opacity for a fill colour")
info.swatchFunc()
eq(Castbar.colors.channel[3], 0.6, "picked colour applied")
eq(Castbar.colors.channel[4], 1, "alpha 1 without opacity")
info.cancelFunc()
eq(GlassUnitFramesDB.castColors, nil, "cancel: back to the default, nothing saved")
local bgs = O._test.controls.castSwatches.background
bgs._scripts.OnClick(bgs)
eq(info.hasOpacity, true, "the background has an opacity")
info.opacityFunc()
eq(Castbar.colors.background[4], 0.5, "its alpha from the picker")
S.ResetCastColors()

-- The ms figure inside the block on a bar tall enough (Quartz).
S.SetCastDetached("player", true)
S.SetCastSize("player", nil, 26)   -- bar 26 - 6 = 20 px
pc.bar._height = 20
local g9 = guid()
WoW.fire("CURRENT_SPELL_CAST_CHANGED", false)
cast("player", g9)
local p = pc.lagText._points[1]
check(p[1] == "BOTTOMRIGHT" and p[2] == pc.bar, "the ms figure inside the block, bottom right")
stop("player", g9); WoW.flushTimers()
S.SetCastDetached("player", false)

-- Saved colours are validated at load: junk falls back to the default.
local saved = GlassUnitFramesDB
saved.castColors = { cast = { 2, 0, 0 }, time = "x", spark = { 1, 0, 0, 0.5 } }
saved.castPrecision = 7
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
Castbar = GlassUF.Castbar
eq(Castbar.colors.cast[1], Castbar.DEFAULT_COLORS.cast[1], "a bad casting colour: the default")
eq(Castbar.colors.time, Castbar.DEFAULT_COLORS.time, "a junk entry: the default")
eq(Castbar.colors.spark[4], 0.5, "a good one is kept")
eq(Castbar.precision, 1, "a bad precision: 1")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
GlassUnitFramesDB = nil
done("test_castlook")
