-- Unlock mode (#34): movers, group moves through anchors, the nudge panel.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
UIParent._center = { 512, 384 }
WoW.alt = true   -- free placement for the mechanics below; snapping has its own tests
local F, M = GlassUF.Frames, GlassUF.Movers
local t, tot, focus, ft, pet = button("target"), button("targettarget"), button("focus"), button("focustarget"), button("pet")

-- Followers are anchored to their leader, CENTER on CENTER, at the offset
-- between the two default points.
eq(tot._points[1][2], t, "targettarget follows the target")
eq(tot._points[1][4], 207.5 - 300, "at the default x offset")
eq(tot._points[1][5], -54 - (-110), "and y offset")
eq(focus._points[1][2], t, "focus follows the target")
eq(ft._points[1][2], focus, "focustarget follows focus")
eq(pet._points[1][2], button("player"), "the pet follows the player")
eq(t._points[1][2], UIParent, "the target sits on the screen")

-- Unlock: a mover per frame, over the button, never the reverse.
check(M.Unlock(), "unlocked")
local mt = M._test.movers.target
check(mt and mt._shown, "the target's mover shows")
eq(mt._parent, UIParent, "movers are plain frames on UIParent")
eq(mt._points[1][2], t, "anchored to the button (SetAllPoints)")
check(M._test.movers.focus._shown, "a mover even for an absent unit (focus)")
check(t._scripts.OnDragStart == nil, "the protected button itself is never dragged")

-- Dragging the target's mover moves the target live; its group follows
-- through the anchors (nothing to do for them).
mt._center = { 512 + 350, 384 - 80 }
mt._scripts.OnDragStart(mt)
check(mt._moving, "the mover (insecure) moves")
mt._scripts.OnUpdate(mt)
eq(t._points[1][4], 350, "target follows the mover live")
eq(t._points[1][5], -80, "both axes")
eq(tot._points[1][2], t, "targettarget still anchored to the target: it moves with it")
mt._scripts.OnDragStop(mt)
eq(GlassUnitFramesDB.pos.target[2], "UIParent", "saved on the screen")
eq(GlassUnitFramesDB.pos.target[4], 350, "saved x")
eq(mt._points[1][2], t, "the mover re-anchors to the button")
eq(M._test.selected(), "target", "the dragged frame is selected")

-- Dragging a follower changes only its offset from the leader.
local mtot = M._test.movers.targettarget
mtot._center = { 512 + 350 - 100, 384 - 80 + 60 }   -- relative to the target's new centre
t._center = { 512 + 350, 384 - 80 }
mtot._scripts.OnDragStart(mtot); mtot._scripts.OnUpdate(mtot); mtot._scripts.OnDragStop(mtot)
eq(GlassUnitFramesDB.pos.targettarget[2], "target", "a follower is saved relative to its leader")
eq(GlassUnitFramesDB.pos.targettarget[4], -100, "offset x from the target")
eq(GlassUnitFramesDB.pos.targettarget[5], 60, "offset y from the target")
eq(tot._points[1][2], t, "and stays anchored to it")

-- The nudge panel: arrows (1, Shift 10), typed values, reset this frame.
mt._scripts.OnMouseUp(mt)
local np = M._test.panel()
check(np._shown, "clicking a mover opens the nudge panel")
M._test.nudge(1, 0)
eq(GlassUnitFramesDB.pos.target[4], 351, "right arrow: 1 unit")
WoW.shift = true
M._test.nudge(0, -1)
WoW.shift = false
eq(GlassUnitFramesDB.pos.target[5], -90, "Shift + down: 10 units")
np.x:SetText("-12.3")
np.x._scripts.OnEnterPressed(np.x)
eq(GlassUnitFramesDB.pos.target[4], -12.5, "typed X, rounded to 0.5 (negatives and decimals accepted)")
np.x:SetText("abc")
np.x._scripts.OnEnterPressed(np.x)
eq(GlassUnitFramesDB.pos.target[4], -12.5, "a non-number is ignored")
np.buttons.reset._scripts.OnClick(np.buttons.reset)
eq(GlassUnitFramesDB.pos.target, nil, "reset: this frame back to its default")
eq(t._points[1][4], 300, "at the default spot")
eq(GlassUnitFramesDB.pos.targettarget[4], -100, "reset one frame leaves the others alone")

-- Switching frames with an uncommitted coordinate discards it: its Enter
-- must never land on the newly selected frame.
local tBefore = GlassUnitFramesDB.pos.target and GlassUnitFramesDB.pos.target[4]
M._test.movers.target._scripts.OnMouseUp(M._test.movers.target)
np.x:SetFocus(); np.x:SetText("325")
local mpet = M._test.movers.pet
mpet._scripts.OnMouseUp(mpet)
check(not np.x:HasFocus(), "switching frames clears the pending edit's focus")
eq(np.x._text, "0", "the X box shows the pet's own offset, not the typed text")
np.x._scripts.OnEnterPressed(np.x)
eq(GlassUnitFramesDB.pos.pet and GlassUnitFramesDB.pos.pet[4] or 0, 0, "the pet never received the target's pending value")
eq(GlassUnitFramesDB.pos.target and GlassUnitFramesDB.pos.target[4], tBefore, "the target is unchanged")
M._test.movers.target._scripts.OnMouseUp(M._test.movers.target)

-- Lock, and /glass unlock|lock.
np.buttons.lock._scripts.OnClick(np.buttons.lock)
check(not M.unlocked and not mt._shown and not np._shown, "Lock hides the movers and the panel")
SlashCmdList.GLASSUNITFRAMES("unlock")
check(M.unlocked, "/glass unlock")
SlashCmdList.GLASSUNITFRAMES("lock")
check(not M.unlocked, "/glass lock")

-- /glass reset re-attaches everything at the defaults.
SlashCmdList.GLASSUNITFRAMES("reset")
eq(next(GlassUnitFramesDB.pos), nil, "all positions cleared")
eq(tot._points[1][4], 207.5 - 300, "targettarget back at its default offset")

-- Saved entries are validated: a malformed one falls back to the default
-- instead of aborting the build of every frame after it.
local saved = GlassUnitFramesDB
saved.pos = { target = { "NOWHERE", "UIParent", "CENTER", "x", nil },
              targettarget = { "CENTER", "focus", "CENTER", 1, 2 },          -- not its leader
              pet = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 100, 200 } }     -- an old-style save
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
for _, u in ipairs(GlassUF.Frames.ORDER) do check(button(u) ~= nil, u .. " built despite bad saves") end
eq(button("target")._points[1][4], 300, "malformed save: default position")
eq(button("targettarget")._points[1][2], button("target"), "wrong relative frame: default anchor")
eq(button("pet")._points[1][1], "TOPLEFT", "an old-style save is still honoured")
GlassUnitFramesDB = nil

-- Snapping (Alt released). Frames get sizes and centres (the stub has no layout).
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon()
F, M = GlassUF.Frames, GlassUF.Movers
WoW.alt = false
UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
M.Unlock()
check(M._test.overlay()._shown, "unlock shows the grid overlay")
check(M._test.overlay().grid._shown, "the grid shows while snap-to-grid is on")
local tgt, plr = button("target"), button("player")
plr._center = { 683 - 300, 384 - 110 }
tgt._width, tgt._height = 365, 62
local mtg = M._test.movers.target
mtg._width, mtg._height = 365, 62
-- Grid: the centre lands on a 16-unit step from the screen centre.
mtg._center = { 683 + 305, 384 - 101 }            -- nothing to align to nearby in y
mtg._scripts.OnDragStart(mtg); mtg._scripts.OnUpdate(mtg); mtg._scripts.OnDragStop(mtg)
eq(GlassUnitFramesDB.pos.target[4], 304, "grid: x snapped to 19 x 16")
eq(GlassUnitFramesDB.pos.target[5], -96, "grid: y snapped to -6 x 16")
-- Alignment: the target's centre within 8 of the player's centre line (y).
plr._width, plr._height = 365, 62
mtg._center = { 683 + 300, 384 - 115 }             -- player centre y is 384 - 110
mtg._scripts.OnDragStart(mtg); mtg._scripts.OnUpdate(mtg)
check(M._test.overlay().hguide._shown, "an alignment shows its guide line")
mtg._scripts.OnDragStop(mtg)
eq(GlassUnitFramesDB.pos.target[5], -110, "aligned with the player's centre (not the grid)")
check(not M._test.overlay().hguide._shown, "guide hidden when the drag ends")
-- Alt: free placement.
WoW.alt = true
mtg._center = { 683 + 301, 384 - 103 }
mtg._scripts.OnDragStart(mtg); mtg._scripts.OnUpdate(mtg); mtg._scripts.OnDragStop(mtg)
eq(GlassUnitFramesDB.pos.target[4], 301, "Alt: no snapping")
WoW.alt = false
-- The switches: saved only when off, the grid hides with its switch.
local np2 = M._test.panel()
np2.snapGrid:SetChecked(false); np2.snapGrid._scripts.OnClick(np2.snapGrid)
eq(GlassUnitFramesDB.snapGrid, false, "grid off: saved")
check(not M._test.overlay().grid._shown, "grid off: grid hidden")
np2.snapGrid:SetChecked(true); np2.snapGrid._scripts.OnClick(np2.snapGrid)
eq(GlassUnitFramesDB.snapGrid, nil, "grid on again: the default, nothing saved")
-- A frame's own followers are not alignment lines for it (they move with it);
-- other frames are.
local tot = button("targettarget")
tot._center, tot._width, tot._height = { 1000, 500 }, 180, 26
local lx = M._test.alignLines("target", "x")
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
check(not has(lx, 1000 - 90), "the target's own ToT is not a line for the target")
check(has(lx, 683 - 300 - 182.5), "the player's left edge is")
check(has(M._test.alignLines("player", "x"), 1000 - 90), "but the ToT is a line for the player")
eq(M._test.alignAxis(100, 10, { 95 }), 105, "alignAxis: low edge onto the line")
-- The grid is rebuilt for a new screen size (UI scale / resolution).
local ov = M._test.overlay()
local before = ov.gridW
UIParent._width = 1600
M.Lock(); M.Unlock()
eq(ov.gridW, 1600, "the grid is rebuilt for the new screen size")
check(before ~= ov.gridW, "it was drawn for the old one before")
-- /glass snap.
SlashCmdList.GLASSUNITFRAMES("snap align off")
eq(GlassUnitFramesDB.snapAlign, false, "/glass snap align off: saved")
check(not M.snapAlign, "and applied")
SlashCmdList.GLASSUNITFRAMES("snap align on")
eq(GlassUnitFramesDB.snapAlign, nil, "on again: nothing saved")
-- The panel (created earlier, reused) follows a slash change.
SlashCmdList.GLASSUNITFRAMES("snap grid off")
M.Lock(); M.Unlock()
check(not M._test.panel().snapGrid:GetChecked(), "grid switch unticked after /glass snap grid off")
SlashCmdList.GLASSUNITFRAMES("snap grid on")
check(M._test.panel().snapGrid:GetChecked(), "and ticked again after on")
M.Lock()
check(not M._test.overlay()._shown, "lock hides the overlay")
WoW.alt = true

-- Review fixes (#52).
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon()
UIParent._center = { 512, 384 }
F, M = GlassUF.Frames, GlassUF.Movers
local pl, pt = button("player"), button("pet")

-- An old-style follower save on the SCREEN: measured from the live rects,
-- never applied as leader offsets (it used to jump ~300 units on a nudge).
GlassUnitFramesDB.pos.pet = { "CENTER", "UIParent", "CENTER", -300, -162 }
pl._center, pt._center = { 512 - 300, 384 - 110 }, { 512 - 300, 384 - 162 }
local x, y, rel = F.PositionOf("pet")
eq(rel, "player", "position reported relative to what it's anchored to")
eq(x, 0, "measured x from the player's centre")
eq(y, -52, "measured y")
check(M.Unlock(), "unlock")
eq(GlassUnitFramesDB.pos.pet[2], "player", "unlock rewrites the old save in the current form")
eq(GlassUnitFramesDB.pos.pet[5], -52, "at the same spot")
M.Lock()

-- An old-style save whose rects aren't laid out: nudges are refused, not invented.
GlassUnitFramesDB.pos.pet = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 100, 200 }
pt._center = nil
eq(F.PositionOf("pet"), nil, "unmeasurable: no position")

-- Offsets are bounded: no ±inf (or nonsense) reaches SavedVariables.
check(not F.SetPosition("player", 1/0, 0), "infinite x refused")
check(not F.SetPosition("player", 5000, 0), "far-off x refused")
check(not F.SavePosition("player", -1/0, 0), "infinite save refused")
GlassUnitFramesDB.pos.player = { "CENTER", "UIParent", "CENTER", 1/0, 0 }
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = GlassUnitFramesDB })
eq(button("player")._points[1][4], -300, "an infinite save falls back to the default")

-- A reset during a drag wins (the drag in flight is dropped, not re-saved),
-- and the open nudge panel shows the reset position.
UIParent._center = { 512, 384 }
F, M = GlassUF.Frames, GlassUF.Movers
M.Unlock()
local mt2 = M._test.movers.target
mt2._center = { 512 + 380, 384 - 60 }
mt2._scripts.OnDragStart(mt2); mt2._scripts.OnUpdate(mt2)
SlashCmdList.GLASSUNITFRAMES("reset")
mt2._scripts.OnDragStop(mt2)
eq(GlassUnitFramesDB.pos.target, nil, "the reset survives the drag's release")
eq(button("target")._points[1][4], 300, "target at its default")
eq(M._test.panel().x._text, "300", "the nudge panel shows the reset position")

-- A drag that holds still doesn't re-anchor the frame every rendered frame.
mt2._center = { 512 + 100, 384 - 100 }
mt2._scripts.OnDragStart(mt2); mt2._scripts.OnUpdate(mt2)
local calls = 0
local realSP = button("target").SetPoint
rawset(button("target"), "SetPoint", function(...) calls = calls + 1; return realSP(...) end)
mt2._scripts.OnUpdate(mt2); mt2._scripts.OnUpdate(mt2)
eq(calls, 0, "no SetPoint while the mover holds still")
rawset(button("target"), "SetPoint", nil)
mt2._scripts.OnDragStop(mt2)
M.Lock()
GlassUnitFramesDB = nil

done("test_movers")
