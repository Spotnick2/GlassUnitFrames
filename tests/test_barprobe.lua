-- BarProbe (#117): a ForeverProbe module. Its panel builds sample glass bars
-- at fixed percentages, its controls retune the empty part of the samples and
-- of GlassUnitFrames' real bars live, the settings are saved and re-applied at
-- login, and its lines never reach chat.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local FP = loadForeverProbe()

-- The probe, as the client loads it (no saved table on a first run).
local ns = {}
assert(loadfile("Tools/BarProbe/BarProbe.lua"))("BarProbe", ns)
check(rawget(_G, "BarProbeDB") == nil, "no saved table made at file scope")
WoW.fire("ADDON_LOADED", "BarProbe")
local T = ns._test
check(T and T.Probe, "the module registered")
check(type(BarProbeDB) == "table" and type(BarProbeDB.log) == "table", "its saved log, made at ADDON_LOADED")
eq(BarProbeDB.settings, nil, "nothing saved until a setting changes")

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local p = button("player")

fp("bar show")
local panel = T.panel()
check(panel and panel:IsShown(), "/fp bar show opens the panel")
eq(#T.samples, 5, "one sample frame per percentage")
local s1 = T.samples[1]
eq(s1.health:GetValue(), 5, "the first sample at 5%")
eq(s1.health.trackClip._alpha, 0.25, "samples start at Frames.lua's strength")
eq(p.health.trackClip._alpha, 0.25, "and so do the real bars")

-- A stepper changes the samples and the real bars, and saves.
T.S.health = 0.5
T.applyAll()
eq(s1.health.trackClip._alpha, 0.5, "a sample takes the new strength")
eq(p.health.trackClip._alpha, 0.5, "a real health bar too")
eq(button("target").health.trackClip._alpha, 0.5, "the target's as well")
eq(p.power.trackClip._alpha, 0.25, "power keeps its own")

-- The edge ramp: on the fill's moving edge, only the fade part of the texture.
T.S.health = 0.6; T.applyAll(); BarProbeDB.settings = { health = 0.6 }
fp("bar reset")
eq(BarProbeDB.settings, nil, "reset forgets the saved tuning (nothing re-applied at login)")
eq(T.S.health, 0.25, "and the controls show the defaults")
T.S.ramp, T.S.length = "edge", 0.1
s1.health:SetWidth(288)
T.applyAll()
local t = s1.health.track
eq(t._points[1][2], s1.health:GetStatusBarTexture(), "the ramp starts at the fill's edge")
eq(t._points[1][3], "TOPRIGHT", "its right side")
eq(t._width, 28.8, "over 10% of the bar")
eq(t._texCoord[1], 0.30, "only the ramp's fade")
eq(t._texCoord[2], 0.85, "to where it reaches clear")
T.S.ramp = "whole"
T.applyAll()
eq(t._points[1][1], "ALL", "whole bar again")
eq(t._points[1][2], s1.health, "across the bar")
eq(t._texCoord[2], 1, "the whole texture")

fp("bar state")
fp("bar hide")
check(not panel:IsShown(), "/fp bar hide")

-- Saved settings are re-applied at login (GlassUF's frames exist by then).
BarProbeDB.settings = { health = 0.4, power = 0.2, ramp = "whole", length = 0.05 }
local ns2 = {}
assert(loadfile("Tools/BarProbe/BarProbe.lua"))("BarProbe", ns2)
WoW.fire("ADDON_LOADED", "BarProbe")
WoW.fire("PLAYER_LOGIN")
eq(p.health.trackClip._alpha, 0.4, "a saved tuning reaches the real bars at login")
eq(p.power.trackClip._alpha, 0.2, "power too")
-- Junk in the saved table falls back to the defaults.
BarProbeDB.settings = { health = "x", ramp = "sideways", length = 9 }
local ns3 = {}
assert(loadfile("Tools/BarProbe/BarProbe.lua"))("BarProbe", ns3)
WoW.fire("ADDON_LOADED", "BarProbe")
eq(ns3._test.S.health, 0.25, "junk strength: default")
eq(ns3._test.S.ramp, "whole", "junk ramp: default")
eq(ns3._test.S.length, 0.5, "length clamped")


-- Nothing in chat: the console and the saved log only.
for _, line in ipairs(WoW.chat) do
    check(not line:find("BarProbe") and not line:find("health %d"), "no probe line in chat: " .. line)
end
local inHost = false
for _, entry in ipairs(FP.lines) do
    if entry.m == "BarProbe" and entry.text:find("health 0%.25") then inHost = true end
end
check(inHost, "its lines reach the host's console")

done("test_barprobe")
