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
Auras.ROWS = {
    { key = "buffs",   filter = "HELPFUL",                        y = -32 },  -- below the cast lane
    { key = "debuffs", filter = "HARMFUL|INCLUDE_NAME_PLATE_ONLY", y = -55 },
}

local function fail(key, err)
    if GlassUF.paintFailures and GlassUF.paintFailures[key] == nil then
        GlassUF.paintFailures[key] = tostring(err)
    end
end

-- Call obj:method(...) if the client has it; record a failure, never throw.
local function try(key, obj, method, ...)
    local fn = obj[method]
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, obj, ...)
    if not ok then fail(key, err) end
    return ok
end

-- The client creates each button; we give it the glass look and hand the
-- client the regions it fills (icon, swipe, stack count, duration text).
-- No scripts, no reads.
local function styleButton(button)
    button:SetSize(ICON, ICON)

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

    local edge = button:CreateTexture(nil, "OVERLAY", nil, 1)
    edge:SetAllPoints(button)
    edge:SetTexture(Glass.MEDIA .. "bar_edge")
    edge:SetTextureSliceMargins(8, 8, 8, 8)

    local dur = Glass.Font(button, 8, "CENTER")
    dur:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
    try("aura duration", button, "SetDurationText", dur, {})

    local count = Glass.Font(button, 9, "RIGHT")
    count:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    try("aura count", button, "SetApplicationCount", count, {})
end

local function ensureLoaded()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn) then return end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_AuraContainer")
    if ok and not loaded then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
end

local function flowLayout(c)
    local axis = rawget(_G, "AnchorUtil") and AnchorUtil.FlowLayoutAxis
    local dir = rawget(_G, "AnchorUtil") and AnchorUtil.FlowDirection
    try("aura layout", c, "SetFlowLayoutAnchorPoint", "TOPLEFT")
    if axis then try("aura layout", c, "SetFlowLayoutAxis", axis.Horizontal) end
    try("aura layout", c, "SetFlowLayoutMaximumLineSize", ROW_W)
    if dir then try("aura layout", c, "SetFlowLayoutGrowthDirection", dir.Right, dir.Down) end
    try("aura layout", c, "SetFlowLayoutPadding", 0, 0, 0, 0)
end

-- One container per row, built once, under the unit frame's body.
function Auras.Attach(b, body)
    ensureLoaded()
    local sortMethod = rawget(_G, "AuraContainerSortMethod")
    local sortDir = rawget(_G, "AuraContainerSortDirection")
    b.auraContainers = {}
    for _, row in ipairs(Auras.ROWS) do
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
        if not ok or not c then
            fail("aura container", c)
            return
        end
        c:SetSize(ROW_W, ICON)
        c:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 2, row.y)
        c:SetFrameLevel(b:GetFrameLevel() + 5)
        flowLayout(c)
        local added = try("aura group", c, "AddAuraGroup", "glass_" .. row.key, row.filter, {
            maxFrameCount = PER_ROW,
            initializeFrame = styleButton,
            candidateFilters = {},
            layout = { elementWidth = ICON, elementHeight = ICON, elementSpacing = GAP, lineSpacing = GAP },
            sortMethod = sortMethod and (sortMethod.ExpirationOnly or sortMethod.Default) or nil,
            sortDirection = sortDir and sortDir.Normal or nil,
        })
        if added then
            -- The unit LAST, then a full refresh (see the header).
            try("aura unit", c, "SetUnit", b.unit)
            try("aura refresh", c, "UpdateAllAuras")
            b.auraContainers[#b.auraContainers + 1] = c
        else
            c:Hide()
        end
    end
end

-- A new target: re-evaluate what the containers show. Fine in combat.
function Auras.Refresh(b)
    for _, c in ipairs(b.auraContainers or {}) do try("aura refresh", c, "UpdateAllAuras") end
end
