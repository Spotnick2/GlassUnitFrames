-- Unlock mode (#34): move the frames, alone or with their group, and place
-- them exactly.
--
-- /glass unlock shows a mover over every frame (units that aren't there too:
-- a hidden frame keeps its rect, so its mover still shows). The movers are
-- plain, insecure frames on UIParent, anchored TO the buttons, never the
-- reverse (a frame a protected frame anchors to becomes protected itself).
-- Dragging moves the MOVER; while it moves, the real frame follows through
-- Frames.SetPosition, and nothing ever starts the client's own drag on a
-- protected button (a drag that combat interrupts can't be stopped, porting
-- guide). Group moves come free: followers are anchored to their leader
-- (Frames.LAYOUT anchorTo), so dragging the target carries its cluster and
-- dragging a follower moves only that follower.
--
-- Clicking a mover selects it and opens a small nudge panel: X/Y in the
-- frame's own offsets (from its leader, or from the screen centre), arrow
-- buttons (1 unit, Shift 10), reset this frame, lock. Out of combat only: a
-- combat start locks everything; unlock and nudges are refused in combat.

GlassUF = GlassUF or {}
local Movers = {}
GlassUF.Movers = Movers

local API, Frames = GlassUF.API, GlassUF.Frames

local NAMES = { player = "Player", target = "Target", pet = "Pet", targettarget = "Target of target",
                targettargettarget = "Target of target of target", focus = "Focus", focustarget = "Focus target" }
local TINT = { 0.30, 0.65, 1.00, 0.35 }

Movers.unlocked = false
local movers, selected, dragging = {}, nil, nil
local panel

-- Snapping while dragging: align a frame's edges and centre to other frames'
-- (and the screen centre) within SNAP_DIST, with a guide line showing each
-- match; else its centre to a GRID. Both on by default (saved when off); Alt
-- held places freely. Everything is in UIParent units, like the offsets.
local GRID, SNAP_DIST = 16, 8
local OVERLAY_LEVEL, MOVER_LEVEL = 1, 10   -- grid and guides below the movers (same strata)
Movers.snapGrid, Movers.snapAlign = true, true

-- Mirroring: the player and target frames stay symmetric around the screen
-- centre. Moving one (drag, arrows, typed X/Y, reset) places the other at the
-- mirrored spot (-x, same y); their groups follow through their anchors. On
-- by default (saved when off), but it only acts on a pair that IS symmetric
-- now: a custom asymmetric layout is never overwritten (reset both, or place
-- them symmetrically once, to start mirroring). Alt at the START of a drag
-- moves one alone; the choice holds for the whole drag.
local MIRROR = { player = "target", target = "player" }
Movers.mirror = true

-- The frame mirrored with `unit` right now, or nil: mirroring on, and the
-- pair currently symmetric (both sit on the screen centre-on-centre, so the
-- mirror is simply -x; within half a unit, the offsets' rounding).
local function mirrorOf(unit)
    local other = Movers.mirror and MIRROR[unit]
    if not other or not Frames.byUnit[other] then return nil end
    local ux, uy = Frames.PositionOf(unit)
    local ox, oy = Frames.PositionOf(other)
    if not (ux and ox) then return nil end
    if math.abs(ux + ox) > 0.5 or math.abs(uy - oy) > 0.5 then return nil end
    return other
end

-- Place `unit` and, if given, its mirror `other` at -x (the one mirror rule);
-- `live` = a drag in flight (not saved yet). Returns ok and the offsets
-- applied to `unit`.
local function place(unit, x, y, live, other)
    local ok, ax, ay = Frames.SetPosition(unit, x, y, live)
    if not ok then return false end
    if other then Frames.SetPosition(other, -ax, ay, live) end
    return true, ax, ay
end
local overlay   -- the grid and the guide lines, full screen, under the movers

local function relName(rel)
    if rel == "UIParent" then return "the screen centre" end
    return NAMES[rel] or rel
end

-- The mover's centre as offsets from the frame's leader (or the screen).
local snappedCenter, showGuide   -- defined below (need the snapping helpers)

local function offsetsFromMover(m)
    local _, relFrame = Frames.AnchorOf(m.unit)   -- what SetPosition places it on
    local mx, my = snappedCenter(m)
    -- Not `relFrame and relFrame:GetCenter()`: `and` keeps only the first return.
    local rx, ry
    if relFrame then rx, ry = relFrame:GetCenter() end
    if type(mx) ~= "number" or type(rx) ~= "number" or type(ry) ~= "number" then return nil end
    return mx - rx, my - ry
end

local function refreshPanel()
    if not (panel and selected) then return end
    local x, y = Frames.PositionOf(selected)
    panel.title:SetText(NAMES[selected] or selected)
    panel.sub:SetText("offsets from " .. relName((Frames.AnchorOf(selected))))
    if not panel.x:HasFocus() then panel.x:SetText(x and string.format("%g", x) or "?") end
    if not panel.y:HasFocus() then panel.y:SetText(y and string.format("%g", y) or "?") end
end

-- Finish a drag in flight: the last position the frame took is saved. Safe
-- in combat (only the insecure mover and a table write are touched).
-- End a drag in flight. `save`: record the last position the frame took
-- (safe in combat: only the insecure mover and a table write are touched);
-- otherwise drop it (a reset is about to run and must win).
local function endDrag(save)
    local m = dragging
    if not m then return end
    dragging = nil
    m:SetScript("OnUpdate", nil)
    m:StopMovingOrSizing()
    if save and m.lastX then
        if InCombatLockdown() then
            -- Only the table (never a protected frame under lockdown).
            Frames.SavePosition(m.unit, m.lastX, m.lastY)
            if m.partner then Frames.SavePosition(m.partner, -m.lastX, m.lastY) end
        else
            place(m.unit, m.lastX, m.lastY, false, m.partner)
        end
    end
    m.lastX, m.lastY, m.lines, m.partner = nil, nil, nil, nil
    m:ClearAllPoints()
    m:SetAllPoints(Frames.byUnit[m.unit])
    showGuide("vguide", nil)
    showGuide("hguide", nil)
end

local function finishDrag() endDrag(true) end

-- Is `unit` carried by `leader` (anchored to it, directly or through a chain)?
local function followsFrom(unit, leader)
    local L = Frames.LAYOUT[unit]
    while L and L.anchorTo do
        if L.anchorTo == leader then return true end
        L = Frames.LAYOUT[L.anchorTo]
    end
    return false
end

-- The lines a dragged frame may align to on one axis: every other frame's
-- two edges and centre (not the frame itself, nor what moves with it), plus
-- the screen centre.
local function alignLines(unit, axis)
    local lines = {}
    local ucx, ucy = UIParent:GetCenter()
    -- Not `axis == "x" and ucx or ucy`: a nil ucx would hand x the y centre.
    local centre
    if axis == "x" then centre = ucx else centre = ucy end
    if type(centre) == "number" then lines[#lines + 1] = centre end
    local m = movers[unit]
    local partner = m and m.partner
    for u, b in pairs(Frames.byUnit) do
        if u ~= unit and not followsFrom(u, unit) and u ~= partner and not (partner and followsFrom(u, partner)) then
            local lo, hi
            if axis == "x" then lo, hi = b:GetLeft(), b:GetRight() else lo, hi = b:GetBottom(), b:GetTop() end
            if type(lo) == "number" and type(hi) == "number" then
                lines[#lines + 1] = lo
                lines[#lines + 1] = hi
                lines[#lines + 1] = (lo + hi) / 2
            end
        end
    end
    return lines
end

-- The nearest alignment for a centre `c` with half-size `half`: its low edge,
-- centre or high edge onto any line within SNAP_DIST. Returns the new centre
-- and the line, or nil.
local EDGES = { -1, 0, 1 }   -- low edge, centre, high edge (times half the size)
local function alignAxis(c, half, lines)
    local bestD, bestC, bestLine
    for _, line in ipairs(lines) do
        for _, k in ipairs(EDGES) do
            local off = k * half
            local d = math.abs(c + off - line)
            if d <= SNAP_DIST and (not bestD or d < bestD) then
                bestD, bestC, bestLine = d, line - off, line
            end
        end
    end
    return bestC, bestLine
end

local function gridAxis(c, origin)
    return origin + math.floor((c - origin) / GRID + 0.5) * GRID
end

function showGuide(which, at)
    if not overlay then return end
    local line = overlay[which]
    if not at then line:Hide(); line.at = nil; return end
    if line.at == at and line:IsShown() then return end
    line.at = at
    line:ClearAllPoints()
    if which == "vguide" then
        line:SetPoint("TOP", UIParent, "BOTTOMLEFT", at, UIParent:GetHeight())
        line:SetSize(1, UIParent:GetHeight())
    else
        line:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, at)
        line:SetSize(UIParent:GetWidth(), 1)
    end
    line:Show()
end

-- The mover's centre after snapping (Alt: none). Also shows the guides.
function snappedCenter(m)
    local mx, my = m:GetCenter()
    if type(mx) ~= "number" or type(my) ~= "number" then return nil end
    local gx, gy
    if not IsAltKeyDown() then
        local w, h = m:GetWidth(), m:GetHeight()
        local ucx, ucy = UIParent:GetCenter()
        local nx, ny
        if Movers.snapAlign and type(w) == "number" and type(h) == "number" then
            -- Nothing the lines depend on moves during a drag (the dragged
            -- frame's own group is excluded): build them once per drag.
            m.lines = m.lines or { x = alignLines(m.unit, "x"), y = alignLines(m.unit, "y") }
            nx, gx = alignAxis(mx, w / 2, m.lines.x)
            ny, gy = alignAxis(my, h / 2, m.lines.y)
        end
        if Movers.snapGrid and type(ucx) == "number" then
            nx = nx or gridAxis(mx, ucx)
            ny = ny or gridAxis(my, ucy)
        end
        mx, my = nx or mx, ny or my
    end
    showGuide("vguide", gx)
    showGuide("hguide", gy)
    return mx, my
end

local function follow(m)
    if InCombatLockdown() then finishDrag(); return end
    local x, y = offsetsFromMover(m)
    if not x then return end
    -- Skip when nothing moved: every SetPoint re-lays out the whole group.
    local rx, ry = math.floor(x * 2 + 0.5) / 2, math.floor(y * 2 + 0.5) / 2
    if rx == m.lastX and ry == m.lastY then return end
    local ok, ax, ay = place(m.unit, x, y, true, m.partner)
    if ok then m.lastX, m.lastY = ax, ay end
end

local function select_(unit)
    -- Switching frames discards a coordinate typed but not committed: its
    -- Enter would otherwise land on the NEW frame (Codex, #52).
    if panel and unit ~= selected then
        panel.x:ClearFocus()
        panel.y:ClearFocus()
    end
    selected = unit
    for u, m in pairs(movers) do m.edge:SetShown(u == unit) end
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint("BOTTOM", movers[unit], "TOP", 0, 8)
        panel:Show()
        refreshPanel()
    end
end

local function makeMover(unit, b)
    local m = CreateFrame("Frame", nil, UIParent)
    m.unit = unit
    m:SetFrameStrata("DIALOG")
    m:SetFrameLevel(MOVER_LEVEL)   -- above the grid and guides
    m:SetAllPoints(b)
    m:EnableMouse(true)
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    m:RegisterForDrag("LeftButton")
    local tint = m:CreateTexture(nil, "BACKGROUND")
    tint:SetAllPoints(m)
    tint:SetColorTexture(TINT[1], TINT[2], TINT[3], TINT[4])
    local edge = m:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", m, "TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 2, -2)
    edge:SetColorTexture(1, 0.82, 0, 0.5)
    edge:Hide()
    m.edge = edge
    local fs = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER", m, "CENTER")
    fs:SetText(NAMES[unit] or unit)
    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        select_(self.unit)
        -- Mirror or not is decided now (Alt held = alone) and holds for the
        -- whole drag, so what's seen is what's saved.
        self.partner = (not IsAltKeyDown()) and mirrorOf(self.unit) or nil
        self:StartMoving()
        dragging = self
        self:SetScript("OnUpdate", follow)
    end)
    m:SetScript("OnDragStop", function(self)
        if dragging ~= self then return end
        follow(self)
        finishDrag()
        refreshPanel()
    end)
    m:SetScript("OnMouseUp", function(self) select_(self.unit) end)
    m:Hide()
    return m
end

-- Nudge / type a position for the selected frame.
local function nudge(dx, dy)
    if not selected or InCombatLockdown() then return end
    local step = IsShiftKeyDown() and 10 or 1
    local x, y = Frames.PositionOf(selected)
    if not x then return end   -- can't tell where it is: never invent a position
    if place(selected, x + dx * step, y + dy * step, false, mirrorOf(selected)) then refreshPanel() end
end

local function makeEdit(parent, onCommit)
    local e, templated = API.SafeFrame("EditBox", parent, "InputBoxTemplate", "Left")
    if not templated then
        local bg = e:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(e)
        bg:SetColorTexture(0, 0, 0, 0.6)
    end
    e:SetSize(64, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlight")
    e:SetJustifyH("CENTER")
    e:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        self:ClearFocus()
        if v then onCommit(v) end
        refreshPanel()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); refreshPanel() end)
    return e
end

local function makeButton(parent, text, w, onClick)
    local b, templated = API.SafeFrame("Button", parent, "UIPanelButtonTemplate", "Text")
    if not templated then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0.2, 0.2, 0.25, 0.9)
        b:SetNormalFontObject("GameFontHighlight")
    end
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function makePanel()
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(100)
    p:SetSize(250, 140)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(0.05, 0.07, 0.10, 0.92)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -6)
    p.sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -2)
    local xl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    xl:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -42)
    xl:SetText("X")
    p.x = makeEdit(p, function(v)
        local _, y = Frames.PositionOf(selected)
        if y then place(selected, v, y, false, mirrorOf(selected)) end
    end)
    p.x:SetPoint("LEFT", xl, "RIGHT", 8, 0)
    local yl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yl:SetPoint("LEFT", p.x, "RIGHT", 10, 0)
    yl:SetText("Y")
    p.y = makeEdit(p, function(v)
        local x = Frames.PositionOf(selected)
        if x then place(selected, x, v, false, mirrorOf(selected)) end
    end)
    p.y:SetPoint("LEFT", yl, "RIGHT", 8, 0)
    -- Arrows: 1 unit, Shift 10. Plain characters (every font has them).
    local left  = makeButton(p, "<", 24, function() nudge(-1, 0) end)
    local right = makeButton(p, ">", 24, function() nudge(1, 0) end)
    local up    = makeButton(p, "^", 24, function() nudge(0, 1) end)
    local down  = makeButton(p, "v", 24, function() nudge(0, -1) end)
    left:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 8, 8)
    right:SetPoint("LEFT", left, "RIGHT", 2, 0)
    up:SetPoint("LEFT", right, "RIGHT", 2, 0)
    down:SetPoint("LEFT", up, "RIGHT", 2, 0)
    local reset = makeButton(p, "Reset", 52, function()
        local other = selected and mirrorOf(selected)   -- before the reset changes it
        if selected and Frames.ResetPosition(selected) then
            if other then Frames.ResetPosition(other) end
            refreshPanel()
        end
    end)
    reset:SetPoint("LEFT", down, "RIGHT", 8, 0)
    local lock = makeButton(p, "Lock", 44, function() Movers.Lock() end)
    lock:SetPoint("LEFT", reset, "RIGHT", 4, 0)
    p.buttons = { left = left, right = right, up = up, down = down, reset = reset, lock = lock }
    -- Snapping switches (Alt while dragging places freely).
    local function toggle(text, key, x, y, setter)
        local cb, templated = API.SafeFrame("CheckButton", p, "UICheckButtonTemplate", "text")
        cb:SetSize(20, 20)
        if not templated then
            cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
            cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        end
        cb:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(text)
        cb:SetChecked(Movers[key])
        cb:SetScript("OnClick", function(self) setter(key, self:GetChecked() and true or false) end)
        return cb
    end
    local function snap(key, on) GlassUF.Settings.SetSnap(key, on) end
    p.snapGrid = toggle("Snap to grid", "snapGrid", 8, -68, snap)
    p.snapAlign = toggle("Align to frames", "snapAlign", 120, -68, snap)
    p.mirror = toggle("Mirror player / target", "mirror", 8, -88, function(_, on) GlassUF.Settings.SetMirror(on) end)
    p:Hide()
    return p
end

-- Full-screen overlay: the grid (every GRID units from the screen centre,
-- the centre lines brighter) and the two guide lines.
-- (Re)draw the grid for the current screen: every GRID units from the screen
-- centre, the centre lines brighter; each line CENTRED on its spot, where the
-- snapped centres land. Reuses its textures; rebuilt when the size changed
-- (UI scale, resolution) since the last unlock.
local function drawGrid(o)
    local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    if o.gridW == w and o.gridH == h then return end
    o.gridW, o.gridH = w, h
    for _, t in ipairs(o.gridLines) do t:Hide() end
    local n, cx, cy = 0, w / 2, h / 2
    local function line(vertical, at, alpha)
        n = n + 1
        local t = o.gridLines[n] or o.grid:CreateTexture(nil, "BACKGROUND")
        o.gridLines[n] = t
        t:ClearAllPoints()
        t:SetColorTexture(1, 1, 1, alpha)
        if vertical then
            t:SetSize(1, h)
            t:SetPoint("BOTTOM", o, "BOTTOMLEFT", at, 0)
        else
            t:SetSize(w, 1)
            t:SetPoint("LEFT", o, "BOTTOMLEFT", 0, at)
        end
        t:Show()
    end
    for i = -math.floor(cx / GRID), math.floor(cx / GRID) do line(true, cx + i * GRID, i == 0 and 0.35 or 0.08) end
    for i = -math.floor(cy / GRID), math.floor(cy / GRID) do line(false, cy + i * GRID, i == 0 and 0.35 or 0.08) end
end

-- The overlay: the grid and the two guide lines, full screen, BELOW the
-- movers (they sit a few levels up in the same strata).
local function makeOverlay()
    local o = CreateFrame("Frame", nil, UIParent)
    o:SetAllPoints(UIParent)
    o:SetFrameStrata("DIALOG")
    o:SetFrameLevel(OVERLAY_LEVEL)
    local grid = CreateFrame("Frame", nil, o)
    grid:SetAllPoints(o)
    grid:SetFrameLevel(OVERLAY_LEVEL)
    o.grid, o.gridLines = grid, {}
    for _, k in ipairs({ "vguide", "hguide" }) do
        local g = o:CreateTexture(nil, "OVERLAY")
        g:SetColorTexture(1, 0.82, 0, 0.9)
        g:Hide()
        o[k] = g
    end
    o:Hide()
    return o
end

local function showGrid()
    if overlay then overlay.grid:SetShown(Movers.snapGrid) end
end

-- Show the movers. Refused in combat (returns false, "combat").
function Movers.Unlock()
    if InCombatLockdown() then return false, "combat" end
    if not next(Frames.byUnit) then return false, "not built" end
    panel = panel or makePanel()
    overlay = overlay or makeOverlay()
    drawGrid(overlay)
    overlay:Show()
    showGrid()
    Frames.NormalizeSaves()   -- older saves rewritten from the live rects, once
    for unit, b in pairs(Frames.byUnit) do
        movers[unit] = movers[unit] or makeMover(unit, b)
        movers[unit]:Show()
    end
    Movers.unlocked = true
    select_("target")
    return true
end

-- Hide the movers and finish any drag. Safe in combat.
function Movers.Lock()
    finishDrag()
    for _, m in pairs(movers) do m:Hide() end
    if panel then panel:Hide() end
    if overlay then overlay:Hide() end
    selected = nil
    Movers.unlocked = false
    return true
end

-- Drop a drag in flight WITHOUT saving it (a reset is about to run: it must
-- win), and bring the panel up to date afterwards.
function Movers.CancelDrag() endDrag(false) end

function Movers.Refresh() refreshPanel() end

-- Turn a snapping mode on or off (GlassUF.Settings.SetSnap saves it).
function Movers.SetSnap(key, on)
    if key ~= "snapGrid" and key ~= "snapAlign" then return false end
    Movers[key] = on and true or false
    -- The panel is reused across unlocks: keep its switch in step with a
    -- /glass snap change (Codex, #55).
    if panel and panel[key] then panel[key]:SetChecked(Movers[key]) end
    showGrid()
    return true
end

-- Saved switches, applied once the settings exist.
function Movers.Load(db)
    Movers.snapGrid = db.snapGrid ~= false
    Movers.snapAlign = db.snapAlign ~= false
    Movers.mirror = db.mirror ~= false
end

-- Mirroring on or off (GlassUF.Settings.SetMirror saves it).
function Movers.SetMirror(on)
    Movers.mirror = on and true or false
    if panel and panel.mirror then panel.mirror:SetChecked(Movers.mirror) end
end

-- Combat started: lock (a protected frame can't move under lockdown).
function Movers.OnCombat()
    if Movers.unlocked then Movers.Lock() end
end

Movers._test = { movers = movers, panel = function() return panel end,
                 overlay = function() return overlay end, alignAxis = alignAxis, alignLines = alignLines,
                 selected = function() return selected end, nudge = nudge }
