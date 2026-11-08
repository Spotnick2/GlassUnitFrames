-- Every widget method the addon calls must exist on this client, on that
-- widget type: the stub answers any method (a no-op for one it doesn't
-- implement), so a call Forever lacks would otherwise pass silently. The
-- addon is exercised as widely as is cheap, then WowTestKit's
-- Kit.checkMethods checks each recorded "Type:Method" against the pinned
-- build's widget methods (an animation subtype may also call Animation's).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

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
-- The cast look (#78): colours (texts, spark, background), icon, precision.
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
-- Blizzard addon the dump did not capture, so neither its widget type nor
-- the methods of the buttons it creates are in the widget walk. Evidence they
-- exist on Forever: DinoUnitFrames (ships on this client) calls every one of
-- them (modules/auras.lua ForeverEnsureAuraContainer / ForeverInitAuraButton),
-- and an AuraContainer is a Frame underneath. Keep this list exact: anything
-- else missing from the build still fails.
local DINO = "DinoUnitFrames-Forever modules/auras.lua (Blizzard_AuraContainer, not in the dump)"
local allow = {
    ["AuraContainer:AddAuraGroup"] = DINO, ["AuraContainer:UpdateAllAuras"] = DINO,
    ["AuraContainer:SetUnit"] = DINO,
    ["AuraContainer:SetFlowLayoutAnchorPoint"] = DINO, ["AuraContainer:SetFlowLayoutAxis"] = DINO,
    ["AuraContainer:SetFlowLayoutMaximumLineSize"] = DINO, ["AuraContainer:SetFlowLayoutGrowthDirection"] = DINO,
    ["AuraContainer:SetFlowLayoutPadding"] = DINO,
    -- on the buttons the container creates (a Button in the tests)
    ["Button:SetIcon"] = DINO, ["Button:SetDurationCooldown"] = DINO,
    ["Button:SetDurationText"] = DINO, ["Button:SetApplicationCount"] = DINO,
}
-- Any other method on an AuraContainer must be a Frame method in the pinned
-- build (a Frame underneath); one that isn't stays unallowed, and fails.
local known = Kit.data("widgetMethods")
for name in pairs(WoW.methodsCalled) do
    local method = name:match("^AuraContainer:(%a+)$")
    if method and not allow[name] and known["Frame:" .. method] then
        allow[name] = "an AuraContainer is a Frame underneath (Frame:" .. method .. ")"
    end
end

local recorded = Kit.checkMethods({ allow = allow })
-- The floor: what the exercise records today (218), rounded down, so it can't quietly shrink.
check(recorded >= 210, "the exercise reached the frames, movers and options pages (" .. recorded .. " recorded)")
done("test_methods")
