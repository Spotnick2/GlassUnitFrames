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
eq(WoW.settings.canvas.name, "GlassUnitFrames", "under the addon's name")

-- /glass options opens it.
SlashCmdList.GLASSUNITFRAMES("options")
eq(WoW.settings.opened, 4242, "/glass options opens the category")

-- Built lazily on first show.
check(controls.slider_fill == nil, "nothing built before the panel is shown")
panel._scripts.OnShow(panel)
check(controls.slider_fill ~= nil and controls.hideBlizzard ~= nil, "built on first show")

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

done("test_options")
