-- GlassUnitFrames: the player's swing timer (#87). Three rows, main hand, off
-- hand and ranged, drawn from the client's own swing tracking:
-- PLAYER_SWING(duration, type) fires once per swing, plain in combat (measured
-- on 70338), and keeps firing with Blizzard's "Enable Swing Timer" option off
-- (the showSwingTimer CVar; measured). Blizzard's own bars are that option's
-- business: GUF never touches their frames (Edit Mode managed frames).
--
-- A row appears on its first swing and stays until combat ends (then hides once
-- its swing is over): a swing is the proof its weapon exists, so the attack
-- speeds (secret in combat) are never read. Docked: 3 px rows inside the player
-- frame, under the power bar and the docked cast row (Frames.ReflowRows).
-- Detached: a glass pill of stacked rows, moved and sized through Castbar's
-- detach machinery (Castbar.bars.swing, db.castBars.swing).
--
-- The fill is the client's: a LuaDurationObject on StatusBar:SetTimerDuration.
-- One 20 Hz ticker, only while a swing is in flight, writes the time text and
-- spots a swing's end (from its plain end time).

GlassUF = GlassUF or {}
local API, Glass, Frames, Castbar = GlassUF.API, GlassUF.Glass, GlassUF.Frames, GlassUF.Castbar
local attempt = Frames.attempt

local Swing = {}
GlassUF.Swing = Swing

local ST = Enum.PlayerSwingType
-- Display order, top to bottom: the type, its colour key.
local ROWS = { { type = ST and ST.MainHand or 0, color = "swingMH" },
               { type = ST and ST.OffHand or 1, color = "swingOH" },
               { type = ST and ST.Ranged or 2, color = "swingRanged" } }
local OUT_OF_RANGE = 0.4   -- a row's alpha out of reach (Blizzard's)
local TEXT_MIN = 8         -- a detached row this tall shows its time
local DETACHED_GAP = 2

Swing.enabled = true       -- db.swingTimer == false turns the rows off
Swing.sample = false       -- unlock mode: a detached pill shows every row, idle
local c                    -- the swing "bar" (Castbar.bars.swing)
local byType = {}          -- swing type -> row
local pending = {}         -- swing type -> a deferred range re-enable is queued

local function plain(v) return not API.IsSecret(v) end

-- Is the player in combat? Unknown (secret, error) counts as in combat, so a
-- row is never dropped on a guess.
local function inCombat()
    local ok, v = pcall(UnitAffectingCombat, "player")
    if not ok or not plain(v) then return true end
    return v and true or false
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Empty: a finished duration counting down (EllesmereUI's way: a plain
-- SetValue may not override an armed timer).
local function setIdle(row)
    row.live, row.endTime = false, nil
    attempt("swing idle", function()
        row.dur:SetTimeFromStart(GetTime() - 1, 1)
        row.bar:SetTimerDuration(row.dur, nil, API.TimerDirection(true))
    end)
    row.text:SetText("")
end

local function setOutOfRange(row, out)
    row.out = out and true or false
    row.bar:SetAlpha(row.out and OUT_OF_RANGE or 1)
end

-- Stack the rows that show, size the host, and tell the player frame how many
-- docked rows it holds.
local function layout()
    if not c then return end
    local docked = not c.detached
    local h = docked and Frames.SWING_ROW or c.rowH
    local gap = docked and Frames.SWING_GAP or DETACHED_GAP
    local inset = docked and 0 or Glass.Inset("small")
    local n = 0
    for _, row in ipairs(c.rows) do
        local show = Swing.enabled and (row.visible or (Swing.sample and not docked))
        row.bar:SetShown(show)
        if show then
            local y = -(inset + n * (h + gap))
            row.bar:ClearAllPoints()
            row.bar:SetHeight(h)
            row.bar:SetPoint("TOPLEFT", c.host, "TOPLEFT", inset, y)
            row.bar:SetPoint("TOPRIGHT", c.host, "TOPRIGHT", -inset, y)
            n = n + 1
        end
        row.text:SetShown(show and not docked and h >= TEXT_MIN)
    end
    c.host:SetHeight(n > 0 and (2 * inset + n * h + (n - 1) * gap) or 1)
    c.host:SetShown(n > 0)
    local count = docked and n or 0
    if c.b.swingCount ~= count then
        c.b.swingCount = count
        Frames.ReflowRows(c.b)
    end
end

-- Ask the client for range edges on a type we show. Never false: that would
-- switch off Blizzard's too (one engine flag per type).
local function enableRange(t)
    attempt("swing range", C_SwingTimer.EnableRangeCheck, t, true)
end

-- Re-read one row's range (after a target change, when it first shows).
local function readRange(row)
    local ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, row.type)
    setOutOfRange(row, ok and plain(inRange) and inRange == false)
end

local function show(row)
    if row.visible then return end
    row.visible = true
    enableRange(row.type)
    readRange(row)
    layout()
end

-- Rows that are idle hide once out of combat.
local function dropIdle()
    if inCombat() then return end
    local changed = false
    for _, row in ipairs(c.rows) do
        if row.visible and not row.live then
            row.visible, changed = false, true
        end
    end
    if changed then layout() end
end

-- Every running swing stops (weapon swap, death); out of combat, the rows go.
local function idleAll()
    for _, row in ipairs(c.rows) do
        if row.live then setIdle(row) end
    end
    c.ticker:Hide()
    dropIdle()
end

local function start(row, dur)
    show(row)
    local now = GetTime()
    if not attempt("swing timer", function()
        row.dur:SetTimeFromStart(now, dur)
        row.bar:SetTimerDuration(row.dur, nil, API.TimerDirection(false))
    end) then return end
    row.live, row.endTime = true, now + dur
    c.ticker:Show()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_TARGET_CHANGED", "WEAPON_SLOT_CHANGED",
                 "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_IN_COMBAT_CHANGED", "CVAR_UPDATE" }

local function onEvent(_, event, a1, a2, a3)
    if not (c and Swing.enabled) then return end
    if event == "PLAYER_SWING" then
        -- a1 = duration, a2 = type: both plain, a finite duration > 0.
        if not (plain(a1) and plain(a2)) then return end
        local row = byType[a2]
        if row and type(a1) == "number" and a1 > 0 and a1 < math.huge then start(row, a1) end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        -- a1 = type, a2 = isInRange, a3 = checksRange; unknown = not dimmed
        -- (an unreadable verdict clears an earlier dimming: Codex, #88).
        if not plain(a1) then return end
        local row = byType[a1]
        if row then setOutOfRange(row, plain(a2) and plain(a3) and a3 == true and a2 == false) end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        for _, row in ipairs(c.rows) do
            if row.visible then
                enableRange(row.type)
                readRange(row)
            end
        end
    elseif event == "CVAR_UPDATE" then
        -- Blizzard flips its range flags with its own option: ask again.
        if plain(a1) and a1 == "showSwingTimer" then
            for _, row in ipairs(c.rows) do
                if row.visible then enableRange(row.type) end
            end
        end
    elseif event == "WEAPON_SLOT_CHANGED" or event == "PLAYER_DEAD" then
        idleAll()
    elseif event == "PLAYER_IN_COMBAT_CHANGED" then
        dropIdle()
    end
end

-- Blizzard's bars switch a type's range check off when their own state flips
-- (their option, Edit Mode visibility). Ours goes back on the next frame,
-- never inside Blizzard's call: one queued callback per type, and only while
-- the rows are on and that row still shows.
local function onRangeCheck(t, on)
    if not (plain(on) and plain(t)) or on ~= false or pending[t] then return end
    local row = byType[t]
    if not (Swing.enabled and row and row.visible) then return end
    pending[t] = true
    C_Timer.After(0, function()
        pending[t] = nil
        local r = byType[t]
        if Swing.enabled and r and r.visible then enableRange(t) end
    end)
end

--------------------------------------------------------------------------------
-- Placement (Castbar.Place hands the swing bar here)
--------------------------------------------------------------------------------

local function place(bar)
    local x, y, w, h, detached, scale = Castbar.Geometry("swing")
    -- Zoomed in combat (#89): laid out detached at the zoom spot (effective only).
    local zx, zy, zs = GlassUF.Zoom.Target("swing")
    if zx then x, y, scale, detached = zx, zy, zs, true end
    bar.detached, bar.rowH = detached, h
    local host = bar.host
    host:ClearAllPoints()
    if detached then
        bar.skin:Show()
        host:SetScale(scale)
        host:SetWidth(w)
        host:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
        bar.b.swingDock = nil
    else
        bar.skin:Hide()
        host:SetScale(1)
        bar.b.swingDock = host   -- Frames.ReflowRows anchors it under power / the cast row
        Frames.ReflowRows(bar.b)
    end
    layout()
end

local function paintColors(bar)
    for _, row in ipairs(bar.rows) do
        local col = Castbar.colors[row.color] or Castbar.DEFAULT_COLORS[row.color]
        row.bar:SetStatusBarColor(col[1], col[2], col[3], col[4])
    end
end

--------------------------------------------------------------------------------
-- Building and settings
--------------------------------------------------------------------------------

-- Called by Frames.Build for the player's frame, after its cast bar.
function Swing.Build(b, db)
    if not (b and b.body and b.rows and rawget(_G, "C_DurationUtil") and rawget(_G, "C_SwingTimer")) then return end
    Swing.enabled = db.swingTimer ~= false
    local body = b.body
    local level = Glass.ContentLevel(body)
    local host = CreateFrame("Frame", nil, b)
    host:SetFrameLevel(level)
    local skin = CreateFrame("Frame", nil, host)
    skin:SetAllPoints(host)
    skin:SetFrameLevel(level)
    local glass = Glass.Apply(skin, "small")
    c = { unit = "swing", b = b, body = body, host = host, skin = skin, glass = glass, rows = {},
          place = place, paintColors = paintColors }
    for i, def in ipairs(ROWS) do
        local bar = CreateFrame("StatusBar", nil, host)
        bar:SetFrameLevel(level + 2)
        bar:SetStatusBarTexture(Glass.MEDIA .. "bar_fill")
        bar:SetMinMaxValues(0, 1)
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        bg:SetColorTexture(0, 0, 0, 0.35)
        local spark = bar:CreateTexture(nil, "OVERLAY")
        spark:SetColorTexture(1, 1, 1, 0.9)
        spark:SetBlendMode("ADD")
        spark:SetWidth(1)
        spark:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        spark:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
        local text = Glass.Font(bar, 9, "RIGHT")
        text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
        local row = { index = i, type = def.type, color = def.color, bar = bar, text = text,
                      dur = C_DurationUtil.CreateDuration(), visible = false, live = false, out = false }
        bar:Hide()
        c.rows[i] = row
        byType[def.type] = row
        setIdle(row)
    end
    -- The ticker: shown only while a swing is in flight.
    local ticker = CreateFrame("Frame", nil, UIParent)
    ticker:Hide()
    ticker.acc = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        local now, any = GetTime(), false
        for _, row in ipairs(c.rows) do
            if row.live then
                local left = row.endTime - now
                if left <= 0 then
                    setIdle(row)
                else
                    any = true
                    if row.text:IsShown() then row.text:SetFormattedText("%.1f", left) end
                end
            end
        end
        if not any then
            self:Hide()
            dropIdle()
        end
    end)
    c.ticker = ticker
    host:Hide()
    Castbar.bars.swing = c
    paintColors(c)
    Castbar.Place(c)

    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", onEvent)
    c.events = ev
    if Swing.enabled then API.RegisterEvents(ev, EVENTS) end
    hooksecurefunc(C_SwingTimer, "EnableRangeCheck", onRangeCheck)
    return c
end

-- Turn the rows on or off (saved only when off). Off: no rows, no events, no
-- range-check calls.
function Swing.SetEnabled(on)
    Swing.enabled = on and true or false
    if not c then return false end
    if Swing.enabled then
        API.RegisterEvents(c.events, EVENTS)
    else
        c.events:UnregisterAllEvents()
        for _, row in ipairs(c.rows) do
            if row.live then setIdle(row) end
            row.visible = false
        end
        c.ticker:Hide()
    end
    layout()
    return true
end

-- Unlock mode: a detached pill shows every row (idle ones too) to be placed.
function Swing.SetSample(on)
    Swing.sample = on and true or false
    layout()
end

-- Blizzard's own swing bars: its "Enable Swing Timer" option (a CVar). Read
-- fresh each time; set only by a click, out of combat, never on our own.
function Swing.BlizzardShown()
    local ok, v = pcall(C_CVar.GetCVarBool, "showSwingTimer")
    return ok and plain(v) and v == true
end

function Swing.SetBlizzardShown(on)
    if InCombatLockdown() then return false end
    local ok, done = pcall(C_CVar.SetCVar, "showSwingTimer", on and "1" or "0")
    return ok and done ~= false
end

Swing._test = { rows = function() return c and c.rows end, bar = function() return c end, byType = byType,
                pending = pending, onRangeCheck = onRangeCheck }
