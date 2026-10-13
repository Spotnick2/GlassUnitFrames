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
    if title then place(col, label(col.parent, title), 22, 4) end
    local group = {}
    for _, o in ipairs(options) do
        local rb = checkButton(o[2], true, col.parent)
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
    local fs = label(col.parent, rowLabel)
    fs:SetWidth(labelWidth)
    place(col, fs, 0, 4)
    local group = {}
    for i, o in ipairs(options) do
        local rb = checkButton(o[2], true, col.parent)
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
-- t = { label, min, max, step (default 0.05), get(), set(v), fmt (default "%.2f"),
-- range() (optional: min, max now, read on every refresh) }.
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
        value:SetText(string.format(t.fmt or "%.2f", v))
        if refreshing then return end
        t.set(v)
    end)
    controls[#controls + 1] = function()
        if t.range then s:SetMinMaxValues(t.range()) end
        local v = t.get()
        s:SetValue(v)
        value:SetText(string.format(t.fmt or "%.2f", v))
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
        -- other pages' changes), not a bare hide. Close(true) skips the
        -- transition back to the Game Menu: plain Close() reopens it from our
        -- (tainted) call, and its Esc handler's protected SpellStopCasting is
        -- then blamed on us (ADDON_ACTION_FORBIDDEN, measured in game by
        -- GlassRaidFrames and by the owner here).
        local sp = rawget(_G, "SettingsPanel")
        if sp and type(sp.Close) == "function" then pcall(sp.Close, sp, true)
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

-- Colour swatches open the client's colour picker (ColorPickerFrame, in the
-- 70338 dump; DinoUF opens it the same way on Forever), above the Settings
-- window (HIGH strata). Cancel puts the colour back as it was, default or set.
local pickerStrata, pickerHooked   -- the picker's own strata while we've raised it
local function openPicker(key, hasAlpha, refresh)
    local cp = rawget(_G, "ColorPickerFrame")
    if not (cp and type(cp.SetupColorPickerAndShow) == "function") then
        GlassUF.API.Fail("colour picker", "no ColorPickerFrame:SetupColorPickerAndShow")
        return false
    end
    local Castbar, S = GlassUF.Castbar, GlassUF.Settings
    local cur = Castbar.colors[key] or Glass.STYLE.tint
    local r0, g0, b0, a0 = cur[1], cur[2], cur[3], cur[4] or 1
    local wasSet = type(db().castColors) == "table" and db().castColors[key] ~= nil
    local function same(x, y) return math.abs(x - y) < 0.001 end
    local edited = false
    local function apply()
        local r, g, b = cp:GetColorRGB()
        local a = 1
        if hasAlpha then a = (cp.GetColorAlpha and cp:GetColorAlpha()) or a0 end
        -- The picker reports its starting colour when it opens: an unchanged
        -- default stays a default (nothing saved), so a later default still
        -- reaches this player. Dragged away and back to it: the override goes
        -- (Codex, #79).
        if not wasSet and same(r, r0) and same(g, g0) and same(b, b0) and same(a, a0) then
            if edited then
                edited = false
                S.SetCastColor(key, nil)
                refresh()
            end
            return
        end
        edited = true
        S.SetCastColor(key, r, g, b, a)
        refresh()   -- this swatch only: a drag calls this many times a second
    end
    -- Above the Settings window (HIGH), and back to its own strata when it
    -- closes: the picker is shared with Blizzard and every addon.
    if not pickerStrata then
        local okS, strata = pcall(cp.GetFrameStrata, cp)
        pickerStrata = okS and strata or "DIALOG"
    end
    if not pickerHooked then   -- once: hooks can't be removed
        pickerHooked = true
        cp:HookScript("OnHide", function(self)
            if pickerStrata then
                pcall(self.SetFrameStrata, self, pickerStrata)
                pickerStrata = nil
            end
        end)
    end
    pcall(cp.SetFrameStrata, cp, "FULLSCREEN_DIALOG")
    local ok = pcall(cp.SetupColorPickerAndShow, cp, {
        r = r0, g = g0, b = b0, opacity = a0, hasOpacity = hasAlpha and true or false,
        swatchFunc = apply, opacityFunc = apply,
        cancelFunc = function()
            if wasSet then S.SetCastColor(key, r0, g0, b0, a0) else S.SetCastColor(key, nil) end
            refresh()
        end,
    })
    return ok
end

-- A colour swatch (a framed square) and its label.
local function swatch(parent, text, key, hasAlpha)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(b)
    edge:SetColorTexture(0.8, 0.8, 0.8, 1)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.fill = fill
    local fs = label(parent, text)
    fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
    local function refresh()
        local c = GlassUF.Castbar.colors[key] or Glass.STYLE.tint
        fill:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    b:SetScript("OnClick", function() openPicker(key, hasAlpha, refresh) end)
    controls[#controls + 1] = refresh
    return b
end

-- Which bar the per-bar controls act on (the "Settings for" row).
local castUnit = "player"

local function buildCast()
    local Castbar, S = GlassUF.Castbar, GlassUF.Settings
    local title = label(castPage, "Cast bars", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", castPage, "TOPLEFT", 16, -16)
    local sub = label(castPage, "Detach a bar to give it its own glass bar on the screen. Unlock to drag it.",
        "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)
    local left, right = column(16, -64, castPage), column(380, -64, castPage)

    controls.castSwatches = {}
    -- Per bar: pick one, then its controls.
    header(left, "Bar")
    local BARS = {}
    for _, o in ipairs({ { "player", "You" }, { "target", "Target" }, { "focus", "Focus" }, { "pet", "Pet" },
                         { "swing", "Swing" } }) do
        if Castbar.bars[o[1]] then BARS[#BARS + 1] = o end
    end
    controls.castBarRow = radioRow(left, "Settings for", BARS,
        function() return castUnit end,
        function(unit) castUnit = unit end,
        84, { 0, 48, 110, 166, 214 })
    controls.castDetach = checkbox(left, "Detached",
        function() return Castbar.IsDetached(castUnit) end,
        function(v)
            S.SetCastDetached(castUnit, v)
            controls.refreshAll()   -- Center follows the mode on this page (Codex, #75)
        end)
    controls.castIcon = radioRow(left, "Spell icon", { { "left", "Left" }, { "right", "Right" }, { "none", "None" } },
        function() return Castbar.IconSide(castUnit) end,
        function(side) S.SetCastIcon(castUnit, side) end,
        84, { 0, 60, 128 })
    -- The swing rows have no spell icon.
    controls[#controls + 1] = function()
        for _, rb in ipairs(controls.castIcon) do rb:SetEnabled(castUnit ~= "swing") end
    end
    controls.castWidth = slider(left, { label = "Width (detached)", min = 80, max = 800, step = 1, fmt = "%d",
        get = function() return (Castbar.SizeOf(castUnit)) end,
        set = function(v) S.SetCastSize(castUnit, v, nil) end })
    controls.castHeight = slider(left, { label = "Height (detached)", min = 12, max = 40, step = 1, fmt = "%d",
        -- A swing row is thin: its own limits (one row's height).
        range = function()
            local lim = (Castbar.LIMITS_FOR[castUnit] or {}).h or Castbar.LIMITS.h
            return lim[1], lim[2]
        end,
        get = function() return select(2, Castbar.SizeOf(castUnit)) end,
        set = function(v) S.SetCastSize(castUnit, nil, v) end })
    controls.castScale = slider(left, { label = "Scale (detached)", min = 0.5, max = 2,
        get = function() return Castbar.ScaleOf(castUnit) end,
        set = function(v) S.SetCastScale(castUnit, v) end })
    local center = button(castPage, "Center horizontally", 190, function() S.CenterCast(castUnit) end)
    place(left, center, 30, 4)
    controls.castCenter = center
    -- Centring moves a detached bar only.
    controls[#controls + 1] = function() center:SetEnabled(Castbar.IsDetached(castUnit)) end

    header(left, "Positions")
    place(left, button(castPage, "Unlock frames", 190, Options.Unlock), 30, 4)
    note(left, "Drag a detached bar; its panel sets X / Y, size and scale, or Attach.", 340)

    -- The swing timer (#87): ours, and Blizzard's own option (a CVar, clicked only).
    local Swing = GlassUF.Swing
    header(left, "Swing timer")
    controls.swingTimer = checkbox(left, "Glass swing timer (main hand, off hand, ranged)",
        function() return Swing.enabled end,
        function(v) S.SetSwingTimer(v) end)
    local blizz = checkButton("Show Blizzard's swing bars", false, castPage)
    place(left, blizz, 28, 4)
    controls.blizzardSwing = blizz
    -- Its value and state follow the client while the page is open: the CVar
    -- can change elsewhere, and it can't be set in combat (InCombatLockdown is
    -- still false inside PLAYER_REGEN_DISABLED, so the event says which).
    local function syncBlizz(inCombat)
        if inCombat == nil then inCombat = InCombatLockdown() end
        blizz:SetChecked(Swing.BlizzardShown())
        blizz:SetEnabled(not inCombat)
    end
    blizz:SetScript("OnClick", function(self)
        if not InCombatLockdown() then S.SetBlizzardSwing(self:GetChecked() and true or false) end
        syncBlizz()   -- a refused write snaps back
    end)
    controls[#controls + 1] = function() syncBlizz() end
    -- The page's own watcher, whatever the glass rows do (they unregister
    -- their events when turned off: Codex, #88).
    local combatWatch = CreateFrame("Frame")
    GlassUF.API.RegisterEvents(combatWatch, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE" })
    combatWatch:SetScript("OnEvent", function(_, event, name)
        if not castPage:IsShown() then return end
        if event == "CVAR_UPDATE" then
            if not GlassUF.API.IsSecret(name) and name == "showSwingTimer" then syncBlizz() end
        else
            syncBlizz(event == "PLAYER_REGEN_DISABLED")
        end
    end)
    controls.combatWatch = combatWatch
    local SWING_SWATCHES = { { "swingMH", "Main hand" }, { "swingOH", "Off hand" }, { "swingRanged", "Ranged" } }
    for i, o in ipairs(SWING_SWATCHES) do
        local sw = swatch(castPage, o[2], o[1])
        local x = (i % 2 == 1) and 4 or 144
        sw:SetPoint("TOPLEFT", castPage, "TOPLEFT", left.x + x, left.y)
        if i % 2 == 0 or i == #SWING_SWATCHES then left.y = left.y - 26 end
        controls.castSwatches[o[1]] = sw
    end

    -- Every bar.
    header(right, "Text")
    controls.castPrecision = slider(right, { label = "Cast time precision", min = 0, max = 3, step = 1, fmt = "%d",
        get = function() return Castbar.precision end,
        set = function(v) S.SetCastPrecision(v) end })
    for _, o in ipairs({ { "totalTime", "Remaining / total time" }, { "targetName", "Spell -> target on your bar" },
                         { "complete", "Flash when a cast completes" } }) do
        local key = o[1]
        controls["cast_" .. key] = checkbox(right, o[2],
            function() return Castbar.options[key] end,
            function(v) S.SetCastOption(key, v) end)
    end

    header(right, "Colours")
    local SWATCHES = { { "spell", "Spell text" }, { "time", "Time text" }, { "cast", "Casting" },
                       { "channel", "Channeling" }, { "complete", "Complete" }, { "failed", "Failed" },
                       { "spark", "Spark", true }, { "background", "Background", true } }
    for i, o in ipairs(SWATCHES) do
        local sw = swatch(castPage, o[2], o[1], o[3])
        -- Two per row.
        local x = (i % 2 == 1) and 4 or 144
        sw:SetPoint("TOPLEFT", castPage, "TOPLEFT", right.x + x, right.y)
        if i % 2 == 0 or i == #SWATCHES then right.y = right.y - 26 end
        controls.castSwatches[o[1]] = sw
    end
    place(right, button(castPage, "Reset colours", 140, function()
        S.ResetCastColors()
        controls.refreshAll()
    end), 30, 4)

    header(right, "Your cast bar")
    local CAST_OPTIONS = { { "latency", "Latency block at the end" }, { "latencyText", "Latency in ms" },
                           { "pushback", "Pushback before the time" } }
    for _, o in ipairs(CAST_OPTIONS) do
        local key = o[1]
        controls["cast_" .. key] = checkbox(right, o[2],
            function() return Castbar.options[key] end,
            function(v) S.SetCastOption(key, v) end)
    end
end

castPage:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        buildCast()
    end
    controls.refreshAll()
end)

--------------------------------------------------------------------------------
-- Combat zoom (sub-page, #89)
--------------------------------------------------------------------------------

local zoomPage = CreateFrame("Frame", "GlassUnitFramesZoomOptions")
zoomPage.name = "Combat zoom"
zoomPage:Hide()   -- or the first visit shows it blank (porting guide)

local ZOOM_LABELS = { player = "Your cast bar", target = "Target cast bar", focus = "Focus cast bar",
                      pet = "Pet cast bar", swing = "Swing timer" }

local function buildZoom()
    local Zoom, S = GlassUF.Zoom, GlassUF.Settings
    local title = label(zoomPage, "Combat zoom", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", zoomPage, "TOPLEFT", 16, -16)
    local sub = label(zoomPage, "In combat, a bar glides to its combat spot, bigger, and back home after.",
        "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)
    local left, right = column(16, -64, zoomPage), column(380, -64, zoomPage)

    header(left, "Bars")
    controls.zoomBars = {}
    -- Every bar, built or not: the page may first show before a build deferred by combat.
    for _, bar in ipairs(Zoom.BARS) do
        controls.zoomBars[bar] = checkbox(left, ZOOM_LABELS[bar] .. ": zoom in combat",
            function() return Zoom.Enabled(bar) end,
            function(v) S.SetZoom(bar, v) end)
        controls["zoomScale_" .. bar] = slider(left, { label = "Combat scale", min = 0.5, max = 2.5,
            get = function() return Zoom.Entry(bar).scale end,
            set = function(v) S.SetZoomScale(bar, v) end })
    end

    header(right, "This character")
    controls.zoomRole = radios(right, nil, { { "global", "Global" }, { "healer", "Healer" },
                                             { "tank", "Tank" }, { "dps", "DPS" } },
        function() return Zoom.role or "global" end,
        function(r) S.SetZoomRole(r ~= "global" and r or nil) end)
    local editing = label(zoomPage, "", "GameFontHighlightSmall")
    place(right, editing, 22, 4)
    controls.zoomEditing = editing
    controls[#controls + 1] = function()
        local key = Zoom.EditedKey()
        editing:SetText(key == "global" and "Editing the global settings."
            or ("Editing the " .. key .. " settings (this character is a " .. key .. ")."))
    end
    note(right, "A role uses its own settings once you change one; until then, the global ones.", 330)
    note(right, "Pick a role here to edit its settings.", 330)
    header(right, "Combat spots")
    place(right, button(zoomPage, "Unlock frames", 190, Options.Unlock), 30, 4)
    note(right, "Each bar that zooms shows a yellow outline at its combat spot: drag it.", 330)
end

zoomPage:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        buildZoom()
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
        ok, err = pcall(Settings.RegisterCanvasLayoutSubcategory, category, zoomPage, zoomPage.name)
        if not ok then GlassUF.API.Fail("combat zoom page", err) end
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

Options._test = { panel = panel, castPage = castPage, zoomPage = zoomPage, controls = controls, scroll = scroll,
                  content = content }
