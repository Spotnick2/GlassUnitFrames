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

if not Glass.SetTrackLength then
    -- LibGlass before r10.
    check(not GlassUF.Settings.SetTrackRamp("edge"), "refused without SetTrackLength")
    eq(GlassUnitFramesDB.trackRamp, nil, "nothing saved")
    SlashCmdList.GLASSUNITFRAMES("ramp edge")
    check(WoW.chat[#WoW.chat]:find("needs LibGlass r10", 1, true), "/glass ramp says why")
    done("test_ramp (LibGlass before r10: refusal only)")
    return
end

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
