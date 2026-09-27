-- Engine.lua: decides WHO gets painted and WHEN. Owns nothing visual:
-- painters are registered per channel by Frames.lua.
--
-- - One tracker frame per unit token, events registered with RegisterUnitEvent
--   so the client filters delivery.
-- - Events are grouped into channels; a burst of events marks channels dirty
--   and one flush on the next frame paints each (frame, channel) once. Dedupe
--   is by channel, never by comparing values: those may be secret.
-- - The cast channel is painted immediately with its event name, because
--   start/stop/interrupt mean different things.
-- - Chained tokens (targettarget, focustarget, ...) have no unit events; ONE
--   shared 0.5s ticker repaints the visible ones.

GlassUF = GlassUF or {}
local API = GlassUF.API
local Engine = {}
GlassUF.Engine = Engine

Engine.CHANNEL_EVENTS = {
    health   = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    -- The power line can carry level/classification text (target), so it
    -- follows those events too.
    power    = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_LEVEL",
                 "UNIT_CLASSIFICATION_CHANGED" },
    name     = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_LEVEL", "UNIT_CONNECTION" },
    portrait = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" },
    -- Raid target / leader / loot / PvP icons. Most of their triggers are
    -- group-wide events, handled by the world frame below; only the PvP flag
    -- is per unit.
    indicators = { "UNIT_FACTION" },
    cast     = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
                 "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
                 "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
                 "UNIT_SPELLCAST_CHANNEL_STOP" },
}
Engine.ORDER = { "name", "health", "power", "portrait", "indicators", "cast" }

local painters = {}
local framesByUnit = {}      -- unit -> { frame, ... }
local eventChannels = {}     -- event -> { channel, ... }
local dirty = {}             -- frame -> { channel = true }
local trackers = {}

for channel, events in pairs(Engine.CHANNEL_EVENTS) do
    for _, e in ipairs(events) do
        eventChannels[e] = eventChannels[e] or {}
        table.insert(eventChannels[e], channel)
    end
end

function Engine.SetPainter(channel, fn)
    painters[channel] = fn
end

-- A painter that throws must not take the rest of the flush with it (nor
-- leave frame.snap set): record the first error per channel and carry on.
GlassUF.paintFailures = GlassUF.paintFailures or {}
local function paint(frame, channel, event)
    local fn = painters[channel]
    if not (fn and frame.channels[channel]) then return end
    local ok, err = pcall(fn, frame, event)
    if not ok and GlassUF.paintFailures["painter " .. channel] == nil then
        GlassUF.paintFailures["painter " .. channel] = tostring(err)
    end
end

-- One flush per rendered frame. Hidden (idle) until something is dirty.
local flusher = CreateFrame("Frame")
flusher:Hide()
flusher:SetScript("OnUpdate", function(self)
    self:Hide()
    local batch = dirty
    dirty = {}
    for frame, chans in pairs(batch) do
        for _, channel in ipairs(Engine.ORDER) do
            if chans[channel] then paint(frame, channel, nil) end
        end
        frame.snap = nil
    end
end)

function Engine.MarkDirty(frame, channel)
    dirty[frame] = dirty[frame] or {}
    dirty[frame][channel] = true
    flusher:Show()
end

-- Every channel the frame uses, including cast (painted with a nil event,
-- which means "look at the unit now").
-- Every channel of a frame, same unit: values may ease (the ticker's refresh).
function Engine.RefreshAll(frame)
    for channel in pairs(frame.channels) do Engine.MarkDirty(frame, channel) end
end

-- A full repaint means the unit may have changed (new target, pet swap,
-- shown again): bars snap to the new values instead of easing from the old
-- unit's. frame.snap is cleared once the flush has painted the frame.
function Engine.FullRepaint(frame)
    frame.snap = true
    -- Remember who this frame shows, so the ticker can tell a later identity
    -- change (no event) from a plain refresh of the same unit.
    local ok, guid = pcall(UnitGUID, frame.unit)
    frame.lastGUID = (ok and not API.IsSecret(guid)) and guid or nil
    Engine.RefreshAll(frame)
end

-- One channel on every frame that uses it (group-wide events). `only`, if
-- given, filters frames (e.g. those showing a group number).
function Engine.RepaintChannel(channel, only)
    for _, list in pairs(framesByUnit) do
        for _, frame in ipairs(list) do
            if frame.channels[channel] and (not only or only(frame)) then Engine.MarkDirty(frame, channel) end
        end
    end
end

function Engine.RepaintUnit(unit)
    for _, frame in ipairs(framesByUnit[unit] or {}) do Engine.FullRepaint(frame) end
end

local function onUnitEvent(_, event, unit)
    local chans = eventChannels[event]
    if not chans then return end
    for _, frame in ipairs(framesByUnit[unit] or {}) do
        for _, channel in ipairs(chans) do
            if channel == "cast" then paint(frame, "cast", event)
            else Engine.MarkDirty(frame, channel) end
        end
    end
end

local function tracker(unit, channels)
    local t = trackers[unit]
    if not t then
        t = CreateFrame("Frame")
        t:SetScript("OnEvent", onUnitEvent)
        t.registered = {}
        trackers[unit] = t
    end
    local want = {}
    for channel in pairs(channels) do
        for _, e in ipairs(Engine.CHANNEL_EVENTS[channel] or {}) do
            if not t.registered[e] then
                t.registered[e] = true
                table.insert(want, e)
            end
        end
    end
    if #want > 0 then API.RegisterUnitEvents(t, want, unit) end
end

-- One ticker for every event-less frame: every 0.5s, repaint the visible ones.
local ticked = {}
local ticker = CreateFrame("Frame")
ticker.elapsed = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    for _, frame in ipairs(ticked) do
        if frame:IsVisible() then
            -- A chained token can change identity with no event at all (e.g.
            -- targettargettarget when targettarget retargets). Compare the
            -- GUID: same unit eases; a different unit, or a GUID we cannot
            -- compare (secret, unreadable), snaps. Conservative on purpose.
            local ok, guid = pcall(UnitGUID, frame.unit)
            if not ok or API.IsSecret(guid) then guid = nil end
            if guid ~= nil and guid == frame.lastGUID then
                Engine.RefreshAll(frame)
            else
                Engine.FullRepaint(frame)
            end
            frame.lastGUID = guid
        end
    end
end)

-- Register a unit frame. frame.unit and frame.channels ({channel = true})
-- must be set. opts.ticker: no unit events exist for this token (a chained
-- token like targettarget); the shared ticker repaints it while visible.
function Engine.Register(frame, opts)
    framesByUnit[frame.unit] = framesByUnit[frame.unit] or {}
    table.insert(framesByUnit[frame.unit], frame)

    if opts and opts.ticker then
        table.insert(ticked, frame)
    else
        tracker(frame.unit, frame.channels)
    end

    frame:HookScript("OnShow", function() Engine.FullRepaint(frame) end)
    -- First paint. A build deferred past PLAYER_ENTERING_WORLD has missed that
    -- repaint, and RegisterUnitWatch may already have shown the frame before
    -- the OnShow hook above existed.
    Engine.FullRepaint(frame)
end

-- Events that change WHICH unit a token means: repaint everything showing it.
-- One rule covers every chain depth: when `base` changes meaning, so does every
-- token starting with base.."target" (targettarget, targettargettarget, ...).
local TOKEN_EVENTS = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus" }

local function repaintChain(base, includeBase)
    local prefix = base .. "target"
    for u in pairs(framesByUnit) do
        if (includeBase and u == base) or u:sub(1, #prefix) == prefix then Engine.RepaintUnit(u) end
    end
end

local world = CreateFrame("Frame")
world:SetScript("OnEvent", function(_, event, unit)
    local base = TOKEN_EVENTS[event]
    if base then
        repaintChain(base, true)
        if Engine.OnTokenChanged then Engine.OnTokenChanged(base) end
    elseif event == "UNIT_PET" then
        if unit == "player" then Engine.RepaintUnit("pet") end
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Only the name line carries the group number: repainting the whole
        -- frame would reload the 3D portrait on every roster change.
        Engine.RepaintChannel("name", function(f) return f.layout and f.layout.groupNumber end)
        Engine.RepaintChannel("indicators")
    elseif event == "PLAYER_FLAGS_CHANGED" then
        -- Fires with group tokens (player, partyN, raidN), never target/focus:
        -- refresh every name line so an AFK tag on target or focus follows too.
        Engine.RepaintChannel("name")
    elseif event == "RAID_TARGET_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "PARTY_LOOT_METHOD_CHANGED" then
        Engine.RepaintChannel("indicators")
    elseif event == "PLAYER_ENTERING_WORLD" then
        for u in pairs(framesByUnit) do Engine.RepaintUnit(u) end
    end
end)
API.RegisterEvents(world, { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_PET",
                            "GROUP_ROSTER_UPDATE", "PLAYER_FLAGS_CHANGED", "RAID_TARGET_UPDATE",
                            "PARTY_LEADER_CHANGED", "PARTY_LOOT_METHOD_CHANGED" })

-- UNIT_TARGET: registered per base unit so the client filters it (it fires for
-- every nameplate/party/raid unit otherwise). The unit whose target changed
-- takes its "<unit>target" chain with it.
local chainWatchers = {}
for _, base in ipairs({ "target", "focus" }) do
    local w = CreateFrame("Frame")
    w:SetScript("OnEvent", function() repaintChain(base, false) end)
    API.RegisterUnitEvents(w, { "UNIT_TARGET" }, base)
    chainWatchers[base] = w
end

Engine._test = { dirty = function() return dirty end, flusher = flusher, trackers = trackers,
                 ticker = ticker, chainWatchers = chainWatchers,
                 framesByUnit = framesByUnit, world = world }
