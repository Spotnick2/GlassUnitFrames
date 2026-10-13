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
--
-- Detachable (#74): each bar's host is a mouse-less child of its unit button
-- (so it hides with it), either docked (the player's row inside the body, the
-- target's pill under it) or detached: a glass pill of its own on the screen,
-- placed and sized in unlock mode (a mover source, "cast:<unit>"), saved in
-- db.castBars[unit]. Nothing secure anchors to a host, and a host is never
-- protected (measured in combat: move, scale, resize, hide, re-dock all ok).

GlassUF = GlassUF or {}
local API, Glass, Engine, Frames = GlassUF.API, GlassUF.Glass, GlassUF.Engine, GlassUF.Frames
local Castbar = {}
GlassUF.Castbar = Castbar

local attempt = Frames.attempt
local CAST, CHANNEL, FAILED = { 0.95, 0.74, 0.22 }, { 0.40, 0.80, 1.00 }, { 0.85, 0.22, 0.22 }
local LAG = { 0.95, 0.20, 0.18, 0.55 }

-- Options (/glass options, Cast bar): all on by default, saved only when off.
Castbar.options = { latency = true, latencyText = true, pushback = true }
Castbar.DB_KEYS = { latency = "castLatency", latencyText = "castLatencyText", pushback = "castPushback" }

function Castbar.Configure(db)
    Castbar.db = db
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
        c.lagText:SetText("")
    end
end

-- The latency block over the end of the bar the cast is heading for: the
-- right for a cast (it fills), the left for a channel (it drains).
local function paintLag(c, d, channel)
    if not c.lag then return end
    local est, approx = Castbar.Latency()
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
    -- The ms figure, just above the block's end: only on a detached bar (the
    -- docked row is 14 px, too small to read it).
    local lt = c.lagText
    if Castbar.options.latencyText and c.detached then
        lt:ClearAllPoints()
        if channel then
            lt:SetPoint("BOTTOMLEFT", c.host, "TOPLEFT", 2, 1)
        else
            lt:SetPoint("BOTTOMRIGHT", c.host, "TOPRIGHT", -2, 1)
        end
        lt:SetFormattedText(approx and "~%dms" or "%dms", math.floor(est * 1000 + 0.5))
    else
        lt:SetText("")
    end
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

-- Where a bar sits. Docked: the player's row inside the body (SUF's
-- auto-hiding cast bar: health and power shrink while it shows), the target's
-- glass pill under the body (under its aura rows). Detached: its own glass
-- pill, CENTER on the screen centre, its spot, size and scale saved. The spot
-- is in screen (UIParent) units at any scale: SetPoint offsets are in the
-- host's own scaled units, so they are divided by the scale. The defaults
-- follow the owner's Quartz layout: the player's bar under the screen centre,
-- the target's just above it.
local PILL_H = 20
Castbar.DETACHED = { player = { x = 0, y = -47, w = 340, h = 20, scale = 1 },
                     target = { x = 0, y = -23, w = 340, h = 20, scale = 1 } }
Castbar.LIMITS = { x = { -4096, 4096 }, y = { -4096, 4096 }, w = { 80, 800 }, h = { 12, 40 },
                   scale = { 0.5, 2 } }
local OTHER = { x = 0, y = -100, w = 240, h = 18, scale = 1 }   -- a bar with no defaults of its own
Castbar.bars = {}   -- unit -> the bar's state (c)

local function inLimits(v, k)
    local lim = Castbar.LIMITS[k]
    return type(v) == "number" and not API.IsSecret(v) and v == v and v >= lim[1] and v <= lim[2]
end

-- The saved entry, or nil. Never trusted field by field: a malformed value
-- falls back to its default, it never aborts a build.
local function saved(unit)
    local db = Castbar.db
    local all = db and db.castBars
    local e = type(all) == "table" and all[unit]
    return type(e) == "table" and e or nil
end

-- x, y, w, h (each valid, else its default), whether it's detached, and its scale.
local function geometry(unit)
    local d, e = Castbar.DETACHED[unit] or OTHER, saved(unit) or {}
    local function pick(k)
        if inLimits(e[k], k) then return e[k] end
        return d[k]
    end
    return pick("x"), pick("y"), pick("w"), pick("h"), e.detached == true, pick("scale")
end

-- The entry to write into (made on the first write).
local function entry(unit)
    local db = Castbar.db
    if type(db.castBars) ~= "table" then db.castBars = {} end
    if type(db.castBars[unit]) ~= "table" then db.castBars[unit] = {} end
    return db.castBars[unit]
end

local function prune(unit)
    local db = Castbar.db
    if type(db.castBars) == "table" and type(db.castBars[unit]) == "table" and next(db.castBars[unit]) == nil then
        db.castBars[unit] = nil
    end
    if type(db.castBars) == "table" and next(db.castBars) == nil then db.castBars = nil end
end

-- Lay a bar out for its mode. Reconciles the player's rows explicitly: they
-- shrink only while the bar is docked inside AND shown.
function Castbar.Place(c)
    local x, y, w, h, detached, scale = geometry(c.unit)
    c.detached = detached
    local host, bar = c.host, c.bar
    host:ClearAllPoints()
    bar:ClearAllPoints()
    if c.inside and not detached then
        c.skin:Hide()
        host:SetScale(1)
        host:SetAllPoints(c.body)
        bar:SetHeight(CAST_ROW)
        bar:SetPoint("TOPLEFT", c.b.power, "BOTTOMLEFT", 0, -CAST_GAP)
        bar:SetPoint("TOPRIGHT", c.b.power, "BOTTOMRIGHT", 0, -CAST_GAP)
    else
        c.skin:Show()
        if detached then
            host:SetScale(scale)
            host:SetSize(w, h)
            host:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
        else
            h = PILL_H
            host:SetScale(1)
            host:SetSize(c.L.w, h)
            -- Under the aura rows when the frame has them (target), else right under the body.
            host:SetPoint("TOP", c.body, "BOTTOM", 0, c.L.auras and (GlassUF.Auras.Bottom() - 6) or -6)
        end
        local inset = Glass.Inset("small")
        bar:SetHeight(math.max(4, h - 2 * inset))
        bar:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
        bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, -inset)
    end
    if c.inside then layoutRows(c.b, not detached and host:IsShown()) end
    if c.lagText and not detached then c.lagText:SetText("") end
end

function Castbar.IsDetached(unit)
    local _, _, _, _, detached = geometry(unit)
    return detached
end

-- Detach or attach a bar. Allowed in combat: nothing here is protected.
function Castbar.SetDetached(unit, on)
    local c = Castbar.bars[unit]
    if not c then return false end
    entry(unit).detached = on and true or nil
    prune(unit)
    Castbar.Place(c)
    -- The ms text follows the mode mid-cast: this bar's frame only.
    Engine.RepaintChannel("cast", function(f) return f.unit == unit end)
    return true
end

-- A detached bar's spot: CENTER offsets from the screen centre.
function Castbar.PositionOf(unit)
    if not Castbar.bars[unit] then return nil end
    local x, y = geometry(unit)
    return x, y
end

-- Record a spot without touching the frame (the mover's combat path).
function Castbar.SavePosition(unit, x, y)
    if not (Castbar.bars[unit] and inLimits(x, "x") and inLimits(y, "y")) then return false end
    local e = entry(unit)
    e.x, e.y = x, y
    return true
end

-- Place a detached bar, rounded to 0.5 units; saved unless `live` (a drag in flight).
function Castbar.SetPosition(unit, x, y, live)
    local c = Castbar.bars[unit]
    if not (c and c.detached and inLimits(x, "x") and inLimits(y, "y")) then return false end
    x, y = math.floor(x * 2 + 0.5) / 2, math.floor(y * 2 + 0.5) / 2
    local scale = select(6, geometry(unit))
    c.host:ClearAllPoints()
    c.host:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
    if not live then Castbar.SavePosition(unit, x, y) end
    return true, x, y
end

function Castbar.SizeOf(unit)
    if not Castbar.bars[unit] then return nil end
    local _, _, w, h = geometry(unit)
    return w, h
end

-- Resize a detached bar, clamped to LIMITS (whole units).
function Castbar.SetSize(unit, w, h)
    local c = Castbar.bars[unit]
    if not (c and c.detached) then return false end
    local function clamp(v, k)
        if type(v) ~= "number" or v ~= v then return nil end
        local lim = Castbar.LIMITS[k]
        return math.max(lim[1], math.min(lim[2], math.floor(v + 0.5)))
    end
    -- Only the dimension given is saved: the other keeps following its default.
    local e = entry(unit)
    e.w, e.h = clamp(w, "w") or e.w, clamp(h, "h") or e.h
    prune(unit)
    Castbar.Place(c)
    return true
end

function Castbar.ScaleOf(unit)
    if not Castbar.bars[unit] then return nil end
    return (select(6, geometry(unit)))
end

-- A bar's scale (shown while detached), clamped to LIMITS, in 0.05 steps.
-- Allowed in combat, like everything here.
function Castbar.SetScale(unit, s)
    local c = Castbar.bars[unit]
    if not c or type(s) ~= "number" or s ~= s then return false end
    local lim = Castbar.LIMITS.scale
    s = math.max(lim[1], math.min(lim[2], math.floor(s * 20 + 0.5) / 20))
    entry(unit).scale = s
    Castbar.Place(c)
    return true, s
end

-- A detached bar in the exact horizontal middle of the screen (its y kept).
function Castbar.CenterX(unit)
    local c = Castbar.bars[unit]
    if not (c and c.detached) then return false end
    local _, y = geometry(unit)
    return Castbar.SetPosition(unit, 0, y)
end

-- A detached bar back at its default spot, size and scale (still detached).
function Castbar.ResetPosition(unit)
    local c = Castbar.bars[unit]
    if not c then return false end
    local e = entry(unit)
    e.x, e.y, e.w, e.h, e.scale = nil, nil, nil, nil, nil
    prune(unit)
    Castbar.Place(c)
    return true
end

-- Every bar back at its default spot and size ("Reset frame positions"); a
-- detached bar stays detached. Also re-places a bar a dropped drag left at an
-- unsaved spot.
function Castbar.ResetPositions()
    for unit in pairs(Castbar.bars) do Castbar.ResetPosition(unit) end
end

-- The unlock-mode source for a detached bar (Movers.lua: id, label, frame,
-- rel, position, set, save, reset, follows; plus size, setSize and attach).
local LABELS = { player = "Player cast bar", target = "Target cast bar" }
function Castbar.MoverSource(unit)
    local c = Castbar.bars[unit]
    if not c then return nil end
    return {
        id = "cast:" .. unit, label = LABELS[unit] or (unit .. " cast bar"),
        frame = function() return c.host end,
        rel = function() return "UIParent", UIParent end,
        position = function() return Castbar.PositionOf(unit) end,
        set = function(x, y, live) return Castbar.SetPosition(unit, x, y, live) end,
        save = function(x, y) return Castbar.SavePosition(unit, x, y) end,
        reset = function() return Castbar.ResetPosition(unit) end,
        follows = function() return false end,
        size = function() return Castbar.SizeOf(unit) end,
        scale = function() return Castbar.ScaleOf(unit) end,
        setScale = function(s) return GlassUF.Settings.SetCastScale(unit, s) end,
        setSize = function(w, h) return Castbar.SetSize(unit, w, h) end,
        attach = function() return GlassUF.Settings.SetCastDetached(unit, false) end,
    }
end

function Castbar.Build(b, body, L)
    local c = { unit = b.unit, b = b, body = body, L = L, token = 0,
                -- Docked inside needs a power bar to sit under; without one, the pill.
                inside = (L.castInside and b.power) and true or false }
    -- Levels, fixed at build (the latency block's clip takes the bar's level
    -- once): host H, its glass pill H (rims H + 10), the bar H + 2 (its glass
    -- overlay H + 6), the text H + 11, above the pill's rims.
    local level = c.inside and Glass.ContentLevel(body) or (b:GetFrameLevel() + 1)
    local host = CreateFrame("Frame", nil, b)
    host:SetFrameLevel(level)
    local skin = CreateFrame("Frame", nil, host)
    skin:SetAllPoints(host)
    skin:SetFrameLevel(level)
    Glass.Apply(skin, "small")
    local bar = Glass.Bar(host, CAST_ROW)
    bar:SetFrameLevel(level + 2)
    local txt = CreateFrame("Frame", nil, host)
    txt:SetAllPoints(bar)
    txt:SetFrameLevel(level + 11)
    local fontSize = c.inside and 10 or 11
    local spell = Glass.Font(txt, fontSize, "LEFT")
    spell:SetPoint("LEFT", bar, "LEFT", 6, 0)
    local time = Glass.Font(txt, fontSize, "RIGHT")
    time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    spell:SetPoint("RIGHT", time, "LEFT", -6, 0)
    c.host, c.skin, c.bar, c.txt, c.spell, c.time = host, skin, bar, txt, spell, time
    host:Hide()

    -- The player's latency block (#72): the bar's own geometry, over its
    -- fill, under its glass overlay. OverlayBar places only its clip frame.
    if b.unit == "player" then
        c.lag = Frames.OverlayBar(bar, LAG, 2, false)
        c.lag:SetAllPoints(bar)
        c.lag:Hide()
        c.lagText = Glass.Font(txt, 8, "RIGHT")
    end
    if c.inside then
        host:SetScript("OnShow", function() layoutRows(b, not c.detached) end)
        host:SetScript("OnHide", function() layoutRows(b, false) end)
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
    Castbar.bars[b.unit] = c
    Castbar.Place(c)
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

Castbar._test = { lat = lat, mayFlash = mayFlash, SAMPLES = SAMPLES, STALE = STALE, geometry = geometry }
