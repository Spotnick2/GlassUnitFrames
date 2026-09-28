-- Unlock mode (#34): movers, group moves through anchors, the nudge panel.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
UIParent._center = { 512, 384 }
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

done("test_movers")
