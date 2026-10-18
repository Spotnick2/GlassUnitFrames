-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- checks each recorded "Type:Method" against the API dump's widget-method
-- walk, falling back to the documented functions for animation subtypes the
-- walk does not cover (Alpha:SetToAlpha, Translation:SetOffset).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DUMP = os.getenv("GLASSUF_API_DUMP") or "C:/Projects/WoW/References/Forever/api/forever-api-1.60.1.70450.md"
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
-- Unlock mode: movers, a drag, the nudge panel (so their methods are checked).
UIParent._center = { 512, 384 }
GlassUF.Movers.Unlock()
local mv = GlassUF.Movers._test.movers.target
mv._center = { 800, 300 }
mv._scripts.OnDragStart(mv); mv._scripts.OnUpdate(mv); mv._scripts.OnDragStop(mv)
mv._scripts.OnMouseUp(mv)
-- Every handler the nudge panel installs, through its own closure.
local np = GlassUF.Movers._test.panel()
for _, k in ipairs({ "left", "right", "up", "down" }) do np.buttons[k]._scripts.OnClick(np.buttons[k]) end
for _, e in ipairs({ np.x, np.y }) do
    e:SetText("12"); e._scripts.OnEnterPressed(e)
    e._scripts.OnEscapePressed(e)
end
np.buttons.reset._scripts.OnClick(np.buttons.reset)
np.buttons.lock._scripts.OnClick(np.buttons.lock)
-- The options panel's Unlock button (it closes the Settings window).
local sp = CreateFrame("Frame", "SettingsPanel", UIParent)
rawset(sp, "Close", function(self, skip) self._closed = true; self._skipBack = skip end)   -- SettingsPanel.Close (a mixin method, in the dump's _G walk)
local optPanel = GlassUF.Options._test.panel
optPanel._scripts.OnShow(optPanel)
for _, w in ipairs(WoW.frames) do
    if w._type == "Button" and w._text == "Unlock frames" then w._scripts.OnClick(w) end
end
check(sp._closed, "Unlock frames closes the Settings window through its own Close")
-- Close(true): no transition back to the Game Menu, whose Esc handler calls the
-- protected SpellStopCasting from our call (ADDON_ACTION_FORBIDDEN in game).
eq(sp._skipBack, true, "Close(true): skip the Game Menu transition")
GlassUF.Movers.Lock()
SlashCmdList.GLASSUNITFRAMES("font friz")
SlashCmdList.GLASSUNITFRAMES("reset")
-- Build the options panel so its widget methods are checked too.
GlassUF.Options._test.panel._scripts.OnShow(GlassUF.Options._test.panel)
-- And the Cast bars sub-page (#74), with a detached, scaled, centred bar and
-- its nudge panel's W/H / Scale / Center X.
local castPage = GlassUF.Options._test.castPage
castPage._scripts.OnShow(castPage)
GlassUF.Settings.SetCastDetached("player", true)
GlassUF.Settings.SetCastScale("player", 1.25)
GlassUF.Settings.CenterCast("player")
castPage._scripts.OnShow(castPage)
GlassUF.Movers.Unlock()
local mcast = GlassUF.Movers._test.movers["cast:player"]
mcast._scripts.OnMouseUp(mcast)
local cnp = GlassUF.Movers._test.panel()
cnp.buttons.center._scripts.OnClick(cnp.buttons.center)
GlassUF.Movers.Lock()
GlassUF.Settings.SetCastDetached("player", false)
-- The Quartz look (#78): colours (texts, spark, background), icon, precision.
GlassUF.Settings.SetCastColor("spell", 1, 0.8, 0, 1)
GlassUF.Settings.SetCastColor("background", 0.1, 0.1, 0.2, 0.9)
GlassUF.Settings.SetCastIcon("player", "right")
GlassUF.Settings.SetCastPrecision(2)
WoW.units.player.casting = { name = "Smite", remaining = 1, total = 2 }
WoW.fire("UNIT_SPELLCAST_START", "player"); WoW.tick(0.1)
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player"); WoW.flushTimers()
GlassUF.Settings.ResetCastColors()
GlassUF.Settings.SetCastIcon("player", "left")
GlassUF.Settings.SetCastPrecision(1)
-- The client builds aura buttons and calls initializeFrame: exercise it.
for key, c in pairs(button("target").auraByKey) do
    c._groups["glass_" .. key].spec.initializeFrame(CreateFrame("Button", nil, c))
end
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
