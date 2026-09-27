-- Frames.lua: the secure unit buttons, their glass, and the channel painters.
--
-- Secret-value rule for every painter: values from the client go straight
-- back to the client (StatusBar:SetMinMaxValues/SetValue, SetText,
-- SetFormattedText, AbbreviateNumbers, UnitHealthPercent). Lua never does
-- arithmetic, comparison, concatenation, tostring or a truth test on them.
-- Plain facts we branch on (connected, dead, class, reaction) go through
-- plain(), which drops anything secret.

GlassUF = GlassUF or {}
local API, Glass, Engine = GlassUF.API, GlassUF.Glass, GlassUF.Engine
local Frames = {}
GlassUF.Frames = Frames
Frames.byUnit = {}

local GAP = 3    -- between portrait tile and body

Frames.LAYOUT = {
    player       = { w = 300, h = 62, point = { "CENTER", "UIParent", "CENTER", -300, -190 },
                     portrait = "left", power = true, cast = true, size = "large", groupNumber = true,
                     text = { healthRight = "curmaxhp", powerLeft = "perpp", powerRight = "curmaxpp" } },
    target       = { w = 300, h = 62, point = { "CENTER", "UIParent", "CENTER", 300, -190 },
                     portrait = "right", power = true, cast = true, sheen = true, size = "large",
                     text = { healthRight = "curmaxhp_perhp", powerLeft = "level_class_perpp", powerRight = "curmaxpp" } },
    pet          = { w = 210, h = 32, point = { "CENTER", "UIParent", "CENTER", -345, -275 },
                     power = true, size = "small", text = { healthRight = "curmaxhp" } },
    targettarget = { w = 180, h = 26, point = { "CENTER", "UIParent", "CENTER", 360, -275 },
                     size = "small", ticker = true, text = { healthRight = "curhp" } },
    -- Below targettarget (fits narrow screens too); name only, as the owner's SUF profile had it.
    targettargettarget = { w = 150, h = 24, point = { "CENTER", "UIParent", "CENTER", 345, -305 },
                     size = "small", ticker = true, nameOnly = true },
    -- Fixed spots near the target frame (above it, focustarget to the right); they
    -- do not follow a moved target frame.
    focus        = { w = 210, h = 32, point = { "CENTER", "UIParent", "CENTER", 345, -128 },
                     power = true, size = "small", text = { healthRight = "curhp" } },
    focustarget  = { w = 180, h = 26, point = { "CENTER", "UIParent", "CENTER", 546, -128 },
                     size = "small", ticker = true, text = { healthRight = "curhp" } },
}
Frames.ORDER = { "player", "target", "pet", "targettarget", "targettargettarget", "focus", "focustarget" }

-- Our own colour tables: PowerBarColor / FACTION_BAR_COLORS are FrameXML
-- tables the API dump cannot confirm.
local POWER_COLORS = {
    MANA = { 0.16, 0.56, 1.00 }, RAGE = { 0.90, 0.22, 0.22 },
    ENERGY = { 1.00, 0.85, 0.25 }, FOCUS = { 1.00, 0.55, 0.25 },
}
local HOSTILE, NEUTRAL, FRIENDLY = { 0.85, 0.22, 0.22 }, { 0.92, 0.76, 0.22 }, { 0.26, 0.74, 0.32 }
local GREY, DEFAULT = { 0.50, 0.50, 0.52 }, { 0.56, 0.34, 0.92 }
local CAST, CHANNEL, FAILED = { 0.95, 0.74, 0.22 }, { 0.40, 0.80, 1.00 }, { 0.85, 0.22, 0.22 }

-- First result of fn(...) if it is plain; nil on error or when secret.
local function plain(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

-- Run a paint step; remember the first failure per step for /glass secrets.
GlassUF.paintFailures = {}
local function attempt(key, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and GlassUF.paintFailures[key] == nil then
        GlassUF.paintFailures[key] = tostring(err)
    end
    return ok
end

local function unitColor(u)
    if plain(UnitIsConnected, u) == false then return GREY end
    if plain(UnitIsDeadOrGhost, u) == true then return GREY end   -- dead reads as dead even on name-only frames
    if plain(UnitIsPlayer, u) == true then
        local ok, _, classFile = pcall(UnitClass, u)
        if ok then
            local r, g, b = API.ClassColor(classFile)
            if r then return { r, g, b } end
        end
    end
    if plain(UnitIsTapDenied, u) == true then return GREY end
    local reaction = plain(UnitReaction, u, "player")
    if type(reaction) == "number" then
        if reaction <= 3 then return HOSTILE elseif reaction == 4 then return NEUTRAL end
        return FRIENDLY
    end
    return DEFAULT
end

--------------------------------------------------------------------------------
-- Text formats, named after the SUF tags the owner's profile used. Not a tag
-- language: a fixed set, each handing client values (often secret) straight to
-- SetFormattedText / AbbreviateNumbers. LAYOUT[unit].text picks them per slot.
--------------------------------------------------------------------------------

local CLASSIFICATION = { worldboss = "Boss", rareelite = "Rare Elite", elite = "Elite", rare = "Rare" }

-- "12 Elite", "?? Boss", "12" or "" from plain level and classification.
local function levelClass(u)
    local out = ""
    local lvl = plain(UnitLevel, u)
    if type(lvl) == "number" then out = (lvl > 0) and tostring(lvl) or "??" end
    local c = CLASSIFICATION[plain(UnitClassification, u) or ""]
    if c then out = (out ~= "" and (out .. " ") or "") .. c end
    return out
end

local TEXT = {
    curhp          = function(fs, u, hp) fs:SetFormattedText("%s", AbbreviateNumbers(hp)) end,
    curmaxhp       = function(fs, u, hp, maxHp)
        fs:SetFormattedText("%s/%s", AbbreviateNumbers(hp), AbbreviateNumbers(maxHp))
    end,
    curmaxhp_perhp = function(fs, u, hp, maxHp)
        fs:SetFormattedText("%s/%s | %.0f%%", AbbreviateNumbers(hp), AbbreviateNumbers(maxHp), API.HealthPercent(u))
    end,
    perpp          = function(fs, u) fs:SetFormattedText("%.0f%%", API.PowerPercent(u)) end,
    curpp          = function(fs, u) fs:SetFormattedText("%s", AbbreviateNumbers(UnitPower(u))) end,
    curmaxpp       = function(fs, u)
        fs:SetFormattedText("%s/%s", AbbreviateNumbers(UnitPower(u)), AbbreviateNumbers(UnitPowerMax(u)))
    end,
    level_class_perpp = function(fs, u)
        local lc = levelClass(u)
        if lc ~= "" then fs:SetFormattedText("%s  %.0f%%", lc, API.PowerPercent(u))
        else fs:SetFormattedText("%.0f%%", API.PowerPercent(u)) end
    end,
}
Frames.TEXT = TEXT

local function paintText(fs, kind, ...)
    if not (fs and kind) then return end
    if not attempt("text " .. kind, TEXT[kind], fs, ...) then fs:SetText("") end
end

-- "(AFK) Name (3)": AFK tag, and the player's raid group number (SUF's
-- [(()afk() )][name][( ()group())]). Name may be secret: formatted by the client.
local function paintName(f, u)
    local afk = (plain(UnitIsAFK, u) == true) and "(AFK) " or ""
    local grp = ""
    if f.layout.groupNumber and plain(IsInRaid) == true then
        local idx = plain(UnitInRaid, u)
        if type(idx) == "number" then
            local ok, _, _, subgroup = pcall(GetRaidRosterInfo, idx)
            if ok and not API.IsSecret(subgroup) and type(subgroup) == "number" then
                grp = " (" .. subgroup .. ")"
            end
        end
    end
    f.nameText:SetFormattedText("%s%s%s", afk, GetUnitName(u, false), grp)
end

--------------------------------------------------------------------------------
-- Painters
--------------------------------------------------------------------------------

-- The health bar's colour depends on death and connection as well as class
-- and reaction, so both the name and the health painters apply it: a unit
-- revived (UNIT_HEALTH) must lose its dead grey without waiting for a name event.
local function paintColor(f, u)
    local c = unitColor(u)
    f.health:SetStatusBarColor(c[1], c[2], c[3])
end

Engine.SetPainter("name", function(f)
    local u = f.unit
    if not UnitExists(u) then return end
    if not attempt("name text", paintName, f, u) then f.nameText:SetText("") end
    paintColor(f, u)
end)

Engine.SetPainter("health", function(f)
    local u = f.unit
    if not UnitExists(u) then return end
    local hp, maxHp = UnitHealth(u), UnitHealthMax(u)
    attempt("health bar", function()
        f.health:SetMinMaxValues(0, maxHp)
        f.health:SetValue(hp)
    end)
    paintColor(f, u)

    if not f.valueText then return end   -- name-only frames
    if plain(UnitIsConnected, u) == false then f.valueText:SetText("Offline") return end
    if plain(UnitIsDeadOrGhost, u) == true then f.valueText:SetText("Dead") return end

    paintText(f.valueText, f.layout.text and f.layout.text.healthRight, u, hp, maxHp)
end)

Engine.SetPainter("power", function(f)
    local u = f.unit
    if not (f.power and UnitExists(u)) then return end
    attempt("power bar", function()
        f.power:SetMinMaxValues(0, UnitPowerMax(u))
        f.power:SetValue(UnitPower(u))
    end)
    local ok, _, token = pcall(UnitPowerType, u)
    if not ok or API.IsSecret(token) then token = nil end
    local c = (token and POWER_COLORS[token]) or POWER_COLORS.MANA
    f.power:SetStatusBarColor(c[1], c[2], c[3])
    local t = f.layout.text or {}
    paintText(f.powerLeftText, t.powerLeft, u)
    paintText(f.powerText, t.powerRight, u)
end)

-- SUF's sequence (modules/portrait.lua): clear, set unit, zoom, reset position.
Engine.SetPainter("portrait", function(f)
    local m, u = f.model, f.unit
    if not (m and UnitExists(u)) then return end
    if plain(UnitIsVisible, u) == false then m:ClearModel() return end
    attempt("portrait", function()
        m:ClearModel()
        m:SetUnit(u)
        m:SetPortraitZoom(1)
        m:SetPosition(0, 0, 0)
    end)
end)

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
        GlassUF.paintFailures["cast duration"] = GlassUF.paintFailures["cast duration"]
            or ("no DurationObject on " .. event)
    end
    -- Nothing casting: hide, unless an interrupt/fail flash is still up.
    if not c.flashing then
        c.duration = nil
        c.host:Hide()
    end
end)

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function savePosition(b)
    local point, _, relPoint, x, y = b:GetPoint(1)
    Frames.db.pos[b.unit] = { point, "UIParent", relPoint, x, y }
end

local function applyPosition(b)
    local p = Frames.db.pos[b.unit] or b.layout.point
    b:ClearAllPoints()
    b:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

-- Shift-drag to move, out of combat only: a protected frame cannot be moved,
-- or stop moving, under lockdown.
local function onDragStart(b)
    if InCombatLockdown() or not IsShiftKeyDown() then return end
    b:StartMoving()
    b.moving = true
end

local function onDragStop(b)
    if not b.moving or InCombatLockdown() then return end
    b:StopMovingOrSizing()
    b.moving = nil
    savePosition(b)
end

-- PLAYER_REGEN_DISABLED fires before lockdown begins: last chance to drop a drag.
function Frames.StopMoving()
    for _, b in pairs(Frames.byUnit) do onDragStop(b) end
end

function Frames.ResetPositions()
    Frames.db.pos = {}
    for _, b in pairs(Frames.byUnit) do applyPosition(b) end
end

local function buildCast(b, body, L)
    local host = CreateFrame("Frame", nil, b)
    host:SetSize(L.w, 20)
    host:SetPoint("TOP", body, "BOTTOM", 0, -6)
    host:SetFrameLevel(b:GetFrameLevel() + 1)
    local g = Glass.Apply(host, "small")
    local inset = Glass.Inset("small")
    local bar = Glass.Bar(host, 20 - 2 * inset)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, -inset)
    bar:SetFrameLevel(Glass.ContentLevel(host))
    local spell = Glass.Font(g.top, 11, "LEFT")
    spell:SetPoint("LEFT", bar, "LEFT", 6, 0)
    local time = Glass.Font(g.top, 11, "RIGHT")
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

local function build(unit)
    local L = Frames.LAYOUT[unit]
    local size = L.size
    local tileW = L.portrait and (L.h + GAP) or 0

    local b = CreateFrame("Button", "GlassUF_" .. unit, UIParent, "SecureUnitButtonTemplate")
    b.unit, b.layout = unit, L
    local hasPower = L.power and not L.nameOnly   -- nameOnly: just the name over a health bar
    b.channels = { name = true, health = true, power = hasPower or nil,
                   portrait = L.portrait and true or nil, cast = L.cast or nil }
    b:SetSize(L.w + tileW, L.h)
    b:SetAttribute("unit", unit)
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "togglemenu")
    b:RegisterForClicks(API.UnitButtonClicks())
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", onDragStart)
    b:SetScript("OnDragStop", onDragStop)
    applyPosition(b)

    -- The glass hosts are plain children without mouse, so a click anywhere
    -- on the unit (portrait included) reaches the secure button.
    local body = CreateFrame("Frame", nil, b)
    body:SetSize(L.w, L.h)
    body:SetPoint(L.portrait == "left" and "RIGHT" or "LEFT", b, L.portrait == "left" and "RIGHT" or "LEFT")
    body:SetFrameLevel(b:GetFrameLevel() + 1)
    local g = Glass.Apply(body, size)
    b.glass = g

    local inset = Glass.Inset(size)
    local large = size == "large"
    local gap = large and 4 or 2
    local healthH = hasPower and (large and 34 or 17) or (L.h - 2 * inset)
    b.health = Glass.Bar(body, healthH)
    b.health:SetPoint("TOPLEFT", body, "TOPLEFT", inset, -inset)
    b.health:SetPoint("TOPRIGHT", body, "TOPRIGHT", -inset, -inset)
    b.health:SetFrameLevel(Glass.ContentLevel(body))
    if hasPower then
        b.power = Glass.Bar(body, L.h - 2 * inset - healthH - gap)
        b.power:SetPoint("TOPLEFT", b.health, "BOTTOMLEFT", 0, -gap)
        b.power:SetPoint("TOPRIGHT", b.health, "BOTTOMRIGHT", 0, -gap)
        b.power:SetFrameLevel(Glass.ContentLevel(body))
    end

    local textSize = large and 15 or 11
    local pad = large and 9 or 5
    b.nameText = Glass.Font(g.top, textSize, "LEFT")
    b.nameText:SetPoint("LEFT", b.health, "LEFT", pad, 0)
    if L.nameOnly then
        b.nameText:SetPoint("RIGHT", b.health, "RIGHT", -pad, 0)
    else
        b.valueText = Glass.Font(g.top, textSize, "RIGHT")
        b.valueText:SetPoint("RIGHT", b.health, "RIGHT", -pad, 0)
        b.nameText:SetPoint("RIGHT", b.valueText, "LEFT", -6, 0)
    end
    if hasPower and large then
        b.powerText = Glass.Font(g.top, 11, "RIGHT")
        b.powerText:SetPoint("RIGHT", b.power, "RIGHT", -7, 0)
        if L.text and L.text.powerLeft then
            b.powerLeftText = Glass.Font(g.top, 11, "LEFT")
            b.powerLeftText:SetPoint("LEFT", b.power, "LEFT", 7, 0)
            b.powerLeftText:SetPoint("RIGHT", b.powerText, "LEFT", -6, 0)
        end
    end

    if L.portrait then
        local tile = CreateFrame("Frame", nil, b)
        tile:SetSize(L.h, L.h)
        tile:SetPoint(L.portrait == "left" and "LEFT" or "RIGHT", b, L.portrait == "left" and "LEFT" or "RIGHT")
        tile:SetFrameLevel(b:GetFrameLevel() + 1)
        Glass.Apply(tile, "large")
        local m = CreateFrame("PlayerModel", nil, tile)
        local mi = Glass.Inset("large") - 1
        m:SetPoint("TOPLEFT", tile, "TOPLEFT", mi, -mi)
        m:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -mi, mi)
        m:SetFrameLevel(Glass.ContentLevel(tile))
        m:SetKeepModelOnHide(true)
        b.model = m
    end

    if L.cast then b.cast = buildCast(b, body, L) end
    if L.sheen then b.sheen = Glass.Sheen(g, body, L.w, L.h) end

    RegisterUnitWatch(b)
    Engine.Register(b, { ticker = L.ticker })
    Frames.byUnit[unit] = b
    return b
end

-- A fresh target sweeps the sheen across its frame. Only the target: a focus
-- change must not replay it or cut off the target's cast flash.
Engine.OnTokenChanged = function(base)
    if base ~= "target" then return end
    local t = Frames.byUnit.target
    if t and t.cast then t.cast.flashing = false end   -- the old target's flash is not the new one's
    if t and t.sheen and UnitExists("target") then
        t.sheen:Stop()
        t.sheen:Play()
    end
end

-- Called once at ADDON_LOADED, before any lockdown can apply.
function Frames.Build(db)
    Frames.db = db
    for _, unit in ipairs(Frames.ORDER) do build(unit) end
end
