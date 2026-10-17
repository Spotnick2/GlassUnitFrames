-- The empty-part ramp (#117): across the whole bar by default (not saved),
-- or from the fill's moving edge over 5% of the bar ("edge", saved), live on
-- every bar, through LibGlass r10's SetTrackLength. With an older copy
-- winning (CI's pin before the bump), refused and a saved choice kept.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon({ db = { trackRamp = "sideways" } })
local Glass = GlassUF.Glass
local p = button("player")
eq(GlassUnitFramesDB.trackRamp, nil, "a junk saved ramp is forgotten")
eq(p.health.track._points[1][1], "ALL", "the whole bar by default")

-- A choice saved under r10, loaded again (with whichever LibGlass this is).
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = { trackRamp = "edge" } })
Glass, p = GlassUF.Glass, button("player")
eq(GlassUnitFramesDB.trackRamp, "edge", "a saved edge is kept at load")

if not Glass.SetTrackLength then
    -- LibGlass before r10 (CI's pin): edge refused, but whole still clears it.
    eq(p.health.track._points[1][1], "ALL", "an older copy draws the whole bar")
    check(not GlassUF.Settings.SetTrackRamp("edge"), "edge refused without SetTrackLength")
    eq(GlassUnitFramesDB.trackRamp, "edge", "a refusal changes nothing")
    SlashCmdList.GLASSUNITFRAMES("ramp edge")
    check(WoW.chat[#WoW.chat]:find("needs LibGlass r10", 1, true), "/glass ramp says why")
    check(GlassUF.Settings.SetTrackRamp("whole"), "whole is accepted: it's what an older copy draws")
    eq(GlassUnitFramesDB.trackRamp, nil, "and clears the saved edge")
    GlassUnitFramesDB.trackRamp = "edge"
    GlassUF.Settings.ResetLook()
    eq(GlassUnitFramesDB.trackRamp, nil, "reset look clears it too")
    GlassUnitFramesDB.trackRamp = "edge"
    local O = GlassUF.Options
    O._test.panel:Show()
    local rows = O._test.controls.trackRamp
    rows[1]._scripts.OnClick(rows[1])
    eq(GlassUnitFramesDB.trackRamp, nil, "and the Whole bar radio")
    check(rows[1]:GetChecked() and not rows[2]:GetChecked(), "which shows checked")
    done("test_ramp (LibGlass before r10)")
    return
end

eq(p.health.track._points[1][2], p.health:GetStatusBarTexture(), "bars are born with the saved edge ramp")
SlashCmdList.GLASSUNITFRAMES("ramp whole")

SlashCmdList.GLASSUNITFRAMES("ramp edge")
eq(GlassUnitFramesDB.trackRamp, "edge", "/glass ramp edge is saved")
local t = p.health.track
eq(t._points[1][2], p.health:GetStatusBarTexture(), "the health ramp starts at the fill's edge")
eq(p.power.track._points[1][2], p.power:GetStatusBarTexture(), "the power ramp too")
eq(button("target").health.track._points[1][3], "TOPRIGHT", "on every frame")
eq(t._texCoord[1], 0.30, "only the fade")
eq(Glass.STYLE.trackLength, GlassUF.RAMP_LENGTH, "over RAMP_LENGTH of the bar")
eq(p.health.trackClip._alpha, 0.25, "the strength is unchanged")

SlashCmdList.GLASSUNITFRAMES("ramp whole")
eq(GlassUnitFramesDB.trackRamp, nil, "whole is the default: not saved")
eq(t._points[1][1], "ALL", "back across the bar")
SlashCmdList.GLASSUNITFRAMES("ramp diagonal")
check(WoW.chat[#WoW.chat]:find("ramp whole|edge", 1, true), "a wrong word gets the usage")

-- Reset look forgets it.
GlassUF.Settings.SetTrackRamp("edge")
GlassUF.Settings.ResetLook()
eq(GlassUnitFramesDB.trackRamp, nil, "reset look forgets the ramp")
eq(t._points[1][1], "ALL", "and puts it back")

-- The options radio goes through the same setter.
local O = GlassUF.Options
O._test.panel:Show()
local rows = O._test.controls.trackRamp
check(rows and #rows == 2, "a Fade radio row")
rows[2]._scripts.OnClick(rows[2])
eq(GlassUnitFramesDB.trackRamp, "edge", "Past the fill: saved")
check(rows[2]:GetChecked() and not rows[1]:GetChecked(), "and checked")
rows[1]._scripts.OnClick(rows[1])
eq(GlassUnitFramesDB.trackRamp, nil, "Whole bar: the default again")

done("test_ramp")
