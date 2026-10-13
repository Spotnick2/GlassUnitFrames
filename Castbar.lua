-- Castbar.lua: the cast bars (player, target, focus, pet): the inside player
-- row, the pills, and the cast channel's painter. Frames.build calls
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
--
-- Quartz's look and options (#78): a spell icon at either end, "Spell ->
-- Target" on the player's bar (SENT's plain target name), "remaining / total",
-- a spark on the fill's moving edge, a short "complete" flash when a cast
-- finishes, the cast time precision, and colours for the texts, the fills,
-- the spark and the pill's background (LibGlass's SetSurfaceTint).

GlassUF = GlassUF or {}
local API, Glass, Engine, Frames = GlassUF.API, GlassUF.Glass, GlassUF.Engine, GlassUF.Frames
local Castbar = {}
GlassUF.Castbar = Castbar

local attempt = Frames.attempt
local LAG = { 0.95, 0.20, 0.18, 0.55 }

-- Options (the Cast bars page): all on by default, saved only when off.
Castbar.options = { latency = true, latencyText = true, pushback = true,
                    targetName = true, totalTime = true, complete = true, craftCount = true }
Castbar.DB_KEYS = { latency = "castLatency", latencyText = "castLatencyText", pushback = "castPushback",
                    targetName = "castTargetName", totalTime = "castTotalTime", complete = "castComplete",
                    craftCount = "castCraftCount" }

-- Colours, every bar (#78). Plain numbers only: they go to SetStatusBarColor
-- on glass bars, whose LibGlass hook compares them. `background` nil = the
-- pill's own glass tint (SetSurfaceTint(g) gives it back).
Castbar.DEFAULT_COLORS = {
    spell = { 1, 1, 1, 1 }, time = { 1, 1, 1, 1 },
    cast = { 0.95, 0.74, 0.22, 1 }, channel = { 0.40, 0.80, 1.00, 1 },
    complete = { 0.30, 0.85, 0.35, 1 }, failed = { 0.85, 0.22, 0.22, 1 },
    spark = { 1, 1, 1, 0.8 },
    -- The swing rows (#87): main hand, off hand, ranged.
    swingMH = { 1.00, 0.82, 0.35, 1 }, swingOH = { 0.95, 0.58, 0.30, 1 }, swingRanged = { 0.45, 0.80, 0.45, 1 },
}
Castbar.COLOR_KEYS = { "spell", "time", "cast", "channel", "complete", "failed", "spark", "background",
                       "swingMH", "swingOH", "swingRanged" }
Castbar.colors = {}

-- A saved colour we can use: four numbers in 0..1 (alpha may be missing).
local function validColor(v)
    if type(v) ~= "table" then return nil end
    for i = 1, 3 do
        local x = v[i]
        if type(x) ~= "number" or API.IsSecret(x) or x ~= x or x < 0 or x > 1 then return nil end
    end
    local a = v[4]
    if a == nil then a = 1 end
    if type(a) ~= "number" or API.IsSecret(a) or a ~= a or a < 0 or a > 1 then return nil end
    return { v[1], v[2], v[3], a }
end

-- The cast time precision (decimals), 0..3, Quartz's slider.
Castbar.precision = 1

-- The time text's formats, built once per precision / option change (the
-- OnUpdate runs 20 times a second). Keyed by pushback sign .. "t" for total.
local FMT = {}
local function buildFormats()
    local p = "%." .. Castbar.precision .. "f"
    for _, sign in ipairs({ "", "+", "-" }) do
        local pre = sign ~= "" and ("|cffff4040" .. sign .. "%.1f|r ") or ""
        FMT[sign] = pre .. p .. "s"
        FMT[sign .. "t"] = pre .. p .. " / " .. p
    end
end
buildFormats()

function Castbar.Configure(db)
    Castbar.db = db
    for key, dbKey in pairs(Castbar.DB_KEYS) do
        Castbar.options[key] = db[dbKey] ~= false
    end
    local p = db.castPrecision
    if type(p) == "number" and not API.IsSecret(p) and p == math.floor(p) and p >= 0 and p <= 3 then
        Castbar.precision = p
    end
    buildFormats()
    local saved = type(db.castColors) == "table" and db.castColors or {}
    for _, k in ipairs(Castbar.COLOR_KEYS) do
        Castbar.colors[k] = validColor(saved[k]) or Castbar.DEFAULT_COLORS[k]
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
local plainString = plainGUID   -- the same test: a plain, non-empty string
local paintColors   -- one bar's colours (defined with the colour setters)

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
local MS_INSIDE = 20   -- bar height from which the ms figure sits inside the block
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
-- A batch craft (#91): the client counts it. At each craft's START,
-- C_TradeSkillUI.GetRemainingRecasts() is the casts left after this one
-- (measured: 4, 3, 2, 1, 0 for a batch of 5, plain), and UnitCastingInfo's
-- 6th return (isTradeskill) is plain true. Nil = not a craft, or unreadable.
local function craftRemaining()
    local ok, isTrade = pcall(function() return select(6, UnitCastingInfo("player")) end)
    if not ok or API.IsSecret(isTrade) or isTrade ~= true then return nil end
    local ts = rawget(_G, "C_TradeSkillUI")
    if not (ts and ts.GetRemainingRecasts) then return nil end
    local okR, r = pcall(ts.GetRemainingRecasts)
    if not okR or not plainNumber(r) or r < 0 or r ~= math.floor(r) or r > 10000 then return nil end
    return r
end

-- A craft's START: the same batch when it is the same recipe and the count went
-- down by exactly one, else a new batch. Anything else clears it.
local function trackCraft(c, guid, spellID)
    local left = craftRemaining()
    if left == nil then
        c.craft = nil
        return
    end
    local k = c.craft
    if k and spellID ~= nil and k.spellID == spellID and left == k.left - 1 then
        k.left, k.guid = left, guid
    else
        c.craft = { spellID = spellID, total = left + 1, left = left, guid = guid }
    end
end

-- Blizzard's craft loop stopped (UPDATE_TRADESKILL_CAST_STOPPED, a world event
-- Engine hands over): the batch is over. Scrapping (true) is left alone.
Engine.OnTradeskillStopped = function(isScrapping)
    if API.IsSecret(isScrapping) or isScrapping ~= false then return end
    local c = Castbar.bars.player
    if c then c.craft = nil end
end

local function trackPlayer(c, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- An instant the server turns down after SENT has no START: its
        -- FAILED may still flash (mayFlash).
        c.sentGUID = plainGUID((select(2, ...)))
        -- "Spell -> Target" (#78): SENT's target name, plain for the player
        -- (CastProbe: "First Surname", as "Karuzo Macphisto"). Not for a
        -- self-cast, matched against every form of our own name (the
        -- display name's format is unmeasured; UnitName gives the first name
        -- with the surname where the realm should be).
        local target = plainString((...))
        if target then
            local first, surname = UnitName("player")
            first, surname = plainString(first), plainString(surname)
            if target == plainString(GetUnitName("player", false)) or target == first
                or (first and surname and target == first .. " " .. surname) then
                target = nil
            end
        end
        c.sentTarget = target
        local now, stamp = GetTime(), lat.stamp
        lat.stamp = nil
        if stamp and now > stamp and now - stamp <= STALE then addSample(now - stamp) end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- The player's complete flash needs this cast's SUCCEEDED (it comes
        -- before the STOP, in the same frame: measured).
        c.succeededGUID = plainGUID((...))
        return
    end
    -- A craft that is followed by another in its batch doesn't flash
    -- "complete" (the next starts ~0.1 s later: measured). Set per STOP.
    c.craftHold = nil
    if CAST_STOP[event] then
        -- The newest cast is over: its pushback mustn't reach a cast painted
        -- later without a START (a full repaint). A late STOP of an older
        -- cast leaves the live one's alone.
        local guid = plainGUID((...))
        if guid == nil or guid == c.latestGUID then c.delay, c.chanEnd = nil, nil end
        -- The batch's craft (its own guid; a late STOP of an older one does
        -- nothing): the stored count from its START decides, never a fresh read.
        local k = c.craft
        if k and (guid == nil or guid == k.guid) then
            if k.left > 0 then c.craftHold = true else c.craft = nil end
        end
    elseif CAST_FAIL[event] then
        -- A cancelled craft ends its batch; a failure of anything else doesn't.
        local guid = plainGUID((...))
        local k = c.craft
        if k and (guid == nil or guid == k.guid) then c.craft = nil end
    elseif CAST_START[event] then
        c.delay = nil
        c.chanEnd = event == "UNIT_SPELLCAST_CHANNEL_START" and channelEnd() or nil
        -- SENT and START share a frame (measured): the target is this cast's.
        local guid = plainGUID((...))
        c.castTarget = (guid ~= nil and guid == c.sentGUID) and c.sentTarget or nil
        if event == "UNIT_SPELLCAST_CHANNEL_START" then
            c.craft = nil
        else
            trackCraft(c, guid, plainNumber((select(2, ...))))
        end
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
    -- The ms figure: inside the block, at its bottom corner (Quartz), on a
    -- bar at least 20 tall (under that it runs into the time text); just above
    -- a smaller detached bar; never on the docked 14 px row.
    local lt = c.lagText
    local barH = c.bar:GetHeight() or 0
    if Castbar.options.latencyText and (barH >= MS_INSIDE or c.detached) then
        lt:ClearAllPoints()
        local inside = barH >= MS_INSIDE
        if channel then
            if inside then lt:SetPoint("BOTTOMLEFT", c.bar, "BOTTOMLEFT", 2, 1)
            else lt:SetPoint("BOTTOMLEFT", c.host, "TOPLEFT", 2, 1) end
        else
            if inside then lt:SetPoint("BOTTOMRIGHT", c.bar, "BOTTOMRIGHT", -2, 1)
            else lt:SetPoint("BOTTOMRIGHT", c.host, "TOPRIGHT", -2, 1) end
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
    local col = Castbar.colors[channel and "channel" or "cast"]
    c.bar:SetStatusBarColor(col[1], col[2], col[3])
    c.duration, c.channel = d, channel
    local info = channel and UnitChannelInfo or UnitCastingInfo
    -- A craft never shows a target; a batch shows its count (#91).
    local craft = not channel and c.craft
    local target = Castbar.options.targetName and not craft and c.castTarget
    local count = craft and craft.total > 1 and Castbar.options.craftCount and craft
    if not attempt("cast name", function()
        -- The name goes to the client as is (other units' may be secret).
        local name = (info(f.unit))
        -- target and count are only ever set on the player's bar, whose name is plain.
        if target and type(name) == "string" then c.spell:SetFormattedText("%s -> %s", name, target)
        elseif count and type(name) == "string" then
            c.spell:SetFormattedText("%s (%d/%d)", name, count.total - count.left, count.total)
        else c.spell:SetText(name) end
    end) then c.spell:SetText("") end
    -- The icon: the texture goes straight to the client (never read in Lua).
    if c.iconSide ~= "none" then
        local ok = attempt("cast icon", function() c.icon:SetTexture((select(3, info(f.unit)))) end)
        c.icon:SetShown(ok)
    end
    c.spark:SetShown(Castbar.colors.spark[4] > 0)
    if not attempt("cast latency", paintLag, c, d, channel) then hideLag(c) end
    c.host:Show()
end

-- A short full bar: "failed" (Failed / Interrupted, text given, its guid
-- remembered so the repeats don't restart it) or "complete" (the spell name
-- kept, nothing remembered).
local function flash(c, text, guid, kind)
    c.token = c.token + 1
    local token = c.token
    c.flashing = true
    if kind ~= "complete" then c.flashedGUID = guid end
    c.duration = nil
    hideLag(c)
    c.spark:Hide()
    c.bar:SetMinMaxValues(0, 1)
    c.bar:SetValue(1)
    local col = Castbar.colors[kind or "failed"]
    c.bar:SetStatusBarColor(col[1], col[2], col[3])
    if text then c.spell:SetText(text) end
    -- The icon still shows the last cast shown: wrong for a failure of
    -- another cast (an instant refused after SENT, no START). Codex, #79.
    if kind ~= "complete" and guid ~= nil and c.latestGUID ~= nil and guid ~= c.latestGUID then
        c.icon:Hide()
    end
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
    if CAST_START[event] then
        c.latestGUID = plainGUID((...))
        c.failedGUID = nil
    end

    local d, channel = currentCast(f.unit)
    if d then
        -- The first INTERRUPTED comes with the cast still live (measured): mark
        -- the newest cast failed, so its STOP is no "complete" flash.
        if CAST_FAIL[event] then
            local guid = plainGUID((...))
            if guid == nil or c.latestGUID == nil or guid == c.latestGUID then c.failedGUID = guid or true end
        end
        showCast(f, c, d, channel)
        return
    end

    if CAST_FAIL[event] then
        local guid = plainGUID((...))
        if mayFlash(c, guid) then flash(c, CAST_FAIL[event], guid) end
    elseif event == "UNIT_SPELLCAST_STOP" and c.duration and not c.channel and not c.flashing
        and Castbar.options.complete then
        -- A cast (not a channel) that ended without failing: Quartz's short
        -- "complete" flash. Only the newest cast's STOP.
        local guid = plainGUID((...))
        local newest = guid == nil or c.latestGUID == nil or guid == c.latestGUID
        local failed = c.failedGUID == true or (guid ~= nil and c.failedGUID == guid)
        -- The player's own: only a cast whose SUCCEEDED we saw (a cast that
        -- fails as it lands never gets one). Other units have no SUCCEEDED
        -- for us: their STOP, as Quartz does.
        if f.unit == "player" and guid ~= nil and c.succeededGUID ~= guid then failed = true end
        -- A craft with more of its batch to come: no flash (#91).
        if newest and not failed and not c.craftHold then flash(c, nil, nil, "complete") end
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

-- The body's rows have one owner, Frames.ReflowRows (#87): the swing rows share them.
local function layoutRows(b, casting)
    b.castShown = casting and true or false
    Frames.ReflowRows(b)
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
                     target = { x = 0, y = -23, w = 340, h = 20, scale = 1 },
                     -- #76: focus above the target's bar, the pet's under the player's
                     -- (thinner, as Quartz's pet bar).
                     focus  = { x = 0, y = 1, w = 340, h = 16, scale = 1 },
                     pet    = { x = 0, y = -71, w = 220, h = 16, scale = 1 },
                     -- #87: the swing rows' pill (h = one row), under the player's bar.
                     swing  = { x = 0, y = -66, w = 340, h = 6, scale = 1 } }
Castbar.LIMITS = { x = { -4096, 4096 }, y = { -4096, 4096 }, w = { 80, 800 }, h = { 12, 40 },
                   scale = { 0.5, 2 } }
-- A bar's own limits where they differ (the swing rows: h is one thin row).
Castbar.LIMITS_FOR = { swing = { h = { 2, 20 } } }
local OTHER = { x = 0, y = -100, w = 240, h = 18, scale = 1 }   -- a bar with no defaults of its own
Castbar.bars = {}   -- unit -> the bar's state (c)

local function limit(k, unit)
    local own = Castbar.LIMITS_FOR[unit]
    return (own and own[k]) or Castbar.LIMITS[k]
end

local function inLimits(v, k, unit)
    local lim = limit(k, unit)
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
        if inLimits(e[k], k, unit) then return e[k] end
        return d[k]
    end
    return pick("x"), pick("y"), pick("w"), pick("h"), e.detached == true, pick("scale")
end
Castbar.Geometry = geometry   -- the swing rows (Swing.lua) place themselves from it

-- What a bar is laid out with now: its geometry, overridden in combat by its
-- zoom spot when its zoom is on (an effective detach; the saved one untouched, #89).
function Castbar.EffectiveGeometry(unit)
    local x, y, w, h, detached, scale = geometry(unit)
    local zx, zy, zs = GlassUF.Zoom.Target(unit)
    if zx then x, y, scale, detached = zx, zy, zs, true end
    return x, y, w, h, detached, scale
end

-- A detached host: its scale, CENTER on the screen centre. The spot is in
-- screen (UIParent) units at any scale, so the offsets are divided by it.
function Castbar.PlaceAt(host, x, y, scale)
    host:ClearAllPoints()
    host:SetScale(scale)
    host:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
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

-- The spell icon's side (#78): yours and the pet's on the left, the target's
-- and the focus's on the right (Quartz's mirrored pair); "none" hides it.
local ICON_SIDES = { left = true, right = true, none = true }
local ICON_DEFAULT = { player = "left", pet = "left", target = "right", focus = "right" }
function Castbar.IconSide(unit)
    local e = saved(unit)
    if e and ICON_SIDES[e.icon] then return e.icon end
    return ICON_DEFAULT[unit] or "left"
end

-- The bar between its two anchors, and the icon (a square as tall as the bar)
-- at one end, the bar shortened to make room.
local function placeBar(c, barH, lRel, lPt, lx, rRel, rPt, rx, y)
    local side = Castbar.IconSide(c.unit)
    c.iconSide = side
    local room = barH + 2
    c.bar:SetHeight(barH)
    c.bar:SetPoint("TOPLEFT", lRel, lPt, lx + (side == "left" and room or 0), y)
    c.bar:SetPoint("TOPRIGHT", rRel, rPt, rx - (side == "right" and room or 0), y)
    c.icon:ClearAllPoints()
    c.icon:SetSize(barH, barH)
    if side == "left" then
        c.icon:SetPoint("TOPLEFT", lRel, lPt, lx, y)
    elseif side == "right" then
        c.icon:SetPoint("TOPRIGHT", rRel, rPt, rx, y)
    else
        c.icon:Hide()
    end
end

-- Lay a bar out for its mode. Reconciles the player's rows explicitly: they
-- shrink only while the bar is docked inside AND shown.
local placeCast

function Castbar.Place(c)
    GlassUF.Zoom.Cancel(c.unit)   -- any placement stops a glide: it snaps (#89)
    if c.place then c.place(c) else placeCast(c) end   -- the swing rows place themselves (#87)
    GlassUF.Zoom.Placed(c.unit)   -- its combat outline follows a new size (#89)
end

function placeCast(c)
    local x, y, w, h, detached, scale = Castbar.EffectiveGeometry(c.unit)
    c.detached = detached
    local host, bar = c.host, c.bar
    host:ClearAllPoints()
    bar:ClearAllPoints()
    if c.inside and not detached then
        c.skin:Hide()
        host:SetScale(1)
        host:SetAllPoints(c.body)
        placeBar(c, CAST_ROW, c.b.power, "BOTTOMLEFT", 0, c.b.power, "BOTTOMRIGHT", 0, -CAST_GAP)
    else
        c.skin:Show()
        if detached then
            host:SetSize(w, h)
            Castbar.PlaceAt(host, x, y, scale)
        else
            h = c.L.castH or PILL_H
            host:SetScale(1)
            host:SetSize(c.L.w, h)
            if c.L.castAbove then
                -- Above the body (focus): 10 up, clear of the leader crown on its top edge.
                host:SetPoint("BOTTOM", c.body, "TOP", 0, 10)
            else
                -- Under the aura rows when the frame has them (target), else right under the body.
                host:SetPoint("TOP", c.body, "BOTTOM", 0, c.L.auras and (GlassUF.Auras.Bottom() - 6) or -6)
            end
        end
        local inset = Glass.Inset("small")
        placeBar(c, math.max(4, h - 2 * inset), host, "TOPLEFT", inset, host, "TOPRIGHT", -inset, -inset)
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
    if not (c and Castbar.IsDetached(unit) and inLimits(x, "x") and inLimits(y, "y")) then return false end
    x, y = math.floor(x * 2 + 0.5) / 2, math.floor(y * 2 + 0.5) / 2
    -- Zoomed (#89): the new home is saved and used when combat ends; the host
    -- stays at (or keeps gliding to) its zoom spot.
    if not GlassUF.Zoom.Target(unit) then Castbar.PlaceAt(c.host, x, y, select(6, geometry(unit))) end
    if not live then Castbar.SavePosition(unit, x, y) end
    return true, x, y
end

function Castbar.SizeOf(unit)
    if not Castbar.bars[unit] then return nil end
    local _, _, w, h = geometry(unit)
    return w, h
end

-- A bar's detached size, clamped to LIMITS (whole units). Allowed while
-- docked too (the Cast bars page): it applies once the bar is detached.
function Castbar.SetSize(unit, w, h)
    local c = Castbar.bars[unit]
    if not c then return false end
    local function clamp(v, k)
        if type(v) ~= "number" or v ~= v then return nil end
        local lim = limit(k, unit)
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

function Castbar.SetIconSide(unit, side)
    local c = Castbar.bars[unit]
    if not (c and ICON_SIDES[side]) then return false end
    local e = entry(unit)
    e.icon = side ~= (ICON_DEFAULT[unit] or "left") and side or nil
    prune(unit)
    Castbar.Place(c)
    Engine.RepaintChannel("cast", function(f) return f.unit == unit end)
    return true
end

-- One bar's colours: texts, spark, background (the fills on its next paint).
function paintColors(c)
    if c.paintColors then return c.paintColors(c) end   -- the swing rows (#87)
    local col = Castbar.colors
    if not col.spell then return end   -- not configured yet
    c.spell:SetTextColor(col.spell[1], col.spell[2], col.spell[3], col.spell[4])
    c.time:SetTextColor(col.time[1], col.time[2], col.time[3], col.time[4])
    c.spark:SetVertexColor(col.spark[1], col.spark[2], col.spark[3], col.spark[4])
    local bg = col.background
    if bg then Glass.SetSurfaceTint(c.glass, bg[1], bg[2], bg[3], bg[4])
    else Glass.SetSurfaceTint(c.glass) end
end

-- The colours on every bar now: texts, spark, background; the fills on the
-- next paint (a repaint follows).
local function applyColors()
    for _, c in pairs(Castbar.bars) do paintColors(c) end
    Engine.RepaintChannel("cast")
end

-- One colour: r, g, b, a (plain, 0..1), saved; nil r = back to the default.
function Castbar.SetColor(key, r, g, b, a)
    local known = false
    for _, k in ipairs(Castbar.COLOR_KEYS) do if k == key then known = true end end
    if not known then return false end
    local db = Castbar.db
    if r == nil then
        Castbar.colors[key] = Castbar.DEFAULT_COLORS[key]
        if type(db.castColors) == "table" then
            db.castColors[key] = nil
            if next(db.castColors) == nil then db.castColors = nil end
        end
    else
        local v = validColor({ r, g, b, a })
        if not v then return false end
        Castbar.colors[key] = v
        if type(db.castColors) ~= "table" then db.castColors = {} end
        db.castColors[key] = v
    end
    applyColors()
    return true
end

function Castbar.ResetColors()
    for _, k in ipairs(Castbar.COLOR_KEYS) do Castbar.colors[k] = Castbar.DEFAULT_COLORS[k] end
    Castbar.db.castColors = nil
    applyColors()
end

-- Cast time precision, 0..3 decimals (saved only when not 1).
function Castbar.SetPrecision(p)
    if type(p) ~= "number" or p ~= p then return false end
    p = math.max(0, math.min(3, math.floor(p + 0.5)))
    Castbar.precision = p
    Castbar.db.castPrecision = p ~= 1 and p or nil
    buildFormats()
    return true, p
end

-- A detached bar in the exact horizontal middle of the screen (its y kept).
function Castbar.CenterX(unit)
    local c = Castbar.bars[unit]
    if not (c and Castbar.IsDetached(unit)) then return false end
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
local LABELS = { player = "Player cast bar", target = "Target cast bar", focus = "Focus cast bar", pet = "Pet cast bar",
                 swing = "Swing timer" }
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
    c.glass = Glass.Apply(skin, "small")   -- SetSurfaceTint: the background colour
    local bar = Glass.Bar(host, CAST_ROW)
    bar:SetFrameLevel(level + 2)
    local txt = CreateFrame("Frame", nil, host)
    txt:SetAllPoints(bar)
    txt:SetFrameLevel(level + 11)
    local fontSize = (c.inside or (L.castH or PILL_H) < PILL_H) and 10 or 11   -- the thinner bars: 10
    local spell = Glass.Font(txt, fontSize, "LEFT")
    spell:SetPoint("LEFT", bar, "LEFT", 6, 0)
    local time = Glass.Font(txt, fontSize, "RIGHT")
    time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    spell:SetPoint("RIGHT", time, "LEFT", -6, 0)
    c.host, c.skin, c.bar, c.txt, c.spell, c.time = host, skin, bar, txt, spell, time
    -- The spell icon, trimmed of its border; placed by placeBar.
    c.icon = txt:CreateTexture(nil, "ARTWORK")
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.icon:Hide()
    -- The spark: a thin bright line just inside the fill's moving edge (the
    -- client moves the edge; no Lua geometry), on the bar's glass overlay and
    -- under its own rounded mask, so a full bar's spark stays inside the
    -- bar's round end. Under the text.
    local over = bar.overlay or bar
    c.spark = over:CreateTexture(nil, "OVERLAY", nil, 3)
    c.spark:SetColorTexture(1, 1, 1, 1)
    c.spark:SetBlendMode("ADD")
    c.spark:SetWidth(2)
    c.spark:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    c.spark:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    c.spark:AddMaskTexture(Glass.Mask(over, "bar_mask", 8, 0, bar))
    c.spark:Hide()
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
    -- The time text, built once: the OnUpdate runs 20 times a second. Pushback
    -- in red before it: + on a cast (it ends later), - on a channel (sooner).
    -- "remaining / total" both go to the client as is (secret-safe).
    local function paintTime()
        local d, delay = c.duration, Castbar.options.pushback and c.delay
        local sign = (delay and delay > 0) and (c.channel and "-" or "+") or ""
        if Castbar.options.totalTime then
            if sign ~= "" then
                c.time:SetFormattedText(FMT[sign .. "t"], delay, d:GetRemainingDuration(), d:GetTotalDuration())
            else
                c.time:SetFormattedText(FMT.t, d:GetRemainingDuration(), d:GetTotalDuration())
            end
        elseif sign ~= "" then
            c.time:SetFormattedText(FMT[sign], delay, d:GetRemainingDuration())
        else
            c.time:SetFormattedText(FMT[""], d:GetRemainingDuration())
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
    paintColors(c)
    return c
end

-- A new unit behind the token (Engine.OnTokenChanged, a target change): the
-- old unit's flash and newest guid aren't the new one's. Not on an ordinary
-- full repaint: that would let an interrupt's repeats flash again.
function Castbar.TokenChanged(c)
    c.flashing = false
    c.latestGUID, c.failedGUID = nil, nil
    -- The old unit's spell icon: with no newest guid, a later FAILED (no
    -- START) would flash it (Codex, #79). The repaint that follows (deferred)
    -- shows the new unit's icon if it is casting.
    c.icon:Hide()
end

-- Turn a cast option on or off; repaint so the change shows mid-cast.
function Castbar.SetOption(key, on)
    if Castbar.DB_KEYS[key] == nil then return false end
    Castbar.options[key] = on and true or false
    Engine.RepaintChannel("cast")
    return true
end

Castbar._test = { lat = lat, mayFlash = mayFlash, SAMPLES = SAMPLES, STALE = STALE, geometry = geometry }
