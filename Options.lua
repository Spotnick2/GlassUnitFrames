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
--
-- Sub-page "Cast bars" (#74): detach, scale and centre each cast bar, and the
-- player bar's latency / pushback switches. Registered right after the main
-- page (in order), hidden at creation (porting guide: a page created shown is
-- blank on its first visit).

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
-- A column lays out top to bottom on `parent` (the main page's scroll child
-- by default, or a sub-page).
local function column(x, top, parent)
    return { x = x, y = top, parent = parent or content }
end

local function place(col, region, height, indent)
    region:SetPoint("TOPLEFT", col.parent, "TOPLEFT", col.x + (indent or 0), col.y)
    col.y = col.y - height
end

local function header(col, text)
    col.y = col.y - 6
    place(col, label(col.parent, text, "GameFontNormalLarge"), 26)
end

local function note(col, text, width)
    local fs = label(col.parent, text, "GameFontHighlightSmall")
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
local function checkButton(text, radio, parent)
    parent = parent or content
    local cb, templated = safeFrame("CheckButton", parent, radio and "UIRadioButtonTemplate" or "UICheckButtonTemplate", "text")
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
    local fs = label(parent, text)
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
    local cb = checkButton(text, false, col.parent)
    place(col, cb, 28, 4)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    controls[#controls + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

-- Hand-built slider: label and value on one line, the track under it.
-- t = { label, min, max, step (default 0.05), get(), set(v) }.
local SLIDER_W = 240
local function slider(col, t)
    local parent, step = col.parent, t.step or 0.05
    local fs = label(parent, t.label)
    local value = label(parent, "")
    value:SetPoint("LEFT", fs, "LEFT", SLIDER_W + 12, 0)
    place(col, fs, 18, 4)
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(SLIDER_W, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(t.min, t.max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    place(col, s, 26, 8)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        value:SetText(string.format("%.2f", v))
        if refreshing then return end
        t.set(v)
    end)
    controls[#controls + 1] = function()
        local v = t.get()
        s:SetValue(v)
        value:SetText(string.format("%.2f", v))
    end
    return s
end

-- A material knob (Glass.TUNABLES) as a slider.
local function tunableSlider(col, t)
    local s = slider(col, { label = t.label, min = t.min, max = t.max,
                            get = function() return Glass.STYLE[t.style] end,
                            set = function(v) GlassUF.Settings.SetTunable(t, v) end })
    s.tunable = t
    return s
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- Shipped look back (knobs and font), saved values forgotten.
function Options.ResetLook() GlassUF.Settings.ResetLook() end

-- Unlock, closing the Settings window, or the movers would sit behind it.
function Options.Unlock()
    if GlassUF.Settings.Unlock() then
        -- Close through the panel's own Close (it commits or prompts for
        -- other pages' changes), not a bare hide.
        local sp = rawget(_G, "SettingsPanel")
        if sp and type(sp.Close) == "function" then pcall(sp.Close, sp)
        elseif sp and rawget(_G, "HideUIPanel") then pcall(HideUIPanel, sp) end
    end
end

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
    for _, t in ipairs(Glass.TUNABLES) do controls["slider_" .. t.key] = tunableSlider(left, t) end
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
    note(right, "On their own page: Glass Unit Frames > Cast bars.", 270)

    header(right, "Positions")
    place(right, button(content, "Unlock frames", 190, Options.Unlock), 30, 4)
    place(right, button(content, "Reset frame positions", 190, GlassUF.Settings.ResetPositions), 30, 4)

    -- Tall enough for the taller column; the scroll bar appears once that
    -- is more than the canvas shows.
    content:SetHeight(math.max(-left.y, -right.y) + 16)
end

--------------------------------------------------------------------------------
-- Cast bars (sub-page, #74)
--------------------------------------------------------------------------------

local castPage = CreateFrame("Frame", "GlassUnitFramesCastOptions")
castPage.name = "Cast bars"
castPage:Hide()   -- or the first visit shows it blank (porting guide)

local function buildCast()
    local Castbar, S = GlassUF.Castbar, GlassUF.Settings
    local title = label(castPage, "Cast bars", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", castPage, "TOPLEFT", 16, -16)
    local sub = label(castPage, "Detach a bar to give it its own glass bar on the screen. Unlock to drag it or set its size.",
        "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)
    local left, right = column(16, -72, castPage), column(380, -72, castPage)

    for _, o in ipairs({ { "player", "Your cast bar" }, { "target", "Your target's cast bar" } }) do
        local unit = o[1]
        if Castbar.bars[unit] then
            header(left, o[2])
            controls["castDetach_" .. unit] = checkbox(left, "Detached",
                function() return Castbar.IsDetached(unit) end,
                function(v)
                    S.SetCastDetached(unit, v)
                    controls.refreshAll()   -- Center follows the mode on this page (Codex, #75)
                end)
            controls["castScale_" .. unit] = slider(left, { label = "Scale (detached)", min = 0.5, max = 2,
                get = function() return Castbar.ScaleOf(unit) end,
                set = function(v) S.SetCastScale(unit, v) end })
            local center = button(castPage, "Center horizontally", 190, function() S.CenterCast(unit) end)
            place(left, center, 30, 4)
            controls["castCenter_" .. unit] = center
            -- Centring moves a detached bar only.
            controls[#controls + 1] = function() center:SetEnabled(Castbar.IsDetached(unit)) end
        end
    end

    header(right, "Your cast bar's extras")
    local CAST_OPTIONS = { { "latency", "Latency block at the end" }, { "latencyText", "Latency in ms (detached bar)" },
                           { "pushback", "Pushback before the time" } }
    for _, o in ipairs(CAST_OPTIONS) do
        local key = o[1]
        controls["cast_" .. key] = checkbox(right, o[2],
            function() return Castbar.options[key] end,
            function(v) S.SetCastOption(key, v) end)
    end
    note(right, "The block estimates the tail you can't cancel:", 270)
    note(right, "key press to cast start.", 270)

    header(right, "Positions")
    place(right, button(castPage, "Unlock frames", 190, Options.Unlock), 30, 4)
    note(right, "Drag a detached bar; its panel sets", 270)
    note(right, "X / Y, width, height and scale, or Attach.", 270)
end

castPage:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        buildCast()
    end
    controls.refreshAll()
end)

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
    -- The sub-page, right after the main page (sub-pages register in order).
    if Settings.RegisterCanvasLayoutSubcategory then
        local ok, err = pcall(Settings.RegisterCanvasLayoutSubcategory, category, castPage, castPage.name)
        if not ok then GlassUF.API.Fail("cast bars page", err) end
    else
        GlassUF.API.Fail("cast bars page", "no Settings subcategory API")
    end
end

-- Open the panel; false when the Settings framework can't (then /glass says where it is).
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

local reg = CreateFrame("Frame")
GlassUF.API.RegisterEvents(reg, { "PLAYER_LOGIN" })
reg:SetScript("OnEvent", register)

Options._test = { panel = panel, castPage = castPage, controls = controls, scroll = scroll, content = content }
