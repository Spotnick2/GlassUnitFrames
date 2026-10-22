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

-- Docked (the default, #142): the player's row inside the body, the target's pill.
check(not Castbar.IsDetached("player") and not Castbar.IsDetached("target"), "docked by default")
eq(pc.host._points[1][1], "ALL", "player: the host covers the body")
check(not pc.skin._shown, "player docked: no pill")
check(tc.skin._shown, "target docked: its pill")
eq(tc.host._points[1][2], tg.body, "target: the pill under the body")
eq(pc.host._scale, 1, "docked: scale 1")
eq(GlassUnitFramesDB.castBars, nil, "nothing saved while docked")

-- Detach the player's bar mid-cast: its own pill on the screen, at the
-- default spot and size, and the frame's rows back to idle.
WoW.units.player.casting = { name = "Wrath", remaining = 1.2 }
WoW.fire("UNIT_SPELLCAST_START", "player"); WoW.tick()
eq(pl.health._height, 22, "docked and casting: health shrinks")
check(S.SetCastDetached("player", true), "detached")
eq(GlassUnitFramesDB.castBars.player.detached, true, "saved")
-- Its default spot is the owner's tested one (#141): (0, -182) at scale 1.5.
eq(pc.host._scale, 1.5, "at the default scale 1.5")
local p = pc.host._points[1]
check(p[1] == "CENTER" and p[2] == UIParent and p[4] == 0 and p[5] == -182 / 1.5, "at the default spot (0, -182)")
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
check(p[2] == UIParent and p[4] == 20 / 1.5 and p[5] == -100 / 1.5, "the host follows (in its scaled units)")
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
-- At its default scale 1.5 its rect is in its own units.
pc.host._center, pc.host._width, pc.host._height = { 683 / 1.5, (384 - 47) / 1.5 }, 340, 20
local function has(list, v) for _, x in ipairs(list) do if math.abs(x - v) < 1e-6 then return true end end return false end
check(has(M._test.alignLines("target", "x"), 683 - 170 * 1.5), "the bar's left edge is a line for the target")
tg._center, tg._width, tg._height = { 983, 274 }, 365, 62
check(has(M._test.alignLines("cast:player", "x"), 983 - 182.5), "the target's edge is a line for the bar")
check(not has(M._test.alignLines("cast:player", "x"), 683 - 170 * 1.5), "but not its own")
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
check(p[4] == 0 and p[5] == -182 / 1.5, "/glass reset mid-drag: the bar at its default spot")
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
-- A bar on a unit with no defaults of its own builds and detaches.
local fb = button("targettarget")
local okb = pcall(Castbar.Build, fb, fb.body, GlassUF.Frames.LAYOUT.targettarget)
check(okb, "a cast bar on a unit without defaults builds")
check(okb and Castbar.SetDetached("targettarget", true), "and detaches")
Castbar.SetDetached("targettarget", false)
Castbar.bars.targettarget = nil

-- Pet and focus (#76): thin pills, the pet's under its body, the focus's
-- above it (under it would cover the ToT row); never a latency block.
local petc, focc = button("pet").cast, button("focus").cast
check(petc and focc, "pet and focus have cast bars")
eq(petc.host:GetParent(), button("pet"), "the pet's host is its button's child")
local pp, fp = petc.host._points[1], focc.host._points[1]
check(pp[1] == "TOP" and pp[2] == button("pet").body and pp[3] == "BOTTOM", "pet: under its body")
check(fp[1] == "BOTTOM" and fp[2] == button("focus").body and fp[3] == "TOP", "focus: above its body")
eq(petc.host._height, 16, "a 16 px pill")
check(petc.lag == nil and focc.lag == nil, "no latency block (other units' timing is never read)")
-- Their casts paint like the target's.
WoW.units.focus.casting = { name = "Heal", remaining = 2 }
WoW.fire("UNIT_SPELLCAST_START", "focus", "Cast-3-1-1-1-2054-F1", 2054); WoW.tick()
check(focc.host._shown and textOf(focc.spell) == "Heal", "the focus's cast shows")
eq(focc.latestGUID, "Cast-3-1-1-1-2054-F1", "its newest guid")
-- A focus change forgets the old focus's cast state; the target's is untouched.
local tGuid = tc.latestGUID
WoW.fire("PLAYER_FOCUS_CHANGED"); WoW.tick()
eq(focc.latestGUID, nil, "a focus change forgets the old focus's guid")
eq(tc.latestGUID, tGuid, "the target's cast state is untouched")
WoW.units.focus.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "focus"); WoW.tick()
-- A new pet (UNIT_PET) does the same for the pet's bar.
WoW.units.pet.casting = { name = "Firebolt", remaining = 1 }
WoW.fire("UNIT_SPELLCAST_START", "pet", "Cast-3-1-1-1-3110-P1", 3110); WoW.tick()
eq(petc.latestGUID, "Cast-3-1-1-1-3110-P1", "the pet's newest guid")
WoW.fire("UNIT_PET", "player"); WoW.tick()
eq(petc.latestGUID, nil, "a new pet forgets the old pet's guid")
WoW.units.pet.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "pet"); WoW.tick()
-- Detachable: their own defaults, their own movers.
S.SetCastDetached("pet", true)
pp = petc.host._points[1]
check(pp[2] == UIParent and pp[4] == 0 and pp[5] == -71, "pet detached: under the player's bar (0, -71)")
check(petc.host._width == 220 and petc.host._height == 16, "220 x 16")
S.SetCastDetached("focus", true)
fp = focc.host._points[1]
check(fp[2] == UIParent and fp[4] == 0 and fp[5] == 1, "focus detached: above the target's bar (0, 1)")
check(M.Unlock(), "unlocked")
check(M._test.movers["cast:pet"]._shown and M._test.movers["cast:focus"]._shown, "movers for both")
eq(M._test.sources["cast:pet"].label, "Pet cast bar", "labelled")
M.Lock()
S.SetCastDetached("pet", false); S.SetCastDetached("focus", false)
eq(petc.host._points[1][2], button("pet").body, "attached: back under the pet")

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
check(p[4] == 0 and p[5] == -182 / 1.5, "bad x / y: the default spot")
check(pc.host._width == 340 and pc.host._height == 20, "bad w / h: the default size")
check(not GlassUF.Castbar.IsDetached("target"), "a junk entry: docked")

-- A saved bar comes back where it was.
saved.castBars = { player = { detached = true, x = 10, y = 20, w = 300, h = 24 } }
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
pc = button("player").cast
p = pc.host._points[1]
check(p[4] == 10 / 1.5 and p[5] == 20 / 1.5, "the saved spot (at the default scale)")
check(pc.host._width == 300 and pc.host._height == 24, "the saved size")
eq(pc.bar._height, 24 - 2 * inset, "the bar at the saved height")

-- Scale (owner's ask): the spot stays in screen units at any scale.
Castbar = GlassUF.Castbar
S = GlassUF.Settings
check(S.SetCastScale("player", 1.5), "scaled")
eq(pc.host._scale, 1.5, "the host scales")
eq(GlassUnitFramesDB.castBars.player.scale, 1.5, "saved")
p = pc.host._points[1]
check(p[4] == 10 / 1.5 and p[5] == 20 / 1.5, "SetPoint offsets divided by the scale: the same screen spot")
Castbar.SetPosition("player", 30, -60)
p = pc.host._points[1]
check(p[4] == 30 / 1.5 and p[5] == -60 / 1.5, "a move at scale 1.5 too")
eq(GlassUnitFramesDB.castBars.player.x, 30, "saved in screen units")
S.SetCastScale("player", 9)
eq(Castbar.ScaleOf("player"), 2, "clamped to 2")
S.SetCastScale("player", 0.73)
eq(Castbar.ScaleOf("player"), 0.75, "in 0.05 steps")
-- Docked bars never scale.
S.SetCastDetached("player", false)
eq(pc.host._scale, 1, "docked: scale 1")
S.SetCastDetached("player", true)
eq(pc.host._scale, 0.75, "detached again: its scale back")

-- Center X: the exact horizontal middle, y kept.
check(S.CenterCast("player"), "centred")
eq(GlassUnitFramesDB.castBars.player.x, 0, "x = 0")
eq(GlassUnitFramesDB.castBars.player.y, -60, "y kept")
S.SetCastDetached("target", false)   -- detached by default (#141)
check(not S.CenterCast("target"), "a docked bar isn't centred")

-- The nudge panel: Scale and Center X.
UIParent._center = { 683, 384 }
M = GlassUF.Movers
check(M.Unlock(), "unlocked")
local mcs = M._test.movers["cast:player"]
mcs._scripts.OnMouseUp(mcs)
local nps = M._test.panel()
eq(nps.s._text, "0.75", "the panel shows the scale")
nps.s:SetText("1.25"); nps.s._scripts.OnEnterPressed(nps.s)
eq(pc.host._scale, 1.25, "typed scale applies")
Castbar.SetPosition("player", 40, -60)
nps.buttons.center._scripts.OnClick(nps.buttons.center)
eq(GlassUnitFramesDB.castBars.player.x, 0, "Center X from the panel")
-- A unit's Center X centres it alone: its mirror partner stays.
local tx = GlassUF.Frames.PositionOf("target")
M._test.movers.player._scripts.OnMouseUp(M._test.movers.player)
nps.buttons.center._scripts.OnClick(nps.buttons.center)
eq(GlassUnitFramesDB.pos.player[4], 0, "the player frame centred")
eq((GlassUF.Frames.PositionOf("target")), tx, "its mirror partner left alone")
-- Alignment in screen units: a scaled bar's own rect is in its own units.
pc.host._center, pc.host._width, pc.host._height = { 683 / 1.25, 300 / 1.25 }, 340, 20
rawset(pc.host, "GetEffectiveScale", function() return 0.64 * 1.25 end)
local function has2(list, v) for _, x in ipairs(list) do if math.abs(x - v) < 1e-6 then return true end end return false end
check(has2(M._test.alignLines("target", "x"), 683 - 170 * 1.25), "a scaled bar's left edge, in screen units")
rawset(pc.host, "GetEffectiveScale", nil)
M.Lock()

-- Options: its own "Cast bars" sub-page, registered right after the main page.
local O = GlassUF.Options
local cp = O._test.castPage
local subs = WoW.settings.subs or {}
check(subs[1] and subs[1].frame == cp and subs[1].parent == WoW.settings.canvas, "a sub-page under the main page")
eq(subs[1] and subs[1].name, "Cast bars", "named Cast bars")
check(not cp._shown, "hidden at creation (else blank on the first visit)")
O._test.panel._scripts.OnShow(O._test.panel)
check(O._test.controls.castDetach == nil, "the main page no longer builds the cast controls")
cp._scripts.OnShow(cp)
local C = O._test.controls
-- One set of per-bar controls, for the bar picked in "Settings for" (#78).
local function pick(unit)
    for _, rb in ipairs(C.castBarRow) do
        if rb.value == unit then rb._scripts.OnClick(rb) end
    end
end
eq(#C.castBarRow, 5, "Settings for: You, Target, Focus, Pet, Swing (#87)")
local cb = C.castDetach
eq(cb:GetParent(), cp, "on the sub-page")
pick("target")
eq(cb:GetChecked(), false, "the target's bar: docked")
eq(C.castCenter._enabled, false, "docked: Center horizontally disabled")
cb:SetChecked(true); cb._scripts.OnClick(cb)
check(GlassUF.Castbar.IsDetached("target"), "ticking it detaches the target's bar")
eq(C.castCenter._enabled, true, "detached on the same page: Center enabled at once")
cb:SetChecked(false); cb._scripts.OnClick(cb)
eq(C.castCenter._enabled, false, "attached on the same page: Center disabled at once")
cb:SetChecked(true); cb._scripts.OnClick(cb)
pick("player")
check(cb:GetChecked(), "picking You shows the player's saved state")
local sl = C.castScale
eq(sl._value, 1.25, "the scale slider shows the picked bar's scale")
sl._scripts.OnValueChanged(sl, 1.5)
eq(GlassUF.Castbar.ScaleOf("player"), 1.5, "the slider sets it")
-- Width and height sliders (the owner's ask), not just scale.
C.castWidth._scripts.OnValueChanged(C.castWidth, 402)
eq((GlassUF.Castbar.SizeOf("player")), 402, "the width slider, whole units (as the unlock panel types them)")
C.castHeight._scripts.OnValueChanged(C.castHeight, 26)
eq(select(2, GlassUF.Castbar.SizeOf("player")), 26, "the height slider")
eq(pc.host._height, 26, "the bar follows")
pick("pet")
eq(C.castWidth._value, 220, "picking Pet shows the pet's width")
Castbar.SetPosition("player", 40, -60)
pick("player")
C.castCenter._scripts.OnClick(C.castCenter)
eq(GlassUnitFramesDB.castBars.player.x, 0, "Center horizontally from the page")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
GlassUnitFramesDB = nil
done("test_castbar_layout")
