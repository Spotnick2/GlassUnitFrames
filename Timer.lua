-- GlassUnitFrames: the combat timer (#120). A glass pill with the fight's time
-- (00:07, 1:00:05 past an hour), counting up from combat start and hidden out
-- of combat. A member of the cast-bar family like the swing rows (#87):
-- Castbar.bars.timer, saved in db.castBars.timer, placed by its own `place`,
-- moved and sized through Castbar's detach machinery (mover cast:timer).
-- Detached by default (Castbar.DEFAULT_DETACHED), at the top centre; docked,
-- a small pill just above the player frame's top-left.
--
-- What shows comes from independent inputs, each set by its own event or
-- setter, and one resolver: off -> hidden; preview -> the preview's clock;
-- unlock sample -> 00:42; a combat start -> its clock; else hidden. Combat is
-- recorded whatever else shows, so the order of the combat handlers
-- (Preview.OnCombat, Movers' lock, this file's frame) never loses a start.
-- The time is our own stamp against GetTime(): plain, no client secret.
--
-- Timer.enabled is public: ForeverCombatAssistant hides its own timer while
-- it's true.

GlassUF = GlassUF or {}
local API, Glass, Castbar = GlassUF.API, GlassUF.Glass, GlassUF.Castbar

local Timer = {}
GlassUF.Timer = Timer

local SAMPLE = 42                                  -- unlock mode's 00:42
local DOCKED_W, DOCKED_H, DOCKED_GAP = 60, 18, 10  -- 10: clear of the leader crown (7 above the edge)
local TEXT_SIZE = 13
local TICK = 0.2
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

Timer.enabled = true   -- db.combatTimer == false turns it off
local c                -- the timer "bar" (Castbar.bars.timer)
local live             -- GetTime() at combat start, or nil out of combat
local previewAt        -- GetTime() at the preview's start, or nil
local sample = false   -- unlock mode
local shownSecond      -- the whole second on screen (the text is written once per second)

function Timer.Format(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

-- What shows now, and since when.
local function mode()
    if not Timer.enabled then return nil end
    if previewAt then return "preview", previewAt end
    if sample then return "sample" end
    if live then return "live", live end
    return nil
end

local function write(seconds)
    local whole = math.floor(seconds)
    if whole == shownSecond then return end
    shownSecond = whole
    c.text:SetText(Timer.Format(whole))
end

local function resolve()
    if not c then return end
    local m, since = mode()
    shownSecond = nil
    if m == "sample" then write(SAMPLE) elseif m then write(GetTime() - since) end
    c.host:SetShown(m ~= nil)
    c.ticker:SetShown(m == "preview" or m == "live")
end

local function onEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        live = GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        live = nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A /reload mid-fight counts from now (the best known); a loading
        -- screen inside a fight already timed keeps its start.
        if InCombatLockdown() then live = live or GetTime() else live = nil end
    end
    resolve()
end

--------------------------------------------------------------------------------
-- Placement and colours (Castbar.Place and its colour pass hand the timer here)
--------------------------------------------------------------------------------

local function place(bar)
    local x, y, w, h, detached, scale = Castbar.EffectiveGeometry("timer")
    bar.detached = detached
    local host = bar.host
    host:ClearAllPoints()
    if detached then
        host:SetSize(w, h)
        Castbar.PlaceAt(host, x, y, scale)
    else
        host:SetScale(1)
        host:SetSize(DOCKED_W, DOCKED_H)
        host:SetPoint("BOTTOMLEFT", bar.b, "TOPLEFT", 0, DOCKED_GAP)
    end
end

-- The cast bars' time text and background colours.
local function paintColors(bar)
    local col = Castbar.colors
    local t = col.time or Castbar.DEFAULT_COLORS.time
    bar.text:SetTextColor(t[1], t[2], t[3], t[4])
    local bg = col.background
    if bg then Glass.SetSurfaceTint(bar.glass, bg[1], bg[2], bg[3], bg[4])
    else Glass.SetSurfaceTint(bar.glass) end
end

--------------------------------------------------------------------------------
-- Building and settings
--------------------------------------------------------------------------------

-- Called by Frames.Build for the player's frame, after the swing rows. Built
-- even when off, so turning it on later works.
function Timer.Build(b, db)
    if not (b and b.body) then return end
    Timer.enabled = db.combatTimer ~= false
    local level = b:GetFrameLevel() + 1
    local host = CreateFrame("Frame", nil, b)   -- a plain child: hidden with the button, never protected
    host:SetFrameLevel(level)
    local skin = CreateFrame("Frame", nil, host)
    skin:SetAllPoints(host)
    skin:SetFrameLevel(level)
    local glass = Glass.Apply(skin, "small")
    local text = Glass.Font(glass.top, TEXT_SIZE, "CENTER")
    text:SetPoint("CENTER", host, "CENTER", 0, 0)
    -- The clock: shown only while one runs; inside the host, so it rests while
    -- the player frame is hidden (the stamp keeps the time).
    local ticker = CreateFrame("Frame", nil, host)
    ticker:Hide()
    ticker.acc = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < TICK then return end
        self.acc = 0
        local _, since = mode()
        if since then write(GetTime() - since) end
    end)
    c = { unit = "timer", b = b, body = b.body, host = host, skin = skin, glass = glass, text = text,
          ticker = ticker, place = place, paintColors = paintColors }
    host:Hide()
    Castbar.bars.timer = c
    paintColors(c)
    Castbar.Place(c)

    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", onEvent)
    c.events = ev
    if Timer.enabled then
        API.RegisterEvents(ev, EVENTS)
        -- A build deferred until now may come after the fight's start.
        live = InCombatLockdown() and GetTime() or nil
    end
    resolve()
    return c
end

-- On or off (saved only when off). A request for the state it's in changes
-- nothing, so a repeated "on" mid-fight keeps counting. Off -> on re-reads
-- combat: the start was missed while off, so it counts from now.
function Timer.SetEnabled(on)
    on = on and true or false
    if not c then
        Timer.enabled = on
        return false
    end
    if on == Timer.enabled then return true end
    Timer.enabled = on
    if on then
        API.RegisterEvents(c.events, EVENTS)
        live = InCombatLockdown() and GetTime() or nil
    else
        c.events:UnregisterAllEvents()
        live = nil
    end
    resolve()
    return true
end

-- Unlock mode: a sample to place.
function Timer.SetSample(on)
    sample = on and true or false
    resolve()
end

-- Preview mode (#109): counts up from 00:00 like a fight.
function Timer.SetPreview(on)
    previewAt = on and GetTime() or nil
    resolve()
end

Timer._test = { bar = function() return c end, live = function() return live end, onEvent = onEvent }
