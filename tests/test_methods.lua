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

-- Methods the dump cannot list: Blizzard_AuraContainer is a load-on-demand
-- Blizzard addon the dump did not capture. Evidence they exist on Forever:
-- DinoUnitFrames (ships on this client) calls every one of them
-- (modules/auras.lua ForeverEnsureAuraContainer / ForeverInitAuraButton).
-- Keep this list exact: anything else missing from the dump still fails.
local AURA_CONTAINER_API = {
    AddAuraGroup = true, UpdateAllAuras = true, SetUnit = true, SetAuraGroupLayout = true,
    SetFlowLayoutAnchorPoint = true, SetFlowLayoutAxis = true, SetFlowLayoutMaximumLineSize = true,
    SetFlowLayoutGrowthDirection = true, SetFlowLayoutPadding = true,
    -- on the buttons the container creates
    SetIcon = true, SetDurationCooldown = true, SetDurationText = true, SetApplicationCount = true,
}

local n = 0
for name in pairs(WoW.methodsCalled) do
    n = n + 1
    local method = name:match(":(%a+)$")
    local wtype = name:match("^(%a+):")
    local ok = widget[name] or documented[method]
        or (wtype == "AuraContainer" and (AURA_CONTAINER_API[method] or widget["Frame:" .. method]))
    check(ok, "method exists on Forever: " .. name)
end
check(n > 40, "recorded a realistic number of methods (" .. n .. ")")
done("test_methods")
