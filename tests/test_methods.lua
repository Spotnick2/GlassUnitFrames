-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- checks each recorded "Type:Method" against the API dump's widget-method
-- walk, falling back to the documented functions for animation subtypes the
-- walk does not cover (Alpha:SetToAlpha, Translation:SetOffset).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DUMP = os.getenv("GLASSUF_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70009.md"
local f = io.open(DUMP, "r")
if not f then
    io.write("test_methods: SKIPPED (no API dump at " .. DUMP .. ")\n")
    os.exit(0)
end
local widget, documented = {}, {}
for line in f:lines() do
    local wm = line:match("^(%a+:%a+)%s*$")
    if wm then widget[wm] = true end
    local fn = line:match("^([%a_]+)%(")
    if fn then documented[fn] = true end
end
f:close()

-- Exercise everything so every method is recorded.
standardUnits()
WoW.units.player.casting = { name = "Shadow Bolt" }
loadAddon()
WoW.fireAllRegistered()
WoW.tick(); WoW.tick(0.1)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player"); WoW.flushTimers()
WoW.shift = true
local p = button("player")
p._scripts.OnDragStart(p); p._scripts.OnDragStop(p)
SlashCmdList.GLASSUNITFRAMES("font friz")
SlashCmdList.GLASSUNITFRAMES("reset")
-- The client builds aura buttons and calls initializeFrame: exercise it.
local aurasC = button("target").auraContainers[1]
aurasC._groups.glass_debuffs.spec.initializeFrame(CreateFrame("Button", nil, aurasC))
local tf = CreateFrame("Frame", "TotemFrame", PlayerFrame)
CreateFrame("Button", nil, tf)
SlashCmdList.GLASSUNITFRAMES("totem")

-- Methods the dump cannot list: Blizzard_AuraContainer is a load-on-demand
-- Blizzard addon the dump did not capture. Evidence they exist on Forever:
-- DinoUnitFrames (ships on this client) calls every one of them
-- (modules/auras.lua ForeverEnsureAuraContainer / ForeverInitAuraButton).
-- Keep this list exact: anything else missing from the dump still fails.
local AURA_CONTAINER_API = {
    ["AuraContainer:AddAuraGroup"] = true, ["AuraContainer:UpdateAllAuras"] = true,
    ["AuraContainer:SetUnit"] = true,
    ["AuraContainer:SetFlowLayoutAnchorPoint"] = true, ["AuraContainer:SetFlowLayoutAxis"] = true,
    ["AuraContainer:SetFlowLayoutMaximumLineSize"] = true, ["AuraContainer:SetFlowLayoutGrowthDirection"] = true,
    ["AuraContainer:SetFlowLayoutPadding"] = true,
    -- on the buttons the container creates (a Button in the tests)
    ["Button:SetIcon"] = true, ["Button:SetDurationCooldown"] = true,
    ["Button:SetDurationText"] = true, ["Button:SetApplicationCount"] = true,
}

local n = 0
for name in pairs(WoW.methodsCalled) do
    n = n + 1
    local method = name:match(":(%a+)$")
    local wtype = name:match("^(%a+):")
    local ok = widget[name] or documented[method] or AURA_CONTAINER_API[name]
        or (wtype == "AuraContainer" and widget["Frame:" .. method])   -- a Frame underneath
    check(ok, "method exists on Forever: " .. name)
end
check(n > 40, "recorded a realistic number of methods (" .. n .. ")")
done("test_methods")
