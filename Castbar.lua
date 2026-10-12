-- Castbar.lua: the cast bars (player and target), moved out of Frames.lua so
-- the cast features (#72 latency and pushback, then detach/zoom) live in one
-- place. Frames.build calls Castbar.CastingRows and Castbar.Build; the cast
-- channel's painter is registered here.
--
-- Secret-value rule as in Frames.lua: the cast's timing reaches the bar as a
-- LuaDurationObject (StatusBar:SetTimerDuration) and its time text through
-- SetFormattedText; Lua never reads start or end times.

GlassUF = GlassUF or {}
local API, Glass, Engine, Frames = GlassUF.API, GlassUF.Glass, GlassUF.Engine, GlassUF.Frames
local Castbar = {}
GlassUF.Castbar = Castbar

local attempt = Frames.attempt
local CAST, CHANNEL, FAILED = { 0.95, 0.74, 0.22 }, { 0.40, 0.80, 1.00 }, { 0.85, 0.22, 0.22 }

local CAST_STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
local CAST_FAIL = { UNIT_SPELLCAST_FAILED = "Failed", UNIT_SPELLCAST_INTERRUPTED = "Interrupted" }

-- What the unit is casting right now: DurationObject + channel flag, or nil.
local function currentCast(u)
    if not UnitExists(u) then return nil end
    local ok, d, channel = pcall(API.CastDuration, u)
    if ok and d then return d, channel end
    return nil
end

local function showCast(f, c, d, channel)
    c.token = c.token + 1
    c.flashing = false
    if not attempt("cast timer", c.bar.SetTimerDuration, c.bar, d, nil, API.TimerDirection(channel)) then
        c.duration = nil
        c.host:Hide()
        return
    end
    -- Colour AFTER attaching the timer: attaching can reset the bar's visual
    -- state (DinoUF re-applies it afterwards too, modules/cast.lua).
    local col = channel and CHANNEL or CAST
    c.bar:SetStatusBarColor(col[1], col[2], col[3])
    c.duration = d
    local info = channel and UnitChannelInfo or UnitCastingInfo
    if not attempt("cast name", function() c.spell:SetText((info(f.unit))) end) then c.spell:SetText("") end
    c.host:Show()
end

local function flash(c, text)
    c.token = c.token + 1
    local token = c.token
    c.flashing = true
    c.duration = nil
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

-- Every event re-reads what the unit is casting NOW rather than trusting the
-- event alone: FAILED also fires for a rejected attempt while another cast
-- carries on, and a STOP can land after the next cast began.
-- event nil = full repaint.
Engine.SetPainter("cast", function(f, event)
    local c = f.cast
    if not c then return end
    local d, channel = currentCast(f.unit)

    if d then
        showCast(f, c, d, channel)
        return
    end

    if CAST_FAIL[event] then
        flash(c, CAST_FAIL[event])
        return
    end

    if event ~= nil and not CAST_STOP[event] then
        API.Fail("cast duration", "no DurationObject on " .. event)
    end
    -- Nothing casting: hide, unless an interrupt/fail flash is still up.
    if not c.flashing then
        c.duration = nil
        c.host:Hide()
    end
end)

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
    host.acc = 0
    host:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        local d = c.duration
        if not d then return end
        attempt("cast time", function() c.time:SetFormattedText("%.1fs", d:GetRemainingDuration()) end)
    end)
    return c
end
