-- The crowd-control icon (#159): a managed aura container of its own on the
-- target and focus, filtered by the client's CROWD_CONTROL (nothing read in
-- Lua), off by default, over the portrait tile or beside the frame, queued in
-- combat, and never an anchor for anything.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local Auras, S = GlassUF.Auras, GlassUF.Settings
local t, f = button("target"), button("focus")

check(t.ccContainer == nil and f.ccContainer == nil, "off by default: no container built")
eq(GlassUnitFramesDB.ccIcon, nil, "and nothing saved")

-- Over the target's portrait.
check(S.SetCCIcon("target", "portrait"), "target: portrait")
local c = t.ccContainer
check(c ~= nil and c._type == "AuraContainer", "a container of its own")
local group = c._groups and c._groups.glass_cc
check(group ~= nil, "its aura group")
eq(group.filter, "HARMFUL|CROWD_CONTROL", "the client's crowd-control filter")
eq(group.spec.maxFrameCount, 1, "one icon")
eq(c._seq[1], "AddAuraGroup", "the group before the unit")
eq(c._modelUnit, "target", "bound to the target")
check(c._shown, "shown")
eq(c._points[1][1], "CENTER", "centred")
eq(c._points[1][2], t.tile, "on the portrait tile")
eq(c:GetScale(), 1, "full size")
check(c._width == c._height and c._width > 40, "a square the size of the portrait (" .. tostring(c._width) .. ")")
check(c:GetFrameLevel() > t.model:GetFrameLevel(), "above the 3D model")
eq(GlassUnitFramesDB.ccIcon.target, "portrait", "saved")
-- The buttons the client makes get the glass look at that size.
local btn = CreateFrame("Button", nil, c)
group.spec.initializeFrame(btn)
eq(btn._width, c._width, "the icon fills the container")
check(btn._cooldown ~= nil and btn._durationText ~= nil, "the client's swipe and timer")

-- Beside the tile: smaller, outside it on the portrait side.
S.SetCCIcon("target", "beside")
eq(t.ccContainer, c, "the same container")
eq(c._points[1][1], "LEFT", "beside: its left edge")
eq(c._points[1][2], t.tile, "next to the tile")
eq(c._points[1][3], "RIGHT", "on the tile's outer side")
check(c:GetScale() < 1, "smaller")

-- No portrait: where the tile would be, full size.
S.SetCCIcon("target", "portrait")
S.SetPortraitMode("target", "none")
eq(c._points[1][2], t.body, "no tile: on the body's edge")
eq(c._points[1][3], "RIGHT", "the portrait side")
eq(c:GetScale(), 1, "full size")
S.SetPortraitMode("target", "3d")
eq(c._points[1][2], t.tile, "the tile back: over it again")

-- Focus has no tile: its left, clear of the focus target.
S.SetCCIcon("focus", "portrait")
local fc = f.ccContainer
check(fc ~= nil, "focus: a container")
eq(fc._modelUnit, "focus", "bound to the focus")
eq(fc._points[1][1], "RIGHT", "focus: right edge")
eq(fc._points[1][2], f.body, "on the body")
eq(fc._points[1][3], "LEFT", "its left side")

-- Off hides it; the save goes when empty.
S.SetCCIcon("focus", "off")
check(not fc._shown, "off: hidden")
eq(GlassUnitFramesDB.ccIcon.focus, nil, "off isn't saved")
S.SetCCIcon("target", "off")
eq(GlassUnitFramesDB.ccIcon, nil, "nothing on: no table")
check(not S.SetCCIcon("player", "portrait"), "not on the player")
check(not S.SetCCIcon("target", "huge"), "an unknown mode refused")

-- In combat: queued, the last request wins, nothing protected touched.
WoW.combat = true
S.SetCCIcon("target", "beside")
S.SetCCIcon("target", "portrait")
check(not c._shown, "in combat: nothing changes yet")
eq(#WoW.blocked, 0, "nothing protected touched in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(c._shown and c._points[1][1] == "CENTER", "after combat: the last request (portrait)")
-- A 3D <-> 2D switch in combat waits too.
WoW.combat = true
S.SetPortraitMode("target", "2d")
eq(#WoW.blocked, 0, "a portrait switch in combat moves nothing protected")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
S.SetPortraitMode("target", "3d")

-- A new target or focus refreshes what the client shows.
S.SetCCIcon("focus", "beside")
local n0, f0 = c._refreshes or 0, fc._refreshes or 0
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check((c._refreshes or 0) > n0, "a target change refreshes the target's icon")
WoW.fire("PLAYER_FOCUS_CHANGED"); WoW.tick()
check((fc._refreshes or 0) > f0, "a focus change refreshes the focus's")

-- Nothing is ever anchored to a container (the client refuses it).
for _, w in ipairs(WoW.frames) do
    for _, p in ipairs(w._points or {}) do
        check(p[2] ~= c and p[2] ~= fc, "nothing anchored to a crowd-control container")
    end
end
eq(next(GlassUF.paintFailures), nil, "no failures")

-- Saved modes come back at load; junk is off.
dofile("tests/wow_stubs.lua")
standardUnits()
loadAddon({ db = { ccIcon = { target = "beside", focus = "giant" } } })
t, f = button("target"), button("focus")
check(t.ccContainer ~= nil and t.ccContainer._shown, "a saved mode builds at load")
eq(t.ccContainer._points[1][2], t.tile, "beside the tile")
check(f.ccContainer == nil, "a junk mode is off")

done("test_cc")
