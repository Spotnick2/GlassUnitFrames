-- Blizzard.lua: hide Blizzard's own unit frames for every unit GlassUF draws.
--
-- The recipe both references use: unregister the frame's unit watch and
-- events, hide it, and reparent it to a hidden frame (except KEEP_PARENT
-- frames, which stay under a Blizzard parent we hide). On this Retail-codebase
-- client, add EllesmereUI's lesson: Edit Mode calls SetParent on these frames
-- whenever it opens or closes, and reparenting back INSIDE that call runs in
-- Blizzard's secure execution and taints secret-value reads for the session.
-- So the re-hide is deferred to a timer, waits while Edit Mode is open, and
-- waits for combat to end (through the addon's one combat queue) if the
-- frame is protected.
--
-- Only frames GlassUF replaces are hidden. ComboFrame goes only once GlassUF
-- has drawn combo pips (rogues and druids; GlassUnitFrames.lua).
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
    target       = { "TargetFrame" },
    targettarget = { "TargetFrameToT" },
    focus        = { "FocusFrame" },
    focustarget  = { "FocusFrameToT" },
}
Blizzard.active = false   -- true once anything was hidden this session

-- Frames that stay under their Blizzard parent (#58): reparenting them breaks
-- Blizzard code that expects that parent. Every managed frame (isManagedFrame,
-- set by ManagedFrameTemplate: PetFrame, PlayerCastingBarFrame, ...): each show
-- puts it back in its container (ManagedFrameSystem UpdateFrame), inside Edit
-- Mode's secure pass, so a reparent hook fights Blizzard there. Plus the ToT
-- frames, which call GetParent():ConfigureAuraContainer() on show and hide.
-- MirrorTimerContainer (#151) is an Edit Mode system: Edit Mode places it.
Blizzard.KEEP_PARENT = { TargetFrameToT = true, FocusFrameToT = true, MirrorTimerContainer = true }

local function keepsParent(frame, name)
    return frame.isManagedFrame == true or Blizzard.KEEP_PARENT[name] == true
end

local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()
Blizzard.hiddenParent = hiddenParent

local hooked, pending = {}, {}

local function editModeOpen()
    local em = rawget(_G, "EditModeManagerFrame")
    return em ~= nil and em:IsShown()
end

-- Run `fn` on `frame` once it is safe: never while Edit Mode is open (retry
-- every 0.25 s), never on a protected frame in combat (queued under `key`,
-- one slot per key, silent). Every retry re-checks both.
local function whenSafe(key, frame, fn)
    if editModeOpen() then
        C_Timer.After(0.25, function() whenSafe(key, frame, fn) end)
    elseif InCombatLockdown() and frame:IsProtected() then
        GlassUF.WhenOutOfCombat(key, function() whenSafe(key, frame, fn) end, false)
    else
        fn()
    end
end

-- Put `frame` back under the hidden parent, when it is safe to.
function Blizzard.Reparent(frame)
    pending[frame] = nil
    if frame:GetParent() == hiddenParent then return end
    pending[frame] = true
    whenSafe("blizzard:" .. tostring(frame:GetName()), frame, function()
        pending[frame] = nil
        if frame:GetParent() ~= hiddenParent then frame:SetParent(hiddenParent) end
    end)
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
    silence(frame.healthbar or frame.healthBar)
    silence(frame.manabar or frame.manaBar)
    silence(frame.spellbar)
    if keepsParent(frame, name) then
        -- Hidden by its hidden parent, except where Blizzard moves it out: a
        -- PetFrame moved in Edit Mode lives under UIParent, and Edit Mode's
        -- exit shows it while a pet is out. Hide it again, deferred (never
        -- inside Blizzard's Show) and when safe.
        frame:HookScript("OnShow", function(self)
            C_Timer.After(0, function()
                whenSafe("blizzard:" .. tostring(self:GetName()), self, function()
                    if self:IsShown() then self:Hide() end
                end)
            end)
        end)
        return true
    end
    frame:SetParent(hiddenParent)
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
    for unit in pairs(units) do
        for _, name in ipairs(Blizzard.FRAMES[unit] or {}) do
            if Blizzard.HideFrame(name) ~= false then Blizzard.active = true end
        end
    end
end

Blizzard._test = { hooked = hooked, pending = pending }
