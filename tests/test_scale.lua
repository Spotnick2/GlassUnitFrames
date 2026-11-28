-- The frame groups' scale (#217, docs/FRAME-SCALE-PLAN.md): the player's
-- (with the pet) and the target's (with ToT, ToTT, focus, focus target).
-- Saves on UIParent are in UIParent units, saves on a leader in design units;
-- the Frames API speaks UIParent units; out of combat; a detached bar keeps
-- its own screen spot and scale.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < (eps or 0.01) end
local function ratio(w) return w:GetEffectiveScale() / UIParent:GetEffectiveScale() end
-- A region's centre and edges in UIParent units.
local function centre(w)
    local x, y = w:GetCenter()
    local k = ratio(w)
    return x * k, y * k
end
local function left(w) return w:GetLeft() * ratio(w) end
local function right(w) return w:GetRight() * ratio(w) end
local function top(w) return w:GetTop() * ratio(w) end

local HUD = { role = "healer", l = 400, b = 228, w = 566, h = 154, top = 382, base = 160, mode = "hud" }
local grfState
local heard
local function boot(db, opts)
    WoW.reset(); standardUnits(); GlassUF = nil
    WoW.layout = true
    UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
    heard = {}
    EventRegistry:RegisterCallback("GlassUnitFrames.LayoutChanged", function(_, ...) heard[#heard + 1] = { ... } end, {})
    rawset(_G, "GlassRaidFrames", { LayoutState = function() return grfState end })
    opts = opts or {}
    opts.db = db
    loadAddon(opts)
    WoW.fire("LOADING_SCREEN_DISABLED")
    return GlassUF.Frames, GlassUF.Settings
end
local function combat(on)
    WoW.combat = on
    WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

-- At scale 1: today's defaults.
grfState = nil
local F, S = boot({})
local pl, pet, tg, tot, focus, ft = button("player"), button("pet"), button("target"), button("targettarget"),
    button("focus"), button("focustarget")
local px, py = centre(pl)
check(near(px, 683 - 304) and near(py, 384 - 272), "scale 1: the player at its default")
eq(F.ScaleOf("pet"), 1, "the pet's group scale is 1")
eq(F.GroupOf("focustarget"), "target", "focus target is in the target's group")
eq(F.GroupOf("pet"), "player", "the pet in the player's")

-- The player's group at 0.7: the leader keeps its centre, the pet's offset
-- shrinks with it, and nothing of the target's group changes.
local tx0, ty0 = centre(tg)
local ok, why, v = S.SetFrameScale("player", 0.7)
check(ok and why == nil and v == 0.7, "set now, out of combat")
eq(GlassUnitFramesDB.frameScale.player, 0.7, "saved")
eq(pl:GetScale(), 0.7, "the player's button scaled")
eq(pet:GetScale(), 0.7, "the pet rides its scale")
eq(tg:GetScale(), 1, "the target's group untouched")
px, py = centre(pl)
check(near(px, 683 - 304) and near(py, 384 - 272), "the player keeps its centre")
local qx, qy = centre(pet)
check(near(qx - px, 0) and near(qy - py, -52 * 0.7), "the pet's offset is its design offset x 0.7")
local tx, ty = centre(tg)
check(near(tx, tx0) and near(ty, ty0), "the target hasn't moved")
local x, y, rel = F.PositionOf("pet")
check(rel == "player" and near(x, 0) and near(y, -52 * 0.7), "PositionOf: UIParent units")

-- The target's group at 0.5: the cluster shrinks around the target.
S.SetFrameScale("target", 0.5)
tx, ty = centre(tg)
check(near(tx, 683 + 304) and near(ty, 384 - 272), "the target keeps its centre")
local ox, oy = centre(tot)
check(near(ox - tx, (211.5 - 304) * 0.5) and near(oy - ty, (-216 + 272) * 0.5), "ToT's offset halves")
local fx, fy = centre(focus)
local gx, gy = centre(ft)
check(near(gx - fx, (608 - 400) * 0.5) and near(gy - fy, (-175 + 174) * 0.5), "focus target rides focus, halved")
eq(ft:GetScale(), 0.5, "focus target at the group's scale")

-- A leader's save stays in UIParent units at any scale.
check(F.SetPosition("player", -200, -100), "a leader placed at 0.7")
px, py = centre(pl)
check(near(px, 683 - 200) and near(py, 384 - 100), "where it was asked, on screen")
eq(GlassUnitFramesDB.pos.player[4], -200, "saved in UIParent units")
S.SetFrameScale("player", 1.2)
px, py = centre(pl)
check(near(px, 683 - 200) and near(py, 384 - 100), "a new scale keeps the saved centre")

-- A follower's save is in design units; the API round-trips UIParent units.
S.SetFrameScale("player", 0.7)
check(F.SetPosition("pet", 10, -40), "a follower placed at 0.7")
px, py = centre(pl)
qx, qy = centre(pet)
check(near(qx - px, 10) and near(qy - py, -40), "on screen where it was asked")
check(near(GlassUnitFramesDB.pos.pet[4], 10 / 0.7) and near(GlassUnitFramesDB.pos.pet[5], -40 / 0.7), "saved in design units")
x, y = F.PositionOf("pet")
check(near(x, 10) and near(y, -40), "PositionOf gives it back in UIParent units")

-- The stored bound (Codex, round 2): refused before anything moves.
S.SetFrameScale("player", 0.5)
local before = { pet._points[1][4], pet._points[1][5] }
local saved = { GlassUnitFramesDB.pos.pet[4], GlassUnitFramesDB.pos.pet[5] }
check(not F.SetPosition("pet", 2100, 0), "4200 stored: refused")
check(not F.SetPosition("pet", 2100, 0, true), "live too")
check(not F.SavePosition("pet", 2100, 0), "and as a bare save")
check(pet._points[1][4] == before[1] and pet._points[1][5] == before[2], "the anchor untouched")
check(GlassUnitFramesDB.pos.pet[4] == saved[1] and GlassUnitFramesDB.pos.pet[5] == saved[2], "the old save intact")
check(F.SetPosition("pet", 2000, 0), "4000 stored: taken")
local db = GlassUnitFramesDB
F = boot(db)
eq(button("pet")._points[1][4], 4000, "and it survives a reload")

-- An older corner save keeps its corner.
db = { pos = { player = { "TOPLEFT", "UIParent", "TOPLEFT", 100, -50 } }, frameScale = { player = 0.6 } }
F, S = boot(db)
pl = button("player")
eq(pl:GetScale(), 0.6, "built at the saved scale")
check(near(left(pl), 100) and near(top(pl), 768 - 50), "its corner where it was saved")
S.SetFrameScale("player", 1.4)
check(near(left(pl), 100) and near(top(pl), 768 - 50), "and there at another scale")

-- Live drags at 0.7: a leader and a follower stay under the mover, during the
-- drag and after the save is applied again.
F, S = boot({ frameScale = { player = 0.7 } })
local M = GlassUF.Movers
WoW.alt = true
M.SetMirror(false)
pl, pet = button("player"), button("pet")
check(M.Unlock(), "unlocked")
local mp = M._test.movers.player
mp._center = { 683 - 250, 384 - 150 }
mp._scripts.OnDragStart(mp); mp._scripts.OnUpdate(mp)
px, py = centre(pl)
check(near(px, 683 - 250) and near(py, 384 - 150), "the leader under the mover, live")
mp._scripts.OnDragStop(mp)
mp._center = nil
F.ApplyPosition("player")
px, py = centre(pl)
check(near(px, 683 - 250) and near(py, 384 - 150), "and after its save is applied again")
local mq = M._test.movers.pet
mq._center = { 683 - 250 + 30, 384 - 150 - 60 }
mq._scripts.OnDragStart(mq); mq._scripts.OnUpdate(mq)
qx, qy = centre(pet)
check(near(qx, 683 - 220) and near(qy, 384 - 210), "the follower under the mover, live")
mq._scripts.OnDragStop(mq)
mq._center = nil
F.ApplyPosition("pet")
qx, qy = centre(pet)
check(near(qx, 683 - 220) and near(qy, 384 - 210), "and after its save is applied again")

-- A scale change mid-drag (Codex, round 3): the drag ends first, saving the
-- spot it reached, and the mover is back on its frame.
mq._center = { 683 - 250 + 50, 384 - 150 - 40 }
mq._scripts.OnDragStart(mq); mq._scripts.OnUpdate(mq)
S.SetFrameScale("player", 0.9)
check(not mq._moving, "the drag ended")
check(near(GlassUnitFramesDB.pos.pet[4], 50 / 0.7) and near(GlassUnitFramesDB.pos.pet[5], -40 / 0.7),
    "the spot it reached saved (design units at the old scale)")
eq(mq._points[1][1], "ALL", "the mover is back on its frame")
mq._center = nil
px, py = centre(pl)
qx, qy = centre(pet)
check(near(qx - px, 50 / 0.7 * 0.9) and near(qy - py, -40 / 0.7 * 0.9), "the pet's offset scales with its group")

-- The nudge panel: the leader's mover carries its group's scale.
mp._scripts.OnMouseUp(mp)
local np = M._test.panel()
check(np.s._shown ~= false, "a scale field for the player")
eq(np.s._text, "0.9", "showing the group's scale")
np.s:SetText("0.75")
np.s._scripts.OnEnterPressed(np.s)
eq(pl:GetScale(), 0.75, "typed: applied")
eq(GlassUnitFramesDB.frameScale.player, 0.75, "and saved")
M.Lock()
WoW.alt = false

-- Edge snapping at 0.7 (Codex, round 2): the scaled mover's own size snaps
-- edge to edge, not centre to centre. The stub's edges use explicit sizes.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = { frameScale = { target = 0.7 } } })
F, M, S = GlassUF.Frames, GlassUF.Movers, GlassUF.Settings
M.SetMirror(false)
S.SetSnap("snapGrid", false)
UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
M.Unlock()
local plr = button("player")
plr._center, plr._width, plr._height = { 383, 384 - 110 }, 364, 62   -- its right edge at 565
local mtg = M._test.movers.target
mtg._width, mtg._height = 360 * 0.7, 62 * 0.7   -- the scaled frame's rect
mtg._center = { 565 + 126 + 4, 384 - 200 }      -- its left edge 4 right of the player's right edge
mtg._scripts.OnDragStart(mtg); mtg._scripts.OnUpdate(mtg); mtg._scripts.OnDragStop(mtg)
eq(GlassUnitFramesDB.pos.target[4], 565 + 126 - 683, "its left edge onto the player's right edge")
eq(GlassUnitFramesDB.pos.target[5], -200, "y left alone (nothing near, no grid)")
M.Lock()

-- The group layout at 0.7: the frames' grid-facing edges at 24 from the
-- grid; a change from the nudge panel while linked applies and announces once.
grfState = HUD
F, S = boot({ frameScale = { player = 0.7, target = 0.7 } })
M = GlassUF.Movers
pl, tg = button("player"), button("target")
check(GlassUF.Link.Placing(), "linked")
check(near(right(pl), HUD.l - 24), "the player's right edge 24 left of the grid")
check(near(left(tg), HUD.l + HUD.w + 24), "the target's left edge 24 right of it")
local last = heard[#heard]
check(last and near(last[4], 365 * 0.7), "announced: the player's scaled width")
check(M.Unlock(), "unlocked while linked")
mp = M._test.movers.player
mp._scripts.OnMouseUp(mp)
np = M._test.panel()
check(np.s:IsEnabled(), "the scale field stays enabled while the layout places the frame")
check(not np.x:IsEnabled(), "the position fields are locked")
local n = #heard
np.s:SetText("0.8")
np.s._scripts.OnEnterPressed(np.s)
eq(pl:GetScale(), 0.8, "applied while linked")
check(near(right(pl), HUD.l - 24), "still by its edge")
eq(#heard, n + 1, "announced once")
check(near(heard[#heard][4], 365 * 0.8), "with the new width")
M.Lock()
-- Too wide for the room beside the grid (Codex, #218): 376 units each side,
-- the frame 511 at 1.4. It stops at the screen's edge, and the dx announced
-- for GlassActionBars is where it really is.
S.SetFrameScale("player", 1.4)
S.SetFrameScale("target", 1.4)
check(near(left(pl), 0), "the player stops at the screen's left edge")
check(near(right(tg), 1366), "the target at its right edge")
last = heard[#heard]
check(near(last[2], 0) and near(last[4], 365 * 1.4), "announced: the rect where it is")
check(near(last[10], 365 * 1.4 / 2 - (683 - 304)), "announced: the dx it really moved")
-- Its own spot clamped to the same edge (Codex, #218 follow-up): saved at
-- -450, its own centre (233) would be off screen at 1.4, so the client keeps
-- it at 255.5 too. Linked or not, it sits there: dx 0.
grfState = HUD
F, S = boot({ pos = { player = { "CENTER", "UIParent", "CENTER", -450, -272 } }, frameScale = { player = 1.4 } })
pl = button("player")
check(near(left(pl), 0), "linked: at the screen's left edge")
check(near(F.OwnCenterX("player"), 365 * 1.4 / 2), "its own centre clamped to the same edge")
last = heard[#heard]
check(near(last[10], 0), "announced dx 0: it didn't move")
grfState = nil

-- A detached bar keeps its own spot and scale; a docked one scales with its
-- frame; the zoom glide reads a bar's scale on screen.
F, S = boot({})
local Castbar, Zoom = GlassUF.Castbar, GlassUF.Zoom
Castbar.SetDetached("player", true)
local ph = Castbar.bars.player.host
local hx, hy = centre(ph)
local hs = ratio(ph)
S.SetFrameScale("player", 0.6)
local hx2, hy2 = centre(ph)
check(near(hx2, hx) and near(hy2, hy), "a detached bar keeps its screen spot")
check(near(ratio(ph), hs), "and its scale on screen")
check(near(select(3, Zoom._test.rectOf(ph)), hs), "the zoom glide reads that scale")
local th = Castbar.bars.target.host
S.SetFrameScale("target", 0.6)
check(near(ratio(th), 0.6), "a docked bar scales with its frame")
check(near(select(3, Zoom._test.rectOf(th)), 0.6), "and the glide starts from that")
-- The swing pill is a bar of the player's group.
Castbar.SetDetached("swing", true)
local sh = Castbar.bars.swing and Castbar.bars.swing.host
if sh then
    local sx, sy = centre(sh)
    local ss = ratio(sh)
    S.SetFrameScale("player", 1.3)
    local sx2, sy2 = centre(sh)
    check(near(sx2, sx) and near(sy2, sy) and near(ratio(sh), ss), "the swing pill keeps its spot and scale")
end

-- In combat: refused for now, queued (last wins, one message), applied when
-- combat ends; a save meanwhile uses the scale the buttons still have.
F, S = boot({})
pl, pet = button("player"), button("pet")
combat(true)
local chat = #WoW.chat
ok, why = S.SetFrameScale("player", 0.8)
check(ok and why == "combat", "in combat: it waits")
eq(pl:GetScale(), 1, "the button unchanged")
eq(GlassUnitFramesDB.frameScale.player, 0.8, "the request saved")
S.SetFrameScale("player", 0.9)
eq(#WoW.chat, chat + 1, "one message for the wait")
check(F.SavePosition("pet", 10, -40), "a save in combat")
eq(GlassUnitFramesDB.pos.pet[4], 10, "converted with the scale still applied (1)")
combat(false)
eq(pl:GetScale(), 0.9, "combat over: the last request applied")
eq(pet:GetScale(), 0.9, "the pet too")
eq(#WoW.blocked, 0, "nothing protected touched in combat")
px, py = centre(pl)
qx, qy = centre(pet)
check(near(qx - px, 10 * 0.9) and near(qy - py, -40 * 0.9), "the combat save lands at the new scale")

-- A build deferred by combat comes up at the saved scale.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.layout = true
UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
loadAddon({ db = { frameScale = { target = 0.65 } }, beforeLoaded = function() WoW.combat = true end })
check(button("target") == nil, "no build under lockdown")
combat(false)
eq(button("target"):GetScale(), 0.65, "built at the saved scale once combat ends")
eq(button("focus"):GetScale(), 0.65, "its followers too")
eq(#WoW.blocked, 0, "nothing blocked")

-- The 3D portrait is loaded again after a scale change (#219): its camera
-- isn't redone when its parent's scale changes (it stayed zoomed in game).
F, S = boot({})
pl, tg = button("player"), button("target")
pl.model._modelUnit, tg.model._modelUnit = nil, nil
S.SetFrameScale("player", 0.8)
WoW.tick()
eq(pl.model._modelUnit, "player", "the player's model loaded again")
eq(tg.model._modelUnit, nil, "the other group's left alone")
S.SetFrameScale("target", 1.3)
WoW.tick()
eq(tg.model._modelUnit, "target", "the target's after its own change")

-- The options sliders: the percentage beside the label, a tick at 100% (#219).
local O = GlassUF.Options
O._test.panel:Show()
local ctl = O._test.controls
local sp = ctl.scalePlayer
check(sp ~= nil and ctl.scaleTarget ~= nil, "both sliders built")
eq(sp.valueText._text, "80%", "the player's shows 80%")
eq(ctl.scaleTarget.valueText._text, "130%", "the target's 130%")
local vp = sp.valueText._points[1]
check(vp[1] == "LEFT" and vp[2] == sp.label and vp[3] == "RIGHT", "the value right after the label")
check(sp.markTick ~= nil, "a tick on the track")
local tp = sp.markTick._points[1]
check(tp[2] == sp and tp[3] == "LEFT" and near(tp[4], 16 + (240 - 32) / 3), "at 100%: a third of the way from 50% to 200%")
sp._scripts.OnValueChanged(sp, 1)
eq(sp.valueText._text, "100%", "dragged to the tick: 100%")
eq(button("player"):GetScale(), 1, "and back to full size")
eq(GlassUnitFramesDB.frameScale and GlassUnitFramesDB.frameScale.player, nil, "100% isn't saved")

-- Saved values are validated; 1 isn't saved; /guf scale.
F, S = boot({ frameScale = { player = "big", target = 7 } })
eq(F.scaleReq.player, 1, "junk: 1")
eq(F.scaleReq.target, 2, "out of range: clamped")
check(not S.SetFrameScale("pet", 0.8), "only the two groups")
check(not S.SetFrameScale("player", 0 / 0), "NaN refused")
S.SetFrameScale("target", 1)
S.SetFrameScale("player", 1)
eq(GlassUnitFramesDB.frameScale, nil, "1 isn't saved; the table goes")
eq(F.NormalizeScale(0.73), 0.75, "rounded to 0.05")
SlashCmdList.GLASSUNITFRAMES("scale player 0.85")
eq(button("player"):GetScale(), 0.85, "/guf scale player 0.85")
chat = #WoW.chat
SlashCmdList.GLASSUNITFRAMES("scale")
check(#WoW.chat == chat + 1 and tostring(WoW.chat[#WoW.chat]):find("player 0.85", 1, true), "/guf scale: usage with both scales")

done("test_scale")
