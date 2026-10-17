-- BarProbe: sample glass frames at fixed fill percentages, built with
-- GlassUnitFrames' own material instance, to tune how a bar's empty part
-- (LibGlass's track ramp) reads at low fill (#117). Every setting applies to
-- the samples AND to GlassUnitFrames' real health and power bars, live, and
-- is saved, so it survives /reload while it's being tried in play and the
-- session can read the chosen values from BarProbeDB.
--
-- Two knobs per bar kind (health, power):
--   strength: the alpha of the track's clip frame (what Frames.lua's
--             QUIET_TRACK sets; a texture's own SetAlpha did nothing, #117).
--   ramp:     "whole" is LibGlass's ramp across the whole bar (today);
--             "edge" moves it to the fill's moving edge and uses only its
--             fade, over `length` of the bar: a try-out of a LibGlass option.
--
-- Throwaway, never shipped (.pkgmeta ignores Tools). A ForeverProbe module:
-- its lines go to the /fp console and its own saved log, never to chat.

local ADDON, NS = ...
local LOG_MAX = 2000

local Probe = ForeverProbe:Module("BarProbe", { api = 1, cmd = "bar" })
local function say(msg) Probe:Say(msg) end

local PCTS = { 5, 10, 25, 50, 80 }
local DEFAULTS = { health = 0.25, power = 0.25, ramp = "whole", length = 0.05 }
local MANA = { 0.16, 0.56, 1.00 }        -- Frames.lua's POWER_COLORS.MANA
local FRIENDLY = { 0.26, 0.74, 0.32 }
-- track_fade: alpha 1 over the first 30% of its width, smoothstep to 0 at 85%.
local FADE_FROM, FADE_TO = 0.30, 0.85

local S = {}          -- the live settings (DEFAULTS, then the saved ones)
local panel, samples = nil, {}

local function GUF() return rawget(_G, "GlassUF") end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function round(v, step) return math.floor(v / step + 0.5) * step end

-- One bar: its strength on the clip frame, its ramp on the track texture.
local function styleBar(bar, kind)
    if not (bar and bar.track and bar.trackClip) then return end
    bar.trackClip:SetAlpha(S[kind])
    local t, fill = bar.track, bar:GetStatusBarTexture()
    t:ClearAllPoints()
    if S.ramp == "edge" then
        t:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        t:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        t:SetWidth(math.max(1, (bar:GetWidth() or 0) * S.length))
        t:SetTexCoord(FADE_FROM, FADE_TO, 0, 1)
    else
        t:SetAllPoints(bar)
        t:SetTexCoord(0, 1, 0, 1)
    end
end

-- Every health and power bar GlassUnitFrames built, and ours.
local function applyAll()
    local G = GUF()
    local byUnit = G and G.Frames and G.Frames.byUnit or {}
    for _, b in pairs(byUnit) do
        styleBar(b.health, "health")
        styleBar(b.power, "power")
        if b.druidMana then styleBar(b.druidMana.bar, "power") end
    end
    for _, s in ipairs(samples) do
        styleBar(s.health, "health")
        styleBar(s.power, "power")
    end
end

local function describe()
    return string.format("health %.2f, power %.2f, ramp %s%s", S.health, S.power, S.ramp,
        S.ramp == "edge" and string.format(" over %d%%", S.length * 100 + 0.5) or "")
end

local function save()
    BarProbeDB.settings = { health = S.health, power = S.power, ramp = S.ramp, length = S.length }
end

local function changed()
    save()
    applyAll()
    if panel then panel.sync() end
    say("now: " .. describe())
end

-- Forget the tuning: nothing is re-applied at login, and /reload hands the
-- bars back to GlassUnitFrames (its strength and its Fade option).
local function forget()
    BarProbeDB.settings = nil
    for k, v in pairs(DEFAULTS) do S[k] = v end
    if panel then panel.sync() end
    say("tuning forgotten: /reload hands the bars back to GlassUnitFrames")
end

local function load(saved)
    for k, v in pairs(DEFAULTS) do S[k] = v end
    if type(saved) ~= "table" then return end
    if type(saved.health) == "number" then S.health = clamp(saved.health, 0, 1) end
    if type(saved.power) == "number" then S.power = clamp(saved.power, 0, 1) end
    if saved.ramp == "edge" or saved.ramp == "whole" then S.ramp = saved.ramp end
    if type(saved.length) == "number" then S.length = clamp(saved.length, 0.01, 0.5) end
end

--------------------------------------------------------------------------------
-- The panel: a control strip, and sample frames floating over the world as
-- the real ones do (no backdrop behind them, which would change the look).
--------------------------------------------------------------------------------

local function button(parent, label, w, onClick)
    local G = GUF()
    local b = G.API.SafeFrame("Button", parent, "UIPanelButtonTemplate", "Text")
    b:SetSize(w, 20)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function text(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if size then fs:SetFont("Fonts\\ARIALN.TTF", size, "") end
    return fs
end

-- A "- value +" stepper for one setting.
local function stepper(parent, label, key, step, lo, hi, x, y, fmt, scale)
    local l = text(parent)
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
    l:SetText(label)
    local minus = button(parent, "-", 22, function()
        S[key] = clamp(round(S[key] - step, step), lo, hi); changed()
    end)
    minus:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 52, y)
    local v = text(parent)
    v:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    v:SetWidth(36)
    local plus = button(parent, "+", 22, function()
        S[key] = clamp(round(S[key] + step, step), lo, hi); changed()
    end)
    plus:SetPoint("LEFT", minus, "RIGHT", 44, 0)
    return function() v:SetText(string.format(fmt, S[key] * (scale or 1))) end
end

local function buildSample(parent, pct, i)
    local G = GUF()
    local Glass = G.Glass
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(300, 62)   -- the player frame's body (Frames.LAYOUT.player)
    host:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -8 - (i - 1) * 70)
    local glass = Glass.Apply(host, "large")
    local inset = Glass.Inset("large")
    local healthH, gap = 34, 4
    local health = Glass.Bar(host, healthH)
    health:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    health:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, -inset)
    health:SetFrameLevel(Glass.ContentLevel(host))
    local power = Glass.Bar(host, 62 - 2 * inset - healthH - gap)
    power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -gap)
    power:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -gap)
    power:SetFrameLevel(Glass.ContentLevel(host))

    local _, class = UnitClass("player")
    local r, g, b = G.API.ClassColor(class)
    if not r then r, g, b = FRIENDLY[1], FRIENDLY[2], FRIENDLY[3] end
    health:SetStatusBarColor(r, g, b)
    power:SetStatusBarColor(MANA[1], MANA[2], MANA[3])
    Glass.SetBar(health, 100, pct, true)
    Glass.SetBar(power, 100, pct, true)

    local lh = Glass.Font(glass.top, 15, "LEFT")
    lh:SetPoint("LEFT", health, "LEFT", 9, 0)
    lh:SetText(pct .. "% health")
    local lp = Glass.Font(glass.top, 11, "LEFT")
    lp:SetPoint("LEFT", power, "LEFT", 7, 0)
    lp:SetText(pct .. "%")
    return { host = host, health = health, power = power }
end

local function buildPanel()
    local G = GUF()
    if not (G and G.Glass and G.API) then say("GlassUnitFrames isn't loaded"); return end
    panel = CreateFrame("Frame", "BarProbePanel", UIParent)
    panel:SetSize(300, 96)
    panel:SetPoint("TOPLEFT", UIParent, "CENTER", -560, 260)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(0, 0, 0, 0.75)

    local title = text(panel)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -5)
    title:SetText("BarProbe: empty part of the bars (drag here)")
    local refresh = {
        stepper(panel, "Health", "health", 0.05, 0, 1, 6, -20, "%.2f"),
        stepper(panel, "Power", "power", 0.05, 0, 1, 152, -20, "%.2f"),
        stepper(panel, "Length", "length", 0.01, 0.01, 0.5, 152, -44, "%.0f%%", 100),
    }
    local ramp = button(panel, "", 140, nil)
    ramp:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -44)
    ramp:SetScript("OnClick", function()
        S.ramp = (S.ramp == "edge") and "whole" or "edge"; changed()
    end)
    local reset = button(panel, "Forget", 70, forget)
    reset:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -70)
    local shot = button(panel, "Shot", 70, function() Probe:Screenshot(describe()) end)
    shot:SetPoint("LEFT", reset, "RIGHT", 4, 0)
    local close = button(panel, "Close", 70, function() panel:Hide() end)
    close:SetPoint("LEFT", shot, "RIGHT", 4, 0)

    local function sync()
        for _, f in ipairs(refresh) do f() end
        ramp:SetText(S.ramp == "edge" and "Ramp: at the fill's edge" or "Ramp: whole bar")
    end
    panel.sync = sync

    for i, pct in ipairs(PCTS) do samples[i] = buildSample(panel, pct, i) end
    sync()
end

local function show()
    if not panel then buildPanel() end
    if not panel then return end
    panel:Show()
    applyAll()   -- widths are known once shown: the edge ramp needs them
    panel.sync()
    say("panel shown: " .. describe())
end

Probe:Command("show", show, "show the sample bars and the controls")
Probe:Command("hide", function() if panel then panel:Hide() end end, "hide the panel (settings stay applied)")
Probe:Command("state", function() say(describe()) end, "print the current settings")
Probe:Command("reset", function() forget() end, "forget the tuning; /reload gives the bars back to GlassUnitFrames")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

Probe:Steps("tune", {
    rev = 1,
    title = "Tune the bars' empty part",
    { text = "Opening the sample bars (drag the strip to move them).", auto = true,
      run = function() show(); return describe() end },
    { text = "Change Health (Power is settled at 0.25) until the 5% and 10% samples read low, and the 50% and 80% ones still look like glass. Then press Next.",
      screenshot = "whole bar" },
    { text = "Press 'Ramp' to try the ramp at the fill's edge, and tune Length. Then press Next.",
      screenshot = "edge ramp" },
    { text = "Keep whichever ramp you prefer on. Does it also read right on your real frames, in a fight?", ask = true },
    { text = "Reloading saves the chosen values.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN" })
boot:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        Probe:Ready()
        if type(rawget(_G, "BarProbeDB")) ~= "table" then BarProbeDB = {} end
        if type(BarProbeDB.log) ~= "table" then BarProbeDB.log = {} end
        Probe:UseLog(BarProbeDB.log, LOG_MAX)
        load(BarProbeDB.settings)
        say("loaded. /fp bar show (or /fp steps bar tune); saved: "
            .. (BarProbeDB.settings and describe() or "none"))
    elseif event == "PLAYER_LOGIN" then
        -- GlassUnitFrames built its frames at its own ADDON_LOADED: a saved
        -- tuning is re-applied to them, so it can be tried in play.
        local db = rawget(_G, "BarProbeDB")
        if db and db.settings then applyAll() end
    end
end)

NS._test = { Probe = Probe, S = S, applyAll = applyAll, show = show, samples = samples,
             panel = function() return panel end }
