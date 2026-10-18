-- The swing timer rows (#87): main hand, off hand, ranged, from PLAYER_SWING.
-- Rows appear on their first swing and stay until combat ends; docked inside
-- the player frame (Frames.ReflowRows), detachable; range dimming with
-- EnableRangeCheck(true) only; Blizzard's own bars through its option (a CVar).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
-- The classic look: the docked rows' documented heights are its rim's (#129).
loadAddon({ db = { look = "classic" } })
local Swing, Castbar, S = GlassUF.Swing, GlassUF.Castbar, GlassUF.Settings
local pl = button("player")
local sw = Castbar.bars.swing
check(sw ~= nil, "the swing rows are built on the player frame")
local rows = sw.rows
local MH, OH, RANGED = rows[1], rows[2], rows[3]
local idleHealth = pl.rows.idle.health

local function combat(on)
    WoW.units.player.combat = on
    WoW.fire("PLAYER_IN_COMBAT_CHANGED", on)
end
local function swing(dur, t) WoW.fire("PLAYER_SWING", dur, t) end
local function after(s) WoW.now = WoW.now + s; WoW.tick(0.06) end
local function shownRows()
    local n = 0
    for _, r in ipairs(rows) do if r.bar._shown then n = n + 1 end end
    return n
end
-- Blizzard's own EnableRangeCheck(type, false) calls, made by this test: the
-- only falses the log may hold.
local blizzFalses = 0
local function blizzardFalse(t)
    blizzFalses = blizzFalses + 1
    C_SwingTimer.EnableRangeCheck(t, false)
end
local function noFalse()
    local n = 0
    for _, c in ipairs(WoW.rangeChecks) do if c[2] ~= true then n = n + 1 end end
    return n == blizzFalses
end

-- Nothing before a swing.
eq(shownRows(), 0, "no row before the first swing")
check(not sw.host._shown, "the host hides with no row")
eq(pl.swingCount, 0, "the player frame holds no swing row")
eq(pl.health:GetHeight(), idleHealth, "health at its idle height")

-- An out-of-combat swing (a pull's opener): its row shows for that swing.
swing(2.5, 0)
check(MH.visible and MH.bar._shown and MH.live, "a main-hand swing shows its row")
eq(MH.bar._timer.duration._dur, 2.5, "the fill is the swing's duration (SetTimerDuration)")
eq(MH.bar._timer.dir, Enum.StatusBarTimerDirection.ElapsedTime, "filling up")
eq(pl.swingCount, 1, "one docked row")
eq(pl.health:GetHeight(), idleHealth - 4, "health gives 4 px (3 px row + 1 px gap)")
eq(sw.host._points[1][2], pl.power, "docked under the power bar")
eq(WoW.rangeChecks[#WoW.rangeChecks][1], 0, "range checks asked for its type")
after(1)
check(MH.bar._shown, "still there mid-swing")
after(2)
check(not MH.live and not MH.bar._shown, "out of combat, the row goes when its swing is over")
eq(pl.swingCount, 0, "and gives its room back")
eq(pl.health:GetHeight(), idleHealth, "health back to its idle height")

-- In combat: rows stay until combat ends; order MH, OH, Ranged whatever came first.
combat(true)
swing(2.0, 1)
swing(2.6, 0)
eq(shownRows(), 2, "two rows")
eq(MH.bar._points[1][5], 0, "main hand on top")
eq(OH.bar._points[1][5], -4, "off hand under it")
eq(pl.health:GetHeight(), idleHealth - 8, "health gives 8 px for two rows")
after(3)
check(not MH.live and MH.bar._shown, "in combat, an idle row stays")
eq(MH.bar._timer.dir, Enum.StatusBarTimerDirection.RemainingTime, "idle: a finished duration (an empty bar)")
WoW.fire("PLAYER_IN_COMBAT_CHANGED", true)
eq(shownRows(), 2, "still in combat: still two rows")
combat(false)
eq(shownRows(), 0, "combat over: the idle rows go")

-- Secret payloads are ignored (no row, no failure).
swing(WoW.Secret("dur"), 0)
swing(2, WoW.Secret("type"))
swing(0, 0)
swing(-1, 0)
eq(shownRows(), 0, "a secret, zero or negative swing shows nothing")

-- Weapon swap / death: out of combat the row goes at once, in combat it idles.
swing(2.5, 0)
WoW.fire("WEAPON_SLOT_CHANGED")
check(not MH.bar._shown, "out of combat, a weapon swap drops the row at once")
combat(true)
swing(2.5, 0)
WoW.fire("WEAPON_SLOT_CHANGED")
check(MH.bar._shown and not MH.live, "in combat, it idles")
swing(2.5, 0)
WoW.fire("PLAYER_DEAD")
check(MH.bar._shown and not MH.live, "death idles the rows too")
combat(false)
eq(shownRows(), 0, "and they go when combat ends")

-- Range: dimmed only on a plain out-of-reach verdict from a checking type.
combat(true)
swing(2.5, 0)
WoW.fire("PLAYER_SWING_RANGE_UPDATE", 0, false, true)
eq(MH.bar:GetAlpha(), 0.4, "out of reach: dimmed")
WoW.fire("PLAYER_SWING_RANGE_UPDATE", 0, true, true)
eq(MH.bar:GetAlpha(), 1, "back in reach")
WoW.fire("PLAYER_SWING_RANGE_UPDATE", 0, false, false)
eq(MH.bar:GetAlpha(), 1, "not checking range: never dimmed")
WoW.fire("PLAYER_SWING_RANGE_UPDATE", 0, false, true)
WoW.fire("PLAYER_SWING_RANGE_UPDATE", 0, WoW.Secret("inRange"), true)
eq(MH.bar:GetAlpha(), 1, "a secret verdict after an out-of-reach one: unknown, not dimmed (Codex, #88)")
WoW.fire("PLAYER_SWING_RANGE_UPDATE", 0, false, true)
WoW.fire("PLAYER_SWING_RANGE_UPDATE", 0, false, WoW.Secret("checks"))
eq(MH.bar:GetAlpha(), 1, "a secret checksRange too")
local before = #WoW.rangeChecks
WoW.swingInRange[0] = false
WoW.fire("PLAYER_TARGET_CHANGED")
eq(MH.bar:GetAlpha(), 0.4, "a target change re-reads the range")
check(#WoW.rangeChecks > before, "and asks for range checks again")
WoW.swingInRange[0] = nil
WoW.fire("PLAYER_TARGET_CHANGED")
eq(MH.bar:GetAlpha(), 1, "nil (no check possible) is not out of range")

-- Blizzard's false is answered next frame, coalesced, never inside its call.
before = #WoW.rangeChecks
blizzardFalse(0)
blizzardFalse(0)
eq(#WoW.rangeChecks, before + 2, "nothing re-enabled inside Blizzard's call")
WoW.flushTimers()
eq(#WoW.rangeChecks, before + 3, "one re-enable on the next frame (coalesced)")
eq(WoW.rangeChecks[#WoW.rangeChecks][2], true, "and it's a true")
blizzardFalse(2)
WoW.flushTimers()
eq(WoW.rangeChecks[#WoW.rangeChecks][1], 2, "a type we don't show is left alone")
-- CVAR_UPDATE for Blizzard's option: ask again.
before = #WoW.rangeChecks
WoW.fire("CVAR_UPDATE", "showSwingTimer", "0")
eq(#WoW.rangeChecks, before + 1, "Blizzard's option changed: range checks asked again")
WoW.fire("CVAR_UPDATE", "someOtherCVar", "1")
eq(#WoW.rangeChecks, before + 1, "another CVar: nothing")

-- Docked reflow with the cast row: the documented heights.
local function castStart()
    WoW.units.player.casting = { name = "Heal", guid = "Cast-3-1-1-1-2050-1", spellID = 2050, total = 2.5,
                                 remaining = 1, startMs = WoW.now * 1000, endMs = (WoW.now + 2.5) * 1000, delayMs = 0 }
    WoW.fire("UNIT_SPELLCAST_START", "player", "Cast-3-1-1-1-2050-1", 2050, "CastBar-1")
end
local function castStop()
    WoW.units.player.casting = nil
    WoW.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-1-1-1-2050-1", 2050, "CastBar-1")
    WoW.flushTimers()
end
swing(2.0, 1)
eq(pl.health:GetHeight(), 26, "idle with MH + OH: health 26")
castStart()
eq(pl.health:GetHeight(), 14, "casting with MH + OH: health 14")
eq(sw.host._points[1][2], pl.cast.bar, "the swing rows go under the docked cast row")
swing(2.4, 2)
eq(pl.health:GetHeight(), 12, "casting with three rows: health at its 12 px floor")
eq(pl.power:GetHeight(), 8, "power gives the rest: 8")
castStop()
eq(pl.health:GetHeight(), 22, "cast over, three rows: health 22")
eq(pl.power:GetHeight(), pl.rows.idle.power, "power back")
eq(sw.host._points[1][2], pl.power, "under the power bar again")

-- Detached: a glass pill of stacked rows; the frame gets its room back.
check(S.SetCastDetached("swing", true), "detached")
eq(GlassUnitFramesDB.castBars.swing.detached, true, "saved with the cast bars")
eq(pl.swingCount, 0, "no docked rows")
eq(pl.health:GetHeight(), idleHealth, "health back to idle")
check(sw.skin._shown, "its glass pill shows")
local inset = GlassUF.Glass.Inset("small")
eq(sw.host:GetHeight(), 2 * inset + 3 * 6 + 2 * 2, "three 6 px rows with 2 px gaps")
eq(sw.host._points[1][1], "CENTER", "on the screen centre")
eq(sw.host._points[1][5], -66, "its default spot")
check(not MH.text._shown, "a 6 px row has no time text")
check(S.SetCastSize("swing", nil, 10), "rows 10 px")
check(MH.text._shown, "a 10 px row shows its time")
swing(2.5, 0)
after(0.5)
eq(textOf(MH.text), string.format("%.1f", 2.0), "the time left, one decimal")
check(S.SetCastSize("swing", nil, 99), "too tall: clamped")
eq(GlassUnitFramesDB.castBars.swing.h, 20, "to 20")
-- Unlock: every row shows, idle, so the pill has a size to drag.
combat(false)
WoW.combat = false
after(3)
eq(shownRows(), 0, "no rows out of combat")
check(GlassUF.Movers.Unlock(), "unlocked")
eq(shownRows(), 3, "unlocked: the detached pill shows every row")
check(GlassUF.Movers._test.movers["cast:swing"], "with a mover of its own")
GlassUF.Movers.Lock()
eq(shownRows(), 0, "locked: back to none")
-- Reset puts the size back; attach puts the rows back inside.
GlassUF.Settings.ResetPositions()
WoW.flushTimers()
local _, _, _, h = Castbar.Geometry("swing")
eq(h, 6, "reset: the default row height")
check(S.SetCastDetached("swing", false), "attached")
check(not sw.skin._shown, "no pill while docked")
swing(2.5, 0)
eq(pl.swingCount, 1, "back inside the player frame")
after(3)

-- The option off: no rows, no events, no range-check calls (even a pending one).
combat(true)
swing(2.5, 0)
blizzardFalse(0)   -- Blizzard's, queues our re-enable
before = #WoW.rangeChecks
check(S.SetSwingTimer(false), "the glass swing timer off")
eq(GlassUnitFramesDB.swingTimer, false, "saved when off")
WoW.flushTimers()
eq(#WoW.rangeChecks, before, "a pending re-enable does nothing once off")
eq(shownRows(), 0, "no rows")
eq(pl.swingCount, 0, "the player frame gives the room back")
swing(2.5, 0)
eq(shownRows(), 0, "swings are ignored")
check(S.SetSwingTimer(true), "on again")
eq(GlassUnitFramesDB.swingTimer, nil, "the default isn't saved")
swing(2.5, 0)
eq(shownRows(), 1, "swings show again")
combat(false)
after(3)
check(noFalse(), "GUF never asked for EnableRangeCheck(false)")

-- Blizzard's own bars: its option, set only from a click, out of combat.
check(Swing.BlizzardShown(), "Blizzard's bars on (the CVar)")
check(S.SetBlizzardSwing(false), "turned off")
eq(WoW.cvars.showSwingTimer, "0", "through showSwingTimer")
check(not Swing.BlizzardShown(), "reads off")
WoW.combat = true
check(not S.SetBlizzardSwing(true), "refused in combat")
eq(WoW.cvars.showSwingTimer, "0", "unchanged")
WoW.combat = false
WoW.cvarRefused = true
check(not S.SetBlizzardSwing(true), "a refused CVar write reports failure")
WoW.cvarRefused = nil

-- The Cast bars page: the swing rows in the picker, and the swing section.
local cp = GlassUF.Options._test.castPage
cp._shown = true
cp._scripts.OnShow(cp)
local C = GlassUF.Options._test.controls
local function pick(unit)
    for _, rb in ipairs(C.castBarRow) do
        if rb.value == unit then rb._scripts.OnClick(rb) end
    end
end
pick("swing")
check(not C.castIcon[1]:IsEnabled(), "the swing rows have no spell icon")
local lo, hi = C.castHeight:GetMinMaxValues()
eq(lo, 2, "the height slider: a thin row (min)")
eq(hi, 20, "max")
pick("player")
lo, hi = C.castHeight:GetMinMaxValues()
eq(lo, 12, "a cast bar's own range again")
check(C.castIcon[1]:IsEnabled(), "and its icon choice")
-- The glass rows' checkbox.
C.swingTimer:SetChecked(false); C.swingTimer._scripts.OnClick(C.swingTimer)
check(not Swing.enabled, "the checkbox turns the rows off")
C.swingTimer:SetChecked(true); C.swingTimer._scripts.OnClick(C.swingTimer)
check(Swing.enabled, "and on")
-- Blizzard's checkbox follows the CVar while the page is open, and combat.
local bz = C.blizzardSwing
check(not bz:GetChecked(), "Blizzard's bars: off (set above)")
C_CVar.SetCVar("showSwingTimer", "1")   -- changed elsewhere (Blizzard's own options)
check(bz:GetChecked(), "an outside change shows at once")
WoW.fire("PLAYER_REGEN_DISABLED")
check(not bz:IsEnabled(), "combat starts: disabled (InCombatLockdown is still false then)")
WoW.combat = true
bz:SetChecked(false); bz._scripts.OnClick(bz)
eq(WoW.cvars.showSwingTimer, "1", "a click in combat changes nothing")
check(bz:GetChecked(), "and snaps back")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(bz:IsEnabled(), "combat over: enabled")
bz:SetChecked(false); bz._scripts.OnClick(bz)
eq(WoW.cvars.showSwingTimer, "0", "a click sets Blizzard's option")
WoW.cvarRefused = true
bz:SetChecked(true); bz._scripts.OnClick(bz)
check(not bz:GetChecked(), "a refused write snaps back to the real value")
WoW.cvarRefused = nil
-- With the glass rows off, the open page still follows Blizzard's option (Codex, #88).
check(S.SetSwingTimer(false), "glass rows off")
C_CVar.SetCVar("showSwingTimer", "1")
check(bz:GetChecked(), "an outside change still shows with the glass rows off")
C_CVar.SetCVar("showSwingTimer", "0")
check(not bz:GetChecked(), "and back")
check(S.SetSwingTimer(true), "glass rows on again")
for _, k in ipairs({ "swingMH", "swingOH", "swingRanged" }) do
    check(C.castSwatches[k] ~= nil, "a colour swatch: " .. k)
end
check(S.SetCastColor("swingMH", 0.1, 0.2, 0.3), "a swing colour")
eq(MH.bar._color and MH.bar._color[1], 0.1, "reaches its row")
cp._shown = false

-- Saved junk falls back to the defaults.
local saved = GlassUnitFramesDB
saved.castBars = { swing = { detached = true, h = "x", w = 5000, x = 0/0 } }
saved.swingTimer = "maybe"
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
local x, _, w, h2, det = GlassUF.Castbar.Geometry("swing")
eq(h2, 6, "a bad row height: the default")
eq(w, 340, "a bad width: the default")
eq(x, 0, "a bad x: the default")
check(det, "detached kept")
check(GlassUF.Swing.enabled, "only false turns the rows off")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
GlassUnitFramesDB = nil
done("test_swing")
