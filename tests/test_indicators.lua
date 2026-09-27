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
check(not t.indicators.raidTarget._shown and not p.indicators.leader._shown and not p.indicators.pvp._shown,
      "secret facts: icons hidden")
eq(next(GlassUF.paintFailures), nil, "no paint failures")

-- A painter that throws is recorded and does not take the flush down.
WoW.secretFields = {}
local realSet = SetRaidTargetIconTexture
SetRaidTargetIconTexture = function() error("boom") end
WoW.units.target.raidTarget = 1
WoW.units.player.health = 321
WoW.fire("RAID_TARGET_UPDATE"); WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
check(GlassUF.paintFailures["painter indicators"] ~= nil, "a throwing painter is recorded")
eq(p.health._value, 321, "and the rest of the flush still paints")
SetRaidTargetIconTexture = realSet

done("test_indicators")
