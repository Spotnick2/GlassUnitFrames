-- DotView.lua: will my DoTs kill it? on the target and focus frames (#175,
-- docs/DOT-KILL-PLAN.md section 7). Draws what Dots.lua hands out:
-- - the marker: a striped segment on the health fill, ending at its moving
--   edge, as wide as the damage our DoTs still have to deal;
-- - tick lines inside it, one per upcoming tick (the next one nearest the edge);
-- - the kill icon, a skull that shows only once the committed estimate
--   reaches the unit's health.
-- Health and max health are secret: they go straight to StatusBars, and the
-- client draws the comparison. No Lua ever compares them.

GlassUF = GlassUF or {}
local API, Engine = GlassUF.API, GlassUF.Engine
local DotView = {}
GlassUF.DotView = DotView

DotView.UNITS = { target = true, focus = true }
DotView.MARKER_COLOR = { 0.85, 0.12, 0.12, 0.45 }   -- the fill under the stripes
-- Run #111: this atlas draws faint light diagonal stripes, which a tint barely
-- colours (hence the fill under it); RaidFrame-Absorb-Overlay draws plus signs.
DotView.STRIPE_ATLAS = "RaidFrame-Shield-Overlay"
DotView.STRIPE_ALPHA = 0.8
DotView.LINE_COLOR = { 1, 1, 1, 0.7 }
DotView.ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"   -- the raid skull
DotView.ICON_SCALE = 0.7       -- of the portrait's inner square
DotView.BAR_LENGTH = 10000     -- the kill icon's comparator bar (plan 7)
DotView.GAP = 3                -- beside the frame, with no portrait tile

-- The options (db.dots, each false when off): marker, tick lines, kill icon,
-- and the focus frame at all.
DotView.options = { marker = true, ticks = true, icon = true, focus = true }

function DotView.Configure(db)
    local saved = type(db.dots) == "table" and db.dots or {}
    for k in pairs(DotView.options) do DotView.options[k] = saved[k] ~= false end
    GlassUF.Dots.enabled = DotView.options.marker or DotView.options.icon
end

function DotView.SetOption(key, on)
    if DotView.options[key] == nil then return false end
    DotView.options[key] = on and true or false
    GlassUF.Dots.SetEnabled(DotView.options.marker or DotView.options.icon)
    Engine.RepaintChannel("dots")
    return true
end

local function mediaFill() return GlassUF.Glass.MEDIA .. "bar_fill" end

-- A reverse-fill bar the health bar's width, its right end on the health
-- fill's moving edge: its fill grows leftward from there.
local function onEdge(bar, b)
    local edge = b.health:GetStatusBarTexture()
    bar:SetReverseFill(true)
    bar:SetWidth(b.healthWidth)
    bar:SetPoint("TOPRIGHT", edge, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
end

local function iconSize(b)
    local inset = GlassUF.Glass.Inset(b.layout.size) - 1
    return math.floor((b.layout.h - 2 * inset) * DotView.ICON_SCALE)
end

local function buildMarker(b)
    local c = DotView.MARKER_COLOR
    local marker = GlassUF.Frames.OverlayBar(b.health, c, 3, false)
    marker:SetAlpha(1)                               -- the alpha is the fill's, not the stripes'
    marker:SetStatusBarColor(c[1], c[2], c[3], c[4])
    onEdge(marker, b)
    local span = marker:GetStatusBarTexture()
    local stripes = marker:CreateTexture(nil, "OVERLAY")
    stripes:SetPoint("TOPLEFT", span, "TOPLEFT", 0, 0)
    stripes:SetPoint("BOTTOMRIGHT", span, "BOTTOMRIGHT", 0, 0)
    if pcall(stripes.SetAtlas, stripes, DotView.STRIPE_ATLAS, false, "LINEAR", "REPEAT", "REPEAT") then
        stripes:SetHorizTile(true)
        stripes:SetVertTile(true)
        stripes:SetAlpha(DotView.STRIPE_ALPHA)
        stripes:AddMaskTexture(GlassUF.Glass.Mask(marker, "bar_mask", 8, 0, b.health))
    else
        stripes:Hide()                               -- the tinted fill alone
    end
    b.dotMarker, b.dotClip = marker, marker:GetParent()

    -- Tick lines: transparent-fill bars on the same edge, each filled to the
    -- running total up to its tick; a 1 px line rides its fill's far end.
    local lines = {}
    local lc = DotView.LINE_COLOR
    for i = 1, GlassUF.Dots.MAX_TICKS do
        local bar = CreateFrame("StatusBar", nil, b.dotClip)
        bar:SetFrameLevel(b.dotClip:GetFrameLevel() + 1)
        bar:SetStatusBarTexture(mediaFill())
        bar:SetStatusBarColor(1, 1, 1, 0)
        onEdge(bar, b)
        local fill = bar:GetStatusBarTexture()
        local line = bar:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(lc[1], lc[2], lc[3], lc[4])
        line:SetWidth(1)
        line:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
        line:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        bar:Hide()
        lines[i] = bar
    end
    b.dotLines = lines
end

-- The kill icon: a window the icon's size clips a 10,000 px normal-fill bar
-- whose right end is the window's; the skull's right edge rides the fill's.
-- With max = health and value = committed * (1 - S/L), the skull enters the
-- window only once committed exceeds health (plan 7).
local function buildIcon(b)
    local size = iconSize(b)
    local win = CreateFrame("Frame", nil, b)
    win:SetSize(size, size)
    win:SetClipsChildren(true)
    -- Over the model, under the tile's rim and the crowd-control icon (+2).
    win:SetFrameLevel((b.tile and GlassUF.Glass.ContentLevel(b.tile) or b:GetFrameLevel()) + 1)
    win:SetAlpha(0)
    local bar = CreateFrame("StatusBar", nil, win)
    bar:SetSize(DotView.BAR_LENGTH, size)
    bar:SetPoint("RIGHT", win, "RIGHT", 0, 0)
    bar:SetStatusBarTexture(mediaFill())
    bar:SetStatusBarColor(1, 1, 1, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local skull = bar:CreateTexture(nil, "OVERLAY")
    skull:SetTexture(DotView.ICON)
    skull:SetSize(size, size)
    skull:SetPoint("RIGHT", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    local pulse = skull:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.5)
    fade:SetDuration(0.7)
    fade:SetSmoothing("IN_OUT")
    pulse:Play()
    b.dotIcon = { window = win, bar = bar, skull = skull, size = size }
end

-- Where the icon sits: centred on the portrait tile, else where the tile
-- would be (focus: left of the frame). A child of the secure button, so it's
-- placed out of combat (the CC icon's rule).
function DotView.Place(b)
    local icon = b.dotIcon
    if not icon then return end
    if InCombatLockdown() then
        GlassUF.WhenOutOfCombat("dots:" .. b.unit, function() DotView.Place(b) end, false)
        return
    end
    local win = icon.window
    win:ClearAllPoints()
    if b.tile and b.portraitMode ~= "none" then
        win:SetPoint("CENTER", b.tile, "CENTER", 0, 0)
    else
        local side = b.layout.portrait or (b.unit == "focus" and "left") or "left"
        if side == "right" then
            win:SetPoint("LEFT", b.body, "RIGHT", DotView.GAP, 0)
        else
            win:SetPoint("RIGHT", b.body, "LEFT", -DotView.GAP, 0)
        end
    end
end

-- At build, for target and focus (under Frames' attempt).
function DotView.Attach(b)
    if not (DotView.UNITS[b.unit] and b.health and b.healthWidth) then return end
    buildMarker(b)
    buildIcon(b)
    b.channels.dots = true
    DotView.Place(b)
end

local function clear(f)
    f.dotMarker:SetMinMaxValues(0, 1)
    f.dotMarker:SetValue(0)
    for _, bar in ipairs(f.dotLines) do bar:Hide() end
    f.dotIcon.bar:SetMinMaxValues(0, 1)
    f.dotIcon.bar:SetValue(0)
    f.dotIcon.window:SetAlpha(0)
end
DotView.Clear = clear

local function readable(v) return API.IsSecret(v) or type(v) == "number" end

-- The bars, from our plain numbers and the client's health (secret: only ever
-- handed to SetMinMaxValues). A line whose total equals the one before isn't
-- drawn.
local function paintBars(f, maxHealth, health, shown, committed, cum)
    local o = DotView.options
    if o.marker then
        f.dotMarker:SetMinMaxValues(0, maxHealth)
        f.dotMarker:SetValue(shown)
        local prev
        for i, bar in ipairs(f.dotLines) do
            local v = o.ticks and cum[i]
            if v and v ~= prev and v < shown then
                bar:SetMinMaxValues(0, maxHealth)
                bar:SetValue(v)
                bar:Show()
            else
                bar:Hide()
            end
            prev = v or prev
        end
    else
        f.dotMarker:SetValue(0)
        for _, bar in ipairs(f.dotLines) do bar:Hide() end
    end
    local icon = f.dotIcon
    if o.icon and committed > 0 then
        icon.bar:SetMinMaxValues(0, health)
        icon.bar:SetValue(committed * (1 - icon.size / DotView.BAR_LENGTH))
        icon.window:SetAlpha(1)
    else
        icon.bar:SetValue(0)
        icon.window:SetAlpha(0)
    end
end

-- Plain values onto a frame's bars: the preview's and the probe's boundary
-- samples (CastProbe `/fp steps cast dotview`).
DotView.PaintValues = paintBars

local function plainTrue(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and not API.IsSecret(v) and v == true
end

function DotView.Paint(f)
    if not f.dotMarker then return end
    local u = f.unit
    if (u == "focus" and not DotView.options.focus) or not plainTrue(UnitExists, u)
        or plainTrue(UnitIsDeadOrGhost, u) or not API.CanAttack(u) then
        clear(f)
        return
    end
    local shown, committed, cum = GlassUF.Dots.Estimate(u)
    if shown <= 0 then
        clear(f)
        return
    end
    local ok = GlassUF.Frames.attempt("dots", function()
        local maxHealth, health = UnitHealthMax(u), UnitHealth(u)
        if not (readable(maxHealth) and readable(health)) then error("health unreadable") end
        paintBars(f, maxHealth, health, shown, committed, cum)
    end)
    if not ok then clear(f) end
end

Engine.SetPainter("dots", function(f) DotView.Paint(f) end)
GlassUF.Dots.OnChange = function() Engine.RepaintChannel("dots") end

-- The preview (#109): the target shows a marker at 35% with four tick lines,
-- the focus a kill icon (its committed sample is past its health).
function DotView.PaintSample(f, s)
    if not f.dotMarker then return end
    if f.unit == "focus" and not DotView.options.focus then return clear(f) end
    if f.unit == "target" then
        local shown = s.maxHp * 0.35
        local q = shown / 4
        paintBars(f, s.maxHp, s.hp, shown, 0, { q, 2 * q, 3 * q, shown })
    else
        paintBars(f, s.maxHp, s.hp, s.hp * 0.3, s.hp * 1.05, {})
    end
end
