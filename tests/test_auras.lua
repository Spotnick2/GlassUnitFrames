-- Target buffs and debuffs via Blizzard's managed aura container (#12).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
-- The target's cast bar docked (detached by default since #141): its pill sits under the aura rows.
loadAddon({ db = { castBars = { target = { detached = false } } } })
local t = button("target")

check(WoW.loadedAddOns.Blizzard_AuraContainer, "Blizzard_AuraContainer loaded on demand")
eq(#(t.auraContainers or {}), 2, "two containers on the target: buffs and debuffs")
for _, u in ipairs(GlassUF.Frames.ORDER) do
    if u ~= "target" then check(button(u).auraContainers == nil, u .. " has no auras (player auras off, as in the profile)") end
end

local buffs, debuffs = t.auraByKey.buffs, t.auraByKey.debuffs
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

-- Owner's layout (#32): buffs right under the frame, debuffs below them, the
-- cast bar under both, ToT/ToTT above the frame. Each row anchored to the
-- unit frame's body, never to another aura container (refused in game).
local by, dy = buffs._points[1][5], debuffs._points[1][5]
check(by >= -6 and by < 0, "buffs right under the frame")
check(by > dy, "buffs above debuffs")
for _, c in ipairs(t.auraContainers) do
    check(c._points[1][2] ~= buffs and c._points[1][2] ~= debuffs, "anchored to our frame, not to an aura container")
end
local castTop = t.cast.host._points[1][5]
check(castTop <= dy - 20, "the cast bar sits under both aura rows")
local LT = GlassUF.Frames.LAYOUT
local targetTop = LT.target.point[5] + LT.target.h / 2
for _, u in ipairs({ "targettarget", "targettargettarget" }) do
    check(LT[u].point[5] - LT[u].h / 2 > targetTop, u .. " sits above the target frame")
end
check(LT.targettarget.point[4] < LT.targettargettarget.point[4], "targettarget left of targettargettarget")
local totTop = LT.targettarget.point[5] + LT.targettarget.h / 2
check(LT.focus.point[5] - LT.focus.h / 2 > totTop, "focus sits above the ToT row")
-- Indicators centred on a top edge stick up by half their size: the target's
-- raid mark (20 px) must clear the ToT row, ToTT's (14 px) must clear focus.
check(targetTop + 10 < LT.targettarget.point[5] - LT.targettarget.h / 2, "target raid mark clears the ToT row")
local totttTop = LT.targettargettarget.point[5] + LT.targettargettarget.h / 2
check(totttTop + 7 < LT.focus.point[5] - LT.focus.h / 2, "ToTT raid mark clears the focus frame")
-- The docked cast bar follows the aura rows.
eq(castTop, GlassUF.Auras.Bottom() - 6, "cast bar offset derived from the aura rows")

-- A client that refuses part of the aura setup must not abort the build:
-- the frame still registers, and later frames still build.
do
    WoW.reset()
    standardUnits()
    GlassUF = nil
    local realCreate = CreateFrame
    CreateFrame = function(ftype, ...)
        local w = realCreate(ftype, ...)
        if ftype == "AuraContainer" then
            rawset(w, "SetPoint", function() error("Anchoring disallowed as dependent object would inherit forbidden aspects") end)
        end
        return w
    end
    loadAddon()
    CreateFrame = realCreate
    check(GlassUF.paintFailures["build auras"] ~= nil, "the refused aura setup is recorded")
    check(WoW.unitWatch[button("target")], "the target frame still registers its unit watch")
    for _, u in ipairs(GlassUF.Frames.ORDER) do check(button(u) ~= nil, u .. " still built after the failure") end
    WoW.reset()
    standardUnits()
    GlassUF = nil
    loadAddon()
    t = button("target")
    buffs, debuffs = t.auraByKey.buffs, t.auraByKey.debuffs
end

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

-- The regions the client registers are placed AFTER registration.
local b2 = CreateFrame("Button", nil, buffs)
local order = {}
local realDur = b2.SetDurationText
rawset(b2, "SetDurationText", function(self, fs, o) order[#order + 1] = "register"; fs._pointsAtRegister = #fs._points; return realDur(self, fs, o) end)
buffs._groups.glass_buffs.spec.initializeFrame(b2)
check(b2._durationText._pointsAtRegister == 0 and #b2._durationText._points == 1,
      "duration text anchored after it is handed to the client")
check(b2._durationText._parent ~= b2, "text sits on an overlay above the cooldown, not on the button")

-- Sort method and direction: both or neither.
AuraContainerSortMethod = { ExpirationOnly = 3 }
local m, d = GlassUF.API.AuraSort()
check(m == nil and d == nil, "a sort method without a direction is not passed")
AuraContainerSortDirection = { Normal = 0 }
m, d = GlassUF.API.AuraSort()
check(m == 3 and d == 0, "both present: both passed")
AuraContainerSortMethod, AuraContainerSortDirection = nil, nil


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

-- A disabled Blizzard_AuraContainer is reported with the client's reason.
WoW.reset()
standardUnits()
GlassUF = nil
C_AddOns.LoadAddOn = function() return false, "DISABLED" end
loadAddon()
check(GlassUF.paintFailures["aura load"] == "DISABLED", "load failure reason recorded")
C_AddOns.LoadAddOn = function(name) WoW.loadedAddOns[name] = true; return true end

-- A container without the group API (template missing its mixin) is
-- reported, not silently hidden.
WoW.reset()
standardUnits()
GlassUF = nil
local realCreate2 = CreateFrame
CreateFrame = function(ftype, ...)
    local w = realCreate2(ftype, ...)
    if ftype == "AuraContainer" then rawset(w, "AddAuraGroup", false) end
    return w
end
loadAddon()
CreateFrame = realCreate2
check((GlassUF.paintFailures["aura group"] or ""):find("missing method AddAuraGroup", 1, true),
      "a missing AddAuraGroup is recorded: " .. tostring(GlassUF.paintFailures["aura group"]))
eq(#button("target").auraContainers, 0, "and no half-built container is kept")

done("test_auras")
