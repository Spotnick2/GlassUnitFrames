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
-- buttons (1 unit, Shift 10), reset this frame, lock; for a detached cast bar
-- (#74) also W/H and Attach. While unlocked, a glass dialog at the top centre
-- (Quartz's idea) says so, with Lock and the snapping / mirroring switches.
-- Out of combat only: a combat start locks everything; unlock and nudges are
-- refused in combat.

GlassUF = GlassUF or {}
local Movers = {}
GlassUF.Movers = Movers

local API, Frames = GlassUF.API, GlassUF.Frames

local NAMES = { player = "Player", target = "Target", pet = "Pet", targettarget = "Target of target",
                targettargettarget = "Target of target of target", focus = "Focus", focustarget = "Focus target" }
local TINT = { 0.30, 0.65, 1.00, 0.35 }

Movers.unlocked = false
local movers, selected, dragging = {}, nil, nil   -- keyed by source id; selected is an id
local panel, dialog

-- What a mover moves: a "source", one per draggable thing, keyed by an id (a
-- unit's id is its unit name). Movers reach positions only through it:
--   label, frame() (what the mover covers), rel() (the name and frame its
--   offsets are from), position() (x, y or nil), set(x, y, live) (ok, x, y;
--   out of combat), save(x, y) (the table only: safe in combat), reset(),
--   follows(id) (is it carried by that source?).
local sources = {}

-- Is `unit` carried by `leader` (anchored to it, directly or through a chain)?
local function followsFrom(unit, leader)
    local L = Frames.LAYOUT[unit]
    while L and L.anchorTo do
        if L.anchorTo == leader then return true end
        L = Frames.LAYOUT[L.anchorTo]
    end
    return false
end

-- The detached cast bars (#74) are sources too, "cast:<unit>", from
-- Castbar.MoverSource (which adds size, setSize and attach).
local function unitSource(unit)
    return {
        id = unit, label = NAMES[unit] or unit,
        frame = function() return Frames.byUnit[unit] end,
        rel = function() return Frames.AnchorOf(unit) end,
        position = function() return Frames.PositionOf(unit) end,
        set = function(x, y, live) return Frames.SetPosition(unit, x, y, live) end,
        save = function(x, y) return Frames.SavePosition(unit, x, y) end,
        reset = function() return Frames.ResetPosition(unit) end,
        follows = function(leader) return followsFrom(unit, leader) end,
    }
end

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

-- Place source `id` and, if given, its mirror `other` at -x (the one mirror
-- rule); `live` = a drag in flight (not saved yet). Returns ok and the
-- offsets applied to `id`.
local function place(id, x, y, live, other)
    local ok, ax, ay = sources[id].set(x, y, live)
    if not ok then return false end
    if other then sources[other].set(-ax, ay, live) end
    return true, ax, ay
end
local overlay   -- the grid and the guide lines, full screen, under the movers
local syncCast  -- defined below (needs endDrag and the movers)

local function relName(rel)
    if rel == "UIParent" then return "the screen centre" end
    return NAMES[rel] or rel
end

-- The mover's centre as offsets from the frame's leader (or the screen).
local snappedCenter, showGuide   -- defined below (need the snapping helpers)

local function offsetsFromMover(m)
    local _, relFrame = sources[m.id].rel()   -- what set() places it on
    local mx, my = snappedCenter(m)
    -- Not `relFrame and relFrame:GetCenter()`: `and` keeps only the first return.
    local rx, ry
    if relFrame then rx, ry = relFrame:GetCenter() end
    if type(mx) ~= "number" or type(rx) ~= "number" or type(ry) ~= "number" then return nil end
    return mx - rx, my - ry
end

local function refreshPanel()
    if not (panel and selected and sources[selected]) then return end
    local src = sources[selected]
    local x, y = src.position()
    panel.title:SetText(src.label)
    panel.sub:SetText("offsets from " .. relName((src.rel())))
    if not panel.x:HasFocus() then panel.x:SetText(x and string.format("%g", x) or "?") end
    if not panel.y:HasFocus() then panel.y:SetText(y and string.format("%g", y) or "?") end
    -- A detached cast bar also has a size and an Attach.
    local sized = src.size ~= nil
    panel:SetHeight(sized and 126 or 100)
    for _, r in ipairs(panel.sizeRow) do r:SetShown(sized) end
    panel.buttons.attach:SetShown(src.attach ~= nil)
    if sized then
        local w, h = src.size()
        if not panel.w:HasFocus() then panel.w:SetText(w and string.format("%g", w) or "?") end
        if not panel.h:HasFocus() then panel.h:SetText(h and string.format("%g", h) or "?") end
    end
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
            sources[m.id].save(m.lastX, m.lastY)
            if m.partner then sources[m.partner].save(-m.lastX, m.lastY) end
        else
            place(m.id, m.lastX, m.lastY, false, m.partner)
        end
    end
    m.lastX, m.lastY, m.lines, m.partner = nil, nil, nil, nil
    m:ClearAllPoints()
    m:SetAllPoints(sources[m.id].frame())
    showGuide("vguide", nil)
    showGuide("hguide", nil)
end

local function finishDrag() endDrag(true) end

-- The lines a dragged frame may align to on one axis: every other source's
-- two edges and centre (not the source itself, nor what moves with it), plus
-- the screen centre.
local function alignLines(id, axis)
    local lines = {}
    local ucx, ucy = UIParent:GetCenter()
    -- Not `axis == "x" and ucx or ucy`: a nil ucx would hand x the y centre.
    local centre
    if axis == "x" then centre = ucx else centre = ucy end
    if type(centre) == "number" then lines[#lines + 1] = centre end
    local m = movers[id]
    local partner = m and m.partner
    for sid, src in pairs(sources) do
        local b = src.frame()
        if b and sid ~= id and not src.follows(id) and sid ~= partner and not (partner and src.follows(partner)) then
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
            m.lines = m.lines or { x = alignLines(m.id, "x"), y = alignLines(m.id, "y") }
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
    local ok, ax, ay = place(m.id, x, y, true, m.partner)
    if ok then m.lastX, m.lastY = ax, ay end
end

local function select_(id)
    -- Switching frames discards a coordinate typed but not committed: its
    -- Enter would otherwise land on the NEW frame (Codex, #52).
    if panel and id ~= selected then
        panel.x:ClearFocus()
        panel.y:ClearFocus()
        panel.w:ClearFocus()
        panel.h:ClearFocus()
    end
    selected = id
    for mid, m in pairs(movers) do m.edge:SetShown(mid == id) end
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint("BOTTOM", movers[id], "TOP", 0, 8)
        panel:Show()
        refreshPanel()
    end
end

local function makeMover(src)
    local m = CreateFrame("Frame", nil, UIParent)
    m.id = src.id
    m:SetFrameStrata("DIALOG")
    m:SetFrameLevel(MOVER_LEVEL)   -- above the grid and guides
    m:SetAllPoints(src.frame())
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
    fs:SetText(src.label)
    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        select_(self.id)
        -- Mirror or not is decided now (Alt held = alone) and holds for the
        -- whole drag, so what's seen is what's saved.
        self.partner = (not IsAltKeyDown()) and mirrorOf(self.id) or nil
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
    m:SetScript("OnMouseUp", function(self) select_(self.id) end)
    m:Hide()
    return m
end

-- Nudge / type a position for the selected frame.
local function nudge(dx, dy)
    if not selected or InCombatLockdown() then return end
    local step = IsShiftKeyDown() and 10 or 1
    local x, y = sources[selected].position()
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

-- A check button with a label, for the dialog's switches.
local function makeToggle(parent, text, checked, onClick)
    local cb, templated = API.SafeFrame("CheckButton", parent, "UICheckButtonTemplate", "text")
    cb:SetSize(20, 20)
    if not templated then
        cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb.label = fs
    cb:SetChecked(checked)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end

local function makePanel()
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(100)
    p:SetSize(290, 100)
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
        if not sources[selected] then return end
        local _, y = sources[selected].position()
        if y then place(selected, v, y, false, mirrorOf(selected)) end
    end)
    p.x:SetPoint("LEFT", xl, "RIGHT", 8, 0)
    local yl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    yl:SetPoint("LEFT", p.x, "RIGHT", 10, 0)
    yl:SetText("Y")
    p.y = makeEdit(p, function(v)
        if not sources[selected] then return end
        local x = sources[selected].position()
        if x then place(selected, x, v, false, mirrorOf(selected)) end
    end)
    p.y:SetPoint("LEFT", yl, "RIGHT", 8, 0)
    -- Width / height: detached cast bars only (refreshPanel shows the row).
    local wl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    wl:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -68)
    wl:SetText("W")
    p.w = makeEdit(p, function(v)
        local src = sources[selected]
        if src and src.setSize then src.setSize(v, nil) end
    end)
    p.w:SetPoint("LEFT", wl, "RIGHT", 6, 0)
    local hl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hl:SetPoint("LEFT", p.w, "RIGHT", 10, 0)
    hl:SetText("H")
    p.h = makeEdit(p, function(v)
        local src = sources[selected]
        if src and src.setSize then src.setSize(nil, v) end
    end)
    p.h:SetPoint("LEFT", hl, "RIGHT", 8, 0)
    p.sizeRow = { wl, p.w, hl, p.h }
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
        if selected and sources[selected].reset() then
            if other then sources[other].reset() end
            refreshPanel()
        end
    end)
    reset:SetPoint("LEFT", down, "RIGHT", 8, 0)
    local lock = makeButton(p, "Lock", 44, function() Movers.Lock() end)
    lock:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 8)
    -- Attach: a detached cast bar back on its frame (its mover goes away).
    local attach = makeButton(p, "Attach", 56, function()
        local src = selected and sources[selected]
        if src and src.attach then src.attach() end
    end)
    attach:SetPoint("RIGHT", lock, "LEFT", -4, 0)
    p.buttons = { left = left, right = right, up = up, down = down, reset = reset, lock = lock, attach = attach }
    p:Hide()
    return p
end

-- The unlock dialog (#74, Quartz's idea): a glass panel at the top centre
-- while unlocked, with Lock and the snapping / mirroring switches.
local function makeDialog()
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetFrameLevel(90)   -- under the nudge panel (100), over the movers (10)
    d:SetSize(460, 66)
    d:SetPoint("TOP", UIParent, "TOP", 0, -40)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    -- Draggable (not saved), so a frame placed under it can still be reached.
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", function(self) self:StartMoving() end)
    d:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local g = GlassUF.Glass.Apply(d, "small")
    local text = g.top:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -10)
    text:SetText("Frames unlocked. Drag to move, click one to nudge. Alt: no snapping.")
    d.text = text
    d.lock = makeButton(d, "Lock", 60, function() Movers.Lock() end)
    d.lock:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -10, 9)
    local function snap(key, on) GlassUF.Settings.SetSnap(key, on) end
    d.snapGrid = makeToggle(d, "Snap to grid", Movers.snapGrid, function(on) snap("snapGrid", on) end)
    d.snapGrid:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 10, 9)
    d.snapAlign = makeToggle(d, "Align to frames", Movers.snapAlign, function(on) snap("snapAlign", on) end)
    d.snapAlign:SetPoint("LEFT", d.snapGrid, "RIGHT", 82, 0)
    d.mirror = makeToggle(d, "Mirror player / target", Movers.mirror, function(on) GlassUF.Settings.SetMirror(on) end)
    d.mirror:SetPoint("LEFT", d.snapAlign, "RIGHT", 92, 0)
    d:Hide()
    return d
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

-- The detached cast bars' sources (#74): one per detached bar, gone (with its
-- mover, its drag and its selection) once the bar is attached.
function syncCast()
    local Castbar = GlassUF.Castbar
    for unit in pairs(Castbar.bars) do
        local id = "cast:" .. unit
        if Castbar.IsDetached(unit) then
            sources[id] = sources[id] or Castbar.MoverSource(unit)
        elseif sources[id] then
            if dragging and dragging.id == id then endDrag(false) end
            sources[id] = nil
            if movers[id] then movers[id]:Hide() end
            if selected == id then
                selected = nil
                if panel then
                    for _, e in ipairs({ panel.x, panel.y, panel.w, panel.h }) do e:ClearFocus() end
                    panel:Hide()
                end
            end
        end
    end
end

-- A cast bar was detached or attached: while unlocked, its mover follows.
function Movers.SyncCastBars()
    if not Movers.unlocked then return end
    syncCast()
    for id, src in pairs(sources) do
        movers[id] = movers[id] or makeMover(src)
        movers[id]:Show()
    end
end

-- Show the movers. Refused in combat (returns false, "combat").
function Movers.Unlock()
    if InCombatLockdown() then return false, "combat" end
    if not next(Frames.byUnit) then return false, "not built" end
    panel = panel or makePanel()
    dialog = dialog or makeDialog()
    overlay = overlay or makeOverlay()
    drawGrid(overlay)
    overlay:Show()
    showGrid()
    Frames.NormalizeSaves()   -- older saves rewritten from the live rects, once
    for unit in pairs(Frames.byUnit) do
        sources[unit] = sources[unit] or unitSource(unit)
    end
    syncCast()
    for id, src in pairs(sources) do
        movers[id] = movers[id] or makeMover(src)
        movers[id]:Show()
    end
    dialog:Show()
    Movers.unlocked = true
    select_("target")
    return true
end

-- Hide the movers and finish any drag. Safe in combat.
function Movers.Lock()
    finishDrag()
    for _, m in pairs(movers) do m:Hide() end
    if panel then panel:Hide() end
    if dialog then dialog:Hide() end
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
    -- The dialog is reused across unlocks: keep its switch in step with a
    -- /glass snap change (Codex, #55).
    if dialog and dialog[key] then dialog[key]:SetChecked(Movers[key]) end
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
    if dialog and dialog.mirror then dialog.mirror:SetChecked(Movers.mirror) end
end

-- Combat started: lock (a protected frame can't move under lockdown).
function Movers.OnCombat()
    if Movers.unlocked then Movers.Lock() end
end

Movers._test = { movers = movers, panel = function() return panel end, dialog = function() return dialog end,
                 sources = sources,
                 overlay = function() return overlay end, alignAxis = alignAxis, alignLines = alignLines,
                 selected = function() return selected end, nudge = nudge }
