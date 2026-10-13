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

eq(next(GlassUF.paintFailures), nil, "no paint failures")
done("test_portrait")
