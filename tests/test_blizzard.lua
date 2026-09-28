-- Hiding Blizzard's unit frames (#7).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local B = GlassUF.Blizzard
local hidden = B.hiddenParent

-- Every unit GlassUF draws loses its Blizzard frame; the rest are untouched.
-- PetFrame and the ToT frames stay under their (hidden) Blizzard parents
-- (#58): Blizzard's code calls into that parent.
local keep = { PetFrame = PlayerFrame, TargetFrameToT = TargetFrame, FocusFrameToT = FocusFrame }
for _, name in ipairs({ "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT" }) do
    local f = _G[name]
    if keep[name] then
        check(f._parent == keep[name], name .. " stays under its Blizzard parent")
    else
        check(f._parent == hidden, name .. " reparented to the hidden parent")
    end
    check(not f._shown, name .. " hidden")
    check(f._silenced, name .. " events unregistered")
    check(f._unwatched and not WoW.unitWatch[f], name .. " unit watch removed")
end
check(_G.PlayerFrame.healthbar._silenced, "child health bar silenced too")
check(ComboFrame._parent == UIParent and not ComboFrame._silenced, "ComboFrame untouched: GlassUF draws no combo points yet")
check(GlassUF.Blizzard.active, "Blizzard.active set once something is hidden")
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

-- The real combat path: Blizzard's code reparents just before combat, the
-- hook's timer fires under lockdown, the frame waits in the addon's combat
-- queue (silently) and is reparented at PLAYER_REGEN_ENABLED.
WoW.timers = {}
TargetFrame:SetParent(UIParent)              -- out of combat: allowed, hook queues a timer
WoW.combat = true
local chatBefore = #WoW.chat
WoW.flushTimers()                            -- timer runs under lockdown
check(TargetFrame._parent == UIParent, "no reparent under lockdown")
eq(#WoW.blocked, 0, "and no blocked call attempted")
eq(#WoW.chat, chatBefore, "deferral is silent")
TargetFrame:SetParent(UIParent)              -- repeated while waiting: still one queue slot
WoW.flushTimers()
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(TargetFrame._parent == hidden, "reparented once combat ends")
check(not B._test.pending[TargetFrame], "nothing left pending")

-- Our own SetParent to the hidden parent does not re-trigger the hook.
WoW.timers = {}
PlayerFrame:SetParent(hidden)
eq(#WoW.timers, 0, "no timer queued for a reparent to the hidden parent")

-- Edit Mode putting PetFrame back in PlayerFrame's managed container (every
-- show, ManagedFrameSystem UpdateFrame) is left alone: no hook fights it.
PetFrame:SetParent(UIParent)
PetFrame:SetParent(PlayerFrame)
eq(#WoW.timers, 0, "no timer queued for PetFrame")
WoW.flushTimers()
check(PetFrame._parent == PlayerFrame, "PetFrame stays where Blizzard put it")
check(not B._test.pending[PetFrame] and not B._test.pending[TargetFrameToT], "no reparent pending for kept frames")

-- Missing Blizzard globals are skipped, not errors.
check(B.HideFrame("NoSuchBlizzardFrame") == false, "absent frame skipped")

-- The setting, named for Blizzard's frames: "show" brings them back (after
-- /reload), "hide" hides them; saved. Old on/off wording is not accepted.
SlashCmdList.GLASSUNITFRAMES("blizzard show")
eq(GlassUnitFramesDB.hideBlizzard, false, "'blizzard show' saved as not hiding")
SlashCmdList.GLASSUNITFRAMES("blizzard hide")
eq(GlassUnitFramesDB.hideBlizzard, true, "'blizzard hide' saved as hiding")
SlashCmdList.GLASSUNITFRAMES("blizzard off")
eq(GlassUnitFramesDB.hideBlizzard, true, "ambiguous 'off' changes nothing")
SlashCmdList.GLASSUNITFRAMES("blizzard SHOW")
eq(GlassUnitFramesDB.hideBlizzard, false, "argument is case-insensitive")
SlashCmdList.GLASSUNITFRAMES("blizzard")
check(WoW.chat[#WoW.chat]:find("are hidden, shown after /reload", 1, true),
      "status reports what is on screen now and what /reload will do: " .. WoW.chat[#WoW.chat])
WoW.reset()
standardUnits()
GlassUF = nil
loadAddon({ db = { font = "arial", hideBlizzard = false } })
check(PlayerFrame._parent == UIParent and PlayerFrame._shown, "hideBlizzard=false leaves PlayerFrame alone")

done("test_blizzard")
