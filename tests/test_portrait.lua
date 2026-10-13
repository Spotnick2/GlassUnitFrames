-- The 3D portrait and its 2D fallback (#82): a unit with no model file (an
-- Earthborer, measured: GetModelFileID() nil, in range) gets one retry, then
-- the client's 2D portrait; out of range, the 2D one at once; a 3D load
-- switches back; a newer paint cancels a pending retry.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local t = button("target")
local function repaint() WoW.fire("UNIT_MODEL_CHANGED", "target"); WoW.tick() end

-- A normal unit: the 3D model, no 2D.
repaint()
check(t.model._shown and not t.portrait2D._shown, "3D portrait shown, no 2D")
eq(t.model._modelUnit, "target", "set to the unit")

-- No model file: one retry, then the 2D portrait.
WoW.SetUnit("target", { name = "Earthborer", reaction = 2, noModel = true })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(not t.portrait2D._shown, "not yet: a retry is pending")
WoW.flushTimers()
check(t.portrait2D._shown and not t.model._shown, "still no model after the retry: the 2D portrait")
eq(t.portrait2D._portraitUnit, "target", "the target's own 2D portrait")
local tc = t.portrait2D._texCoord
check(tc and tc[1] == 0.15 and tc[2] == 0.85 and tc[3] == 0.15 and tc[4] == 0.85,
      "cropped to the square inside the round portrait (#84)")

-- The model loads on the retry: 3D after all.
WoW.SetUnit("target", { name = "Kobold", reaction = 2, noModel = true })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
WoW.units.target.noModel = nil
WoW.flushTimers()
check(t.model._shown and not t.portrait2D._shown, "loaded on the retry: back to 3D")

-- A newer paint cancels a pending retry (a target change in between).
WoW.SetUnit("target", { name = "Earthborer", reaction = 2, noModel = true })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
WoW.SetUnit("target", { name = "Defias Pillager", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
local sets = #t.model._seq
WoW.flushTimers()
eq(#t.model._seq, sets, "the cancelled retry doesn't reload the model")
check(t.model._shown and not t.portrait2D._shown, "the old retry doesn't put the 2D portrait on the new target")

-- Out of range: the 2D portrait at once (not an empty tile).
WoW.units.target.visible = false
repaint()
check(t.portrait2D._shown and not t.model._shown, "out of range: the 2D portrait")
WoW.units.target.visible = nil
repaint()
check(t.model._shown and not t.portrait2D._shown, "back in range: 3D again")

-- An unreadable model file id never swaps a working 3D portrait.
rawset(t.model, "GetModelFileID", function() error("nope") end)
repaint()
WoW.flushTimers()
check(t.model._shown and not t.portrait2D._shown, "unreadable: keep the 3D portrait")
rawset(t.model, "GetModelFileID", nil)

-- Portrait modes (#97): 3D, 2D or none, per frame.
local S, F = GlassUF.Settings, GlassUF.Frames
local L = F.LAYOUT.target
local fullW, bodyW = L.w + L.h + 3, L.w
eq(t._width, fullW, "3D by default: tile + body")
eq(F.PortraitModeOf("target"), "3d", "3d by default")
-- 2D: live, never the model.
local seq = #t.model._seq
check(S.SetPortraitMode("target", "2d"), "2D")
eq(GlassUnitFramesDB.portrait.target, "2d", "saved")
WoW.tick()
check(t.portrait2D._shown and not t.model._shown, "2D: the flat portrait")
eq(#t.model._seq, seq, "the model is never loaded")
-- 2D in combat applies at once (nothing protected).
WoW.combat = true
check(S.SetPortraitMode("target", "3d"), "3D in combat")
WoW.tick()
check(t.model._shown, "back to 3D at once, in combat")
eq(GlassUnitFramesDB.portrait, nil, "3D isn't saved")
WoW.combat = false
-- A pending 3D retry never lands after a switch.
WoW.SetUnit("target", { name = "Earthborer", reaction = 2, noModel = true })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
seq = #t.model._seq
S.SetPortraitMode("target", "2d")
WoW.flushTimers()   -- the retry fires before the switch's repaint
WoW.tick()
eq(#t.model._seq, seq, "the old retry doesn't reload the model after a switch to 2D")
check(t.portrait2D._shown and not t.model._shown, "still 2D")
S.SetPortraitMode("target", "3d"); WoW.tick(); WoW.flushTimers()
-- None: no tile, the button narrows.
check(S.SetPortraitMode("target", "none"), "none")
check(not t.tile._shown, "the tile hides")
eq(t._width, bodyW, "the button narrows to the body")
eq(#WoW.blocked, 0, "out of combat: nothing blocked")
WoW.SetUnit("target", { name = "Kobold", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick(); WoW.flushTimers()
check(not t.model._shown and not t.portrait2D._shown, "no model, no flat portrait (even for a unit with one)")
-- The level "on the portrait" goes to the power line while there's no tile.
S.SetLevelPosition("portrait"); WoW.tick()
check(textOf(t.levelText) ~= "", "the level shows on the power line")
eq(textOf(t.levelOnTile), "", "not on the hidden tile")
eq(t.powerLeftText._points[1][2], t.levelText, "the power text steps past the level")
-- The PvP badge moves to the body.
if t.indicators and t.indicators.pvp then
    eq(t.indicators.pvp._parent, t.glass.top, "PvP on the body's top layer")
end
-- Back to 3D: the tile, the width, the level on the tile.
check(S.SetPortraitMode("target", "3d"), "back to 3D")
check(t.tile._shown and t._width == fullW, "tile and width back")
WoW.tick()
check(textOf(t.levelOnTile) ~= "" and textOf(t.levelText) == "", "the level back on the tile")
if t.indicators and t.indicators.pvp then eq(t.indicators.pvp._parent, t.tileTop, "PvP back on the tile") end
S.SetLevelPosition("power")
-- None in combat waits; the last request wins.
WoW.combat = true
local ok, why = S.SetPortraitMode("target", "none")
check(ok and why == "combat", "none in combat: queued")
eq(t._width, fullW, "nothing resized in combat")
check(t.tile._shown, "the tile still shows")
S.SetPortraitMode("target", "2d")
WoW.tick()
check(t.portrait2D._shown, "a 2D request applies at once")
S.SetPortraitMode("target", "none")
eq(#WoW.blocked, 0, "nothing protected touched in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(t._width, bodyW, "after combat: the last request (none) applies")
check(not t.tile._shown, "no tile")
-- The pet's happiness anchors to the frame with no tile.
local pet = button("pet")
if pet.indicators and pet.indicators.happiness then
    S.SetPortraitMode("pet", "none")
    eq(pet.indicators.happiness._points[1][2], pet, "happiness anchors to the frame")
    S.SetPortraitMode("pet", "3d")
    eq(pet.indicators.happiness._points[1][2], pet.tile, "back to the tile")
end
-- Junk: unknown modes refused; saved junk falls back to 3D.
check(not S.SetPortraitMode("target", "4d"), "an unknown mode is refused")
check(not S.SetPortraitMode("focus", "2d"), "a frame without a portrait is refused")
local saved = GlassUnitFramesDB
saved.portrait = { target = "none", player = "sideways" }
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
eq(button("target")._width, bodyW, "a saved none applies at build")
eq(GlassUF.Frames.PortraitModeOf("player"), "3d", "saved junk: 3D")
-- A mixed pair (the target on none) still mirrors by centre (#97, by intent).
local M = GlassUF.Movers
WoW.alt = false
M.SetSnap("snapGrid", false); M.SetSnap("snapAlign", false)
UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
check(M.Unlock(), "unlocked")
local mp = M._test.movers.player
mp._center = { 683 - 250, 384 - 90 }
mp._scripts.OnDragStart(mp); mp._scripts.OnUpdate(mp); mp._scripts.OnDragStop(mp)
eq(button("target")._points[1][4], 250, "the narrowed target still mirrors the player's centre")
M.Lock()
-- The options rows.
local O = GlassUF.Options._test
O.panel._scripts.OnShow(O.panel)
local rows = O.controls.portraitRows
check(rows.player and rows.target and rows.pet, "a row per portrait frame")
for _, rb in ipairs(rows.target) do if rb.value == "none" then check(rb:GetChecked(), "shows none") end end
for _, rb in ipairs(rows.player) do if rb.value == "2d" then rb._scripts.OnClick(rb) end end
eq(GlassUnitFramesDB.portrait.player, "2d", "the radio saves")
GlassUnitFramesDB = nil

eq(next(GlassUF.paintFailures), nil, "no paint failures")
done("test_portrait")
