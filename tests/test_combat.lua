-- Combat lockdown: protected frames are never touched under lockdown.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local p = button("player")

-- Drag: shift required, refused in combat, dropped at PLAYER_REGEN_DISABLED.
p._scripts.OnDragStart(p)
check(not p._moving, "no drag without shift")
WoW.shift = true
p._scripts.OnDragStart(p)
check(p._moving, "shift-drag starts out of combat")
WoW.fire("PLAYER_REGEN_DISABLED")          -- fires before lockdown begins
check(not p._moving, "drag dropped when combat starts")
eq(GlassUnitFramesDB.pos.player[4], 111, "dropped position saved")

WoW.combat = true
p._scripts.OnDragStart(p)
check(not p._moving, "no drag in combat")

-- /glass reset in combat waits for PLAYER_REGEN_ENABLED.
SlashCmdList.GLASSUNITFRAMES("reset")
check(GlassUnitFramesDB.pos.player ~= nil, "reset deferred in combat")

-- Heavy event traffic in combat, including target and pet churn and casts.
WoW.units.target.casting = { name = "Fireball" }
WoW.fireAllRegistered()
WoW.SetUnit("target", nil)
WoW.fire("PLAYER_TARGET_CHANGED")
WoW.SetUnit("target", { name = "Wolf", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED")
WoW.fire("UNIT_PET", "player")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target")
WoW.tick(); WoW.tick(0.6); WoW.flushTimers()
SlashCmdList.GLASSUNITFRAMES("font friz")
eq(#WoW.blocked, 0, "no protected frame touched in combat: " .. table.concat(WoW.blocked, ", "))

WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GlassUnitFramesDB.pos.player, nil, "deferred reset ran after combat")
eq(p._points[1][4], -300, "player back at the default position")

-- A drag that combat caught mid-way is finished when combat ends.
WoW.shift = true
p._scripts.OnDragStart(p)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")           -- worst case: lockdown already on
check(p.moving, "drag cannot be stopped under lockdown")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(not p.moving and not p._moving, "drag finished after combat")
eq(#WoW.blocked, 0, "nothing touched while locked: " .. table.concat(WoW.blocked, ", "))

-- Loaded under lockdown: the build waits for combat to end.
WoW.reset()
standardUnits()
GlassUF = nil
WoW.combat = true
loadAddon()
eq(next(GlassUF.Frames.byUnit), nil, "no secure frames built under lockdown")
eq(#WoW.blocked, 0, "nothing blocked while deferring the build")
-- Review #3: a reset queued behind the deferred build must not run first
-- (it needs Frames.db) and must not lose the build.
SlashCmdList.GLASSUNITFRAMES("reset")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(button("player") ~= nil, "frames built once combat ends")
check(button("target") ~= nil, "all frames built, not just some")
-- Review #3: PLAYER_ENTERING_WORLD fired before the build, so without a
-- first paint at registration these would still be blank.
WoW.tick()
eq(textOf(button("player").nameText), "Morphisto", "deferred build paints the player at once")
eq(button("target").health._value, 830, "deferred build paints the target at once")

-- A saved position is applied at load.
WoW.reset()
standardUnits()
GlassUF = nil
loadAddon({ db = { font = "arial", pos = { target = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 50, 60 } } } })
eq(button("target")._points[1][4], 50, "saved position applied at load")

done("test_combat")
