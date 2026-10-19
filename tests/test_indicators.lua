-- Indicators (#11): raid target, leader/assistant, master looter, PvP.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local p, t, f = button("player"), button("target"), button("focus")

-- Which frames carry which icons (the owner's SUF defaults).
check(p.indicators.raidTarget and p.indicators.leader and p.indicators.masterLoot and p.indicators.pvp,
      "player: raid target, leader, master loot, PvP")
check(t.indicators.raidTarget and t.indicators.leader and t.indicators.pvp and not t.indicators.masterLoot,
      "target: raid target, leader, PvP")
check(f.indicators.raidTarget and f.indicators.leader and not f.indicators.pvp, "focus: raid target, leader (no portrait for PvP)")
for _, u in ipairs(GlassUF.Frames.ORDER) do
    check(button(u).indicators and button(u).indicators.raidTarget, u .. " shows raid marks (SUF default)")
end
for _, icon in pairs(p.indicators) do check(not icon._shown, "all icons hidden when nothing applies") end

-- Raid target follows RAID_TARGET_UPDATE (a group-wide event).
WoW.units.target.raidTarget = 8
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
check(t.indicators.raidTarget._shown and t.indicators.raidTarget._raidIndex == 8, "skull on the target")
check(f.indicators.raidTarget._shown == false, "unmarked focus shows none")
WoW.units.target.raidTarget = nil
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
check(not t.indicators.raidTarget._shown, "cleared mark hides")

-- /glass secrets reports the mark index and the icon's state (a diagnostic
-- for in-game cases where the mark does not show).
WoW.units.target.raidTarget = 6
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
SlashCmdList.GLASSUNITFRAMES("secrets")
local line
for _, l in ipairs(WoW.chat) do if l:find("  target: ", 1, true) then line = l end end
check(line and line:find("mark=ok", 1, true) and line:find("markIcon=shown", 1, true), "secrets reports mark and icon: " .. tostring(line))
WoW.units.target.raidTarget = nil
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()

-- The mark index is secret for other units on Forever: it goes straight to
-- the client (SetSpriteSheetCell), never through Lua maths.
WoW.units.target.raidTarget = 8
WoW.secretFields.raidTarget = true
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
check(t.indicators.raidTarget._shown, "a secret mark index still shows the icon")
check(WoW.IsSecret(t.indicators.raidTarget._raidIndex), "the secret index is handed to the client untouched")
eq(t.indicators.raidTarget._sheet[1], 4, "4x4 marker sheet")
WoW.units.target.raidTarget = nil
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
check(not t.indicators.raidTarget._shown, "no mark (plain nil): hidden")
WoW.secretFields.raidTarget = nil
eq(next(GlassUF.paintFailures), nil, "no paint failures with a secret mark")

-- Leader / assistant follow PARTY_LEADER_CHANGED.
WoW.units.player.leader = true
WoW.fire("PARTY_LEADER_CHANGED"); WoW.tick()
check(p.indicators.leader._shown and p.indicators.leader._file:find("LeaderIcon"), "leader crown")
WoW.units.player.leader, WoW.units.player.assistant = false, true
WoW.fire("GROUP_ROSTER_UPDATE"); WoW.tick()
check(p.indicators.leader._shown and p.indicators.leader._file:find("AssistantIcon"), "assistant icon")
WoW.units.player.assistant = false
WoW.fire("GROUP_ROSTER_UPDATE"); WoW.tick()
check(not p.indicators.leader._shown, "no rank: hidden")

-- Master looter (IsMasterLooter): takes the corner, or sits right of the leader.
WoW.masterLooter = true
WoW.fire("PARTY_LOOT_METHOD_CHANGED"); WoW.tick()
check(p.indicators.masterLoot._shown, "player is master looter")
eq(p.indicators.masterLoot._points[1][2], p.indCorner.anchor, "loot bag takes the corner when not leader")
WoW.units.player.leader = true
WoW.fire("PARTY_LEADER_CHANGED"); WoW.tick()
eq(p.indicators.masterLoot._points[1][2], p.indicators.leader, "loot bag sits right of the leader crown")
WoW.units.player.leader = false
WoW.masterLooter = false
WoW.fire("PARTY_LOOT_METHOD_CHANGED"); WoW.tick()
check(not p.indicators.masterLoot._shown, "not master looter: hidden")

-- PvP flag follows UNIT_FACTION (per unit).
WoW.units.player.pvp = true
WoW.fire("UNIT_FACTION", "player"); WoW.tick()
check(p.indicators.pvp._shown and p.indicators.pvp._file:find("UI%-PVP%-Horde"), "Horde PvP badge")
WoW.units.player.ffa = true
WoW.fire("UNIT_FACTION", "player"); WoW.tick()
check(p.indicators.pvp._file:find("UI%-PVP%-FFA"), "free-for-all badge wins")
WoW.units.player.pvp, WoW.units.player.ffa = false, false
WoW.fire("UNIT_FACTION", "player"); WoW.tick()
check(not p.indicators.pvp._shown, "unflagged: hidden")
WoW.units.target.faction, WoW.units.target.pvp = "Neutral", true
WoW.fire("UNIT_FACTION", "target"); WoW.tick()
check(not t.indicators.pvp._shown, "neutral faction: no badge")

-- Secret facts never branch: show the icons with plain values first, then
-- the same facts as secrets must hide them (not merely leave them hidden).
WoW.units.target.raidTarget, WoW.units.player.leader, WoW.units.player.pvp = 3, true, true
WoW.units.player.faction = "Horde"
WoW.fire("RAID_TARGET_UPDATE"); WoW.fire("PARTY_LEADER_CHANGED"); WoW.fire("UNIT_FACTION", "player"); WoW.tick()
check(t.indicators.raidTarget._shown and p.indicators.leader._shown and p.indicators.pvp._shown,
      "plain facts: icons shown (precondition)")
for _, fld in ipairs({ "raidTarget", "leader", "assistant", "pvp", "ffa", "faction" }) do WoW.secretFields[fld] = true end
WoW.fire("RAID_TARGET_UPDATE"); WoW.fire("PARTY_LEADER_CHANGED"); WoW.fire("UNIT_FACTION", "player"); WoW.tick()
check(not p.indicators.leader._shown and not p.indicators.pvp._shown,
      "secret leader/PvP facts: icons hidden")
check(t.indicators.raidTarget._shown, "a secret mark still shows (the client picks the cell)")
eq(next(GlassUF.paintFailures), nil, "no paint failures")

-- A painter that throws is recorded and does not take the flush down.
WoW.secretFields = {}
rawset(p.indicators.leader, "SetTexture", function() error("boom") end)
WoW.units.player.leader = true
WoW.units.player.health = 321
WoW.fire("PARTY_LEADER_CHANGED"); WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
check(GlassUF.paintFailures["painter indicators"] ~= nil, "a throwing painter is recorded")
eq(p.health._value, 321, "and the rest of the flush still paints")
rawset(p.indicators.leader, "SetTexture", nil)
WoW.units.player.leader = false

-- Resting (player only): Blizzard's animated flipbook, shown while resting.
local rest = p.indicators.resting
check(rest and rest.animated, "player has the animated rest icon")
check(not t.indicators.resting, "no rest icon on the target")
check(not rest._shown, "hidden when not resting")
WoW.resting = true
WoW.fire("PLAYER_UPDATE_RESTING"); WoW.tick()
check(rest._shown, "shown while resting")
WoW.resting = false
WoW.fire("PLAYER_UPDATE_RESTING"); WoW.tick()
check(not rest._shown, "hidden after leaving the inn")
-- A client without the atlas: the static state icon instead.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.atlases = {}
loadAddon()
local r2 = button("player").indicators.resting
check(r2 and not r2.animated, "static fallback without the flipbook atlas")

-- Raid mark placement (#30): "name" by default, a slot before the name.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon()
local tg = button("target")
local mk = tg.indicators.raidTarget
eq(GlassUF.Frames.markPos, "name", "default placement: before the name")
eq(mk._points[1][2], tg.health, "mark sits inside the health bar")
eq(mk._points[1][1], "LEFT", "at its left edge")
eq(tg.nameText._points[1][2], tg.health, "unmarked: the name starts at the bar's padding")
WoW.units.target.raidTarget = 8
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
eq(tg.nameText._points[1][2], mk, "marked: the name moves right of the mark")
-- A secret index (other units on Forever) still says "a mark exists".
WoW.secretFields.raidTarget = true
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
eq(tg.nameText._points[1][2], mk, "secret mark index: the name still makes room")
WoW.secretFields.raidTarget = nil
SlashCmdList.GLASSUNITFRAMES("mark top")
eq(mk._points[1][2], tg.body, "top: centred on the frame's top edge")
eq(tg.nameText._points[1][2], tg.health, "top: the name goes back to the bar's padding")
eq(GlassUnitFramesDB.mark, "top", "placement saved")
SlashCmdList.GLASSUNITFRAMES("mark right")
eq(mk._points[1][2], tg.tile, "right: on the frame's right edge, the target's portrait tile (#132: never the button)")
eq(mk._points[1][3], "RIGHT", "past its right edge")
SlashCmdList.GLASSUNITFRAMES("mark sideways")
eq(GlassUnitFramesDB.mark, "right", "unknown placement rejected")
WoW.units.target.raidTarget = nil
WoW.fire("RAID_TARGET_UPDATE"); WoW.tick()
-- A saved placement is used at build.
local saved = GlassUnitFramesDB
WoW.reset(); standardUnits(); GlassUF = nil
GlassUnitFramesDB = saved
loadAddon()
eq(button("target").indicators.raidTarget._points[1][2], button("target").tile, "saved 'right' applied at build")
GlassUF.Settings.SetPortraitMode("target", "none")
eq(button("target").indicators.raidTarget._points[1][2], button("target").body, "no tile: the body's right edge")
GlassUnitFramesDB = nil

done("test_indicators")
