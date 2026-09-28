-- GlassUnitFrames options panel (#39): Game Menu > Options > AddOns >
-- GlassUnitFrames. A canvas panel registered with Retail's Settings framework
-- (Settings.RegisterCanvasLayoutCategory + RegisterAddOnCategory, as Priestly
-- does on Forever). Classic option templates (OptionsSliderTemplate,
-- InterfaceOptionsCheckButtonTemplate) are not part of this client and
-- UIDropDownMenu is a Retail-migration trap, so the controls are our own:
-- template-free sliders, check buttons with their own art when the template
-- is missing, and rows of buttons for choices.
--
-- Everything the panel changes goes through the same setters as /glass, and
-- the panel re-reads the current state every time it opens, so a change made
-- with a slash command never leaves it showing stale values.

GlassUF = GlassUF or {}
local Options = {}
GlassUF.Options = Options

local Glass, Frames, Blizzard = GlassUF.Glass, GlassUF.Frames, GlassUF.Blizzard

local panel = CreateFrame("Frame", "GlassUnitFramesOptions")
panel.name = "GlassUnitFrames"
local controls = {}      -- refresh() callbacks, run on every OnShow
local refreshing = false -- set while syncing controls, so a SetValue doesn't save
local category

local function db() return GlassUnitFramesDB end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local CHECK_ART = {
    normal    = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed    = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked   = "Interface\\Buttons\\UI-CheckBox-Check",
}

-- CreateFrame with a template that may not exist on this client: a missing
-- template doesn't throw, it returns a bare frame, so `proof` names a field
-- the template would have created (Priestly, docs/FOREVER-PROBE.md).
local function safeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

local function label(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- Lays controls out top to bottom.
local y = -16
local function place(region, height, x)
    region:SetPoint("TOPLEFT", panel, "TOPLEFT", x or 16, y)
    y = y - height
end

local function header(text)
    y = y - 8
    place(label(panel, text, "GameFontNormalLarge"), 26)
end

local function note(text)
    local fs = label(panel, text, "GameFontHighlightSmall")
    fs:SetWidth(560)
    place(fs, 18, 20)
end

local function button(parent, text, width, onClick)
    local b, templated = safeFrame("Button", parent, "UIPanelButtonTemplate", "Text")
    b:SetSize(width, 22)
    if not templated then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0.2, 0.2, 0.25, 0.9)
        b:SetNormalFontObject("GameFontHighlight")
    end
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- A row of mutually exclusive choices: { {value, text}, ... }. The chosen one
-- stays highlighted.
local function choices(title, options, get, set)
    place(label(panel, title), 22, 20)
    local row, prev = {}, nil
    for _, o in ipairs(options) do
        local b = button(panel, o[2], 150, function()
            if set(o[1]) then controls.refreshAll() end
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else place(b, 30, 24) end
        b.value = o[1]
        row[#row + 1] = b
        prev = b
    end
    controls[#controls + 1] = function()
        local current = get()
        for _, b in ipairs(row) do
            if b.value == current then b:LockHighlight() else b:UnlockHighlight() end
        end
    end
    return row
end

local function checkbox(text, get, set)
    local cb, templated = safeFrame("CheckButton", panel, "UICheckButtonTemplate", "text")
    cb:SetSize(24, 24)
    if not templated then
        cb:SetNormalTexture(CHECK_ART.normal)
        cb:SetPushedTexture(CHECK_ART.pushed)
        cb:SetHighlightTexture(CHECK_ART.highlight)
        cb:SetCheckedTexture(CHECK_ART.checked)
    end
    local fs = label(panel, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    place(cb, 28, 20)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    controls[#controls + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

-- Template-free slider (OptionsSliderTemplate isn't on this client): track,
-- thumb and a value readout. Steps of 0.05.
local SLIDER_W = 220
local function slider(t)
    local fs = label(panel, t.label)
    place(fs, 20, 20)
    local s = CreateFrame("Slider", nil, panel)
    s:SetSize(SLIDER_W, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(t.min, t.max)
    s:SetValueStep(0.05)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local value = label(panel, "")
    value:SetPoint("LEFT", s, "RIGHT", 12, 0)
    place(s, 26, 24)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v * 20 + 0.5) / 20
        value:SetText(string.format("%.2f", v))
        if refreshing then return end
        if t.set(v) then db()[t.key] = v end
    end)
    controls[#controls + 1] = function()
        local v = Glass.STYLE[t.style]
        s:SetValue(v)
        value:SetText(string.format("%.2f", v))
    end
    s.tunable = t
    return s
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- Put every tunable back to its shipped default and forget the saved value,
-- so future default changes reach this player again.
function Options.ResetLook()
    for _, t in ipairs(Glass.TUNABLES) do
        t.set(t.default)
        db()[t.key] = nil
    end
end

local function build()
    local title = label(panel, "GlassUnitFrames", "GameFontNormalHuge")
    place(title, 30)
    note("Liquid-glass unit frames. Shift-drag a frame to move it (out of combat). /glass lists the commands.")

    header("Look")
    choices("Font", { { "arial", "Arial Narrow" }, { "friz", "Friz Quadrata" } },
        function() return Glass.fontKey end,
        function(v)
            if not Glass.SetFont(v) then return false end
            db().font = v
            return true
        end)
    for _, t in ipairs(Glass.TUNABLES) do controls["slider_" .. t.key] = slider(t) end
    place(button(panel, "Reset look to defaults", 190, function()
        Options.ResetLook()
        controls.refreshAll()
    end), 32, 24)

    header("Raid mark")
    choices("Placement", { { "name", "Before the name" }, { "top", "On the top edge" }, { "right", "Right of the frame" } },
        function() return Frames.markPos end,
        function(v)
            if not Frames.SetMarkPosition(v) then return false end
            db().mark = v
            return true
        end)

    header("Blizzard frames")
    controls.hideBlizzard = checkbox("Hide Blizzard's frames for the units GlassUF draws",
        function() return db().hideBlizzard end,
        function(v) db().hideBlizzard = v end)
    controls.hideBlizzardCast = checkbox("Also hide Blizzard's player cast bar",
        function() return db().hideBlizzardCast end,
        function(v) db().hideBlizzardCast = v or nil end)
    note("Both take effect after a /reload.")

    header("Positions")
    place(button(panel, "Reset frame positions", 190, function()
        GlassUF.WhenOutOfCombat("reset", function() Frames.ResetPositions() end,
            "positions reset when combat ends")
    end), 32, 24)
end

function controls.refreshAll()
    refreshing = true
    for _, fn in ipairs(controls) do pcall(fn) end
    refreshing = false
end

panel:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        build()
    end
    controls.refreshAll()
end)

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local function register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

-- Open the panel; false when the Settings framework can't (then /glass says where it is).
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

local reg = CreateFrame("Frame")
GlassUF.API.RegisterEvents(reg, { "PLAYER_LOGIN" })
reg:SetScript("OnEvent", register)

Options._test = { panel = panel, controls = controls }
