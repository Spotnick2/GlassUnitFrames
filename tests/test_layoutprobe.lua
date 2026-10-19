-- LayoutProbe (#132, M5): a ForeverProbe module that announces a fake Glass
-- Raid Frames centred layout through the real event, so GlassUnitFrames'
-- link places (and glides) its frames; "off" lets go. Its lines never reach chat.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
WoW.fire("LOADING_SCREEN_DISABLED")   -- long after login, as the probe runs
UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
WoW.layout = true
local FP = loadForeverProbe()

local ns = {}
assert(loadfile("Tools/LayoutProbe/LayoutProbe.lua"))("LayoutProbe", ns)
check(rawget(_G, "LayoutProbeDB") == nil, "no saved table made at file scope")
WoW.fire("ADDON_LOADED", "LayoutProbe")
local T = ns._test
check(T and T.Probe, "the module registered")
check(type(LayoutProbeDB) == "table" and type(LayoutProbeDB.log) == "table", "its saved log, made at ADDON_LOADED")

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local Link = GlassUF.Link
local pl = button("player")
local home = { pl._points[1][1], pl._points[1][4], pl._points[1][5] }

fp("layout hud")
check(Link.Placing(), "/fp layout hud: GlassUnitFrames places its frames")
local s = T.state(0)
check(math.abs(s.base - 768 * 152 / 1080) < 0.01, "the baseline at 152/1080 of UIParent's height")
check(math.abs(pl._points[1][4] - (s.l - 24 - 365 / 2)) < 0.01 and pl._points[1][5] == home[3],
      "the player beside the grid, at its own height")
fp("layout wide")
check(next(Link._test.glides) ~= nil, "/fp layout wide: the frames glide")
WoW.tick(1)
fp("layout off")
check(not Link.Placing(), "/fp layout off: let go")
check(pl._points[1][1] == home[1] and pl._points[1][4] == home[2] and pl._points[1][5] == home[3], "back home exactly")
WoW.combat = true
local ok, why = T.announce(T.state(0))
check(not ok and why:find("combat"), "refused in combat, as GRF never announces there")
check(not Link.Placing(), "nothing placed")
WoW.combat = false
fp("layout state")

-- A fake pet dx for GlassActionBars (section 5b), and back to the real state.
local heard = {}
EventRegistry:RegisterCallback("GlassUnitFrames.LayoutChanged", function(_, ...) heard[#heard + 1] = { ... } end, {})
fp("layout pet -150")
check(heard[1] and heard[1][1] == true and heard[1][10] == -150 and heard[1][11] == -150 and heard[1][4] == 365,
      "/fp layout pet -150: linked, the real rects, player and pet moved -150")
fp("layout stance 80")
check(heard[2] and heard[2][1] == true and heard[2][10] == 80 and heard[2][11] == 0, "/fp layout stance 80: the player only")
fp("layout pet off")
check(heard[3] and heard[3][1] == false and heard[3][10] == 0 and heard[3][11] == 0,
      "/fp layout pet off: GlassUnitFrames' real state (not linked, no move)")
fp("layout pet sideways")
eq(#heard, 3, "junk: nothing sent")

for _, line in ipairs(WoW.chat) do
    check(not line:find("LayoutProbe") and not line:find("visuals gliding"), "no probe line in chat: " .. line)
end
local inHost = false
for _, entry in ipairs(FP.lines) do
    if entry.m == "LayoutProbe" and entry.text:find("hud at l") then inHost = true end
end
check(inHost, "its lines reach the host's console")
eq(next(GlassUF.paintFailures), nil, "no failures")
done("test_layoutprobe")
