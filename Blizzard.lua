-- Blizzard.lua: hide Blizzard's own unit frames for every unit GlassUF draws.
--
-- The recipe both references use: unregister the frame's unit watch and
-- events, hide it, and reparent it to a hidden frame. On this Retail-codebase
-- client, add EllesmereUI's lesson: Edit Mode calls SetParent on these frames
-- whenever it opens or closes, and reparenting back INSIDE that call runs in
-- Blizzard's secure execution and taints secret-value reads for the session.
-- So the re-hide is deferred to a timer, waits while Edit Mode is open, and
-- waits for combat to end if the frame is protected.
--
-- Hiding is one-way for a session: /glass blizzard show takes effect after
-- /reload. Party frames are never touched (the owner uses Cell).

GlassUF = GlassUF or {}
local Blizzard = {}
GlassUF.Blizzard = Blizzard

-- Our unit -> Blizzard frames to hide when we draw that unit.
Blizzard.FRAMES = {
    player       = { "PlayerFrame" },
    pet          = { "PetFrame" },
    target       = { "TargetFrame", "ComboFrame" },
    targettarget = { "TargetFrameToT" },
    focus        = { "FocusFrame" },
    focustarget  = { "FocusFrameToT" },
}

local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()
Blizzard.hiddenParent = hiddenParent

local hooked, pending, afterCombat = {}, {}, {}

local regen = CreateFrame("Frame")
regen:SetScript("OnEvent", function(self)
    if InCombatLockdown() then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local list = afterCombat
    afterCombat = {}
    for frame in pairs(list) do Blizzard.Reparent(frame) end
end)

local function editModeOpen()
    local em = rawget(_G, "EditModeManagerFrame")
    return em ~= nil and em:IsShown()
end

-- Put `frame` back under the hidden parent, when it is safe to.
function Blizzard.Reparent(frame)
    pending[frame] = nil
    if frame:GetParent() == hiddenParent then return end
    if editModeOpen() then
        pending[frame] = true
        C_Timer.After(0.25, function() Blizzard.Reparent(frame) end)
    elseif InCombatLockdown() and frame:IsProtected() then
        afterCombat[frame] = true
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        frame:SetParent(hiddenParent)
    end
end

local function silence(child)
    if child and child.UnregisterAllEvents then child:UnregisterAllEvents() end
end

-- Hide one Blizzard frame by global name. Must run out of combat.
function Blizzard.HideFrame(name)
    local frame = rawget(_G, name)   -- a Blizzard global may not exist on this client
    if not frame or hooked[frame] then return false end
    hooked[frame] = true
    UnregisterUnitWatch(frame)
    frame:UnregisterAllEvents()
    frame:Hide()
    frame:SetParent(hiddenParent)
    silence(frame.healthbar or frame.healthBar)
    silence(frame.manabar or frame.manaBar)
    silence(frame.spellbar)
    -- Edit Mode (or anything else) reparenting it: undo that on a timer, never
    -- synchronously inside the caller's SetParent.
    hooksecurefunc(frame, "SetParent", function(self, parent)
        if parent ~= hiddenParent and not pending[self] then
            pending[self] = true
            C_Timer.After(0, function() Blizzard.Reparent(self) end)
        end
    end)
    return true
end

-- Hide the Blizzard counterparts of every unit in `units` (GlassUF's built frames).
function Blizzard.HideFor(units)
    local hidden = {}
    for unit in pairs(units) do
        for _, name in ipairs(Blizzard.FRAMES[unit] or {}) do
            if Blizzard.HideFrame(name) then hidden[#hidden + 1] = name end
        end
    end
    table.sort(hidden)
    return hidden
end

Blizzard._test = { hooked = hooked, pending = pending, afterCombat = afterCombat, regen = regen }
