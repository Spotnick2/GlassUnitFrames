-- #86: the experiment never ranks or logs secrets, and never changes live GUF.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
standardUnits()
loadAddon()
local FP = loadForeverProbe()

-- MinimalScrollBar's public mixin contract, from the forever UI source.
-- Model callbacks and geometry explicitly: the generic method sink proves neither.
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    if template == "MinimalScrollBar" then
        f.RegisterCallback = function(self, event, fn, owner) self.callback, self.owner = fn, owner end
        f.Init = function(self, extent, pan) self.extent, self.pan, self.percent = extent, pan, 0 end
        f.SetVisibleExtentPercentage = function(self, v) self.extent = v end
        f.SetPanExtentPercentage = function(self, v) self.pan = v end
        f.SetScrollPercentage = function(self, v)
            self.percent = v
            self.callback(self.owner, v)
        end
    end
    return f
end

local group, raid = false, false
rawset(_G, "IsInGroup", function() return group end)
rawset(_G, "IsInRaid", function() return raid end)
rawset(_G, "IsInInstance", function() return true, "party" end)
local secret = WoW.Secret("threat")
local detailMode = "plain"
rawset(_G, "UnitDetailedThreatSituation", function(u, mob)
    if detailMode == "error" then error(secret) end
    if detailMode == "nil" then return end
    if detailMode == "secret" then return secret, 1, secret, nil, secret end
    return false, 1, 82, 90, 12345
end)
rawset(_G, "UnitThreatLeadSituation", function() return secret end)
rawset(_G, "UnitThreatSituation", function() if detailMode == "secret" then return secret end; return 1 end)
rawset(_G, "UnitThreatPercentageOfLead", function() return nil end)
rawset(_G, "GetThreatStatusColor", function(v) return secret, secret, secret end)
rawset(_G, "C_Secrets", {
    ShouldUnitThreatStateBeSecret = function() return false end,
    ShouldUnitThreatValuesBeSecret = function() return secret end,
})
local ns = {}
assert(loadfile("Tools/ThreatProbe/ThreatProbe.lua"))("ThreatProbe", ns)
assert(loadfile("Tools/ThreatProbe/Preview.lua"))("ThreatProbe", ns)
WoW.fire("ADDON_LOADED", "ThreatProbe")
local T, UI = ns._test, ns.UI
local function fp(s) SlashCmdList.FOREVERPROBE("threat " .. s) end
local function tick(dt) T.boot._scripts.OnUpdate(T.boot, dt) end
local function logged(pattern)
    for _, line in ipairs(FP.lines) do
        if line.m == "ThreatProbe" and line.text:find(pattern, 1, true) then return true end
    end
    return false
end
local watch, render = T.state()
check(not watch and not render and UI.window == nil, "no tracing or windows at login")
eq(T.classify(secret), "secret", "secret classified before formatting")
eq(T.classify(nil), "nil", "nil classified separately")
eq(T.classify(false), "false", "false preserved")
eq(ns.Invoke(nil), "missing API", "missing API distinguished")
eq(ns.Invoke(function() error(secret) end), "error", "secret errors never stringified")

fp("scan")
check(logged("scaled=82 rawPct=90 rawThreat=12345"), "all detailed return positions")
check(logged("leadStatus=secret"), "secret status logged safely")
check(logged("leadPct=nil"), "nil retained")
check(logged("policy=secret"), "secret policy not truth-tested")
check(logged("targettargettarget"), "chained token comparison included")
local lead = UnitThreatLeadSituation
rawset(_G, "UnitThreatLeadSituation", nil)
detailMode = "error"; fp("scan")
check(logged("UnitDetailedThreatSituation error"), "errors logged without their payload")
check(logged("UnitThreatLeadSituation missing API"), "missing functions logged")
rawset(_G, "UnitThreatLeadSituation", lead)

group = true
WoW.SetUnit("party1", { name = "Tank" })
WoW.SetUnit("partypet1", { name = "Pet" })
local units, kind = ns.Roster(false)
eq(kind, "party", "party context")
check(table.concat(units, ","):find("party1,partypet1", 1, true), "party pet included in token order")
raid = true
WoW.units.raid1 = WoW.units.player
WoW.units.raidpet1 = WoW.units.pet
WoW.SetUnit("raid2", { name = "Tank" })
units = ns.Roster(false)
check(not table.concat(units, ","):find("raid1", 1, true), "player alias excluded from render roster")
units = ns.Roster(true)
check(table.concat(units, ","):find("raid1", 1, true), "player alias retained for measurement")
raid = false

-- Coalescing includes event names, and OnUpdate never catches up in a burst.
detailMode = "plain"
fp("watch on")
local _, _, before = T.state()
for i = 1, 20 do WoW.fire("UNIT_THREAT_LIST_UPDATE", secret) end
tick(0.24)
local _, _, n = T.state(); eq(n, before, "no early snapshot")
tick(0.01)
_, _, n = T.state(); eq(n, before + 1, "event burst coalesced")
check(logged("events UNIT_THREAT_LIST_UPDATE"), "trace names the triggering event")
tick(5)
_, _, n = T.state(); eq(n, before + 1, "no repeated unchanged snapshot")
fp("watch off")
WoW.fire("UNIT_THREAT_LIST_UPDATE", "player"); tick(1)
_, _, n = T.state(); eq(n, before + 1, "watch stops")

-- Compact stack: body, pet body, then active docked pet cast.
local pet = GlassUF.Frames.byUnit.pet
local cast = GlassUF.Castbar.bars.pet
pet:Hide()
fp("preview compact")
check(UI.compact:IsShown(), "compact shown")
eq(UI.compactText._text, "#3 · 82%", "rank plus percent to pull")
eq(UI.compact._points[1][2], GlassUF.Frames.byUnit.player.body, "below player without pet")
pet:Show(); cast.host:Hide(); T.dockCompact()
eq(UI.compact._points[1][2], pet.body, "below pet when present")
cast.detached = false; cast.host:Show(); T.dockCompact()
eq(UI.compact._points[1][2], cast.host, "clears docked pet cast")
cast.detached = true; T.dockCompact()
eq(UI.compact._points[1][2], pet.body, "detached cast does not move compact")

fp("preview expanded")
check(UI.window:IsShown() and not UI.compact:IsShown(), "expanded replaces compact")
eq(UI.count, 5, "party sample")
eq(UI.rows[3].value._text, "82%", "player sample percent")
UI.minimize._scripts.OnClick()
check(not UI.container:IsShown() and UI.window:IsShown(), "minimized header survives")
UI.minimize._scripts.OnClick()
check(UI.container:IsShown(), "restored from minimized")
fp("scenario raid")
eq(UI.count, 40, "raid sample")
check(UI.scrollbar:IsShown() and UI.range > 0, "raid scrolls")
UI.viewport._scripts.OnMouseWheel(UI.viewport, -1)
check(UI.scroll > 0, "wheel changes scrollbar and content offset")
eq(UI.rows[40].name._text, "40. Sample 40", "last row exists")
local fullCount = UI.count
UI.count = 1; UI.Layout()
eq(UI.scrollbar.percent, 0, "roster shrink also resets the scrollbar thumb")
UI.count = fullCount; UI.Layout()
UI.window:SetSize(200, 120); UI.window._scripts.OnSizeChanged()
check(UI.range > 850, "resize recomputes scroll range")
fp("scenario restricted")
eq(UI.rows[1].name._text, "Sample 1", "unranked sample has no invented rank")
fp("preview compact")
eq(UI.compactText._text, "#— · 82%", "rank unavailable while percent remains")
fp("scenario empty")
eq(UI.compactText._text, "#— · —", "empty compact is explicit")
fp("preview expanded")
eq(UI.count, 0, "empty window has no old rows")
check(not UI.rows[1].host:IsShown(), "old sample hidden")

-- Saved coordinates belong only to the prototype, and malformed saves clamp.
UIParent._center = { 512, 384 }
UI.window._center = { 412, 204 }
UI.window._scripts.OnDragStart(UI.window)
UI.window._scripts.OnDragStop(UI.window)
eq(ThreatProbeDB.expanded.x, -100, "drag saves parent-relative X")
eq(ThreatProbeDB.expanded.y, -180, "drag saves parent-relative Y")
UI.resize._scripts.OnMouseDown(UI.resize, "LeftButton")
UI.resize._scripts.OnMouseUp()
UI.resize._scripts.OnEnter(UI.resize); UI.resize._scripts.OnLeave(UI.resize)
ThreatProbeDB.compact = { x = 100, y = -50 }
fp("preview compact")
eq(UI.compact._points[1][4], 100, "compact position restored")
ThreatProbeDB.compact = { x = secret, y = 2 }
T.dockCompact()
eq(UI.compact._points[1][2], pet.body, "invalid compact position falls back")
fp("reset")
eq(ThreatProbeDB.compact, nil, "reset forgets compact override")
eq(ThreatProbeDB.expanded, nil, "reset forgets window override")
eq(UI.window:GetWidth(), 300, "reset width")

-- Sample data ends at combat; explicitly enabled diagnostic rendering does not.
WoW.fire("PLAYER_REGEN_DISABLED")
eq(UI.mode, nil, "combat closes samples")
check(not UI.compact:IsShown() and not UI.window:IsShown(), "no sample UI in combat")
WoW.combat = true
fp("preview compact")
eq(UI.mode, nil, "cannot start samples during combat")
detailMode = "secret"
fp("render on")
eq(UI.mode, "diagnostic", "diagnostics allowed in combat")
check(UI.rows[1].bar:GetValue() == secret, "secret percentage handed straight to StatusBar")
check(logged("player:SetFormattedText=ok"), "native text formatting accepted")
check(logged("player:SetStatusBarColor=ok"), "native secret colors accepted")
WoW.fire("PLAYER_TARGET_CHANGED")
eq(UI.rows[1].bar:GetValue(), 0, "target switch clears old values immediately")
detailMode = "nil"; tick(0.25)
eq(UI.rows[1].value._text, "—", "nil never leaves stale percentage")
detailMode = "plain"
local setValue = UI.rows[1].bar.SetValue
UI.rows[1].bar.SetValue = function(self, v) if v == 82 then error("rejected") else setValue(self, v) end end
tick(0.25)
check(logged("player:SetValue=error"), "one native rejection is reported")
eq(UI.rows[1].value._text, "82%", "text still tested after bar rejection")
UI.rows[1].bar.SetValue = setValue
fp("render off")
watch, render = T.state(); check(not render and not UI.window:IsShown(), "diagnostics stop")
fp("render on"); WoW.fire("PLAYER_ENTERING_WORLD")
watch, render = T.state(); check(not render and UI.mode == nil, "world transition stops diagnostics")
WoW.combat = false
fp("preview off"); fp("watch invalid"); fp("render invalid"); fp("preview invalid"); fp("scenario invalid")
check(#WoW.blocked == 0, "no protected frame changes")
eq(GlassUnitFramesDB.threat, nil, "production settings untouched")

-- Reload restores only prototype placement, never tracing or diagnostics.
-- The optional suite contract supplies the same backing and accent as its meter.
ThreatProbeDB.expanded = { x = -123, y = 45, w = 999, h = 10 }
local body = { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = { 0.025, 0.03, 0.045, 0.35 } }
local accent = { 0.65, 0.835, 0.905 }
rawset(_G, "GlassUI", { Suite = { API = 1, LOOK_EVENT = "GlassUI.Suite.LookChanged",
    Body = function() return body end, Accent = function() return accent end } })
local ns2 = {}
assert(loadfile("Tools/ThreatProbe/ThreatProbe.lua"))("ThreatProbe", ns2)
assert(loadfile("Tools/ThreatProbe/Preview.lua"))("ThreatProbe", ns2)
WoW.fire("ADDON_LOADED", "ThreatProbe")
local w2, r2 = ns2._test.state()
check(not w2 and not r2 and ns2.UI.window == nil, "reload does not restart experiments")
ns2.UI.Preview("expanded")
local ui2 = ns2.UI
eq(ui2.window._points[1][4], -123, "reload restores expanded X")
eq(ui2.window:GetWidth(), 600, "saved width bounded")
eq(ui2.window:GetHeight(), 120, "saved height bounded")
eq(ui2.surfaces[1].backing._color[4], 0.35, "suite meter backing, not opaque window floor")
body.backing[4] = 0.92
EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged")
eq(ui2.surfaces[1].backing._color[4], 0.92, "suite changes repaint surfaces live")
body = { classShade = 0.6, wash = 1, backing = { 0, 0, 0, 0.35 } }
ui2.Restyle()
check(ui2.surfaces[1].g.tint._color ~= nil, "class tint can repaint")
ui2.Hide()

-- Every native method exercised here must exist on the measured client.
-- MinimalScrollBar methods above belong to FrameXML, not the native dump.
local dump = io.open(os.getenv("GLASSUF_API_DUMP") or "C:/Projects/WoW/References/Forever/api/forever-api-1.60.1.70450.md", "r")
if dump then
    local methods = {}
    for line in dump:lines() do
        local method = line:match("^(%a+:%a+)%s*$")
        if method then methods[method] = true end
    end
    dump:close()
    for method in pairs(WoW.methodsCalled) do
        -- EventFrame is a Frame with a Lua mixin (used by MinimalScrollBar).
        local native = method:gsub("^EventFrame:", "Frame:")
        local kind = native:match("^(%a+):")
        if kind == "Frame" or kind == "Button" or kind == "StatusBar" or kind == "FontString" or kind == "Texture" then
            check(methods[native], "native widget method exists: " .. native)
        end
    end
end

-- The host enforces the saved-log cap, not just the display's line limit.
for i = 1, 4010 do T.Probe:Say("bounded " .. i) end
check(#ThreatProbeDB.log <= 4000, "saved log bounded")
fp("clear")
check(#ThreatProbeDB.log <= 1, "clear removes saved measurements")
done("test_threatprobe")
