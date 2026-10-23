-- Target-relative Pearl threat plate, persistent ranking and transient hover details.
local API, T = GlassUF.API, GlassUF.Threat
local UI = { rows = {}, tipRows = {}, count = 0, scroll = 0 }
GlassUF.ThreatView = UI
local G, window, compact, viewport, content, scrollbar, title, empty, tooltip
local ROW, HEADER, PAD, MAX_ROWS = 24, 26, 6, 8
local function finite(v) return not API.IsSecret(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local ANIMATION = 0.25
local function drawOpening(frame, progress)
    frame.open = progress
    frame:SetAlpha(progress)
    local w, h = frame.fullWidth or 112, frame.fullHeight or 22
    local horizontal = frame.direction == "right" or frame.direction == "left"
    local shownW, shownH = horizontal and math.max(2, w * progress) or w,
        horizontal and h or math.max(2, h * progress)
    frame:SetSize(shownW, shownH)
    local a = frame.dockPoint
    if a and not frame.dragging and not frame.sizing then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", a.relative, a.point,
            a.x + (frame.direction == "left" and w - shownW or 0),
            a.y + (frame.direction == "down" and h - shownH or 0))
    end
end
local function animate(frame, to)
    if frame.animation and frame.animation.to == to then return end
    if not frame.animation and frame.open == to then return end
    frame.animation = { from = frame.open or 0, to = to, elapsed = 0 }
    frame:SetClipsChildren(true)
    frame:Show()
end
local function stepAnimation(frame, dt)
    local a = frame.animation
    if not a then return end
    a.elapsed = math.min(ANIMATION, a.elapsed + dt)
    local t = a.elapsed / ANIMATION
    local eased = t * t * (3 - 2 * t)
    drawOpening(frame, a.from + (a.to - a.from) * eased)
    if t == 1 then
        frame.animation = nil
        frame:SetClipsChildren(false)
        if a.to == 0 then
            frame:Hide()
            if UI.closing == frame then UI.kind, UI.closing, UI.snapshot = nil, nil, nil end
        end
        if frame == window then UI.Layout() end
    end
end
local function font(parent, size, justify)
    return G.Font(parent, size or 12, justify or "LEFT")
end
local function surface(frame, dark)
    local g = G.Apply(frame, "small")
    G.SetSurfaceTint(g, 0.055, 0.06, 0.075, 0.55)
    G.SetWash(g, 0.06)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints(frame); bg:AddMaskTexture(g.mask)
    bg:SetColorTexture(0.025, 0.028, 0.035, dark and 0.94 or 0.72)
    return g
end
local function bar(parent)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    b:SetMinMaxValues(0, 100)
    b:SetValue(0)
    return b
end
-- Clamp only plain graphical values. Native StatusBar clamps secret values;
-- the text receives the untouched percentage (including values above 100).
local function percent(fill, text, value)
    if fill then fill:SetValue(0) end
    text:SetText("—")
    if API.IsSecret(value) or finite(value) then
        local graphical = value
        if not API.IsSecret(value) then graphical = clamp(value, 0, 100) end
        if fill and not pcall(fill.SetValue, fill, graphical) then API.Fail("threat fill", "native percentage rendering rejected") end
        if not pcall(text.SetFormattedText, text, "%.0f%%", value) then API.Fail("threat text", "native percentage formatting rejected") end
    end
end
local function summary(parent)
    local rank, value = font(parent, 11, "RIGHT"), font(parent, 13, "RIGHT")
    value:SetPoint("RIGHT", parent, "RIGHT", -8, 1); value:SetWidth(54)
    rank:SetPoint("RIGHT", value, "LEFT", -3, 0); rank:SetWidth(40)
    return { rank = rank, value = value }
end
local function paintSummary(w, s, fill)
    local p, color = s.player, s.color or T.UNKNOWN
    w.rank:SetText("#" .. (p and p.rank or "—") .. " ·")
    w.rank:SetTextColor(0.78, 0.81, 0.84)
    w.value:SetTextColor(unpack(color))
    percent(fill, w.value, p and p.scaled)
    if fill then fill:SetStatusBarColor(unpack(color)) end
end
local function validPosition(p) return type(p) == "table" and finite(p.x) and finite(p.y) end
local function setDock(frame, relative, point, x, y, custom)
    frame.direction = "right"
    if custom then
        local target = GlassUF.Frames.byUnit.target.body
        local tx, ty = target:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local scale = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if finite(tx) and finite(ty) and finite(ux) and finite(uy) and finite(scale) then
            -- Use the compact-sized attachment area, so changing views does not
            -- change the inferred direction. Coordinates are read only on docking.
            local dx, dy = ux + x + 56 - tx * scale, uy + y + 11 - ty * scale
            if math.abs(dx) > math.abs(dy) then frame.direction = dx >= 0 and "right" or "left"
            else frame.direction = dy >= 0 and "up" or "down" end
        end
    end
    frame.dockPoint = { relative = relative, point = point, x = x, y = y }
    frame:SetPoint("BOTTOMLEFT", relative, point, x, y)
    if frame.open then drawOpening(frame, frame.open) end
end
local function dock(frame, key)
    if frame.dragging or frame.sizing then return end
    local p = T.Geometry(key .. "Anchor")
    -- Preserve the old shared placement until each view is moved independently.
    if not validPosition(p) then p = T.Geometry("anchor") end
    frame:ClearAllPoints()
    if validPosition(p) then
        setDock(frame, UIParent, "CENTER", clamp(p.x, -4096, 4096), clamp(p.y, -4096, 4096), true)
        return
    end
    -- Old placements were independent centre anchors. Keep each one's location;
    -- convert to bottom-left so content changes grow upward, not into the target.
    p = T.Geometry(key)
    if validPosition(p) then
        local w = key == "compact" and 120 or (finite(p.w) and clamp(p.w, 200, 600) or 300)
        local h = key == "compact" and 22 or (finite(p.h) and clamp(p.h, 120, 400) or 180)
        setDock(frame, UIParent, "CENTER", p.x - w / 2, p.y - h / 2, true)
        return
    end
    local target = GlassUF.Frames.byUnit.target
    local edge = GlassUF.Frames.EdgeVisual(target, "right")
    local scale = target.body:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local inset = GlassUF.Glass.Inset(target.layout.size or "large")
    -- Compact's centre matches the health/name row. Expanded shares its lower
    -- edge and grows upward; the native visual anchor rides layout glides.
    local y = (target.body:GetHeight() / 2 - inset - target.health:GetHeight() / 2) * scale - 11
    setDock(frame, edge, "RIGHT", 8, y)
end
-- No cast-space reservation: this dock is beside the target's outer visual edge.
function UI.Reanchor()
    if not window then return end
    dock(window, "expanded"); dock(compact, "compact")
end
local function saveGeometry(frame, key)
    frame:StopMovingOrSizing()
    frame.dragging, frame.sizing = false, false
    local x, y = frame:GetLeft(), frame:GetBottom()
    local ux, uy = UIParent:GetCenter()
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if finite(x) and finite(y) and finite(ux) and finite(uy) and finite(scale) and finite(parentScale) and parentScale > 0 then
        local k = scale / parentScale
        T.SaveGeometry(key .. "Anchor", { x = clamp(x * k - ux, -4096, 4096), y = clamp(y * k - uy, -4096, 4096) })
    end
    if key == "expanded" then
        T.SaveGeometry("size", { w = clamp(frame:GetWidth(), 220, 600),
            rows = clamp(math.floor((frame:GetHeight() - HEADER - PAD) / ROW + 0.5), 1, 15) })
    end
    dock(window, "expanded"); dock(compact, "compact")
end
local function movable(frame, key)
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self.animation = nil; drawOpening(self, 1); self:SetClipsChildren(false)
            UI.HideTooltip(); self.dragging = true; self.wasDragged = true; self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self) saveGeometry(self, key) end)
end
function UI.HideTooltip()
    UI.hovered = false
    if tooltip then tooltip:Hide() end
end
function UI.Layout()
    if not window or not scrollbar then return end
    local height = math.max(1, (window.animation and window.fullHeight or window:GetHeight()) - HEADER - PAD)
    local total = math.max(1, UI.count * ROW)
    UI.range = math.max(0, total - height)
    UI.scroll = UI.range == 0 and 0 or clamp(UI.scroll, 0, 1)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, UI.range * UI.scroll)
    content:SetPoint("TOPRIGHT", viewport, "TOPRIGHT", 0, UI.range * UI.scroll)
    content:SetHeight(total)
    scrollbar:SetVisibleExtentPercentage(math.min(1, height / total))
    scrollbar:SetPanExtentPercentage(ROW / math.max(ROW, UI.range))
    scrollbar:SetShown(UI.range > 0)
    if UI.range == 0 then scrollbar:SetScrollPercentage(0, false) end
end
local function makeRow(parent, index, rows)
    if rows[index] then return rows[index] end
    local host = CreateFrame("Frame", nil, parent)
    host:SetHeight(ROW)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW)
    host:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ROW)
    local fill = bar(host)
    fill:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -1)
    fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 1)
    local rank = font(fill, 11, "CENTER")
    rank:SetPoint("LEFT", fill, "LEFT", 2, 0); rank:SetWidth(20)
    local icon = fill:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16); icon:SetPoint("LEFT", fill, "LEFT", 25, 0)
    local value, name = font(fill, 12, "RIGHT"), font(fill, 12)
    value:SetPoint("RIGHT", fill, "RIGHT", -4, 0); value:SetWidth(48)
    name:SetPoint("LEFT", fill, "LEFT", 46, 0)
    name:SetPoint("RIGHT", value, "LEFT", -42, 0); name:SetWordWrap(false)
    local you = font(fill, 9)
    you:SetPoint("RIGHT", value, "LEFT", -4, 0); you:SetText("You")
    local edge = fill:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(0.82, 0.9, 0.91, 0.75); edge:SetWidth(2)
    edge:SetPoint("TOPLEFT", fill, "TOPLEFT"); edge:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
    local aggro = font(fill, 10)
    aggro:SetPoint("LEFT", icon, "RIGHT", 0, 0); aggro:SetText("•"); aggro:SetTextColor(1, 0.8, 0.55)
    rows[index] = { host = host, bar = fill, rank = rank, name = name, value = value, icon = icon, you = you, edge = edge, aggro = aggro }
    return rows[index]
end
local function paintRow(r, e)
    r.rank:SetText(e.rank or "—"); r.name:SetText(e.name)
    r.name:SetTextColor(0.95, 0.96, 0.98); r.value:SetTextColor(0.95, 0.96, 0.98)
    r.you:SetShown(e.player == true); r.edge:SetShown(e.player == true)
    r.aggro:SetShown(e.tank == true)
    if e.class then r.icon:SetAtlas("classicon-" .. e.class:lower()); r.icon:Show() else r.icon:Hide() end
    local red, green, blue = API.ClassColor(e.class)
    if not red or (red > 0.9 and green > 0.9 and blue > 0.9) then red, green, blue = 0.67, 0.72, 0.77 end
    r.bar:SetStatusBarColor(red, green, blue, 0.35)
    percent(r.bar, r.value, e.scaled)
end
function UI.UpdateTooltip()
    local s = UI.snapshot
    if not UI.hovered or UI.closing or UI.kind ~= "compact" or not s or not s.valid then UI.HideTooltip(); return end
    UI.tipTarget:SetText(s.targetName or "Target · preview")
    paintSummary(UI.tipSummary, s)
    local holder
    for _, e in ipairs(s.rows) do if e.tank == true then holder = e; break end end
    UI.tipHolder:SetText(holder and holder.name or "Unknown")
    local n = math.min(5, #s.rows)
    for i = 1, n do local r = makeRow(UI.tipContent, i, UI.tipRows); paintRow(r, s.rows[i]); r.host:Show() end
    for i = n + 1, #UI.tipRows do UI.tipRows[i].host:Hide() end
    tooltip:SetHeight(104 + math.max(1, n) * ROW)
    tooltip:Show()
end
local function build()
    if window then return end
    G = GlassUF.Glass
    local lib = LibStub("LibGlass-1.0")
    local ok, made = pcall(lib.New, lib, { preset = "pearl", font = GlassUF.Glass.fontKey })
    if ok then G = made end
    window = CreateFrame("Frame", "GlassUnitFramesThreatWindow", UIParent)
    window.fullWidth, window.fullHeight = 300, HEADER + PAD + ROW
    window:SetSize(300, HEADER + PAD + ROW)
    window:SetFrameStrata("MEDIUM"); window:SetResizable(true)
    window:SetResizeBounds(220, HEADER + PAD + ROW, 600, HEADER + PAD + 15 * ROW)
    movable(window, "expanded")
    local wg = surface(window)
    title = font(wg.top, 13); title:SetPoint("TOPLEFT", window, "TOPLEFT", 9, -6)
    title:SetTextColor(0.94, 0.96, 1)
    local summaryHost = CreateFrame("Frame", nil, wg.top)
    summaryHost:SetSize(115, HEADER); summaryHost:SetPoint("TOPRIGHT", window, "TOPRIGHT", -22, 0)
    UI.headerSummary = summary(summaryHost)
    local collapse = CreateFrame("Button", nil, wg.top)
    collapse:SetSize(20, 22); collapse:SetPoint("TOPRIGHT", window, "TOPRIGHT", -3, -1)
    for _, side in ipairs({ -1, 1 }) do
        local line = collapse:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(0.8, 0.85, 0.9, 1); line:SetSize(6, 1.2)
        line:SetPoint("CENTER", collapse, "CENTER", side * 2, 0)
        line:SetRotation(side * math.pi / 4)
    end
    collapse:SetScript("OnClick", function() UI.HideTooltip(); T.SetDisplay("compact") end)
    UI.minimize = collapse
    viewport = CreateFrame("Frame", nil, window)
    viewport:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -HEADER)
    viewport:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, PAD)
    viewport:SetFrameLevel(G.ContentLevel(window)); viewport:SetClipsChildren(true)
    content = CreateFrame("Frame", nil, viewport)
    empty = font(viewport); empty:SetPoint("CENTER", viewport, "CENTER")
    scrollbar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
    scrollbar:SetPoint("TOPLEFT", viewport, "TOPRIGHT", 1, 0)
    scrollbar:SetPoint("BOTTOMLEFT", viewport, "BOTTOMRIGHT", 1, 0)
    scrollbar:SetFrameLevel(viewport:GetFrameLevel() + 2); scrollbar:SetAlpha(0.4)
    scrollbar:RegisterCallback("OnScroll", function(_, p)
        if UI.scroll ~= p then UI.scroll = p; UI.Layout() end
    end, UI)
    scrollbar:Init(1, 0.2)
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        scrollbar:SetScrollPercentage(clamp(UI.scroll - delta * ROW / math.max(ROW, UI.range), 0, 1), true)
    end)
    local resize = CreateFrame("Button", nil, wg.top)
    resize:SetSize(14, 14); resize:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    -- Width/row limit adjustment from the top-left keeps the lower edge clear of the target.
    resize:ClearAllPoints(); resize:SetPoint("TOPLEFT", window, "TOPLEFT", -3, 3)
    resize:SetScript("OnMouseDown", function(_, b)
        if b == "LeftButton" and not InCombatLockdown() then window.animation = nil; drawOpening(window, 1); window:SetClipsChildren(false); window.sizing = true; window:StartSizing("TOPLEFT") end
    end)
    resize:SetScript("OnMouseUp", function() saveGeometry(window, "expanded"); T.Refresh() end)
    local grip = font(resize, 11); grip:SetPoint("CENTER", resize, "CENTER"); grip:SetText("/"); grip:SetTextColor(0.65, 0.7, 0.75)
    UI.resize = resize
    window:SetScript("OnSizeChanged", function() if not window.animation then UI.Layout() end end)
    window:SetScript("OnUpdate", stepAnimation)
    compact = CreateFrame("Button", "GlassUnitFramesThreatCompact", UIParent)
    compact:SetSize(112, 22); compact:SetFrameStrata("MEDIUM"); movable(compact, "compact")
    local cg = surface(compact)
    UI.compactGlass, UI.compactSummary = cg, summary(cg.top)
    -- Anchor summary to the fixed plate, not the material's overlay dimensions.
    UI.compactSummary.value:ClearAllPoints(); UI.compactSummary.value:SetPoint("RIGHT", compact, "RIGHT", -8, 1)
    UI.compactText = UI.compactSummary.value
    UI.compactFill = bar(cg.top)
    UI.compactFill:SetHeight(2); UI.compactFill:SetPoint("BOTTOMLEFT", compact, "BOTTOMLEFT", 5, 3)
    UI.compactFill:SetPoint("BOTTOMRIGHT", compact, "BOTTOMRIGHT", -5, 3)
    compact.fullWidth, compact.fullHeight = 112, 22
    compact:SetScript("OnUpdate", stepAnimation)
    compact:SetScript("OnMouseDown", function() compact.wasDragged = false end)
    compact:SetScript("OnClick", function()
        if not compact.wasDragged then UI.HideTooltip(); T.SetDisplay("expanded") end
    end)
    compact:SetScript("OnEnter", function() UI.hovered = true; UI.UpdateTooltip() end)
    compact:SetScript("OnLeave", UI.HideTooltip)
    tooltip = CreateFrame("Frame", nil, UIParent)
    tooltip:SetWidth(310); tooltip:SetFrameStrata("TOOLTIP"); tooltip:SetClampedToScreen(true)
    tooltip:SetPoint("BOTTOMLEFT", compact, "TOPLEFT", 0, 6)
    local tg = surface(tooltip, true)
    UI.tipTarget = font(tg.top, 13); UI.tipTarget:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 9, -8)
    UI.tipTarget:SetWidth(290); UI.tipTarget:SetWordWrap(false)
    local holderLabel = font(tg.top, 10); holderLabel:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 9, -28); holderLabel:SetText("Holds aggro:")
    UI.tipHolder = font(tg.top, 10); UI.tipHolder:SetPoint("LEFT", holderLabel, "RIGHT", 5, 0); UI.tipHolder:SetWidth(180); UI.tipHolder:SetWordWrap(false)
    local ownLabel = font(tg.top, 11); ownLabel:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 9, -44); ownLabel:SetText("Your threat")
    local sh = CreateFrame("Frame", nil, tg.top); sh:SetSize(112, 22); sh:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", -4, -39)
    UI.tipSummary = summary(sh)
    UI.tipContent = CreateFrame("Frame", nil, tg.top)
    UI.tipContent:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 7, -63); UI.tipContent:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", -7, -63)
    UI.tipContent:SetHeight(5 * ROW)
    local note = font(tg.top, 10); note:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", 9, 23); note:SetText("% progress toward pulling aggro")
    local hint = font(tg.top, 11); hint:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMLEFT", 9, 7); hint:SetText("Click to expand")
    UI.window, UI.compact, UI.container, UI.tooltip = window, compact, window, tooltip
    UI.viewport, UI.scrollbar = viewport, scrollbar
    for _, unit in ipairs({ "target" }) do
        local b = GlassUF.Frames.byUnit[unit]
        if b then
            b:HookScript("OnShow", UI.Reanchor); b:HookScript("OnHide", UI.Reanchor)
            b.body:HookScript("OnSizeChanged", UI.Reanchor)
            b.health:HookScript("OnSizeChanged", UI.Reanchor)
        end
    end
    for _, method in ipairs({ "SetPosition", "ApplyPosition", "ResetPosition", "ResetPositions", "SetPortraitMode" }) do
        hooksecurefunc(GlassUF.Frames, method, UI.Reanchor)
    end
    hooksecurefunc(GlassUF.Settings, "SetFont", function(key)
        if GlassUF.Glass.fontKey == key then G.SetFont(key) end
    end)
    local registry = rawget(_G, "EventRegistry")
    if registry and type(registry.RegisterCallback) == "function" then
        registry:RegisterCallback("GlassUnitFrames.LayoutChanged", UI.Reanchor, UI)
    end
    UI.Reanchor()
    window:Hide(); compact:Hide(); tooltip:Hide()
end
function UI.Hide(animated)
    UI.HideTooltip()
    if not window then return end
    if animated and UI.kind then
        local outgoing = UI.kind == "compact" and compact or window
        UI.closing = outgoing
        animate(outgoing, 0)
        return
    end
    UI.kind, UI.snapshot, UI.closing = nil, nil, nil
    for _, f in ipairs({ window, compact }) do
        if f.dragging or f.sizing then f:StopMovingOrSizing() end
        f.dragging, f.sizing, f.animation = false, false, nil
        f.open = 0; f:Hide(); f:SetAlpha(0)
    end
end
function UI.Show(s, kind, preview)
    build()
    if not s.valid then UI.HideTooltip() end
    UI.snapshot = s
    if UI.kind ~= kind then
        UI.HideTooltip()
        for _, f in ipairs({ window, compact }) do
            if f.dragging or f.sizing then f:StopMovingOrSizing() end
            f.dragging, f.sizing, f.animation = false, false, nil
            f.open = 0
        end
        dock(kind == "compact" and compact or window, kind)
    end
    UI.closing = nil
    UI.kind = kind
    if kind == "compact" then
        window:Hide(); paintSummary(UI.compactSummary, s, UI.compactFill)
        animate(compact, 1); drawOpening(compact, compact.open or 0)
        compact:Show(); UI.UpdateTooltip(); return
    end
    UI.HideTooltip(); compact:Hide()
    title:SetText(preview and "Threat · preview" or "Threat")
    paintSummary(UI.headerSummary, s)
    UI.count = #s.rows
    for i, e in ipairs(s.rows) do local r = makeRow(content, i, UI.rows); paintRow(r, e); r.host:Show() end
    for i = #s.rows + 1, #UI.rows do UI.rows[i].host:Hide() end
    empty:SetText(s.message or "No threat data"); empty:SetShown(#s.rows == 0)
    local size, legacy = T.Geometry("size"), T.Geometry("expanded")
    local w, limit = 300, MAX_ROWS
    if type(legacy) == "table" then
        if finite(legacy.w) then w = clamp(legacy.w, 220, 600) end
        if finite(legacy.h) then limit = clamp(math.floor((legacy.h - HEADER - PAD) / ROW), 1, 15) end
    end
    if type(size) == "table" then
        if finite(size.w) then w = clamp(size.w, 220, 600) end
        if finite(size.rows) then limit = clamp(math.floor(size.rows), 1, 15) end
    end
    if not window.sizing then
        window.fullHeight = HEADER + PAD + math.max(1, math.min(limit, #s.rows)) * ROW
        window.fullWidth = w
        animate(window, 1); drawOpening(window, window.open or 0)
    end
    UI.Layout(); window:Show()
end
function UI.ResetPositions()
    T.SaveGeometry("size", nil)
    if not window then return end
    UI.Reanchor()
end
UI._test = { saveGeometry = saveGeometry, dock = dock }
