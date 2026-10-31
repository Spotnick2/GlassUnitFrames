-- Mirror.lua (#151): the client's mirror timers (breath, fatigue, feign
-- death) as glass bars, and a small hook for custom timers on the same pill.
--
-- The rows come from MIRROR_TIMER_START / PAUSE / STOP, rebuilt from
-- GetMirrorTimerInfo at PLAYER_ENTERING_WORLD, as Blizzard's container does
-- (Blizzard_MirrorTimer, MirrorTimer.lua). Values go straight to the client:
-- maxValue to SetMinMaxValues and GetMirrorTimerProgress to SetValue, so a
-- secret works too (their secrecy is unmeasured: /fp steps cast mirror). The
-- seconds are written only when the progress is plain.
--
-- The pill is a bar of Castbar's (Castbar.bars.mirror), always detached: its
-- spot, size and scale are saved in db.castBars.mirror and moved in unlock
-- mode (mover cast:mirror). Blizzard's MirrorTimerContainer, an Edit Mode
-- system, is hidden by Blizzard.lua the managed way (never reparented).
--
-- Built offline, awaiting the in-game check.

GlassUF = GlassUF or {}
local API, Glass, Castbar = GlassUF.API, GlassUF.Glass, GlassUF.Castbar
local Mirror = {}
GlassUF.Mirror = Mirror

local GAP = 2
local MAX_ROWS = 5
-- Blizzard's fills, as colours (MirrorTimerAtlas): plain numbers, fixed (the
-- Cast bars page has no room for swatches).
Mirror.COLORS = {
    BREATH = { 0.25, 0.55, 1.00 }, EXHAUSTION = { 0.95, 0.74, 0.22 },
    FEIGNDEATH = { 0.95, 0.60, 0.20 }, DEATH = { 0.75, 0.75, 0.75 },
}
local CUSTOM_COLOR = { 0.55, 0.65, 0.95 }
local SAMPLE = { label = "Breath", color = Mirror.COLORS.BREATH, value = 0.65 }

Mirror.enabled = true
local c                -- the pill (Castbar.bars.mirror)
local rows = {}        -- the row widgets, in order
local active = {}      -- key -> timer: { key, label, color, paused, mirror | dur, ends }
local order = {}       -- active keys, in start order
local sampleOn = { unlock = false, preview = false }

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end
local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function sampling() return sampleOn.unlock or sampleOn.preview end

-- The rows that show, top to bottom: the live timers, or the sample alone.
local function layout()
    if not c then return end
    local shown = {}
    if #order == 0 and sampling() then
        shown[1] = SAMPLE
    else
        for i = 1, math.min(#order, MAX_ROWS) do shown[i] = active[order[i]] end
    end
    local h, inset = c.rowH or 14, Glass.Inset("small")
    for i, row in ipairs(rows) do
        local t = shown[i]
        row.timer = t
        if t then
            row.bar:ClearAllPoints()
            row.bar:SetPoint("TOPLEFT", c.host, "TOPLEFT", inset, -inset - (i - 1) * (h + GAP))
            row.bar:SetPoint("TOPRIGHT", c.host, "TOPRIGHT", -inset, -inset - (i - 1) * (h + GAP))
            row.bar:SetHeight(h)
            row.bar:SetStatusBarColor(t.color[1], t.color[2], t.color[3])
            row.label:SetText(t.label)
            if t == SAMPLE then
                row.bar:SetMinMaxValues(0, 1)
                row.bar:SetValue(t.value)
                row.time:SetText("39")
            end
            row.bar:Show()
        else
            row.bar:Hide()
        end
    end
    local n = #shown
    if n == 0 then
        c.host:Hide()
        return
    end
    c.host:SetHeight(n * h + (n - 1) * GAP + 2 * inset)
    c.host:Show()
end

local function place(bar)
    local x, y, w, h, _, scale = Castbar.EffectiveGeometry("mirror")
    bar.rowH = h
    bar.host:ClearAllPoints()
    bar.host:SetWidth(w)
    Castbar.PlaceAt(bar.host, x, y, scale)
    layout()
end

local function paintColors() layout() end   -- fixed colours: a relayout repaints them

--------------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------------

local function add(key, t)
    if not active[key] then order[#order + 1] = key end
    t.key = key
    active[key] = t
end

local function remove(key)
    if not active[key] then return end
    active[key] = nil
    for i, k in ipairs(order) do
        if k == key then table.remove(order, i) break end
    end
end

-- A mirror timer (name, value, maxValue, paused, label): the client's values,
-- handed back to it. A name we can't read can't key a row: skipped.
local function startMirror(name, value, maxValue, paused, label)
    local key = plainString(name)
    if not key then
        API.Fail("mirror timer", "unreadable timer name")
        return
    end
    local t = { mirror = key, label = label, color = Mirror.COLORS[key] or CUSTOM_COLOR,
                paused = not API.IsSecret(paused) and paused ~= nil and paused ~= 0 and paused ~= false }
    add("mirror:" .. key, t)
    layout()
    for _, row in ipairs(rows) do
        if row.timer == t then
            local ok = pcall(function()
                row.bar:SetMinMaxValues(0, maxValue)
                row.bar:SetValue(value)
            end)
            if not ok then API.Fail("mirror timer", "values refused") end
        end
    end
end

-- One row's value and seconds, from the client (every frame it runs).
local function update(row)
    local t = row.timer
    if not t or t == SAMPLE then return end
    if t.mirror then
        if t.paused then return end
        local v = GetMirrorTimerProgress(t.mirror)
        local s = plainNumber(v)
        if s == nil and not API.IsSecret(v) then return end   -- no progress (it just ended)
        row.bar:SetValue(v)
        if s then row.time:SetFormattedText("%d", math.max(0, math.ceil(s / 1000))) else row.time:SetText("") end
    else
        local left = t.ends - GetTime()
        if left <= 0 then
            remove(t.key)
            layout()
            return
        end
        row.time:SetFormattedText("%d", math.ceil(left))
    end
end

-- The live timers again, as the client has them (a loading screen, a /reload).
local function rebuild()
    for _, key in ipairs({ unpack(order) }) do
        if active[key].mirror then remove(key) end
    end
    if Mirror.enabled and type(rawget(_G, "GetMirrorTimerInfo")) == "function" then
        for i = 1, 3 do
            local ok, name, value, maxValue, _, paused, label = pcall(GetMirrorTimerInfo, i)
            if ok and plainString(name) and name ~= "UNKNOWN" then startMirror(name, value, maxValue, paused, label) end
        end
    end
    layout()
end

local EVENTS = { "MIRROR_TIMER_START", "MIRROR_TIMER_PAUSE", "MIRROR_TIMER_STOP", "PLAYER_ENTERING_WORLD" }

local function onEvent(_, event, ...)
    if event == "MIRROR_TIMER_START" then
        local name, value, maxValue, _, paused, label = ...
        startMirror(name, value, maxValue, paused, label)
    elseif event == "MIRROR_TIMER_PAUSE" then
        local name, paused = ...
        local key = plainString(name)
        local t = key and active["mirror:" .. key]
        if t then t.paused = not API.IsSecret(paused) and paused ~= nil and paused ~= 0 and paused ~= false end
    elseif event == "MIRROR_TIMER_STOP" then
        local key = plainString((...))
        if key then
            remove("mirror:" .. key)
            layout()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        rebuild()
    end
end

--------------------------------------------------------------------------------
-- The custom-timer hook
--------------------------------------------------------------------------------

-- A timer of your own on the same pill: id (any plain string), its label, its
-- length in seconds, and an optional colour { r, g, b }. Starting an id again
-- restarts it. Returns false when it can't show.
function Mirror.Start(id, label, seconds, color)
    if not (c and Mirror.enabled and plainString(id) and plainString(label)) then return false end
    seconds = plainNumber(seconds)
    if not seconds or seconds <= 0 or seconds > 86400 then return false end
    local col = CUSTOM_COLOR
    if type(color) == "table" and plainNumber(color[1]) and plainNumber(color[2]) and plainNumber(color[3]) then
        col = { color[1], color[2], color[3] }
    end
    local now = GetTime()
    local t = { label = label, color = col, ends = now + seconds, dur = C_DurationUtil.CreateDuration() }
    t.dur:SetTimeFromStart(now, seconds)
    add("custom:" .. id, t)
    layout()
    for _, row in ipairs(rows) do
        if row.timer == t then
            row.bar:SetTimerDuration(t.dur, nil, API.TimerDirection(true))
            update(row)
        end
    end
    return true
end

function Mirror.Stop(id)
    if not plainString(id) or not active["custom:" .. id] then return false end
    remove("custom:" .. id)
    layout()
    return true
end

--------------------------------------------------------------------------------
-- Building and settings
--------------------------------------------------------------------------------

-- The sample row: while unlocked (so the pill has a size to drag) and in a preview.
function Mirror.SetSample(on) sampleOn.unlock = on and true or false; layout() end
function Mirror.SetPreview(on) sampleOn.preview = on and true or false; layout() end

function Mirror.SetEnabled(on)
    Mirror.enabled = on and true or false
    if not c then return end
    if Mirror.enabled then
        API.RegisterEvents(c.events, EVENTS)
        rebuild()
    else
        c.events:UnregisterAllEvents()
        for _, key in ipairs({ unpack(order) }) do remove(key) end
        layout()
    end
end

-- Called by Frames.Build, once Castbar is configured.
function Mirror.Build(db)
    if type(rawget(_G, "GetMirrorTimerProgress")) ~= "function" or not rawget(_G, "C_DurationUtil") then return end
    Mirror.enabled = db.mirrorTimers ~= false
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("MEDIUM")
    local skin = CreateFrame("Frame", nil, host)
    skin:SetAllPoints(host)
    local glass = Glass.Apply(skin, "small")
    local level = host:GetFrameLevel()
    c = { unit = "mirror", host = host, skin = skin, glass = glass, place = place, paintColors = paintColors }
    for i = 1, MAX_ROWS do
        local bar = CreateFrame("StatusBar", nil, host)
        bar:SetFrameLevel(level + 2)
        bar:SetStatusBarTexture(Glass.MEDIA .. "bar_fill")
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        bg:SetColorTexture(0, 0, 0, 0.35)
        local label = Glass.Font(bar, 10, "LEFT")
        label:SetPoint("LEFT", bar, "LEFT", 5, 0)
        local time = Glass.Font(bar, 10, "RIGHT")
        time:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
        label:SetPoint("RIGHT", time, "LEFT", -4, 0)
        bar:Hide()
        rows[i] = { bar = bar, label = label, time = time }
    end
    host.acc = 0
    host:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        for _, row in ipairs(rows) do
            if row.timer then GlassUF.Frames.attempt("mirror update", update, row) end
        end
    end)
    host:Hide()
    Castbar.bars.mirror = c
    Castbar.Place(c)
    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(...) GlassUF.Frames.attempt("mirror event", onEvent, ...) end)
    c.events = ev
    if Mirror.enabled then API.RegisterEvents(ev, EVENTS) end
    rebuild()
    return c
end

Mirror._test = { active = active, order = order, rows = rows, SAMPLE = SAMPLE, bar = function() return c end }
