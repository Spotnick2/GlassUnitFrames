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

local function relName(rel)
    if rel == "UIParent" then return "the screen centre" end
    return NAMES[rel] or rel
end

-- The mover's centre as offsets from the frame's leader (or the screen).
local function offsetsFromMover(m)
    local _, _, rel = Frames.PositionOf(m.unit)
    local mx, my = m:GetCenter()
    local relFrame = (rel == "UIParent") and UIParent or Frames.byUnit[rel]
    -- Not `relFrame and relFrame:GetCenter()`: `and` keeps only the first return.
    local rx, ry
    if relFrame then rx, ry = relFrame:GetCenter() end
    if type(mx) ~= "number" or type(rx) ~= "number" or type(ry) ~= "number" then return nil end
    return mx - rx, my - ry
end

local function refreshPanel()
    if not (panel and selected) then return end
    local x, y, rel = Frames.PositionOf(selected)
    panel.title:SetText(NAMES[selected] or selected)
    panel.sub:SetText("offsets from " .. relName(rel))
    if not panel.x:HasFocus() then panel.x:SetText(string.format("%g", x or 0)) end
    if not panel.y:HasFocus() then panel.y:SetText(string.format("%g", y or 0)) end
end

-- Finish a drag in flight: the last position the frame took is saved. Safe
-- in combat (only the insecure mover and a table write are touched).
local function finishDrag()
    local m = dragging
    if not m then return end
    dragging = nil
    m:SetScript("OnUpdate", nil)
    m:StopMovingOrSizing()
    if m.lastX then
        -- The frame already sits there (applied live before any lockdown);
        -- record it. In combat only the table is written, never the frame.
        if InCombatLockdown() then
            Frames.db.pos[m.unit] = { "CENTER", Frames.byUnit[m.unit].layout.anchorTo or "UIParent",
                                      "CENTER", m.lastX, m.lastY }
        else
            Frames.SetPosition(m.unit, m.lastX, m.lastY)
        end
    end
    m.lastX, m.lastY = nil, nil
    m:ClearAllPoints()
    m:SetAllPoints(Frames.byUnit[m.unit])
end

local function follow(m)
    if InCombatLockdown() then finishDrag(); return end
    local x, y = offsetsFromMover(m)
    if x and Frames.SetPosition(m.unit, x, y, true) then
        m.lastX, m.lastY = math.floor(x * 2 + 0.5) / 2, math.floor(y * 2 + 0.5) / 2
    end
end

local function select_(unit)
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
    if Frames.SetPosition(selected, x + dx * step, y + dy * step) then refreshPanel() end
end

local function makeEdit(parent, onCommit)
    local ok, e = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
    if not ok or not e then e = CreateFrame("EditBox", nil, parent) end
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
    local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not ok or not b then b = CreateFrame("Button", nil, parent) end
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function makePanel()
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(100)
    p:SetSize(250, 96)
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
        Frames.SetPosition(selected, v, y)
    end)
    p.x:SetPoint("LEFT", xl, "RIGHT", 8, 0)
    local yl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yl:SetPoint("LEFT", p.x, "RIGHT", 10, 0)
    yl:SetText("Y")
    p.y = makeEdit(p, function(v)
        local x = Frames.PositionOf(selected)
        Frames.SetPosition(selected, x, v)
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
        if selected and Frames.ResetPosition(selected) then refreshPanel() end
    end)
    reset:SetPoint("LEFT", down, "RIGHT", 8, 0)
    local lock = makeButton(p, "Lock", 44, function() Movers.Lock() end)
    lock:SetPoint("LEFT", reset, "RIGHT", 4, 0)
    p.buttons = { left = left, right = right, up = up, down = down, reset = reset, lock = lock }
    p:Hide()
    return p
end

-- Show the movers. Refused in combat (returns false, "combat").
function Movers.Unlock()
    if InCombatLockdown() then return false, "combat" end
    if not next(Frames.byUnit) then return false, "not built" end
    panel = panel or makePanel()
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
    selected = nil
    Movers.unlocked = false
    return true
end

-- Combat started: lock (a protected frame can't move under lockdown).
function Movers.OnCombat()
    if Movers.unlocked then Movers.Lock() end
end

Movers._test = { movers = movers, panel = function() return panel end,
                 selected = function() return selected end, nudge = nudge }
