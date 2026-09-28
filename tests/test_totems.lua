-- #18: a shaman keeps Blizzard's TotemFrame, hosted under our player frame.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function makeTotemFrame()
    local tf = CreateFrame("Frame", "TotemFrame", PlayerFrame)
    tf:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 0, 0)
    tf.updates = 0
    rawset(tf, "Update", function(self) self.updates = self.updates + 1 end)
    return tf
end

-- Any class (TotemFrame only shows with an active totem slot): it moves into
-- our holder, under the player frame.
standardUnits()
WoW.units.player.class = "SHAMAN"
local tf = makeTotemFrame()
loadAddon()
local T = GlassUF.Blizzard._test.totem
check(T.holder ~= nil, "a shaman gets the holder")
eq(T.holder._points[1][2], button("player").body, "the holder hangs under the player frame")
eq(tf._parent, T.holder, "TotemFrame reparented into the holder")
eq(tf._points[1][2], T.holder, "and anchored in it")
eq(T.glass._parent, T.holder, "the glass is the holder's child")
check(tf._level > T.glass._level + 10, "TotemFrame sits above the glass's rim layer (+10)")
tf:Hide()
check(not T.glass._shown, "no totems (TotemFrame hidden): no glass")
tf:Show()
check(T.glass._shown, "TotemFrame shown: glass shown")

-- Blizzard re-lays it out: repaired on the next tick, never synchronously.
tf:SetParent(PlayerFrame)
eq(tf._parent, PlayerFrame, "not undone inside the caller's SetParent")
WoW.flushTimers()
eq(tf._parent, T.holder, "back in the holder after the deferred repair")
tf:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 0, 0)
WoW.flushTimers()
eq(tf._points[1][2], T.holder, "re-anchored after a Blizzard SetPoint")
-- Already in place: a repair does nothing (no churn).
local sets = 0
local realSet = tf.SetPoint
rawset(tf, "SetPoint", function(...) sets = sets + 1; return realSet(...) end)
GlassUF.Blizzard._test.repair()
eq(sets, 0, "already placed: no re-anchor")
rawset(tf, "SetPoint", nil)

-- Edit Mode open: wait until it closes.
WoW.SetEditMode(true)
tf:SetParent(PlayerFrame)
WoW.flushTimers()
eq(tf._parent, PlayerFrame, "waits while Edit Mode is open")
WoW.SetEditMode(false)
WoW.flushTimers()
eq(tf._parent, T.holder, "repaired once Edit Mode closes")

-- Protected in combat (unmeasured with totems down): queued for after combat,
-- nothing protected touched under lockdown.
rawset(tf, "IsProtected", function() return true, false end)
WoW.combat = true
tf:SetParent(PlayerFrame)
WoW.flushTimers()
eq(tf._parent, PlayerFrame, "protected in combat: not reparented under lockdown")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(tf._parent, T.holder, "repaired after combat")

-- Queued in combat, then Edit Mode opens before combat ends: the queued repair
-- re-checks and waits for Edit Mode too.
WoW.combat = true
tf:SetParent(PlayerFrame)
WoW.flushTimers()
WoW.SetEditMode(true)
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(tf._parent, PlayerFrame, "after combat but Edit Mode open: still waiting")
WoW.SetEditMode(false)
WoW.flushTimers()
eq(tf._parent, T.holder, "repaired once Edit Mode closes")
rawset(_G, "TotemFrame", nil)

-- Blizzard frames shown (hideBlizzard off): TotemFrame stays in PlayerFrame.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class = "SHAMAN"
tf = makeTotemFrame()
loadAddon({ db = { font = "arial", hideBlizzard = false, pos = {} } })
eq(tf._parent, PlayerFrame, "Blizzard's player frame shown: totems stay put")
rawset(_G, "TotemFrame", nil)
GlassUnitFramesDB = nil

-- A failure while hosting is recorded, and the rest of the build carries on.
WoW.reset(); standardUnits(); GlassUF = nil
tf = makeTotemFrame()
rawset(tf, "HookScript", function() error("refused") end)
loadAddon()
check(GlassUF.paintFailures.totems ~= nil, "hosting failure recorded")
for _, u in ipairs(GlassUF.Frames.ORDER) do check(button(u) ~= nil, u .. " still built") end
rawset(_G, "TotemFrame", nil)

done("test_totems")
