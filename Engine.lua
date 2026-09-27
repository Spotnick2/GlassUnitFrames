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
-- - targettarget has no unit events; a 0.5s ticker repaints it while shown.

GlassUF = GlassUF or {}
local API = GlassUF.API
local Engine = {}
GlassUF.Engine = Engine

Engine.CHANNEL_EVENTS = {
    health   = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    power    = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
    name     = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_LEVEL", "UNIT_CONNECTION" },
    portrait = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" },
    cast     = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
                 "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
                 "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
                 "UNIT_SPELLCAST_CHANNEL_STOP" },
}
Engine.ORDER = { "name", "health", "power", "portrait", "cast" }

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

local function paint(frame, channel, event)
    local fn = painters[channel]
    if fn and frame.channels[channel] then fn(frame, event) end
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
    end
end)

function Engine.MarkDirty(frame, channel)
    dirty[frame] = dirty[frame] or {}
    dirty[frame][channel] = true
    flusher:Show()
end

-- Every channel the frame uses, including cast (painted with a nil event,
-- which means "look at the unit now").
function Engine.FullRepaint(frame)
    for channel in pairs(frame.channels) do Engine.MarkDirty(frame, channel) end
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

-- Register a unit frame. frame.unit and frame.channels ({channel = true})
-- must be set. opts.ticker: no unit events exist for this token (targettarget);
-- repaint every 0.5s while the frame is shown instead.
function Engine.Register(frame, opts)
    framesByUnit[frame.unit] = framesByUnit[frame.unit] or {}
    table.insert(framesByUnit[frame.unit], frame)

    if opts and opts.ticker then
        local tick = CreateFrame("Frame", nil, frame)   -- a child: only runs while shown
        tick.elapsed = 0
        tick:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed >= 0.5 then
                self.elapsed = 0
                Engine.FullRepaint(frame)
            end
        end)
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
-- UNIT_TARGET fires for the unit whose target changed; its "<unit>target"
-- chain follows.
Engine.TOKEN_EVENTS = {
    PLAYER_TARGET_CHANGED = { "target", "targettarget" },
    PLAYER_FOCUS_CHANGED  = { "focus", "focustarget" },
}
Engine.TARGET_CHAINS = {
    target = { "targettarget" },
    focus  = { "focustarget" },
}

local world = CreateFrame("Frame")
world:SetScript("OnEvent", function(_, event, unit)
    local swapped = Engine.TOKEN_EVENTS[event]
    if swapped then
        for _, u in ipairs(swapped) do Engine.RepaintUnit(u) end
        if event == "PLAYER_TARGET_CHANGED" and Engine.OnTargetChanged then Engine.OnTargetChanged() end
    elseif event == "UNIT_TARGET" then
        for _, u in ipairs(Engine.TARGET_CHAINS[unit] or {}) do Engine.RepaintUnit(u) end
    elseif event == "UNIT_PET" then
        if unit == "player" then Engine.RepaintUnit("pet") end
    else   -- PLAYER_ENTERING_WORLD
        for u in pairs(framesByUnit) do Engine.RepaintUnit(u) end
    end
end)
API.RegisterEvents(world, { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD",
                            "UNIT_TARGET", "UNIT_PET" })

Engine._test = { dirty = function() return dirty end, flusher = flusher, trackers = trackers,
                 framesByUnit = framesByUnit, world = world }
