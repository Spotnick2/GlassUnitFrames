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
-- Two FIXED rows under the cast lane. Debuffs on top: on a hostile target your
-- DoTs are what matters mid-fight, and they no longer sit under an empty buff
-- row. Rows cannot be chained: anchoring a frame to an aura container is
-- refused in game ("Anchoring disallowed as dependent object would inherit
-- forbidden aspects: UntrustedLayoutScriptExecution", 70009).
Auras.ROWS = {
    { key = "debuffs", filter = "HARMFUL|INCLUDE_NAME_PLATE_ONLY", y = -32 },
    { key = "buffs",   filter = "HELPFUL",                        y = -55 },
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
    local dur = Glass.Font(over, 8, "CENTER")
    try("aura duration", button, "SetDurationText", dur, {})
    dur:ClearAllPoints()
    dur:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)

    local count = Glass.Font(over, 9, "RIGHT")
    try("aura count", button, "SetApplicationCount", count, {})
    count:ClearAllPoints()
    count:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
end

local function flowLayout(c)
    local axis, right, down = API.FlowLayout()
    try("aura layout", c, "SetFlowLayoutAnchorPoint", "TOPLEFT")
    if axis then try("aura layout", c, "SetFlowLayoutAxis", axis) end
    try("aura layout", c, "SetFlowLayoutMaximumLineSize", ROW_W)
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
            initializeFrame = styleButton,
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
end
