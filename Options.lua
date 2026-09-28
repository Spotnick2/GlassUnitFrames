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

-- Two columns, each laid out top to bottom: the panel must fit the Settings
-- canvas without scrolling (one column overflowed it in game).
local function column(x, top)
    return { x = x, y = top }
end

local function place(col, region, height, indent)
    region:SetPoint("TOPLEFT", panel, "TOPLEFT", col.x + (indent or 0), col.y)
    col.y = col.y - height
end

local function header(col, text)
    col.y = col.y - 6
    place(col, label(panel, text, "GameFontNormalLarge"), 26)
end

local function note(col, text, width)
    local fs = label(panel, text, "GameFontHighlightSmall")
    fs:SetWidth(width or 400)
    place(col, fs, 18, 4)
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

-- A labelled check button: UICheckButtonTemplate / UIRadioButtonTemplate when
-- the client has them (both ship here, per Priestly), else our own art.
local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed
local function checkButton(text, radio)
    local cb, templated = safeFrame("CheckButton", panel, radio and "UIRadioButtonTemplate" or "UICheckButtonTemplate", "text")
    if not templated then
        if radio then
            cb:SetSize(16, 16)
            cb:SetNormalTexture(RADIO_ART)
            cb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
            cb:SetCheckedTexture(RADIO_ART)
            cb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
            cb:SetHighlightTexture(RADIO_ART)
            cb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
        else
            cb:SetSize(24, 24)
            cb:SetNormalTexture(CHECK_ART.normal)
            cb:SetPushedTexture(CHECK_ART.pushed)
            cb:SetHighlightTexture(CHECK_ART.highlight)
            cb:SetCheckedTexture(CHECK_ART.checked)
        end
    elseif not radio then
        cb:SetSize(24, 24)
    end
    local fs = label(panel, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = fs
    return cb
end

-- Mutually exclusive choices as radio buttons: { {value, text}, ... }.
local function radios(col, title, options, get, set)
    place(col, label(panel, title), 22, 4)
    local group = {}
    for _, o in ipairs(options) do
        local rb = checkButton(o[2], true)
        rb.value = o[1]
        -- Re-sync the whole group either way: a refused choice snaps back.
        rb:SetScript("OnClick", function()
            set(o[1])
            controls.refreshAll()
        end)
        place(col, rb, 22, 8)
        group[#group + 1] = rb
    end
    controls[#controls + 1] = function()
        local current = get()
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
    end
    return group
end

local function checkbox(col, text, get, set)
    local cb = checkButton(text, false)
    place(col, cb, 28, 4)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    controls[#controls + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

-- Template-free slider (OptionsSliderTemplate isn't on this client): label
-- and value on one line, the track under it. Steps of 0.05.
local SLIDER_W = 240
local function slider(col, t)
    local fs = label(panel, t.label)
    local value = label(panel, "")
    value:SetPoint("LEFT", fs, "LEFT", SLIDER_W + 12, 0)
    place(col, fs, 18, 4)
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
    place(col, s, 26, 8)
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
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    local sub = label(panel, "Liquid-glass unit frames. Shift-drag a frame to move it (out of combat). /glass lists the commands.",
        "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)

    local left, right = column(16, -72), column(400, -72)

    header(left, "Look")
    radios(left, "Font", { { "arial", "Arial Narrow" }, { "friz", "Friz Quadrata" } },
        function() return Glass.fontKey end,
        function(v)
            if not Glass.SetFont(v) then return false end
            db().font = v
            return true
        end)
    left.y = left.y - 6
    for _, t in ipairs(Glass.TUNABLES) do controls["slider_" .. t.key] = slider(left, t) end
    place(left, button(panel, "Reset look to defaults", 190, function()
        Options.ResetLook()
        controls.refreshAll()
    end), 30, 4)

    header(right, "Raid mark")
    radios(right, "Placement", { { "name", "Before the name" }, { "top", "On the top edge" }, { "right", "Right of the frame" } },
        function() return Frames.markPos end,
        function(v)
            if not Frames.SetMarkPosition(v) then return false end
            db().mark = v
            return true
        end)

    header(right, "Blizzard frames")
    controls.hideBlizzard = checkbox(right, "Hide Blizzard's frames for the units GlassUF draws",
        function() return db().hideBlizzard end,
        function(v) db().hideBlizzard = v end)
    controls.hideBlizzardCast = checkbox(right, "Also hide Blizzard's player cast bar",
        function() return db().hideBlizzardCast end,
        function(v) db().hideBlizzardCast = v or nil end)
    note(right, "Both take effect after a /reload.")

    header(right, "Positions")
    place(right, button(panel, "Reset frame positions", 190, function()
        GlassUF.WhenOutOfCombat("reset", function() Frames.ResetPositions() end,
            "positions reset when combat ends")
    end), 30, 4)
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
