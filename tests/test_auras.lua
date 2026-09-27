-- Target buffs and debuffs via Blizzard's managed aura container (#12).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local t = button("target")

check(WoW.loadedAddOns.Blizzard_AuraContainer, "Blizzard_AuraContainer loaded on demand")
eq(#(t.auraContainers or {}), 2, "two containers on the target: buffs and debuffs")
for _, u in ipairs(GlassUF.Frames.ORDER) do
    if u ~= "target" then check(button(u).auraContainers == nil, u .. " has no auras (player auras off, as in the profile)") end
end

local buffs, debuffs = t.auraContainers[1], t.auraContainers[2]
eq(buffs._template, "CustomAuraContainerTemplate", "managed container template")
eq(buffs._groups.glass_buffs.filter, "HELPFUL", "buff row filter")
eq(debuffs._groups.glass_debuffs.filter, "HARMFUL|INCLUDE_NAME_PLATE_ONLY", "debuff row filter (as DinoUF)")
eq(buffs._groups.glass_buffs.spec.maxFrameCount, 13, "13 icons per row")
eq(next(buffs._groups.glass_buffs.spec.candidateFilters), nil, "no filtering (impossible under secrecy)")

-- Order matters: groups are declared before the unit is bound, then a refresh.
eq(buffs._modelUnit, "target", "bound to the target token")
eq(table.concat(buffs._seq, ","), "AddAuraGroup,SetUnit,UpdateAllAuras",
   "groups BEFORE the unit (else UNIT_AURA stays unregistered), then a refresh")
eq(table.concat(debuffs._seq, ","), "AddAuraGroup,SetUnit,UpdateAllAuras", "same order for debuffs")

-- Rows sit under the cast lane, buffs above debuffs; ToT is clear of them.
local by, dy = buffs._points[1][5], debuffs._points[1][5]
check(by > dy, "buffs above debuffs")
check(by <= -26, "buffs start below the 20 px cast lane (6 px gap)")
local totY = GlassUF.Frames.LAYOUT.targettarget.point[5]
local targetBottom = GlassUF.Frames.LAYOUT.target.point[5] - GlassUF.Frames.LAYOUT.target.h / 2
check(totY + 13 < targetBottom + dy - 20, "targettarget sits below the debuff row")

-- A new target: both containers re-evaluate (also mid-combat: no secure calls).
WoW.combat = true
WoW.SetUnit("target", { name = "Kobold", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(buffs._refreshes, 2, "buffs refresh on a target change")
eq(debuffs._refreshes, 2, "debuffs refresh on a target change")
eq(#WoW.blocked, 0, "nothing protected touched in combat")
WoW.combat = false
WoW.SetUnit("focus", { name = "Hogger", reaction = 2 })
WoW.fire("PLAYER_FOCUS_CHANGED"); WoW.tick()
eq(buffs._refreshes, 2, "a focus change does not refresh the target's auras")

-- The client calls initializeFrame on each button it creates: we hand it the
-- regions it fills, and add no scripts.
local btn = CreateFrame("Button", nil, buffs)
buffs._groups.glass_buffs.spec.initializeFrame(btn)
check(btn._icon and btn._icon._type == "Texture", "icon region handed over")
check(btn._cooldown and btn._cooldown._template == "CooldownFrameTemplate", "cooldown swipe handed over")
check(btn._durationText and btn._countText, "duration and stack text handed over")
eq(next(btn._scripts), nil, "no scripts on a managed button")

-- No container API on this client (e.g. the Blizzard addon missing): no
-- error, no auras, the failure recorded.
WoW.reset()
standardUnits()
GlassUF = nil
local realCreate = CreateFrame
CreateFrame = function(ftype, ...)
    if ftype == "AuraContainer" then error("unknown frame type") end
    return realCreate(ftype, ...)
end
loadAddon()
CreateFrame = realCreate
eq(#(button("target").auraContainers or {}), 0, "no containers when the type is missing")
check(GlassUF.paintFailures["aura container"] ~= nil, "the failure is recorded for /glass secrets")
check(button("target").health ~= nil, "the rest of the target frame still built")

done("test_auras")
