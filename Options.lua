-- GlassUnitFrames options panel (#39): Game Menu > Options > AddOns > Glass
-- Unit Frames. A canvas panel registered with Retail's Settings framework
-- (Settings.RegisterCanvasLayoutCategory + RegisterAddOnCategory, as Priestly
-- does on Forever). Check and radio buttons use UICheckButtonTemplate /
-- UIRadioButtonTemplate (both exist here, per the porting guide and Priestly),
-- with our own art only if one ever goes missing. The slider is hand-built on
-- purpose, for a compact label + value line (OptionsSliderTemplate exists too).
-- No UIDropDownMenu (a Retail-migration trap): choices are radio groups.
--
-- Everything the panel changes goes through GlassUF.Settings, the same
-- apply-and-save helpers as /glass, and
-- the panel re-reads the current state every time it opens, so a change made
-- with a slash command never leaves it showing stale values.

GlassUF = GlassUF or {}
local Options = {}
GlassUF.Options = Options

local Glass, Frames, Blizzard = GlassUF.Glass, GlassUF.Frames, GlassUF.Blizzard

local panel = CreateFrame("Frame", "GlassUnitFramesOptions")
panel.name = "Glass Unit Frames"
local controls = {}      -- refresh() callbacks, run on every OnShow
local refreshing = false -- set while syncing controls, so a SetValue doesn't save
local category

local function db() return GlassUnitFramesDB end

-- Everything sits in a scroll child: the panel is due to outgrow the Settings
-- canvas, and UIPanelScrollFrameTemplate exists on this client (porting guide).
-- Without the template, a plain ScrollFrame still clips and scrolls by wheel.
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(660, 600)
scroll:SetScrollChild(content)
if not scroll.ScrollBar then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local v = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
        self:SetVerticalScroll(v)
    end)
end
-- The template shows its bar even with nothing to scroll: show it only when
-- the content is taller than the canvas.
if scroll.ScrollBar then
    scroll:HookScript("OnScrollRangeChanged", function(self, _, yrange)
        self.ScrollBar:SetShown((yrange or self:GetVerticalScrollRange()) > 0)
    end)
end
-- Keep the content as wide as the visible area.
scroll:SetScript("OnSizeChanged", function(self, w)
    if type(w) == "number" and w > 0 then content:SetWidth(w) end
end)

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
local safeFrame = GlassUF.API.SafeFrame

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
    region:SetPoint("TOPLEFT", content, "TOPLEFT", col.x + (indent or 0), col.y)
    col.y = col.y - height
end

local function header(col, text)
    col.y = col.y - 6
    place(col, label(content, text, "GameFontNormalLarge"), 26)
end

local function note(col, text, width)
    local fs = label(content, text, "GameFontHighlightSmall")
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
    local cb, templated = safeFrame("CheckButton", content, radio and "UIRadioButtonTemplate" or "UICheckButtonTemplate", "text")
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
    local fs = label(content, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label = fs
    return cb
end

-- Mutually exclusive choices as radio buttons: { {value, text}, ... }.
local function radios(col, title, options, get, set)
    if title then place(col, label(content, title), 22, 4) end
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

-- The same, laid out side by side on one line after a row label (compact
-- grids: one row per frame). `offsets[i]` is radio i's x after the label, so a
-- long option ("cur/max") gets the room it needs.
local function radioRow(col, rowLabel, options, get, set, labelWidth, offsets)
    local fs = label(content, rowLabel)
    fs:SetWidth(labelWidth)
    place(col, fs, 0, 4)
    local group = {}
    for i, o in ipairs(options) do
        local rb = checkButton(o[2], true)
        rb.value = o[1]
        rb:SetScript("OnClick", function()
            set(o[1])
            controls.refreshAll()
        end)
        rb:SetPoint("LEFT", fs, "LEFT", labelWidth + offsets[i], 0)
        group[#group + 1] = rb
    end
    col.y = col.y - 24
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

-- Hand-built slider: label and value on one line, the track under it.
-- Steps of 0.05.
local SLIDER_W = 240
local function slider(col, t)
    local fs = label(content, t.label)
    local value = label(content, "")
    value:SetPoint("LEFT", fs, "LEFT", SLIDER_W + 12, 0)
    place(col, fs, 18, 4)
    local s = CreateFrame("Slider", nil, content)
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
        GlassUF.Settings.SetTunable(t, v)
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

-- Shipped look back (knobs and font), saved values forgotten.
function Options.ResetLook() GlassUF.Settings.ResetLook() end

local function build()
    local title = label(content, "Glass Unit Frames", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    local sub = label(content, "Liquid-glass unit frames. Unlock them below to move them. /glass lists the commands.",
        "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)

    local left, right = column(16, -72), column(400, -72)

    header(left, "Look")
    radios(left, "Font", { { "arial", "Arial Narrow" }, { "friz", "Friz Quadrata" } },
        function() return Glass.fontKey end,
        GlassUF.Settings.SetFont)
    left.y = left.y - 6
    for _, t in ipairs(Glass.TUNABLES) do controls["slider_" .. t.key] = slider(left, t) end
    place(left, button(content, "Reset look to defaults", 190, function()
        Options.ResetLook()
        controls.refreshAll()
    end), 30, 4)

    -- Health text per frame: one row each, the formats side by side.
    header(left, "Health text")
    local FORMATS = { { "curhp", "cur" }, { "curmaxhp", "cur/max" }, { "perhp", "%" }, { "curmaxhp_perhp", "both" } }
    local ROWS = { { "player", "Player" }, { "target", "Target" }, { "pet", "Pet" },
                   { "targettarget", "Target of target" }, { "focus", "Focus" }, { "focustarget", "Focus target" } }
    controls.healthRows = {}
    for _, r in ipairs(ROWS) do
        local unit = r[1]
        if Frames.byUnit[unit] and Frames.byUnit[unit].valueText then
            controls.healthRows[unit] = radioRow(left, r[2], FORMATS,
                function() return Frames.HealthFormatOf(unit) end,
                function(kind) return GlassUF.Settings.SetHealthFormat(unit, kind) end,
                100, { 0, 56, 140, 186 })
        end
    end

    header(right, "Raid mark")
    radios(right, "Placement", { { "name", "Before the name" }, { "top", "On the top edge" }, { "right", "Right of the frame" } },
        function() return Frames.markPos end,
        GlassUF.Settings.SetMark)

    -- The Settings canvas is only ~680 units wide: the right column keeps
    -- its labels short and its choices stacked.
    header(right, "Target level")
    controls.levelRow = radios(right, nil, { { "power", "On the power line" }, { "name", "Before the name" }, { "portrait", "On the portrait" } },
        function() return Frames.levelPos end,
        GlassUF.Settings.SetLevelPosition)

    header(right, "Pet happiness")
    controls.happinessRow = radios(right, nil, { { "left", "Left of the portrait" }, { "right", "Right of the frame" }, { "under", "Under the portrait" } },
        function() return Frames.happinessPos end,
        GlassUF.Settings.SetHappinessPosition)

    header(right, "Blizzard frames")
    controls.hideBlizzard = checkbox(right, "Hide Blizzard's unit frames",
        function() return db().hideBlizzard end,
        function(v) db().hideBlizzard = v end)
    controls.hideBlizzardCast = checkbox(right, "Hide Blizzard's player cast bar",
        function() return db().hideBlizzardCast end,
        function(v) db().hideBlizzardCast = v or nil end)
    note(right, "Both take effect after a /reload.", 270)

    header(right, "Colours")
    controls.aggroRed = checkbox(right, "Neutral NPCs turn red in a fight",
        function() return Frames.aggroRed end,
        GlassUF.Settings.SetAggroRed)
    note(right, "While they fight you or your group.", 270)

    header(right, "Cast bars")
    for _, o in ipairs({ { "player", "Detach the player's cast bar" }, { "target", "Detach the target's cast bar" } }) do
        local unit = o[1]
        if GlassUF.Castbar.bars[unit] then
            controls["castDetach_" .. unit] = checkbox(right, o[2],
                function() return GlassUF.Castbar.IsDetached(unit) end,
                function(v) GlassUF.Settings.SetCastDetached(unit, v) end)
        end
    end
    note(right, "Unlock to move or resize a detached bar; Attach puts it back.", 270)
    local CAST_OPTIONS = { { "latency", "Latency block at the end" }, { "latencyText", "Latency in ms (detached bar)" },
                           { "pushback", "Pushback before the time" } }
    for _, o in ipairs(CAST_OPTIONS) do
        local key = o[1]
        controls["cast_" .. key] = checkbox(right, o[2],
            function() return GlassUF.Castbar.options[key] end,
            function(v) GlassUF.Settings.SetCastOption(key, v) end)
    end
    note(right, "Your own casts only. The block estimates the tail you can't cancel: key press to cast start.", 270)

    header(right, "Positions")
    -- Unlocking closes the Settings window, or the movers would sit behind it.
    place(right, button(content, "Unlock frames", 190, function()
        if GlassUF.Settings.Unlock() then
            -- Close through the panel's own Close (it commits or prompts for
            -- other pages' changes), not a bare hide.
            local sp = rawget(_G, "SettingsPanel")
            if sp and type(sp.Close) == "function" then pcall(sp.Close, sp)
            elseif sp and rawget(_G, "HideUIPanel") then pcall(HideUIPanel, sp) end
        end
    end), 30, 4)
    place(right, button(content, "Reset frame positions", 190, GlassUF.Settings.ResetPositions), 30, 4)

    -- Tall enough for the taller column; the scroll bar appears once that
    -- is more than the canvas shows.
    content:SetHeight(math.max(-left.y, -right.y) + 16)
end

function controls.refreshAll()
    refreshing = true
    for i, fn in ipairs(controls) do
        local ok, err = pcall(fn)
        if not ok then GlassUF.API.Fail("options control " .. i, err) end   -- shows in /glass secrets
    end
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

Options._test = { panel = panel, controls = controls, scroll = scroll, content = content }
