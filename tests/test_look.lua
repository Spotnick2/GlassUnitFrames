-- The glass look (#102): classic by default; LibGlass r6's clean preset chosen
-- at load from db.look (after /reload), through the forwarding GlassUF.Glass.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local S = GlassUF.Settings
eq(GlassUF.look, "classic", "classic by default")
check(not GlassUF.Glass.STYLE.thinRim, "classic rims")
eq(button("player").glass.size, "large", "the player's glass: the classic large rim")

-- The setting: saved now, built after /reload.
check(S.SetLook("clean"), "clean chosen")
eq(GlassUnitFramesDB.look, "clean", "saved")
eq(GlassUF.look, "classic", "this session keeps its look (surfaces are built)")
check(not S.SetLook("frosted"), "an unknown look is refused")
eq(GlassUnitFramesDB.look, "clean", "and changes nothing")
check(S.SetLook("classic"), "back to classic")
eq(GlassUnitFramesDB.look, nil, "the default isn't saved")
SlashCmdList.GLASSUNITFRAMES("look clean")
eq(GlassUnitFramesDB.look, "clean", "/glass look clean")

-- After /reload: the clean instance builds every surface, and the saved knobs
-- and slash tweaks reach it.
local saved = GlassUnitFramesDB
saved.rim = 0.5
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
local Glass = GlassUF.Glass
eq(GlassUF.look, "clean", "clean after the reload")
check(Glass.STYLE.thinRim, "the clean preset's thin rims")
eq(Glass.STYLE.grain, 0, "no grain")
eq(button("player").glass.size, "thin", "the player's glass is built thin")
eq(Glass.STYLE.rimAlpha, 0.5, "a saved knob reaches the clean instance")
SlashCmdList.GLASSUNITFRAMES("rim 0.7")
eq(Glass.STYLE.rimAlpha, 0.7, "/glass rim tunes the clean instance")
eq(GlassUnitFramesDB.rim, 0.7, "and saves")

-- The options radio.
local O = GlassUF.Options._test
O.panel._scripts.OnShow(O.panel)
local row = O.controls.look
check(row and #row == 2, "a Classic / Clean row on the main page")
for _, rb in ipairs(row) do
    if rb.value == "clean" then check(rb:GetChecked(), "shows the saved clean") end
end
for _, rb in ipairs(row) do
    if rb.value == "classic" then rb._scripts.OnClick(rb) end
end
eq(GlassUnitFramesDB.look, nil, "Classic from the radio")
-- "Reset look to defaults" resets the glass look too (Codex, #103).
S.SetLook("clean")
GlassUF.Options.ResetLook()
eq(GlassUnitFramesDB.look, nil, "reset: back to classic (after /reload)")
O.controls.refreshAll()
for _, rb in ipairs(row) do
    if rb.value == "classic" then check(rb:GetChecked(), "the radio shows Classic after the reset") end
end

-- The glass body (#101): clear by default, smoked after /reload; with either look.
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
savedBody.look = nil   -- smoked on its own, classic look
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = savedBody })
eq(GlassUF.body, "smoked", "smoked after the reload")
eq(GlassUF.look, "classic", "on the classic look")
eq(GlassUF.Glass.STYLE.bodyAlpha, GlassUF.SMOKED, "the instance's body opacity")
check(not GlassUF.Glass.STYLE.thinRim, "classic rims kept")
-- Both together.
savedBody.look = "clean"
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = savedBody })
check(GlassUF.look == "clean" and GlassUF.body == "smoked", "clean and smoked together")
check(GlassUF.Glass.STYLE.thinRim and GlassUF.Glass.STYLE.bodyAlpha == GlassUF.SMOKED, "one instance with both")
-- Reset look puts both back.
GlassUF.Options.ResetLook()
eq(GlassUnitFramesDB.look, nil, "reset: classic")
eq(GlassUnitFramesDB.glassBody, nil, "reset: clear")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
GlassUnitFramesDB = nil
done("test_look")
