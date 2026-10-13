-- Castbar.lua: the cast bars (player and target): the inside player row,
-- the target's pill, and the cast channel's painter. Frames.build calls
-- Castbar.CastingRows and Castbar.Build.
--
-- Secret-value rule as in Frames.lua: a cast's timing reaches the bar as a
-- LuaDurationObject (StatusBar:SetTimerDuration) and its time text through
-- SetFormattedText. The one exception is the PLAYER's own cast (#72): its
-- start/end, delay and total duration were measured plain on 1.60.1.70338,
-- in and out of combat, so the latency block and the pushback text read them,
-- each behind an IsSecret guard (a secret value means "not shown", never an
-- error). Other units' casts stay unread.

GlassUF = GlassUF or {}
local API, Glass, Engine, Frames = GlassUF.API, GlassUF.Glass, GlassUF.Engine, GlassUF.Frames
local Castbar = {}
GlassUF.Castbar = Castbar

local attempt = Frames.attempt
local CAST, CHANNEL, FAILED = { 0.95, 0.74, 0.22 }, { 0.40, 0.80, 1.00 }, { 0.85, 0.22, 0.22 }
local LAG = { 0.95, 0.20, 0.18, 0.55 }

-- Options (/glass options, Cast bar): all on by default, saved only when off.
Castbar.options = { latency = true, pushback = true }
Castbar.DB_KEYS = { latency = "castLatency", pushback = "castPushback" }

function Castbar.Configure(db)
    for key, dbKey in pairs(Castbar.DB_KEYS) do
        Castbar.options[key] = db[dbKey] ~= false
    end
end

local CAST_STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
local CAST_FAIL = { UNIT_SPELLCAST_FAILED = "Failed", UNIT_SPELLCAST_INTERRUPTED = "Interrupted" }
local CAST_START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true }
-- The player-only events (Engine.PLAYER_CAST_EVENTS): state, never a repaint.
local TRACK_ONLY = { UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true }

-- Plain values only: a secret, or the wrong type, reads as nil.
local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end
local function plainGUID(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

--------------------------------------------------------------------------------
-- Latency estimate (#72). On Forever the SENT and START of a hard cast arrive
-- in the same frame, so send->start is always 0 (measured). What the trace did
-- show is a steady interval from CURRENT_SPELL_CAST_CHANGED(false) (the key
-- press) to SENT: median 139 ms over 110 casts, where GetNetStats said 33 ms.
-- The difference is the server's processing; a cancel pays it too, so this is
-- the estimate the block shows. It is an estimate of the tail you probably
-- can't cancel, not a measured round trip.
--   - A sample is taken at every player SENT (casts and instants), from the
--     latest CAST_CHANGED(false) no older than STALE seconds; every SENT
--     consumes the stamp, kept or not.
--   - A queued cast arrives in the frame its predecessor ended
--     (SUCCEEDED/STOP(prev) -> CAST_CHANGED(false) -> SENT -> START, every
--     time in the traces), so its sample is 0: a same-frame sample is
--     dropped. (Not "an end event in the SENT frame": an unrelated SUCCEEDED,
--     Auto Shot say, would drop real samples.)
--   - Shown: the median of the last SAMPLES samples, which shrugs off a key
--     press that waited out a global cooldown. Before any sample, GetNetStats
--     (shown with a ~, since it leaves the server's share out).
--------------------------------------------------------------------------------

local SAMPLES, STALE = 7, 1
local lat = { samples = {} }   -- also: stamp

Engine.OnCastChanged = function(cancelled)
    if API.IsSecret(cancelled) or cancelled ~= false then return end
    lat.stamp = GetTime()
end

local function addSample(s)
    local list = lat.samples
    list[#list + 1] = s
    if #list > SAMPLES then table.remove(list, 1) end
end

-- Seconds, and whether it's only the GetNetStats fallback. nil: no estimate.
function Castbar.Latency()
    local n = #lat.samples
    if n == 0 then
        local net = API.NetLatency()
        if net then return net, true end
        return nil
    end
    local sorted = {}
    for i, v in ipairs(lat.samples) do sorted[i] = v end
    table.sort(sorted)
    local mid = math.floor((n + 1) / 2)
    if n % 2 == 1 then return sorted[mid], false end
    return (sorted[mid] + sorted[mid + 1]) / 2, false
end

-- The player's channel end (ms), plain or nil: a channel's pushback shortens
-- it (UnitChannelInfo has no delay field).
local function channelEnd()
    local ok, _, _, _, _, endMs = pcall(UnitChannelInfo, "player")
    return ok and plainNumber(endMs) or nil
end

-- The player's cast delay (ms), plain or nil: UnitCastingInfo's 11th return.
local function castDelay()
    local ok, delayMs = pcall(function() return select(11, UnitCastingInfo("player")) end)
    return ok and plainNumber(delayMs) or nil
end

-- The player's state, updated BEFORE the painter reads it (Engine hands the
-- payload to the painter, which calls this first: one ordered path).
-- Payload after the unit: SENT (target, castGUID, spellID); the others
-- (castGUID, spellID, ...).
local function trackPlayer(c, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- An instant the server turns down after SENT has no START: its
        -- FAILED may still flash (mayFlash).
        c.sentGUID = plainGUID((select(2, ...)))
        local now, stamp = GetTime(), lat.stamp
        lat.stamp = nil
        if stamp and now > stamp and now - stamp <= STALE then addSample(now - stamp) end
        return
    end
    if CAST_STOP[event] then
        -- The newest cast is over: its pushback mustn't reach a cast painted
        -- later without a START (a full repaint). A late STOP of an older
        -- cast leaves the live one's alone.
        local guid = plainGUID((...))
        if guid == nil or guid == c.latestGUID then c.delay, c.chanEnd = nil, nil end
    elseif CAST_START[event] then
        c.delay = nil
        c.chanEnd = event == "UNIT_SPELLCAST_CHANNEL_START" and channelEnd() or nil
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        -- Cumulative and plain for the player (measured: 1000, 1800, 2400 ms,
        -- the start moving by the same amount): assigned, never added up.
        local delayMs = castDelay()
        if delayMs then c.delay = delayMs / 1000 end
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        local endNow = channelEnd()
        if c.chanEnd and endNow then c.delay = (c.chanEnd - endNow) / 1000 end
    end
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

-- What the unit is casting right now: DurationObject + channel flag, or nil.
local function currentCast(u)
    if not UnitExists(u) then return nil end
    local ok, d, channel = pcall(API.CastDuration, u)
    if ok and d then return d, channel end
    return nil
end

local function hideLag(c)
    if c.lag then
        c.lag:Hide()
    end
end

-- The latency block over the end of the bar the cast is heading for: the
-- right for a cast (it fills), the left for a channel (it drains).
local function paintLag(c, d, channel)
    if not c.lag then return end
    local est = Castbar.Latency()
    local total
    if est and Castbar.options.latency then
        local ok, hasSecret = pcall(d.HasSecretValues, d)
        if ok and not API.IsSecret(hasSecret) and hasSecret == false then
            local okT, t = pcall(d.GetTotalDuration, d)
            t = okT and plainNumber(t) or nil
            if t and t > 0 then total = t end
        end
    end
    if not total then
        hideLag(c)
        return
    end
    c.lag:SetReverseFill(not channel)
    c.lag:SetValue(math.max(0, math.min(1, est / total)))
    c.lag:Show()
end

local function showCast(f, c, d, channel)
    c.token = c.token + 1
    c.flashing = false
    if not attempt("cast timer", c.bar.SetTimerDuration, c.bar, d, nil, API.TimerDirection(channel)) then
        c.duration = nil
        hideLag(c)
        c.host:Hide()
        return
    end
    -- Colour AFTER attaching the timer: attaching can reset the bar's visual
    -- state (DinoUF re-applies it afterwards too, modules/cast.lua).
    local col = channel and CHANNEL or CAST
    c.bar:SetStatusBarColor(col[1], col[2], col[3])
    c.duration, c.channel = d, channel
    local info = channel and UnitChannelInfo or UnitCastingInfo
    if not attempt("cast name", function() c.spell:SetText((info(f.unit))) end) then c.spell:SetText("") end
    if not attempt("cast latency", paintLag, c, d, channel) then hideLag(c) end
    c.host:Show()
end

local function flash(c, text, guid)
    c.token = c.token + 1
    local token = c.token
    c.flashing = true
    c.flashedGUID = guid
    c.duration = nil
    hideLag(c)
    c.bar:SetMinMaxValues(0, 1)
    c.bar:SetValue(1)
    c.bar:SetStatusBarColor(FAILED[1], FAILED[2], FAILED[3])
    c.spell:SetText(text)
    c.time:SetText("")
    c.host:Show()
    C_Timer.After(0.5, function()
        if c.token == token then
            c.flashing = false
            c.host:Hide()
        end
    end)
end

-- May a FAILED/INTERRUPTED for `guid` start a flash? The client repeats an
-- interrupt after the STOP (3 times ~0.1 s later, or twice in the same frame;
-- measured), and the first INTERRUPTED still has the cast live, so the flash
-- starts on a repeat. A guid flashes only once, even when the newest cast's
-- guid is unknown (a target picked mid-cast, no START seen). Once it is known,
-- only that guid (or the player's last SENT, for an instant refused after it)
-- may flash. A guid we can't read (secret, absent) keeps the old behaviour.
local function mayFlash(c, guid)
    if guid == nil then return true end
    if guid == c.flashedGUID then return false end
    if c.latestGUID == nil then return true end
    -- An older cast, or a rejected attempt (a client-side guid, never SENT).
    return guid == c.latestGUID or guid == c.sentGUID
end

-- Every event re-reads what the unit is casting NOW rather than trusting the
-- event alone: FAILED also fires for a rejected attempt while another cast
-- carries on, and a STOP can land after the next cast began.
-- event nil = full repaint. `...` is the event's payload after the unit.
Engine.SetPainter("cast", function(f, event, ...)
    local c = f.cast
    if not c then return end
    if event and f.unit == "player" then trackPlayer(c, event, ...) end
    if TRACK_ONLY[event] then return end
    if CAST_START[event] then c.latestGUID = plainGUID((...)) end

    local d, channel = currentCast(f.unit)
    if d then
        showCast(f, c, d, channel)
        return
    end

    if CAST_FAIL[event] then
        local guid = plainGUID((...))
        if mayFlash(c, guid) then flash(c, CAST_FAIL[event], guid) end
    elseif event ~= nil and not CAST_STOP[event] then
        API.Fail("cast duration", "no DurationObject on " .. event)
    end
    -- Nothing casting: hide, unless an interrupt/fail flash is still up.
    if not c.flashing then
        c.duration = nil
        hideLag(c)
        c.host:Hide()
    end
end)

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- An inside cast row: CAST_ROW px plus CAST_GAP above it and between
-- health and power. The idle heights come from build() (b.rows.idle); the
-- casting ones are derived from them, so a different frame height still
-- fills its body. No secure frame is touched, so this works in combat.
local CAST_ROW, CAST_GAP = 14, 2

function Castbar.CastingRows(idle)
    local inner = idle.health + idle.gap + idle.power
    local power = math.max(8, idle.power - 2)
    return { health = inner - CAST_ROW - 2 * CAST_GAP - power, gap = CAST_GAP, power = power }
end

local function layoutRows(b, casting)
    local r = casting and b.rows.casting or b.rows.idle
    b.health:SetHeight(r.health)
    if b.healPred then b.healPred:SetHeight(r.health) end
    b.power:ClearAllPoints()
    b.power:SetPoint("TOPLEFT", b.health, "BOTTOMLEFT", 0, -r.gap)
    b.power:SetPoint("TOPRIGHT", b.health, "BOTTOMRIGHT", 0, -r.gap)
    b.power:SetHeight(r.power)
end

-- The cast bar either rides in its own glass pill under the body (target), or
-- is a row inside the body that appears only while casting (player, SUF's
-- auto-hiding cast bar): health and power shrink while it shows.
local function castHost(b, body, L)
    -- Needs a power bar to sit under; a frame without one keeps the pill.
    if L.castInside and b.power then
        local host = CreateFrame("Frame", nil, body)
        host:SetAllPoints(body)
        host:SetFrameLevel(Glass.ContentLevel(body))
        local bar = Glass.Bar(host, CAST_ROW)
        bar:SetPoint("TOPLEFT", b.power, "BOTTOMLEFT", 0, -CAST_GAP)
        bar:SetPoint("TOPRIGHT", b.power, "BOTTOMRIGHT", 0, -CAST_GAP)
        bar:SetFrameLevel(Glass.ContentLevel(body))
        -- Text above the bar's glass overlay (Glass.OVERLAY_LEVEL); hides with the host.
        local txt = CreateFrame("Frame", nil, host)
        txt:SetAllPoints(bar)
        txt:SetFrameLevel(bar:GetFrameLevel() + Glass.OVERLAY_LEVEL + 1)
        host:SetScript("OnShow", function() layoutRows(b, true) end)
        host:SetScript("OnHide", function() layoutRows(b, false) end)
        return host, bar, txt, 10
    end
    local host = CreateFrame("Frame", nil, b)
    host:SetSize(L.w, 20)
    -- Under the aura rows when the frame has them (target), else right under the body.
    host:SetPoint("TOP", body, "BOTTOM", 0, L.auras and (GlassUF.Auras.Bottom() - 6) or -6)
    host:SetFrameLevel(b:GetFrameLevel() + 1)
    local g = Glass.Apply(host, "small")
    local inset = Glass.Inset("small")
    local bar = Glass.Bar(host, 20 - 2 * inset)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, -inset)
    bar:SetFrameLevel(Glass.ContentLevel(host))
    return host, bar, g.top, 11
end

function Castbar.Build(b, body, L)
    local host, bar, textLayer, fontSize = castHost(b, body, L)
    local spell = Glass.Font(textLayer, fontSize, "LEFT")
    spell:SetPoint("LEFT", bar, "LEFT", 6, 0)
    local time = Glass.Font(textLayer, fontSize, "RIGHT")
    time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    spell:SetPoint("RIGHT", time, "LEFT", -6, 0)
    host:Hide()

    local c = { host = host, bar = bar, spell = spell, time = time, token = 0 }
    -- The player's latency block (#72): the bar's own geometry, over its
    -- fill, under its glass overlay. OverlayBar places only its clip frame.
    if b.unit == "player" then
        c.lag = Frames.OverlayBar(bar, LAG, 2, false)
        c.lag:SetAllPoints(bar)
        c.lag:Hide()
    end
    -- The time text, built once: the OnUpdate runs 20 times a second.
    local function paintTime()
        local d, delay = c.duration, Castbar.options.pushback and c.delay
        if delay and delay > 0 then
            -- Pushback in red before the time: + on a cast (it ends later),
            -- - on a channel (it ends sooner).
            local fmt = c.channel and "|cffff4040-%.1f|r %.1fs" or "|cffff4040+%.1f|r %.1fs"
            c.time:SetFormattedText(fmt, delay, d:GetRemainingDuration())
        else
            c.time:SetFormattedText("%.1fs", d:GetRemainingDuration())
        end
    end
    host.acc = 0
    host:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        if c.duration then attempt("cast time", paintTime) end
    end)
    return c
end

-- A new unit behind the token (Engine.OnTokenChanged, a target change): the
-- old unit's flash and newest guid aren't the new one's. Not on an ordinary
-- full repaint: that would let an interrupt's repeats flash again.
function Castbar.TokenChanged(c)
    c.flashing = false
    c.latestGUID = nil
end

-- Turn a cast option on or off; repaint so the change shows mid-cast.
function Castbar.SetOption(key, on)
    if Castbar.DB_KEYS[key] == nil then return false end
    Castbar.options[key] = on and true or false
    Engine.RepaintChannel("cast")
    return true
end

Castbar._test = { lat = lat, mayFlash = mayFlash, SAMPLES = SAMPLES, STALE = STALE }
