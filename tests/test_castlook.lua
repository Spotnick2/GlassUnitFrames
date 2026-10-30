-- The look and options on the cast bars (#78): the spell icon, "Spell ->
-- Target", "remaining / total", the precision, the spark, the complete flash,
-- the colours (validated, saved, applied; the picker), the ms figure inside
-- the block.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
-- Docked bars (detached by default since #141): the player's 14 px row, the target's pill.
loadAddon({ db = { castBars = { player = { detached = false }, target = { detached = false } } } })
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

-- The icon: yours on the left, the target's on the right (the mirrored
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
eq(GlassUnitFramesDB.castBars.player.icon, nil, "the default again: the icon side not saved")
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
rawset(picker, "SetupColorPickerAndShow", function(self, i) info = i; self:Show() end)
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

-- The ms figure inside the block on a bar tall enough.
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

-- Review fixes (/code-review, #79).
Castbar = GlassUF.Castbar
-- Self-cast, in every form of our name (Forever: "First Surname"; UnitName
-- gives the first name with the surname where the realm should be).
WoW.units.player.name = "Karuzo Macphisto"
for _, form in ipairs({ "Karuzo Macphisto", "Karuzo" }) do
    local gs = guid()
    cast("player", gs, nil, { sentTo = form })
    eq(textOf(pc.spell), "Greater Heal", "no arrow on a self-cast named '" .. form .. "'")
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", gs, 2061, "CastBar-1")
    stop("player", gs); WoW.flushTimers()
end
WoW.units.player.name = "Morphisto"
-- The player's complete flash needs this cast's SUCCEEDED: a cast that stops
-- without one (failed as it landed) doesn't flash green.
local gn = guid()
cast("player", gn)
stop("player", gn)
check(not pc.host._shown, "no SUCCEEDED: no complete flash")
-- A nil name with a target set never reaches %s.
local gz = guid()
cast("player", gz, nil, { sentTo = "Someone Else" })
WoW.units.player.casting.name = nil
GlassUF.Engine.FullRepaint(pl); WoW.tick()
eq(GlassUF.paintFailures["cast name"], nil, "a nil name: no paint failure")
stop("player", gz); WoW.flushTimers()
-- A new unit forgets the old one's failed mark (an unreadable guid's true).
tc.failedGUID = true
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(tc.failedGUID, nil, "a target change forgets the failed mark")
-- The ms figure goes inside the block only from a 20 px bar (under that it
-- runs into the time text): above the detached bar at 18.
S.SetCastDetached("player", true)
pc.bar._height = 18
local gm = guid()
WoW.fire("CURRENT_SPELL_CAST_CHANGED", false)
cast("player", gm)
eq(pc.lagText._points[1][2], pc.host, "an 18 px bar: the ms figure above the bar")
stop("player", gm); WoW.flushTimers()
S.SetCastDetached("player", false)
-- The picker reports its starting colour on opening: nothing saved; and its
-- strata is given back when it closes (it's shared).
picker:Hide()   -- the earlier session closes, as it would in game
picker._strata = "DIALOG"
picker:Show()
picker:Hide()
local d = Castbar.DEFAULT_COLORS.cast
rawset(picker, "GetColorRGB", function() return d[1], d[2], d[3] end)
local cs = O._test.controls.castSwatches.cast
cs._scripts.OnClick(cs)
eq(picker._strata, "FULLSCREEN_DIALOG", "raised over the Settings window while open")
info.swatchFunc()
eq(GlassUnitFramesDB.castColors, nil, "an unchanged default: nothing saved")
picker:Hide()
eq(picker._strata, "DIALOG", "its own strata back when it closes")
-- Dragged away and back to the starting default: the override goes (Codex).
cs._scripts.OnClick(cs)
rawset(picker, "GetColorRGB", function() return 0.1, 0.2, 0.3 end)
info.swatchFunc()
eq(GlassUnitFramesDB.castColors.cast[1], 0.1, "dragged away: saved")
rawset(picker, "GetColorRGB", function() return d[1], d[2], d[3] end)
info.swatchFunc()
eq(GlassUnitFramesDB.castColors, nil, "back to the default: the override cleared")
eq(Castbar.colors.cast[1], d[1], "and the bar's colour is the default again")
picker:Hide()
-- A refused instant (SENT, FAILED, no START) after a cast with an icon: the
-- red flash doesn't show the previous spell's icon (Codex).
local gp = guid()
cast("player", gp)
check(pc.icon._shown, "the cast's icon")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", gp, 2061, "CastBar-1")
stop("player", gp); WoW.flushTimers()
local gi = guid()
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", gi, 139)
WoW.fire("UNIT_SPELLCAST_FAILED", "player", gi, 139)
check(pc.host._shown and textOf(pc.spell) == "Failed", "the refused instant flashes")
check(not pc.icon._shown, "without the previous spell's icon")
WoW.flushTimers()
-- An interrupt of the cast shown keeps its own icon.
local gk = guid()
cast("player", gk)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", gk, 2061, nil, "CastBar-1")
stop("player", gk)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", gk, 2061, nil, nil)
check(pc.host._shown and pc.icon._shown, "an interrupt keeps the interrupted cast's icon")
WoW.flushTimers()
-- A target change, then a FAILED with no START on the new target: no newest
-- guid to compare, so the old target's icon must already be gone (Codex).
local gt = guid()
cast("target", gt)
check(tc.icon._shown, "the target's cast icon")
stop("target", gt); WoW.tick(); WoW.flushTimers()
WoW.SetUnit("target", { name = "Defias Pillager", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
WoW.fire("UNIT_SPELLCAST_FAILED", "target", guid(), 2061)
check(tc.host._shown and textOf(tc.spell) == "Failed", "the new target's failure flashes")
check(not tc.icon._shown, "without the old target's icon")
WoW.flushTimers()
-- A new target picked mid-cast: the repaint shows its icon.
WoW.SetUnit("target", { name = "Defias Pillager", reaction = 2 })
WoW.units.target.casting = { name = "Fireball", guid = guid(), spellID = 133, total = 3, remaining = 2,
                             startMs = WoW.now * 1000, endMs = (WoW.now + 3) * 1000, delayMs = 0 }
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(tc.host._shown and tc.icon._shown, "a target picked mid-cast shows its icon")
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "target", nil, 133); WoW.tick(); WoW.flushTimers()

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
