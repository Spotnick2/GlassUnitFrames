-- Hiding Blizzard's unit frames (#7).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local B = GlassUF.Blizzard
local hidden = B.hiddenParent

-- Every unit GlassUF draws loses its Blizzard frame; the rest are untouched.
for _, name in ipairs({ "PlayerFrame", "PetFrame", "TargetFrame", "ComboFrame", "TargetFrameToT" }) do
    local f = _G[name]
    check(f._parent == hidden, name .. " reparented to the hidden parent")
    check(not f._shown, name .. " hidden")
    check(f._silenced, name .. " events unregistered")
    check(f._unwatched and not WoW.unitWatch[f], name .. " unit watch removed")
end
check(_G.PlayerFrame.healthbar._silenced, "child health bar silenced too")
check(FocusFrame._parent == UIParent, "FocusFrame untouched: GlassUF draws no focus frame yet")
eq(#WoW.blocked, 0, "nothing blocked at load")

-- Anything reparenting a hidden frame (Edit Mode closed): undone on the next
-- timer tick, never synchronously inside the caller's SetParent, which would
-- run in Blizzard's secure execution and taint.
PlayerFrame:SetParent(UIParent)
check(PlayerFrame._parent == UIParent, "reparent is not undone inside the caller's SetParent")
WoW.flushTimers()
check(PlayerFrame._parent == hidden, "undone on the next timer tick")

-- Edit Mode reparents a hidden frame: never undone synchronously, and not
-- while Edit Mode is open; done on the timer after it closes.
WoW.SetEditMode(true)
PlayerFrame:SetParent(UIParent)
check(PlayerFrame._parent == UIParent, "not reparented back inside the caller's SetParent")
WoW.flushTimers()
check(PlayerFrame._parent == UIParent, "still waiting while Edit Mode is open")
WoW.SetEditMode(false)
WoW.flushTimers()
WoW.flushTimers()
check(PlayerFrame._parent == hidden, "back under the hidden parent after Edit Mode closes")

-- A protected frame reparented during combat waits for PLAYER_REGEN_ENABLED.
WoW.combat = true
rawset(TargetFrame, "_parent", UIParent)     -- Blizzard's own (secure) code moved it
B.Reparent(TargetFrame)
check(TargetFrame._parent == UIParent, "no reparent under lockdown")
eq(#WoW.blocked, 0, "and no blocked call attempted")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(TargetFrame._parent == hidden, "reparented once combat ends")

-- Our own SetParent to the hidden parent does not re-trigger the hook.
WoW.timers = {}
PetFrame:SetParent(hidden)
eq(#WoW.timers, 0, "no timer queued for a reparent to the hidden parent")

-- Missing Blizzard globals are skipped, not errors.
rawset(_G, "ComboFrame", nil)
check(B.HideFrame("ComboFrame") == false, "absent frame skipped")

-- The setting: off leaves Blizzard alone (after /reload), and is saved.
SlashCmdList.GLASSUNITFRAMES("blizzard off")
eq(GlassUnitFramesDB.hideBlizzard, false, "setting saved")
WoW.reset()
standardUnits()
GlassUF = nil
loadAddon({ db = { font = "arial", hideBlizzard = false } })
check(PlayerFrame._parent == UIParent and PlayerFrame._shown, "hideBlizzard=false leaves PlayerFrame alone")

done("test_blizzard")
