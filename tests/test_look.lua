-- The glass look (#102, #129): LibGlass's presets, Pearl by default (not
-- saved), Clean or Classic chosen at load from db.look (after /reload),
-- through the forwarding GlassUF.Glass. Pearl needs LibGlass r11: an older
-- winning copy gets Clean, and says so.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function reload(db, opts)
    WoW.reset(); standardUnits(); GlassUF = nil
    opts = opts or {}
    opts.db = db
    loadAddon(opts)
end

-- A fresh profile: Pearl.
standardUnits()
loadAddon()
local S = GlassUF.Settings
eq(GlassUF.look, "pearl", "Pearl by default")
eq(GlassUF.Glass.preset, "pearl", "LibGlass's Pearl preset")
check(GlassUF.Glass.STYLE.thinRim, "Pearl's thin rims")
eq(GlassUF.Glass.STYLE.rimAlpha, 0.6, "Pearl's rim")
eq(button("player").glass.size, "thin", "the player's glass is built thin")
eq(GlassUnitFramesDB.look, nil, "the default isn't saved")
eq(GlassUF.SuiteStatus(), nil, "nothing to say")

-- The setting: saved now, built after /reload.
check(S.SetLook("clean"), "clean chosen")
eq(GlassUnitFramesDB.look, "clean", "saved")
eq(GlassUF.look, "pearl", "this session keeps its look (surfaces are built)")
check(not S.SetLook("frosted"), "an unknown look is refused")
eq(GlassUnitFramesDB.look, "clean", "and changes nothing")
check(S.SetLook("classic"), "classic chosen")
eq(GlassUnitFramesDB.look, "classic", "classic is saved: it isn't the default")
check(S.SetLook("pearl"), "back to Pearl")
eq(GlassUnitFramesDB.look, nil, "the default isn't saved")
SlashCmdList.GLASSUNITFRAMES("look clean")
eq(GlassUnitFramesDB.look, "clean", "/glass look clean")

-- After /reload: the clean instance builds every surface, and the saved knobs
-- and slash tweaks reach it.
local saved = GlassUnitFramesDB
saved.rim = 0.5
reload(saved)
local Glass = GlassUF.Glass
eq(GlassUF.look, "clean", "a saved Clean is kept")
check(Glass.preset ~= "pearl", "not Pearl")
check(Glass.STYLE.thinRim, "the clean preset's thin rims")
eq(Glass.STYLE.grain, 0, "no grain")
eq(button("player").glass.size, "thin", "the player's glass is built thin")
eq(Glass.STYLE.rimAlpha, 0.5, "a saved knob reaches the clean instance")
SlashCmdList.GLASSUNITFRAMES("rim 0.7")
eq(Glass.STYLE.rimAlpha, 0.7, "/glass rim tunes the clean instance")
eq(GlassUnitFramesDB.rim, 0.7, "and saves")
saved.rim = nil

-- A saved Classic is kept.
saved.look = "classic"
reload(saved)
eq(GlassUF.look, "classic", "a saved Classic is kept")
check(not GlassUF.Glass.STYLE.thinRim, "classic rims")
eq(button("player").glass.size, "large", "the player's glass: the classic large rim")
eq(GlassUnitFramesDB.look, "classic", "and stays saved")

-- Junk saved: the default, the junk left for SetLook to replace.
reload({ look = "frosted" })
eq(GlassUF.look, "pearl", "an unknown saved look builds Pearl")

-- The options radio: Pearl, Clean, Classic.
reload({ look = "clean" })
S = GlassUF.Settings
local O = GlassUF.Options._test
O.panel._scripts.OnShow(O.panel)
local row = O.controls.look
local values = {}
for i, rb in ipairs(row) do values[i] = rb.value end
eq(table.concat(values, " "), "pearl clean classic", "a Pearl / Clean / Classic row on the main page")
for _, rb in ipairs(row) do eq(rb:GetChecked() and true or false, rb.value == "clean", "shows the saved Clean: " .. rb.value) end
for _, rb in ipairs(row) do
    if rb.value == "classic" then rb._scripts.OnClick(rb) end
end
eq(GlassUnitFramesDB.look, "classic", "Classic from the radio")
for _, rb in ipairs(row) do
    if rb.value == "pearl" then rb._scripts.OnClick(rb) end
end
eq(GlassUnitFramesDB.look, nil, "Pearl from the radio: the default, not saved")
check(O.controls.suiteNote == nil, "no note on the default look")
-- "Reset look to defaults" resets the glass look too (Codex, #103).
S.SetLook("clean")
GlassUF.Options.ResetLook()
eq(GlassUnitFramesDB.look, nil, "reset: back to Pearl (after /reload)")
O.controls.refreshAll()
for _, rb in ipairs(row) do
    if rb.value == "pearl" then check(rb:GetChecked(), "the radio shows Pearl after the reset") end
end

-- The glass body (#101): clear by default, smoked after /reload; with any look.
eq(GlassUF.body, "clear", "a clear body by default")
check(S.SetGlassBody("smoked"), "smoked chosen")
eq(GlassUnitFramesDB.glassBody, "smoked", "saved")
check(not S.SetGlassBody("murky"), "an unknown body is refused")
SlashCmdList.GLASSUNITFRAMES("body clear")
eq(GlassUnitFramesDB.glassBody, nil, "/glass body clear: the default isn't saved")
SlashCmdList.GLASSUNITFRAMES("body smoked")
for _, rb in ipairs(O.controls.glassBody) do
    if rb.value == "smoked" then O.controls.refreshAll(); check(rb:GetChecked(), "the Body radio shows Smoked") end
end
local savedBody = GlassUnitFramesDB
savedBody.look = nil   -- smoked on its own, the default look
reload(savedBody)
eq(GlassUF.body, "smoked", "smoked after the reload")
eq(GlassUF.look, "pearl", "on Pearl")
eq(GlassUF.Glass.preset, "pearl", "one Pearl instance")
eq(GlassUF.Glass.STYLE.bodyAlpha, GlassUF.SMOKED, "with the smoked body opacity")
savedBody.look = "classic"
reload(savedBody)
check(GlassUF.look == "classic" and GlassUF.Glass.STYLE.bodyAlpha == GlassUF.SMOKED, "classic and smoked together")
check(not GlassUF.Glass.STYLE.thinRim, "classic rims kept")
savedBody.look = "clean"
reload(savedBody)
check(GlassUF.look == "clean" and GlassUF.body == "smoked", "clean and smoked together")
check(GlassUF.Glass.STYLE.thinRim and GlassUF.Glass.STYLE.bodyAlpha == GlassUF.SMOKED, "one instance with both")
-- Reset look puts both back.
GlassUF.Options.ResetLook()
eq(GlassUnitFramesDB.look, nil, "reset: Pearl")
eq(GlassUnitFramesDB.glassBody, nil, "reset: clear")
eq(next(GlassUF.paintFailures), nil, "no paint failures")

-- Pearl needs r11. An older winning copy (MINOR 10, refusing pearl as r6-r10
-- do) gets Clean, says so, and saves nothing; a failing Pearl build too.
local FALLBACK = "Pearl needs LibGlass r11 or newer: Clean in use"
local function oldLib(minor, throws)
    local undo
    return function()
        local lib = LibStub("LibGlass-1.0")
        local realNew, realMinor, realReady = lib.New, LibStub.minors["LibGlass-1.0"], lib.ready
        LibStub.minors["LibGlass-1.0"], lib.ready = minor, minor
        -- r6-r10 refuse any preset but "clean"; r1-r5 knew none and ignored it.
        lib.New = function(self, opts)
            local preset = opts and opts.preset
            if minor < 6 and preset ~= nil then
                return realNew(self, { bodyAlpha = opts.bodyAlpha })
            elseif minor < 11 and preset ~= nil and preset ~= "clean" then
                error("LibGlass-1.0: unknown preset " .. tostring(preset) .. ' (use "clean" or omit it)', 2)
            elseif preset == "pearl" and throws then
                error("LibGlass-1.0: boom")
            end
            return realNew(self, opts)
        end
        undo = function() lib.New, LibStub.minors["LibGlass-1.0"], lib.ready = realNew, realMinor, realReady end
    end, function() undo() end
end
for _, case in ipairs({ { 10, false, "an r10 copy winning" }, { 5, false, "an r5 copy (ignores presets)" },
                        { 11, true, "Pearl's build failing" } }) do
    local install, undo = oldLib(case[1], case[2])
    local db = { glassBody = "smoked" }
    reload(db, { beforeLoaded = install })
    eq(GlassUF.look, "clean", case[3] .. ": Clean")
    check(GlassUF.Glass.preset ~= "pearl", case[3] .. ": not Pearl")
    if case[1] >= 6 then check(GlassUF.Glass.STYLE.thinRim, case[3] .. ": the clean instance") end
    eq(GlassUF.body, "smoked", case[3] .. ": the body still applies")
    eq(db.look, nil, case[3] .. ": nothing saved (Pearl comes back with a newer copy)")
    eq(GlassUF.SuiteStatus(), FALLBACK, case[3] .. ": said on the options page")
    local printed = false
    for _, line in ipairs(WoW.chat) do printed = printed or line:find("look: " .. FALLBACK, 1, true) ~= nil end
    check(printed, case[3] .. ": and once at load")
    WoW.chat = {}
    SlashCmdList.GLASSUNITFRAMES("look")
    check(WoW.chat[#WoW.chat]:find("now clean; " .. FALLBACK, 1, true) ~= nil, case[3] .. ": /glass look: " .. WoW.chat[#WoW.chat])
    GlassUF.Options._test.panel:Show()
    eq(GlassUF.Options._test.controls.suiteNote._text, FALLBACK, case[3] .. ": the note under Look")
    check(GlassUF.Options._test.controls.look[1]:IsEnabled(), case[3] .. ": the look is still ours to choose")
    undo()
end
-- An old copy with Classic saved: classic, no fallback.
do
    local install, undo = oldLib(10)
    reload({ look = "classic" }, { beforeLoaded = install })
    eq(GlassUF.look, "classic", "an r10 copy with Classic saved: Classic")
    eq(GlassUF.lookFallback, nil, "no fallback")
    undo()
end

GlassUnitFramesDB = nil
done("test_look")
