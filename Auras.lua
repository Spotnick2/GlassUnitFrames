-- Auras.lua: the target's buffs and debuffs, rendered by Blizzard's managed
-- aura container (CustomAuraContainerTemplate from Blizzard_AuraContainer).
--
-- The client selects, sorts and draws the auras, so their data (secret in
-- combat) never reaches Lua. We only declare the rows and style the buttons
-- the client creates. Design from a Codex consult of DinoUF and EllesmereUI
-- on this client (issue #12):
-- - declare the aura group BEFORE SetUnit: binding first leaves UNIT_AURA
--   unregistered (EllesmereUI_AuraKit.lua, FinishContainer);
-- - UpdateAllAuras() on every target change; the "target" token itself stays;
-- - never read aura data, never put scripts on the managed buttons, no 1.42
--   scaling (a DinoUF profile artefact), no retry timers (those were for the
--   player's own auras at login).
--
-- The container API is not in the API dump (it lives in a load-on-demand
-- Blizzard addon the dump did not capture); DinoUF ships it on Forever.

GlassUF = GlassUF or {}
local API, Glass = GlassUF.API, GlassUF.Glass
local Auras = {}
GlassUF.Auras = Auras

local ICON, GAP, PER_ROW = 20, 3, 13           -- 13 x 20 + 12 x 3 = 296 px, under a 300 px body
local ROW_W = PER_ROW * ICON + (PER_ROW - 1) * GAP

-- Offset of the lowest aura row's bottom edge under the body: whatever sits
-- under the rows (the target's cast bar) derives its position from this.
function Auras.Bottom()
    return Auras.ROWS[#Auras.ROWS].y - ICON
end
-- Two FIXED rows right under the unit frame (owner's layout, #32): buffs
-- first, debuffs below; the cast bar sits under both. Rows cannot be chained:
-- anchoring a frame to an aura container is refused in game ("Anchoring
-- disallowed as dependent object would inherit forbidden aspects:
-- UntrustedLayoutScriptExecution", 70009).
Auras.ROWS = {
    { key = "buffs",   filter = "HELPFUL",                        y = -4 },
    { key = "debuffs", filter = "HARMFUL|INCLUDE_NAME_PLATE_ONLY", y = -27 },
}

-- Call obj:method(...); a missing method or a throw is recorded (so
-- /glass secrets can say why auras are missing), never raised.
local function try(key, obj, method, ...)
    local fn = obj[method]
    if type(fn) ~= "function" then
        API.Fail(key, "missing method " .. method)
        return false
    end
    local ok, err = pcall(fn, obj, ...)
    if not ok then API.Fail(key, err) end
    return ok
end

-- The client creates each button; we give it the glass look and hand the
-- client the regions it fills (icon, swipe, stack count, duration text).
-- No scripts, no reads. `size` and the fonts: the rows' 20 px icons, or the
-- crowd-control icon's (#159).
local function styleButton(button, size, durFont, countFont)
    size, durFont, countFont = size or ICON, durFont or 8, countFont or 9
    button:SetSize(size, size)

    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(button)
    back:SetColorTexture(0, 0, 0, 0.6)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    try("aura icon", button, "SetIcon", icon)

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    cd:SetReverse(true)
    cd:SetSwipeColor(0, 0, 0, 0.4)
    cd:SetHideCountdownNumbers(true)          -- our duration text instead of Blizzard's numbers
    try("aura cooldown", button, "SetDurationCooldown", cd)

    -- Edge and text on an overlay ABOVE the cooldown frame, so the dark
    -- swipe doesn't dim them.
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints(button)
    over:SetFrameLevel(cd:GetFrameLevel() + 1)

    local edge = over:CreateTexture(nil, "OVERLAY", nil, 1)
    edge:SetAllPoints(over)
    edge:SetTexture(Glass.MEDIA .. "bar_edge")
    edge:SetTextureSliceMargins(8, 8, 8, 8)

    -- The client re-anchors the regions it registers (DinoUF re-asserts
    -- them), so place each one AFTER handing it over.
    local dur = Glass.Font(over, durFont, "CENTER")
    try("aura duration", button, "SetDurationText", dur, {})
    dur:ClearAllPoints()
    dur:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)

    local count = Glass.Font(over, countFont, "RIGHT")
    try("aura count", button, "SetApplicationCount", count, {})
    count:ClearAllPoints()
    count:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
end

local function flowLayout(c, lineSize)
    local axis, right, down = API.FlowLayout()
    try("aura layout", c, "SetFlowLayoutAnchorPoint", "TOPLEFT")
    if axis then try("aura layout", c, "SetFlowLayoutAxis", axis) end
    try("aura layout", c, "SetFlowLayoutMaximumLineSize", lineSize or ROW_W)
    if right and down then try("aura layout", c, "SetFlowLayoutGrowthDirection", right, down) end
    try("aura layout", c, "SetFlowLayoutPadding", 0, 0, 0, 0)
end

-- One container per row, built once, under the unit frame's body.
function Auras.Attach(b, body)
    local loaded, why = API.LoadBlizzardAddOn("Blizzard_AuraContainer")
    if not loaded then API.Fail("aura load", why) end   -- keep going: the type may exist anyway
    local sortMethod, sortDir = API.AuraSort()
    b.auraContainers = {}
    b.auraByKey = {}
    for _, row in ipairs(Auras.ROWS) do
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
        if not ok or not c then
            API.Fail("aura container", c)
            return
        end
        c:SetSize(ROW_W, ICON)
        -- Anchored to OUR frame only (never to another aura container).
        c:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 2, row.y)
        c:SetFrameLevel(b:GetFrameLevel() + 5)
        flowLayout(c)
        local added = try("aura group", c, "AddAuraGroup", "glass_" .. row.key, row.filter, {
            maxFrameCount = PER_ROW,
            initializeFrame = function(button) styleButton(button) end,
            candidateFilters = {},
            layout = { elementWidth = ICON, elementHeight = ICON, elementSpacing = GAP, lineSpacing = GAP },
            sortMethod = sortMethod,
            sortDirection = sortDir,
        })
        if added then
            -- The unit LAST, then a full refresh (see the header).
            try("aura unit", c, "SetUnit", b.unit)
            try("aura refresh", c, "UpdateAllAuras")
            b.auraContainers[#b.auraContainers + 1] = c
            b.auraByKey[row.key] = c
        else
            c:Hide()
        end
    end
end

-- A new target: re-evaluate what the containers show. Fine in combat.
function Auras.Refresh(b)
    for _, c in ipairs(b.auraContainers or {}) do try("aura refresh", c, "UpdateAllAuras") end
    if b.ccContainer then try("cc refresh", b.ccContainer, "UpdateAllAuras") end
end

--------------------------------------------------------------------------------
-- The crowd-control icon (#159): one large icon with the client's swipe and
-- timer while the target or focus is stunned, feared, rooted, silenced...
-- The client's own CROWD_CONTROL aura filter (AuraUtil.AuraFilters: "auras
-- that have a crowd control effect") picks it, in a container of its own:
-- nothing is read in Lua, so it works in combat. Built offline and off by
-- default: whether Forever's Vanilla rules flag anything as CC is unmeasured
-- (/fp steps cast cc). If nothing matches, #159 closes.
--
-- Placement, per unit (db.ccIcon[unit]):
-- - "portrait": over the portrait tile, covering the model while it lasts
--   (the tile's rim layer stays above it); with no tile shown, where the tile
--   would be, on the frame's portrait side (focus has none: its left, clear
--   of the focus target);
-- - "beside": the same icon at BESIDE_SCALE, outside the tile (or the body).
-- The container is anchored to our frames only, and nothing to it.
--------------------------------------------------------------------------------

Auras.CC_UNITS = { target = true, focus = true }
Auras.CC_MODES = { portrait = true, beside = true }
Auras.CC_FILTER = "HARMFUL|CROWD_CONTROL"
Auras.ccMode = {}   -- unit -> "portrait" | "beside"; nil = off
local CC_SIDE = { focus = "left" }   -- a frame with no portrait side
local BESIDE_SCALE, CC_GAP = 0.6, 3

-- The saved modes, validated (junk is off).
function Auras.ConfigureCC(db)
    local saved = type(db.ccIcon) == "table" and db.ccIcon or {}
    for unit in pairs(Auras.CC_UNITS) do
        local m = saved[unit]
        Auras.ccMode[unit] = (type(m) == "string" and Auras.CC_MODES[m]) and m or nil
    end
end

-- The icon's size: the portrait's own rect (the model's inset), so it covers it.
local function ccInset(b) return Glass.Inset(b.layout.size) - 1 end
local function ccSize(b) return b.layout.h - 2 * ccInset(b) end

local function buildCC(b)
    local loaded, why = API.LoadBlizzardAddOn("Blizzard_AuraContainer")
    if not loaded then API.Fail("aura load", why) end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not ok or not c then
        API.Fail("cc container", c)
        return
    end
    local size = ccSize(b)
    c:SetSize(size, size)
    -- Over the model, under the tile's rim layer.
    c:SetFrameLevel((b.tile and Glass.ContentLevel(b.tile) or b:GetFrameLevel()) + 2)
    flowLayout(c, size)
    local sortMethod, sortDir = API.AuraSort()
    local fontD, fontC = math.max(8, math.floor(size / 4)), math.max(9, math.floor(size / 4.5))
    local added = try("cc group", c, "AddAuraGroup", "glass_cc", Auras.CC_FILTER, {
        maxFrameCount = 1,
        initializeFrame = function(button) styleButton(button, size, fontD, fontC) end,
        candidateFilters = {},
        layout = { elementWidth = size, elementHeight = size, elementSpacing = 0, lineSpacing = 0 },
        sortMethod = sortMethod,
        sortDirection = sortDir,
    })
    if not added then
        c:Hide()
        return
    end
    try("cc unit", c, "SetUnit", b.unit)   -- the unit LAST (see the header)
    try("cc refresh", c, "UpdateAllAuras")
    b.ccContainer = c
end

-- Lay the icon out for its mode and the tile's state; off hides it. Out of
-- combat (the callers make sure): it is a child of the secure button.
function Auras.PlaceCC(b)
    local c = b.ccContainer
    if not c then return end
    -- A 3D <-> 2D switch re-places in combat: wait (it changes nothing there).
    if InCombatLockdown() then
        GlassUF.WhenOutOfCombat("cc:" .. b.unit, function() Auras.PlaceCC(b) end, false)
        return
    end
    local mode = Auras.ccMode[b.unit]
    if not mode then
        c:Hide()
        return
    end
    local tile = b.tile and b.portraitMode ~= "none" and b.tile or nil
    local scale = mode == "beside" and BESIDE_SCALE or 1
    c:ClearAllPoints()
    c:SetScale(scale)
    if mode == "portrait" and tile then
        c:SetPoint("CENTER", tile, "CENTER", 0, 0)
    else
        -- Outside the tile (beside) or the body (no tile); SetPoint offsets
        -- are in the container's scaled units. With no tile, the gap is the
        -- tile's: the icon's edge where the model's would be.
        local edge = (mode == "beside" and tile) or b.body
        local gap = (mode == "portrait") and (3 + ccInset(b)) or CC_GAP
        if (b.layout.portrait or CC_SIDE[b.unit]) == "right" then
            c:SetPoint("LEFT", edge, "RIGHT", gap / scale, 0)
        else
            c:SetPoint("RIGHT", edge, "LEFT", -gap / scale, 0)
        end
    end
    c:Show()
end

-- At build, and when a mode is set: the container the first time it's on.
function Auras.AttachCC(b)
    if not Auras.CC_UNITS[b.unit] then return end
    if Auras.ccMode[b.unit] and not b.ccContainer then buildCC(b) end
    Auras.PlaceCC(b)
end

-- A mode for a unit ("off" | "portrait" | "beside"), applied out of combat
-- (queued under WhenOutOfCombat in a fight, the last request winning).
function Auras.SetCCMode(unit, mode)
    if not Auras.CC_UNITS[unit] or not (mode == "off" or Auras.CC_MODES[mode]) then return false end
    Auras.ccMode[unit] = mode ~= "off" and mode or nil
    local b = GlassUF.Frames.byUnit[unit]
    if b then
        GlassUF.WhenOutOfCombat("cc:" .. unit, function()
            GlassUF.Frames.attempt("build cc", Auras.AttachCC, b)
        end, "the crowd-control icon changes when combat ends")
    end
    return true
end
