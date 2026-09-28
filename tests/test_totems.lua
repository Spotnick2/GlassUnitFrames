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

-- Not a shaman: left alone.
standardUnits()
local tf = makeTotemFrame()
loadAddon()
check(GlassUF.Blizzard._test.totem.holder == nil, "a warlock gets no totem holder")
rawset(_G, "TotemFrame", nil)

-- A shaman: TotemFrame moves into our holder, under the player frame.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class = "SHAMAN"
tf = makeTotemFrame()
loadAddon()
local T = GlassUF.Blizzard._test.totem
check(T.holder ~= nil, "a shaman gets the holder")
eq(T.holder._points[1][2], button("player").body, "the holder hangs under the player frame")
eq(tf._parent, T.holder, "TotemFrame reparented into the holder")
eq(tf._points[1][2], T.holder, "and anchored in it")
eq(T.glass._parent, tf, "the glass is TotemFrame's child: its shown state carries the art")

-- Blizzard re-lays it out: repaired on the next tick, never synchronously.
tf:SetParent(PlayerFrame)
eq(tf._parent, PlayerFrame, "not undone inside the caller's SetParent")
WoW.flushTimers()
eq(tf._parent, T.holder, "back in the holder after the deferred repair")
tf:Update()
tf:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 0, 0)
WoW.flushTimers()
eq(tf._points[1][2], T.holder, "re-anchored after Update / SetPoint")

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
rawset(_G, "TotemFrame", nil)

-- Blizzard frames shown (hideBlizzard off): TotemFrame stays in PlayerFrame.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class = "SHAMAN"
tf = makeTotemFrame()
loadAddon({ db = { font = "arial", hideBlizzard = false, pos = {} } })
eq(tf._parent, PlayerFrame, "Blizzard's player frame shown: totems stay put")
rawset(_G, "TotemFrame", nil)
GlassUnitFramesDB = nil

done("test_totems")
