-- Options panel (#39): registered under Options > AddOns, built on first
-- show, every control wired to the same setters as /glass, and re-synced
-- from the current state each time it opens.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local O = GlassUF.Options
local panel, controls = O._test.panel, O._test.controls
local Glass = GlassUF.Glass

-- Registered with Retail's Settings framework at PLAYER_LOGIN.
eq(WoW.settings.canvas and WoW.settings.canvas.frame, panel, "canvas category registered for the panel")
eq(WoW.settings.addon, WoW.settings.canvas, "and added to Options > AddOns")
eq(WoW.settings.canvas.name, "Glass Unit Frames", "under the addon's display name")

-- /glass options opens it.
SlashCmdList.GLASSUNITFRAMES("options")
eq(WoW.settings.opened, 4242, "/glass options opens the category")

-- Built lazily on first show.
check(controls.slider_fill == nil, "nothing built before the panel is shown")
-- Hidden at creation, so Settings' first display fires OnShow and builds it
-- (created shown, that display fired nothing: a blank page, #104).
check(not panel._shown, "the main page is hidden at creation")
panel:Show()
check(controls.slider_fill ~= nil and controls.hideBlizzard ~= nil, "its first display builds it")
-- Everything lives in a scroll child, sized to the taller column.
local sc, content = O._test.scroll, O._test.content
eq(sc._scrollChild, content, "controls sit in the scroll frame's child")
eq(controls.slider_fill:GetParent(), content, "widgets are parented to the scroll child")
check(content._height > 400, "content height covers both columns: " .. tostring(content._height))
-- The scroll bar only shows when there is something to scroll.
local bar = CreateFrame("Slider", nil, sc)
sc.ScrollBar = bar
check(sc._scripts.OnScrollRangeChanged ~= nil, "scroll range watched")
sc._scripts.OnScrollRangeChanged(sc, 0, 0)
check(bar._shown == false, "nothing to scroll: bar hidden")
sc._scripts.OnScrollRangeChanged(sc, 0, 120)
check(bar._shown == true, "taller than the canvas: bar shown")

-- A slider drives the material and saves only what the player set.
local s = controls.slider_fill
eq(s._value, 0.6, "fill slider shows the current opacity")
s._scripts.OnValueChanged(s, 0.43)            -- rounded to a 0.05 step
eq(Glass.STYLE.fillAlpha, 0.45, "fill set through Glass (0.05 steps)")
eq(GlassUnitFramesDB.fill, 0.45, "and saved")
eq(GlassUnitFramesDB.rim, nil, "untouched knobs are not saved")

-- Opening re-syncs the controls from the current state (a slash change).
SlashCmdList.GLASSUNITFRAMES("rim 0.4")
panel._scripts.OnShow(panel)
eq(controls.slider_rim._value, 0.4, "a /glass change shows up the next time the panel opens")
eq(GlassUnitFramesDB.fill, 0.45, "re-syncing does not save anything by itself")
eq(GlassUnitFramesDB.track, nil, "re-syncing (SetValue fires OnValueChanged) saves no untouched knob")
eq(GlassUnitFramesDB.fade, nil, "nor this one")

-- Reset look: shipped defaults back (font included), saved values forgotten.
GlassUF.Settings.SetFont("friz")
O.ResetLook()
eq(Glass.STYLE.fillAlpha, 0.6, "reset: fill back to its default")
eq(Glass.STYLE.rimAlpha, 0.7, "reset: rim back to its default")
eq(GlassUnitFramesDB.fill, nil, "reset: saved fill forgotten")
eq(GlassUnitFramesDB.rim, nil, "reset: saved rim forgotten")
eq(Glass.fontKey, "arial", "reset: font back to Arial Narrow")

-- Checkboxes write the settings the next /reload reads.
local cast = controls.hideBlizzardCast
cast:SetChecked(true)
cast._scripts.OnClick(cast)
eq(GlassUnitFramesDB.hideBlizzardCast, true, "cast bar toggle saved")
cast:SetChecked(false)
cast._scripts.OnClick(cast)
eq(GlassUnitFramesDB.hideBlizzardCast, nil, "unticked: the key goes away")
local hide = controls.hideBlizzard
hide:SetChecked(false)
hide._scripts.OnClick(hide)
eq(GlassUnitFramesDB.hideBlizzard, false, "Blizzard frames toggle saved")

-- Radio groups: the raid mark placement and the font.
local function findRadio(text)
    for _, w in ipairs(WoW.frames) do
        if w._type == "CheckButton" and w.label and w.label._text == text then return w end
    end
end
local right, before = findRadio("Right of the frame"), findRadio("Before the name")
check(right ~= nil and before ~= nil, "raid mark placement is a radio group")
check(before._checked and not right._checked, "the current placement is the checked radio")
right._scripts.OnClick(right)
eq(GlassUF.Frames.markPos, "right", "placement switched live")
eq(GlassUnitFramesDB.mark, "right", "and saved")
check(right._checked and not before._checked, "only the chosen radio stays checked")
-- Health text grid and level placement.
local row = controls.healthRows.player
check(row and #row == 4, "a health-text row per frame, four formats")
check(controls.healthRows.targettargettarget == nil, "no row for the name-only frame")
row[3]._scripts.OnClick(row[3])                       -- "%"
eq(GlassUF.Frames.HealthFormatOf("player"), "perhp", "health text set from the panel")
check(row[3]._checked and not row[2]._checked, "the chosen format is checked")
local lvl = controls.levelRow
lvl[3]._scripts.OnClick(lvl[3])                       -- "Portrait"
eq(GlassUF.Frames.levelPos, "portrait", "level placement set from the panel")
eq(GlassUnitFramesDB.level, "portrait", "and saved")
local friz = findRadio("Friz Quadrata")
friz._scripts.OnClick(friz)
eq(GlassUnitFramesDB.font, "friz", "font choice saved")
eq(Glass.fontKey, "friz", "and applied")

-- The saved cast bar setting hides Blizzard's cast bar at the next load.
local saved = GlassUnitFramesDB
saved.hideBlizzardCast = true
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
check(not PlayerCastingBarFrame._shown, "hideBlizzardCast: Blizzard's cast bar hidden at load")
WoW.reset(); standardUnits(); GlassUF = nil
GlassUnitFramesDB = nil                      -- fresh settings: the default
loadAddon()
check(PlayerCastingBarFrame._shown ~= false, "by default Blizzard's cast bar is left alone")

-- The cast bar alone doesn't make /glass blizzard claim the frames are hidden,
-- and "/glass blizzard show" brings the cast bar back too.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = { font = "arial", hideBlizzard = false, hideBlizzardCast = true, pos = {} } })
check(not PlayerCastingBarFrame._shown, "cast bar hidden on its own")
check(not GlassUF.Blizzard.active, "unit frames not counted as hidden")
SlashCmdList.GLASSUNITFRAMES("blizzard")
check(WoW.chat[#WoW.chat]:find("frames are shown", 1, true), "status: shown: " .. WoW.chat[#WoW.chat])
SlashCmdList.GLASSUNITFRAMES("blizzard show")
eq(GlassUnitFramesDB.hideBlizzardCast, nil, "'show' clears the cast bar setting too")

-- The Cast bars page doesn't scroll: everything on it stays inside the
-- Settings canvas (about 601 units tall on 70450, Blizzard_SettingsPanel.xml),
-- leaving room for a 26-unit control (#120: a new switch once spilled out).
local castPage = O._test.castPage
castPage:Show()
local lowest, lowestName = 0, nil
local function scan(name, w)
    local pt = type(w) == "table" and w._points and w._points[1]
    if pt and pt[2] == castPage and type(pt[5]) == "number" and pt[5] < lowest then lowest, lowestName = pt[5], name end
end
for k, v in pairs(controls) do
    scan(k, v)
    if type(v) == "table" and not v._points then for k2, v2 in pairs(v) do scan(k .. "." .. tostring(k2), v2) end end
end
check(lowest < -500, "the scan found the page's lower controls (" .. tostring(lowestName) .. " at " .. lowest .. ")")
check(lowest >= -601 + 26, "the lowest, " .. tostring(lowestName) .. ", sits inside the canvas (" .. lowest .. ")")
castPage:Hide()

done("test_options")
