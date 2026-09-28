-- Blizzard.lua: hide Blizzard's own unit frames for every unit GlassUF draws.
--
-- The recipe both references use: unregister the frame's unit watch and
-- events, hide it, and reparent it to a hidden frame. On this Retail-codebase
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
    for unit in pairs(units) do
        for _, name in ipairs(Blizzard.FRAMES[unit] or {}) do
            if Blizzard.HideFrame(name) ~= false then Blizzard.active = true end
        end
    end
end

-- Totems (#18). GlassUF can't draw totems (GetTotemInfo is secret), and
-- hiding PlayerFrame hides its child TotemFrame too. So host Blizzard's OWN
-- TotemFrame in a holder under our player frame: Blizzard keeps drawing the
-- timers, swipes and right-click-to-destroy (EllesmereUI's approach). Any
-- class: TotemFrame only shows while a totem slot is active.
--
-- The glass is the holder's child, BELOW TotemFrame (Glass.Apply puts its rim
-- on a layer 10 levels up, so TotemFrame is raised above that), and follows
-- TotemFrame's own shown state: no totems, no glass.
--
-- Anything may SetParent / SetPoint TotemFrame back (its layout parent, Edit
-- Mode). Those hooks schedule ONE deferred repair, never inside Blizzard's own
-- call (the Edit Mode taint rule), through whenSafe. A repair that finds it
-- already in place does nothing.
local totem = { holder = nil, ready = false, applying = false, scheduled = false }

local function totemsPlaced(tf)
    if tf:GetParent() ~= totem.holder then return false end
    local ok, _, rel = pcall(tf.GetPoint, tf, 1)
    return ok and rel == totem.holder
end

local function placeTotems()
    local tf, holder = rawget(_G, "TotemFrame"), totem.holder
    if not (tf and holder) or totemsPlaced(tf) then return end
    totem.applying = true
    if tf:GetParent() ~= holder then tf:SetParent(holder) end
    tf:SetFrameLevel(holder:GetFrameLevel() + 12)   -- above the glass's rim layer
    tf:ClearAllPoints()
    tf:SetPoint("TOP", holder, "TOP", 0, 0)
    totem.applying = false
end

local function repairTotems()
    totem.scheduled = false
    local tf = rawget(_G, "TotemFrame")
    if tf and totem.ready then whenSafe("totems", tf, placeTotems) end
end

local function scheduleTotems()
    if totem.applying or totem.scheduled or not totem.ready then return end
    totem.scheduled = true
    C_Timer.After(0, repairTotems)
end

-- Host TotemFrame under `anchor` (the player frame's body). Only while
-- PlayerFrame is hidden (the caller decides); a second call does nothing.
function Blizzard.HostTotems(anchor)
    local tf = rawget(_G, "TotemFrame")
    if not (tf and anchor) or totem.ready then return false end
    local holder = totem.holder or CreateFrame("Frame", "GlassUF_TotemHolder", UIParent)
    holder:SetSize(1, 1)
    holder:ClearAllPoints()
    holder:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    totem.holder = holder
    if not totem.glass then
        local glass = CreateFrame("Frame", nil, holder)
        glass:SetFrameLevel(holder:GetFrameLevel())
        glass:SetPoint("TOPLEFT", tf, "TOPLEFT", -4, 4)
        glass:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", 4, -4)
        GlassUF.Glass.Apply(glass, "small")
        glass:SetShown(tf:IsShown())
        tf:HookScript("OnShow", function() glass:Show() end)
        tf:HookScript("OnHide", function() glass:Hide() end)
        totem.glass = glass
        hooksecurefunc(tf, "SetParent", function(_, parent) if parent ~= totem.holder then scheduleTotems() end end)
        hooksecurefunc(tf, "SetPoint", scheduleTotems)
    end
    totem.ready = true   -- only once everything above succeeded
    repairTotems()
    return true
end

Blizzard._test = { hooked = hooked, pending = pending, totem = totem, repair = repairTotems }
