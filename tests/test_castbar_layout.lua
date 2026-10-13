-- Detachable cast bars (#74): docked vs detached geometry, the player's rows,
-- levels and mouse, saved-value validation, the unlock movers (W/H, Attach),
-- the unlock dialog, combat, and the ms figure on a detached bar.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
local Castbar, M, S = GlassUF.Castbar, GlassUF.Movers, GlassUF.Settings
local pl, tg = button("player"), button("target")
local pc, tc = pl.cast, tg.cast
local inset = GlassUF.Glass.Inset("small")

-- Every host is a child of its button: it hides with it (no target, no pill).
eq(pc.host:GetParent(), pl, "the player's host is a child of its button")
eq(tc.host:GetParent(), tg, "the target's too")
-- No mouse anywhere in a cast bar: clicks reach the secure button.
local function underHost(w, host)
    local p = w._parent
    while p do if p == host then return true end; p = p._parent end
    return false
end
local mouse = {}
for _, w in ipairs(WoW.frames) do
    if (w == pc.host or underHost(w, pc.host) or w == tc.host or underHost(w, tc.host)) and w._mouse then
        mouse[#mouse + 1] = w._type
    end
end
eq(#mouse, 0, "no mouse on a cast bar or its children")
-- Levels: the pill's rims under the text, the latency block between the bar's
-- fill and its glass overlay.
for _, c in ipairs({ pc, tc }) do
    local H = c.host:GetFrameLevel()
    eq(c.skin:GetFrameLevel(), H, "the pill at the host's level")
    check(c.bar:GetFrameLevel() > H, "the bar over the pill")
    check(c.txt:GetFrameLevel() > H + 10, "the text above the pill's rims (H + 10)")
    check(c.txt:GetFrameLevel() > c.bar.overlay:GetFrameLevel(), "and above the bar's glass overlay")
end
local lagClip = pc.lag:GetParent()
check(lagClip:GetFrameLevel() > pc.bar:GetFrameLevel() and lagClip:GetFrameLevel() < pc.bar.overlay:GetFrameLevel(),
      "the latency block between the fill and the glass overlay")

-- Docked (the default): the player's row inside the body, the target's pill.
check(not Castbar.IsDetached("player") and not Castbar.IsDetached("target"), "docked by default")
eq(pc.host._points[1][1], "ALL", "player: the host covers the body")
check(not pc.skin._shown, "player docked: no pill")
check(tc.skin._shown, "target docked: its pill")
eq(tc.host._points[1][2], tg.body, "target: the pill under the body")
eq(GlassUnitFramesDB.castBars, nil, "nothing saved while docked")

-- Detach the player's bar mid-cast: its own pill on the screen, at the
-- default spot and size, and the frame's rows back to idle.
WoW.units.player.casting = { name = "Wrath", remaining = 1.2 }
WoW.fire("UNIT_SPELLCAST_START", "player"); WoW.tick()
eq(pl.health._height, 22, "docked and casting: health shrinks")
check(S.SetCastDetached("player", true), "detached")
eq(GlassUnitFramesDB.castBars.player.detached, true, "saved")
local p = pc.host._points[1]
check(p[1] == "CENTER" and p[2] == UIParent and p[4] == 0 and p[5] == -47, "at the default spot (0, -47)")
eq(pc.host._width, 340, "default width")
eq(pc.host._height, 20, "default height")
check(pc.skin._shown, "detached: its own glass pill")
eq(pc.bar._points[1][2], pc.host, "the bar inside the pill")
eq(pc.bar._height, 20 - 2 * inset, "the bar fills the pill's height")
eq(pl.health._height, 34, "detached mid-cast: the frame's rows back to idle")
check(pc.host._shown, "the cast still shows")
-- A cast while detached leaves the rows alone.
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player"); WoW.tick()
WoW.units.player.casting = { name = "Wrath", remaining = 1.2 }
WoW.fire("UNIT_SPELLCAST_START", "player"); WoW.tick()
eq(pl.health._height, 34, "a detached cast doesn't shrink the rows")

-- The ms figure: shown above a detached bar (the GetNetStats fallback here).
eq(textOf(pc.lagText), "~33ms", "detached: the ms figure, ~ for the fallback")
eq(pc.lagText._points[1][1], "BOTTOMRIGHT", "above the block's end (right, for a cast)")
S.SetCastOption("latencyText", false); WoW.tick()
eq(textOf(pc.lagText), "", "the option off hides it")
eq(GlassUnitFramesDB.castLatencyText, false, "saved when off")
S.SetCastOption("latencyText", true); WoW.tick()

-- Unlock: a mover for the detached bar, a source of its own.
check(M.Unlock(), "unlocked")
local mc = M._test.movers["cast:player"]
check(mc and mc._shown, "the detached bar has a mover")
eq(mc._points[1][2], pc.host, "over the bar's host")
check(M._test.movers["cast:target"] == nil, "a docked bar has none")
check(M._test.dialog()._shown, "the unlock dialog shows")
-- Dragging it saves its own entry, never db.pos, and mirrors nothing.
WoW.alt = true   -- free placement
local tBefore = GlassUnitFramesDB.pos.target
mc._center = { 683 + 20, 384 - 100 }
mc._scripts.OnDragStart(mc); mc._scripts.OnUpdate(mc); mc._scripts.OnDragStop(mc)
eq(GlassUnitFramesDB.castBars.player.x, 20, "dragged: x saved in castBars")
eq(GlassUnitFramesDB.castBars.player.y, -100, "and y")
eq(GlassUnitFramesDB.pos["cast:player"], nil, "never in the unit positions")
eq(GlassUnitFramesDB.pos.target, tBefore, "no mirroring for a cast bar")
p = pc.host._points[1]
check(p[2] == UIParent and p[4] == 20 and p[5] == -100, "the host follows")
eq(M._test.selected(), "cast:player", "the dragged bar is selected")
-- The nudge panel: W/H and Attach for a cast bar, not for a unit.
local np = M._test.panel()
check(np.w._shown and np.h._shown and np.buttons.attach._shown, "W/H and Attach for a cast bar")
eq(np.w._text, "340", "the width")
np.w:SetText("300"); np.w._scripts.OnEnterPressed(np.w)
eq(pc.host._width, 300, "typed W resizes")
np.h:SetText("99"); np.h._scripts.OnEnterPressed(np.h)
eq(pc.host._height, 40, "H clamped to its limit")
eq(pc.bar._height, 40 - 2 * inset, "the bar follows the height")
M._test.nudge(0, 1)
eq(GlassUnitFramesDB.castBars.player.y, -99, "arrows nudge it")
-- Reset: the default spot and size, still detached.
np.buttons.reset._scripts.OnClick(np.buttons.reset)
eq(GlassUnitFramesDB.castBars.player.x, nil, "reset: spot forgotten")
eq(pc.host._width, 340, "reset: default size")
check(Castbar.IsDetached("player"), "reset keeps it detached")
-- A unit's panel: no W/H, no Attach.
M._test.movers.target._scripts.OnMouseUp(M._test.movers.target)
check(not np.w._shown and not np.buttons.attach._shown, "no W/H or Attach for a unit")
-- Alignment: the detached bar's edges are lines for a unit, and the reverse.
pc.host._center, pc.host._width, pc.host._height = { 683, 384 - 47 }, 340, 20
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
check(has(M._test.alignLines("target", "x"), 683 - 170), "the bar's left edge is a line for the target")
tg._center, tg._width, tg._height = { 983, 274 }, 365, 62
check(has(M._test.alignLines("cast:player", "x"), 983 - 182.5), "the target's edge is a line for the bar")
check(not has(M._test.alignLines("cast:player", "x"), 683 - 170), "but not its own")
-- Attach from the panel: docked again, its mover and panel gone.
mc._scripts.OnMouseUp(mc)
np.buttons.attach._scripts.OnClick(np.buttons.attach)
check(not Castbar.IsDetached("player"), "attached")
eq(GlassUnitFramesDB.castBars, nil, "nothing left to save: pruned")
check(not mc._shown, "its mover goes")
check(not np._shown, "and the panel with it")
eq(pl.health._height, 22, "docked again mid-cast: the rows shrink")
check(not pc.skin._shown, "no pill once docked")
WoW.tick()   -- the repaint SetDetached asked for
check(pc.lag._shown, "the block still shows docked")
eq(textOf(pc.lagText), "", "no ms figure docked")
-- Detaching while unlocked brings its mover.
S.SetCastDetached("target", true)
check(M._test.movers["cast:target"]._shown, "detaching while unlocked shows its mover")
M.Lock()
check(not M._test.dialog()._shown and not M._test.movers["cast:target"]._shown, "Lock hides the dialog and the movers")

-- The target's detached bar is still the button's child: no target, no bar.
eq(tc.host:GetParent(), tg, "detached, still the button's child")
tg:Hide()
check(not tc.host:IsVisible(), "the target gone: its detached bar hides with the button")
tg:Show()
S.SetCastDetached("target", false)

-- In combat: detach and attach touch nothing protected.
WoW.combat = true
check(S.SetCastDetached("player", true), "detach in combat")
check(S.SetCastDetached("player", false), "attach in combat")
eq(#WoW.blocked, 0, "nothing protected touched: " .. table.concat(WoW.blocked, ", "))
WoW.combat = false
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player"); WoW.tick()

-- Review fixes (/code-review, #75).
-- Detaching repaints only that bar's frame: a target mid-cast keeps its token.
WoW.units.target.casting = { name = "Fireball" }
WoW.fire("UNIT_SPELLCAST_START", "target"); WoW.tick()
local ttok = tc.token
S.SetCastDetached("player", true); WoW.tick()
eq(tc.token, ttok, "detaching the player's bar leaves the target's alone")
WoW.units.target.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "target"); WoW.tick()
-- Typing only W keeps H on its default (a later default change still reaches it).
Castbar.SetSize("player", 300, nil)
eq(GlassUnitFramesDB.castBars.player.h, nil, "only the dimension given is saved")
-- "Reset frame positions" mid-drag: the bar goes back to its default spot and
-- size, not to the unsaved spot the dropped drag left it at.
check(M.Unlock(), "unlocked again")
local mc2 = M._test.movers["cast:player"]
mc2._center = { 683 + 50, 384 - 150 }
mc2._scripts.OnDragStart(mc2); mc2._scripts.OnUpdate(mc2)
SlashCmdList.GLASSUNITFRAMES("reset")
mc2._scripts.OnDragStop(mc2)
p = pc.host._points[1]
check(p[4] == 0 and p[5] == -47, "/glass reset mid-drag: the bar at its default spot")
eq(pc.host._width, 340, "and its default size")
check(Castbar.IsDetached("player"), "still detached")
-- Attach with an X typed but not committed: its Enter does nothing (no error).
mc2._scripts.OnMouseUp(mc2)
local np3 = M._test.panel()
np3.x:SetFocus(); np3.x:SetText("12")
np3.buttons.attach._scripts.OnClick(np3.buttons.attach)
check(not np3.x:HasFocus(), "attaching drops the pending edit")
local ok3 = pcall(np3.x._scripts.OnEnterPressed, np3.x)
check(ok3, "a late Enter on the gone bar's X doesn't throw")
-- The dialog: under the nudge panel, and movable out of the way.
local dlg = M._test.dialog()
check(dlg:GetFrameLevel() < np3:GetFrameLevel(), "the dialog under the nudge panel")
check(dlg._scripts.OnDragStart ~= nil, "the dialog can be dragged aside")
M.Lock()
-- A bar on a unit with no defaults of its own (focus, later) builds and detaches.
local fb = button("focus")
local okb, fc = pcall(Castbar.Build, fb, fb.body, GlassUF.Frames.LAYOUT.focus)
check(okb, "a cast bar on a unit without defaults builds")
check(okb and Castbar.SetDetached("focus", true), "and detaches")
Castbar.SetDetached("focus", false)
Castbar.bars.focus = nil

-- Saved entries are validated field by field: junk falls back to defaults,
-- and the build goes on.
local saved = GlassUnitFramesDB
saved.castBars = { player = { detached = true, x = "a", y = 1 / 0, w = 5000, h = -3 }, target = "junk" }
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
for _, u in ipairs(GlassUF.Frames.ORDER) do check(button(u) ~= nil, u .. " built despite bad cast saves") end
pc = button("player").cast
check(GlassUF.Castbar.IsDetached("player"), "the detached flag is kept")
p = pc.host._points[1]
check(p[4] == 0 and p[5] == -47, "bad x / y: the default spot")
check(pc.host._width == 340 and pc.host._height == 20, "bad w / h: the default size")
check(not GlassUF.Castbar.IsDetached("target"), "a junk entry: docked")

-- A saved bar comes back where it was.
saved.castBars = { player = { detached = true, x = 10, y = 20, w = 300, h = 24 } }
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
pc = button("player").cast
p = pc.host._points[1]
check(p[4] == 10 and p[5] == 20, "the saved spot")
check(pc.host._width == 300 and pc.host._height == 24, "the saved size")
eq(pc.bar._height, 24 - 2 * inset, "the bar at the saved height")

-- Options: a Detach box per bar, wired to the settings.
local O = GlassUF.Options
O._test.panel._scripts.OnShow(O._test.panel)
local cb = O._test.controls.castDetach_target
check(cb ~= nil, "a Detach box for the target's bar")
cb:SetChecked(true); cb._scripts.OnClick(cb)
check(GlassUF.Castbar.IsDetached("target"), "ticking it detaches the bar")
check(O._test.controls.castDetach_player:GetChecked(), "the player's box shows its saved state")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
GlassUnitFramesDB = nil
done("test_castbar_layout")
