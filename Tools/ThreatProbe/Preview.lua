-- Independent meter shell: Blizzard's assets and dimensions, no damage-meter
-- mixins/data ownership. Samples never enter combat; diagnostic rows may.
local _, NS = ...
local API, Probe = GlassUF.API, NS.Probe
local UI = { rows = {}, surfaces = {}, mode = nil, scenario = "party", count = 0, scroll = 0 }
NS.UI = UI
local G, window, compact, container, viewport, content, scrollbar, title, empty
local ROW, HEADER = 24, 32
local scenarios = { party = true, raid = true, restricted = true, empty = true }
local function finite(v) return not API.IsSecret(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function suite()
    local gui = rawget(_G, "GlassUI")
    local s = type(gui) == "table" and rawget(gui, "Suite")
    if type(s) == "table" and rawget(s, "API") == 1 then return s end
end
local function suiteCall(key)
    local s = suite()
    local fn = s and rawget(s, key)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if ok and type(value) == "table" then return value end
end

local function surface(host, size)
    local g = G.Apply(host, size)
    local backing = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    backing:SetAllPoints(host)
    backing:AddMaskTexture(g.mask)
    UI.surfaces[#UI.surfaces + 1] = { g = g, backing = backing }
    return g
end

function UI.Restyle()
    if not G then return end
    local body = suiteCall("Body")
    for _, s in ipairs(UI.surfaces) do
        if body then
            local tint = body.tint
            if body.classShade then
                local _, class = UnitClass("player")
                local r, g, b = API.ClassColor(class)
                if r then tint = { r * body.classShade, g * body.classShade, b * body.classShade } end
            end
            if tint then G.SetSurfaceTint(s.g, unpack(tint)) else G.SetSurfaceTint(s.g) end
            G.SetWash(s.g, G.STYLE.wash * body.wash)
            s.backing:SetColorTexture(unpack(body.backing))
        else
            s.backing:SetColorTexture(0.025, 0.03, 0.045, 0.35)
        end
    end
    local accent = suiteCall("Accent") or { 1, 0.82, 0 }
    title:SetTextColor(unpack(accent))
end

local function font(parent, template)
    return parent:CreateFontString(nil, "OVERLAY", template or "NumberFontNormal")
end

local function saveGeometry(frame, key)
    frame:StopMovingOrSizing()
    local x, y = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local w, h = frame:GetWidth(), frame:GetHeight()
    if not (finite(x) and finite(y) and finite(ux) and finite(uy) and finite(scale)
        and finite(parentScale) and finite(w) and finite(h)) or parentScale <= 0 then return end
    local k = scale / parentScale
    ThreatProbeDB[key] = { x = clamp(x * k - ux, -4096, 4096), y = clamp(y * k - uy, -4096, 4096),
        w = clamp(w, 200, 600), h = clamp(h, 120, 400) }
end

local function restore(frame, key)
    local p = ThreatProbeDB[key]
    if type(p) ~= "table" or not finite(p.x) or not finite(p.y) then return false end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", clamp(p.x, -4096, 4096), clamp(p.y, -4096, 4096))
    if key == "expanded" and finite(p.w) and finite(p.h) then frame:SetSize(clamp(p.w, 200, 600), clamp(p.h, 120, 400)) end
    return true
end

local function dockCompact()
    if compact.dragging then return end
    if restore(compact, "compact") then return end
    local frames = GlassUF.Frames.byUnit
    local base = frames.player.body
    local pet = frames.pet
    if pet and pet:IsShown() then
        base = pet.body
        local cast = GlassUF.Castbar.bars.pet
        if cast and not cast.detached and cast.host:IsShown() then base = cast.host end
    end
    compact:ClearAllPoints()
    compact:SetPoint("TOP", base, "BOTTOM", 0, -6)
end

local function movable(frame, key)
    frame.dragging = false
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self.dragging = true; self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self) self.dragging = false; saveGeometry(self, key) end)
end

local function atlasButton(parent, normal, pushed, highlight, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    for _, spec in ipairs({ { "Normal", normal }, { "Pushed", pushed }, { "Highlight", highlight } }) do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints(b); t:SetAtlas(spec[2])
        b["Set" .. spec[1] .. "Texture"](b, t)
    end
    return b
end

function UI.Layout()
    if not window then return end
    local height = math.max(1, window:GetHeight() - HEADER - 8)
    local total = math.max(1, UI.count * ROW)
    UI.range = math.max(0, total - height)
    local oldScroll = UI.scroll
    UI.scroll = clamp(UI.scroll, 0, 1)
    if UI.range == 0 then UI.scroll = 0 end
    if oldScroll ~= UI.scroll then scrollbar:SetScrollPercentage(UI.scroll, true) end
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, UI.range * UI.scroll)
    content:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, UI.range * UI.scroll)
    content:SetHeight(total)
    scrollbar:SetVisibleExtentPercentage(math.min(1, height / total))
    scrollbar:SetPanExtentPercentage(ROW / math.max(ROW, UI.range))
    scrollbar:SetShown(UI.range > 0)
end

local function build()
    if window then return end
    G = GlassUF.Glass
    -- GlassUI currently skins meters with Pearl, independently of GUF's own
    -- appearance overrides. Build our own instance, never change GUF's.
    if suite() then
        local lib = LibStub("LibGlass-1.0")
        local ok, made = pcall(lib.New, lib, { preset = "pearl" })
        if ok then G = made end
    end
    window = CreateFrame("Frame", "ThreatProbeWindow", UIParent)
    window:SetSize(300, 180)
    window:SetPoint("BOTTOM", UIParent, "BOTTOM", -304, 12)
    window:SetFrameStrata("MEDIUM")
    window:SetResizable(true); window:SetResizeBounds(200, 120, 600, 400)
    movable(window, "expanded")
    restore(window, "expanded")
    container = CreateFrame("Frame", nil, window)
    container:SetAllPoints(window)
    surface(container, "large")
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER)
    local hg = surface(header, "small")
    title = font(hg.top, "GameFontNormalMed1")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -28, 0)
    title:SetJustifyH("LEFT")
    local minimize = atlasButton(hg.top, "ui-questtrackerbutton-collapse-all", "ui-questtrackerbutton-collapse-all-pressed",
        "ui-questtrackerbutton-red-highlight", 18, 19)
    minimize:SetPoint("TOPRIGHT", header, "TOPRIGHT", -3, -5)
    minimize:SetScript("OnClick", function()
        container:SetShown(not container:IsShown())
        minimize:GetNormalTexture():SetAtlas(container:IsShown() and "ui-questtrackerbutton-collapse-all" or "ui-questtrackerbutton-expand-all")
    end)
    UI.minimize = minimize
    viewport = CreateFrame("Frame", nil, container)
    viewport:SetPoint("TOPLEFT", window, "TOPLEFT", 4, -HEADER)
    viewport:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 8)
    viewport:SetFrameLevel(G.ContentLevel(container))
    viewport:SetClipsChildren(true)
    content = CreateFrame("Frame", nil, viewport)
    empty = font(viewport, "GameFontNormalMed1")
    empty:SetPoint("CENTER", viewport, "CENTER", 0, 0)
    scrollbar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
    scrollbar:SetPoint("TOPLEFT", viewport, "TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMLEFT", viewport, "BOTTOMRIGHT", 0, 8)
    scrollbar:SetFrameLevel(viewport:GetFrameLevel() + 2)
    scrollbar:SetAlpha(0.3)
    scrollbar:RegisterCallback("OnScroll", function(_, pct) UI.scroll = pct; UI.Layout() end, UI)
    scrollbar:Init(1, 0.2)
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        scrollbar:SetScrollPercentage(clamp(UI.scroll - delta * ROW / math.max(ROW, UI.range), 0, 1), true)
    end)
    local resize = atlasButton(container, "damagemeters-scalehandle", "damagemeters-scalehandle-pressed",
        "damagemeters-scalehandle-hover", 60, 60)
    resize:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 9, -8)
    resize:SetFrameLevel(viewport:GetFrameLevel() + 3)
    resize:SetAlpha(0.3)
    resize:SetScript("OnMouseDown", function(_, b) if b == "LeftButton" and not InCombatLockdown() then window:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp", function() saveGeometry(window, "expanded"); UI.Layout() end)
    resize:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    resize:SetScript("OnLeave", function(self) self:SetAlpha(0.3) end)
    UI.resize, UI.viewport, UI.scrollbar = resize, viewport, scrollbar
    window:SetScript("OnSizeChanged", UI.Layout)
    compact = CreateFrame("Frame", "ThreatProbeCompact", UIParent)
    compact:SetSize(120, 22)
    movable(compact, "compact")
    local cg = surface(compact, "small")
    UI.compactText = font(cg.top)
    UI.compactText:SetPoint("CENTER", compact, "CENTER", 0, 0)
    local dockElapsed = 0
    compact:SetScript("OnUpdate", function(_, dt)
        dockElapsed = dockElapsed + dt
        if dockElapsed >= 0.25 then dockElapsed = 0; dockCompact() end
    end)
    UI.window, UI.compact, UI.container = window, compact, container
    UI.Restyle()
    local s, registry = suite(), rawget(_G, "EventRegistry")
    if s and type(rawget(s, "LOOK_EVENT")) == "string" and registry and type(registry.RegisterCallback) == "function" then
        registry:RegisterCallback(s.LOOK_EVENT, function() UI.Restyle() end, UI)
    end
    window:Hide(); compact:Hide()
end

local function row(i)
    if UI.rows[i] then return UI.rows[i] end
    local host = CreateFrame("Frame", nil, content)
    host:SetHeight(ROW)
    host:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW)
    host:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * ROW)
    local icon = host:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW, ROW); icon:SetPoint("LEFT", host, "LEFT", 0, 0)
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", ROW, 0)
    bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    local texture = bar:CreateTexture(nil, "ARTWORK")
    texture:SetAtlas("UI-HUD-CoolDownManager-Bar"); bar:SetStatusBarTexture(texture)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("ui-damagemeters-bar-shadowbg"); bg:SetAllPoints(bar)
    local edge = bar:CreateTexture(nil, "OVERLAY")
    edge:SetAtlas("ui-damagemeters-bar-shadowedge")
    edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2); edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
    bar:SetMinMaxValues(0, 100)
    local value, name = font(bar), font(bar)
    value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    value:SetWidth(56); value:SetJustifyH("RIGHT")
    name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    name:SetPoint("RIGHT", value, "LEFT", -4, 0)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    UI.rows[i] = { host = host, bar = bar, value = value, name = name, icon = icon }
    return UI.rows[i]
end

function UI.ClearRow(r)
    r.bar:SetValue(0); r.value:SetText("—"); r.bar:SetStatusBarColor(0.45, 0.45, 0.45)
end
function UI.ClearAll()
    for _, r in ipairs(UI.rows) do UI.ClearRow(r) end
end
function UI.Hide()
    UI.mode = nil
    if window then
        window:StopMovingOrSizing(); compact:StopMovingOrSizing()
        window.dragging, compact.dragging = false, false
        window:Hide(); compact:Hide(); UI.ClearAll()
    end
end

local function showRows(count, heading, message)
    build()
    title:SetText(heading)
    UI.count = count
    for i = 1, count do row(i).host:Show() end
    for i = count + 1, #UI.rows do UI.rows[i].host:Hide() end
    empty:SetText(message or ""); empty:SetShown(count == 0)
    compact:Hide(); window:Show()
    UI.Layout()
end

function UI.ShowDiagnostic(units)
    showRows(#units, "Threat · diagnostic", "No roster data")
    UI.mode = "diagnostic"
    for i, u in ipairs(units) do
        local r = UI.rows[i]
        r.name:SetText(u); r.icon:Hide()
        r.bar:ClearAllPoints()
        r.bar:SetPoint("TOPLEFT", r.host, "TOPLEFT", 0, 0)
        r.bar:SetPoint("BOTTOMRIGHT", r.host, "BOTTOMRIGHT", 0, 0)
    end
end

local classes = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "WARLOCK", "DRUID", "PALADIN", "SHAMAN" }
function UI.Preview(kind)
    if kind == "off" then NS.StopRender(); return end
    if kind ~= "compact" and kind ~= "expanded" then Probe:Say("preview compact|expanded|off"); return end
    if InCombatLockdown() then Probe:Say("Sample previews are out of combat only."); return end
    NS.StopRender()
    build()
    UI.kind, UI.mode = kind, "preview"
    UI.scroll = 0
    scrollbar:SetScrollPercentage(0, true)
    if kind == "compact" then
        local label = "#3 · 82%"
        if UI.scenario == "restricted" then label = "#— · 82%" elseif UI.scenario == "empty" then label = "#— · —" end
        UI.compactText:SetText(label)
        dockCompact(); compact:Show()
    else
        local count = UI.scenario == "raid" and 40 or 5
        if UI.scenario == "empty" then count = 0 end
        showRows(count, "Threat · preview", "No target / no threat data")
        container:Show()
        UI.minimize:GetNormalTexture():SetAtlas("ui-questtrackerbutton-collapse-all")
        for i = 1, count do
            local r, class = UI.rows[i], classes[(i - 1) % #classes + 1]
            local red, green, blue = API.ClassColor(class)
            r.bar:ClearAllPoints()
            r.bar:SetPoint("TOPLEFT", r.host, "TOPLEFT", ROW, 0)
            r.bar:SetPoint("BOTTOMRIGHT", r.host, "BOTTOMRIGHT", 0, 0)
            r.icon:SetAtlas("classicon-" .. class:lower()); r.icon:Show()
            local pct = i == 1 and 100 or (i == 3 and 82 or math.max(1, 98 - i * 4))
            r.bar:SetValue(pct); r.bar:SetStatusBarColor(red or 0.5, green or 0.5, blue or 0.5)
            r.value:SetFormattedText("%.0f%%", pct)
            local name = i == 3 and "You" or (i == 5 and "Sample Pet" or "Sample " .. i)
            r.name:SetText((UI.scenario == "restricted" and "" or i .. ". ") .. name)
        end
        if UI.scenario == "restricted" then title:SetText("Threat · group order (preview)") end
    end
    Probe:Say("Sample " .. kind .. " · " .. UI.scenario .. "; drag to place. /fp threat preview off to close.")
end

Probe:Command("preview", UI.Preview, "compact|expanded|off: sample display, out of combat")
Probe:Command("scenario", function(args)
    if not scenarios[args] then Probe:Say("scenario party|raid|restricted|empty"); return end
    UI.scenario = args
    if UI.mode == "preview" then UI.Preview(UI.kind) else Probe:Say("scenario " .. args) end
end, "party|raid|restricted|empty: deterministic samples")
Probe:Command("reset", function()
    ThreatProbeDB.compact, ThreatProbeDB.expanded = nil, nil
    if window then
        window:ClearAllPoints(); window:SetSize(300, 180)
        window:SetPoint("BOTTOM", UIParent, "BOTTOM", -304, 12)
        dockCompact(); UI.Layout()
    end
    Probe:Say("Prototype positions reset.")
end, "reset prototype positions and size")
NS._test.UI = UI
NS._test.saveGeometry = saveGeometry
NS._test.dockCompact = dockCompact
