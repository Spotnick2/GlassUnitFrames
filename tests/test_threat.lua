-- Real state transitions and the measured 70532 party tuples, including

-- mixed secret/plain data. No native widget is allowed to format a secret in Lua.

dofile("tests/wow_stubs.lua")

dofile("tests/harness.lua")

standardUnits()

local grouped, raid, hostile = false, false, true

local data, lead, sounds, tankRole = {}, 0, {}, false

rawset(_G, "IsInGroup", function() return grouped end)

rawset(_G, "IsInRaid", function() return raid end)

rawset(_G, "UnitCanAttack", function() return hostile end)

rawset(_G, "UnitDetailedThreatSituation", function(u, mob)

    assert(mob == "target", "only direct target token")

    if data[u] == "error" then error("failed read") end

    if data[u] then return unpack(data[u]) end

end)

rawset(_G, "UnitThreatLeadSituation", function() return lead end)

rawset(_G, "PlayerUtil", { IsPlayerEffectivelyTank = function() return tankRole end })

rawset(_G, "PlaySoundFile", function(path, channel) sounds[#sounds + 1] = { path, channel }; return true, 1 end)

-- Public MinimalScrollBar mixin, verified in the forever FrameXML source.

local create = CreateFrame

CreateFrame = function(kind, name, parent, template)

    local f = create(kind, name, parent, template)

    f.SetClampedToScreen = function(self, on) self.clamped = on end
    if template == "MinimalScrollBar" then

        f.RegisterCallback = function(self, event, fn, owner) self.callback, self.owner = fn, owner end

        f.Init = function(self, extent, pan) self.extent, self.pan, self.percent = extent, pan, 0 end

        f.SetVisibleExtentPercentage = function(self, value) self.extent = value end

        f.SetPanExtentPercentage = function(self, value) self.pan = value end

        f.SetScrollPercentage = function(self, value) self.percent = value; self.callback(self.owner, value) end

    end

    return f

end

loadAddon()

local T, V, S = GlassUF.Threat, GlassUF.ThreatView, GlassUF.Settings

local function command(s) SlashCmdList.GLASSUNITFRAMES("threat " .. s) end

local function refresh() T.Refresh() end

local function fight(on)

    WoW.combat = on

    WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")

end

eq(T.Mode(), "group", "group display enabled by default")

check(T.enabled and T.SoundEnabled() and T.Expand(), "feature, sound and combat expansion default on")

eq(V.window, nil, "solo default does not build UI")



grouped = true

WoW.SetUnit("party1", { name = "Other", class = "HUNTER", player = true })

WoW.SetUnit("partypet1", { name = "Other Pet" })

data.player = { false, 0, 0, 0, 0 }

data.party1 = { true, 3, 100, 255, 192 }

data.partypet1 = { false, 0, 43.63636, 48, 94 }

WoW.fire("GROUP_ROSTER_UPDATE")

eq(V.window, nil, "group idle is hidden by default")

eq(T.HideDelay(), 10, "post-combat delay defaults to ten seconds")

fight(true)

check(V.compact:IsShown() and not V.window:IsShown(), "group idle is compact")

eq(V.compactSummary.rank._text, "#3 ·", "rank includes group pets")

eq(V.compactText._text, "0%", "real zero is displayed")

eq(T.Display(), "compact", "new default is click-to-expand")

S.SetThreatExpand(true)

eq(V.compact._points[1][1], "BOTTOMLEFT", "compact uses a bottom-left anchor")

eq(V.compact._points[1][3], "RIGHT", "compact beside target outer edge")

eq(T.snapshot.rows[1].unit, "party1", "raw 192 first")

eq(T.snapshot.rows[2].unit, "partypet1", "raw 94 second")

fight(true)

check(V.window:IsShown() and not V.compact:IsShown(), "combat expands")

eq(V.window._alpha, 0, "expansion starts transparent")

V.window._scripts.OnUpdate(V.window, 0.125)

eq(V.window._alpha, 0.5, "expansion fades halfway")

refresh()

eq(V.window._alpha, 0.5, "data refresh does not restart fade")

V.window._scripts.OnUpdate(V.window, 0.125)

eq(V.window._alpha, 1, "expansion finishes opaque")

fight(false)

check(V.window:IsShown(), "combat end keeps panel during grace period")

WoW.now = WoW.now + 10; refresh()

check(V.window.animation and V.window.animation.to == 0, "delay starts reverse animation")

V.window._scripts.OnUpdate(V.window, 0.25)

check(not V.window:IsShown() and not V.compact:IsShown(), "reverse animation closes meter")

T.SetDisplay("compact"); fight(true)

eq(V.compact._alpha, 0, "compact reappearance animates")

V.compact._scripts.OnUpdate(V.compact, 0.25)

eq(V.compact._alpha, 1, "compact opening completes")

S.SetThreatExpand(true)

eq(V.rows[1].name._text, "Other", "expanded name separate from rank")

eq(V.rows[2].value._text, "44%", "scaled percent rather than raw percent")

eq(#sounds, 0, "safe threat is silent")



-- Non-tank warning, hysteresis, cooldown and secret gaps.

data.player = { false, 1, 90, 99, 190 }

refresh()

eq(#sounds, 1, "crossing 90 percent warns")

check(sounds[1][1]:find("BoxingArenaSound.ogg", 1, true), "requested gong asset")

eq(sounds[1][2], "Master", "warning channel")

refresh(); refresh()

eq(#sounds, 1, "same warning does not repeat")

data.player[3] = 87; refresh(); data.player[3] = 91; refresh()

eq(#sounds, 1, "85-90 hysteresis prevents chatter")

data.player[3] = 80; refresh(); data.player[3] = 91; refresh()

eq(#sounds, 1, "cooldown also prevents immediate re-entry spam")

WoW.now = WoW.now + 6

data.player[3] = 80; refresh(); data.player[3] = 91; refresh()

eq(#sounds, 2, "safe then risky can warn after cooldown")

S.SetThreatSound(false)

WoW.now = WoW.now + 6

data.player[3] = 80; refresh(); data.player[3] = 91; refresh()

eq(#sounds, 2, "sound toggle disables automatic warnings")

S.SetThreatSound(true)

refresh(); eq(#sounds, 2, "re-enabling does not replay current warning")



local secret = WoW.Secret("threat")

data.player = { secret, secret, secret, secret, secret }

WoW.secretFields.name = true

refresh()

check(not T.snapshot.ranked, "mixed secret raw values disable all ranks")

eq(T.snapshot.rows[1].unit, "player", "restricted roster uses stable group order")

eq(T.snapshot.rows[2].rank, nil, "plain rows do not retain old ranks")

check(V.rows[1].bar:GetValue() == secret, "secret percent goes directly to native bar")

eq(V.rows[1].value._text.secretFormat, "%.0f%%", "native formatting receives secret")

eq(#sounds, 2, "unknown danger does not play sound")

S.SetThreatExpand(false)

check(V.compact:IsShown(), "expansion can be disabled during combat")

eq(V.compactText._text.secretFormat, "%.0f%%", "unknown rank keeps native percentage")

WoW.secretFields.name = nil

data.player = "error"; refresh()

eq(V.compactText._text, "—", "read failure clears stale secret percentage")

data.player = nil; refresh()

eq(T.snapshot.player, nil, "nil tuple is no threat entry, not zero")

local detailed = UnitDetailedThreatSituation

rawset(_G, "UnitDetailedThreatSituation", nil); refresh()

check(not T.snapshot.ranked, "missing API cannot produce fabricated ranks")

rawset(_G, "UnitDetailedThreatSituation", detailed)



-- Secret hostility hides values instead of branching on it or using stale data.

hostile = secret; refresh()

eq(V.compactText._text, "—", "unreadable target clears compact")

hostile = false; command("always")

eq(V.count, 0, "friendly target has explicit empty window")

hostile = true

data.player = { true, 3, 100, 255, 210 }

refresh(); eq(#sounds, 2, "holding aggro does not trigger approaching-aggro sound")

data.player = { false, 3, 231.818176, 255, 0 }

refresh()

eq(V.rows[#T.snapshot.rows].value._text, "232%", "measured over-100 percent is preserved in text")

check(T.snapshot.player.tank == false, "status 3 does not overwrite explicit tanking false")



-- Tank colours use the lead API; manual role wins over automatic role.

data.player = { true, 3, 100, 255, 210 }

GlassUF.Zoom.role = "tank"

lead = 0; refresh(); local beforeTank = #sounds

eq(T.snapshot.color, T.COLORS[1], "secure tank is green, not red")

WoW.now = WoW.now + 6

lead = 1; refresh(); eq(#sounds, beforeTank + 1, "tank's weakening lead warns")

eq(T.snapshot.color, T.COLORS[2], "tank lead colour")

lead = secret; refresh()

eq(T.snapshot.color, T.UNKNOWN, "secret tank lead not indexed or compared")

GlassUF.Zoom.role = "dps"; refresh()

eq(T.snapshot.color, T.COLORS[4], "non-tank holding aggro is red")

GlassUF.Zoom.role = nil; tankRole = true; lead = 0; refresh()

eq(T.snapshot.color, T.COLORS[1], "auto tank detection when no manual role")

tankRole = false



-- Per-role expansion, group departure, Always and Off.

command("on"); GlassUF.Zoom.role = "healer"; S.SetThreatExpand(true)

check(T.Expand(), "role override on")

GlassUF.Zoom.role = nil; check(not T.Expand(), "global expansion remains off")

fight(false)

grouped = false; WoW.fire("GROUP_ROSTER_UPDATE")

check(not V.compact:IsShown() and not V.window:IsShown(), "leaving group hides default display")

command("always"); fight(true)

check(V.window:IsShown(), "solo combat mode includes solo fights")

command("off")

check(not T.enabled and not V.window:IsShown(), "Off hides display")

eq(GlassUnitFramesDB.threat.mode, "off", "Off persisted")

fight(false)

command("preview expanded")

eq(V.count, 5, "explicit preview available while disabled")

fight(true)

check(T.preview == nil and not V.window:IsShown(), "combat ends sample preview")

check(not T.Preview("compact"), "preview refused in combat")

fight(false)

command("preview compact")

eq(V.compactText._text, "82%", "placement preview")

UIParent._center = { 512, 384 }

V.compact._center = { 200, 240 }

V.compact._scripts.OnDragStart(V.compact); V.compact._scripts.OnDragStop(V.compact)

check(GlassUnitFramesDB.threat.compactAnchor ~= nil, "compact bottom-left position saved in GUF")

command("preview expanded")

V.window._center = { 200, 160 }

V.window:SetSize(250, 160)

V.resize._scripts.OnMouseDown(V.resize, "LeftButton"); V.window:SetSize(250, 160); V.resize._scripts.OnMouseUp()

eq(GlassUnitFramesDB.threat.size.w, 250, "resized width saved")

V.minimize._scripts.OnClick(); check(V.compact:IsShown() and not V.window:IsShown(), "collapse replaces panel")

V.compact._scripts.OnMouseDown(); V.compact._scripts.OnClick(); check(V.window:IsShown(), "click expands plate")

command("reset")

eq(GlassUnitFramesDB.threat.compact, nil, "reset clears compact override")

V.window._scripts.OnUpdate(V.window, 0.25)
eq(V.window:GetWidth(), 300, "reset restores width")

command("preview off")



-- Raid roster must not duplicate the player's alias or their pet.

grouped, raid = true, true

WoW.units.raid1 = WoW.units.player; WoW.units.raidpet1 = WoW.units.pet

WoW.units.raid2 = WoW.units.party1

data.pet = { false, 0, 30, 33, 50 }

data.raid2 = { false, 0, 50, 55, 100 }

command("on"); fight(true)

local seen = {}

for _, e in ipairs(T.snapshot.rows) do check(not seen[e.unit], "unique raid token " .. e.unit); seen[e.unit] = true end

check(seen.player and not seen.raid1 and not seen.raidpet1, "player and pet aliases replaced")

-- Use enough members to exercise native scrolling and roster shrink cleanup.

for i = 3, 40 do WoW.SetUnit("raid" .. i, { name = "Raider " .. i }); data["raid" .. i] = { false, 0, 1, 1, i } end

command("always")

check(V.range > 0 and V.scrollbar:IsShown(), "large raid scrolls")

V.viewport._scripts.OnMouseWheel(V.viewport, -1)

check(V.scroll > 0, "wheel scrolls real roster")

raid, grouped = false, false

data = {}; refresh()

eq(V.count, 0, "roster shrink removes old rows")

eq(V.scrollbar.percent, 0, "empty roster resets scrollbar")

check(not V.rows[1].host:IsShown(), "no stale row after roster shrink")



-- Settings controls call the real setters and keep the explicit defaults.

local page = GlassUF.Options._test.threatPage

page._scripts.OnShow(page)

local controls = GlassUF.Options._test.controls

controls.threatHideDelay:SetValue(4)

eq(T.HideDelay(), 4, "settings hide delay control")

controls.threatMode[3]._scripts.OnClick()

eq(T.Mode(), "off", "settings Off control")

controls.threatMode[1]._scripts.OnClick()

eq(T.Mode(), "group", "settings default control")

controls.threatSound:SetChecked(false); controls.threatSound._scripts.OnClick(controls.threatSound)

check(not T.SoundEnabled(), "settings sound control")

controls.threatExpand:SetChecked(true); controls.threatExpand._scripts.OnClick(controls.threatExpand)

check(T.Expand(), "settings expansion control")

check(not T.SetMode("bad") and not T.SetSound("yes") and not T.Preview("bad"), "invalid settings rejected")

-- Cohesive plate: same metric, raw rank distinct from actual holder, transient tooltip.

grouped, raid, hostile = true, false, true

WoW.units.target.dead = false

WoW.units.party1.name = "A very long participant name that must be truncated"

data = { player = { false, 0, 48, 62, 220 }, party1 = { true, 3, 100, 100, 200 } }

command("on"); command("view compact"); fight(true)

V.compact._scripts.OnUpdate(V.compact, 0.25)

eq(V.compactSummary.rank._text, "#1 ·", "highest raw threat need not hold aggro")

eq(V.compactText._text, "48%", "compact uses scaled percent")

eq(V.compactFill:GetValue(), 48, "compact strip matches percentage")

local width = V.compact:GetWidth()

V.compact._scripts.OnEnter()

check(V.tooltip:IsShown(), "hover opens temporary details")

eq(V.tipHolder._text, WoW.units.party1.name, "holder comes from tanking flag, not rank")

eq(V.tipRows[1].name._text, WoW.units.player.name, "tooltip shares sorted snapshot")

check(not V.tipRows[1].aggro:IsShown() and V.tipRows[2].aggro:IsShown(), "actual holder marker differs from rank one")

eq(T.Display(), "compact", "hover does not persist expanded mode")

V.compact._scripts.OnLeave(); check(not V.tooltip:IsShown(), "leave closes tooltip")

V.compact._scripts.OnEnter(); V.compact._scripts.OnMouseDown(); V.compact._scripts.OnClick()

check(not V.tooltip:IsShown() and V.window:IsShown(), "click replaces plate and closes tooltip")

eq(GlassUnitFramesDB.threat.view, "expanded", "click saves expanded mode")

V.window._scripts.OnUpdate(V.window, 0.25)

eq(V.window:GetHeight(), 80, "two rows fit header plus padding without unused space")

check(V.rows[1].you:IsShown() and V.rows[1].edge:IsShown(), "local row has You and pale edge")

check(not V.rows[1].aggro:IsShown() and V.rows[2].aggro:IsShown(), "expanded actual holder is independent of raw rank")

eq(V.rows[2].name._text, WoW.units.party1.name, "long name handed intact to constrained native text")

T.Configure(GlassUnitFramesDB)

eq(T.Display(), "expanded", "saved display restored on configuration load")

V.minimize._scripts.OnClick()
V.compact._scripts.OnUpdate(V.compact, 0.25)

eq(T.Display(), "compact", "collapse persists compact mode")

data.player[3] = 231.818176; refresh()

eq(V.compactText._text, "232%", "over-100 numeric meaning preserved")

eq(V.compactFill:GetValue(), 100, "only graphical fill clamps")

eq(V.compact:GetWidth(), width, "changing rank and percentage keeps fixed width")

data.player[3] = 0; refresh(); eq(V.compactText._text, "0%", "zero remains distinct from missing")

V.compact._scripts.OnEnter(); WoW.units.target.dead = true; refresh()

check(not V.tooltip:IsShown(), "target death closes tooltip")

eq(V.compactText._text, "—", "target death clears stale percent")

eq(V.compactFill:GetValue(), 0, "target death clears fill")

WoW.units.target.dead = false; refresh(); V.compact._scripts.OnEnter()

WoW.fire("PLAYER_TARGET_CHANGED")

check(not V.tooltip:IsShown(), "target switch closes old tooltip even with new valid target")

local savedTarget = WoW.units.target; WoW.units.target = nil; WoW.fire("PLAYER_TARGET_CHANGED")

check(not V.compact:IsShown() and not V.tooltip:IsShown(), "target clearing immediately hides meter and tooltip")

WoW.units.target = savedTarget; refresh()



-- Grace period and reversible animation: fixed bottom anchor, no restart on updates.

command("view expanded"); V.window._scripts.OnUpdate(V.window, 0.25)

command("delay 3"); fight(false)

local full = V.window:GetWidth()

WoW.now = WoW.now + 2.9; refresh()

check(V.window:IsShown() and not V.closing, "still open just before configured deadline")

WoW.now = WoW.now + 0.2; refresh()

V.window._scripts.OnUpdate(V.window, 0.125)

eq(V.window:GetWidth(), full / 2, "side dock closes right to left")

eq(V.window._points[1][1], "BOTTOMLEFT", "animation retains lower-left anchor")

local partial = V.window.open

fight(true)

eq(V.window.open, partial, "new combat reverses without snapping")

V.window._scripts.OnUpdate(V.window, 0.25)

eq(V.window:GetWidth(), full, "reversed animation fully reopens")

command("delay 0"); fight(false)

check(V.closing == V.window, "zero delay starts close immediately")

V.window._scripts.OnUpdate(V.window, 0.25)

check(not V.window:IsShown(), "zero delay still performs closing animation")

command("always"); T.Configure(GlassUnitFramesDB)

check(not V.window:IsShown() and not V.compact:IsShown(), "solo option does not show idle meter after reload")

GlassUnitFramesDB.threat.showOutOfCombat = true; refresh()

check(not V.compact:IsShown(), "obsolete idle preference cannot override combat-only visibility")



-- Position migration and layout: legacy overrides survive until reset or drag.

GlassUnitFramesDB.threat.anchor = nil

GlassUnitFramesDB.threat.compact = { x = -100, y = 100 }

GlassUnitFramesDB.threat.expanded = { x = 120, y = 80, w = 280, h = 160 }

command("preview compact")

eq(V.compact._points[1][2], UIParent, "legacy compact remains independently positioned")

eq(V.compact._points[1][4], -160, "legacy compact centre converted to fixed lower edge")

command("preview expanded")

eq(V.window._points[1][4], -20, "legacy expanded position preserved")

command("reset")

local target = GlassUF.Frames.byUnit.target

local tot = GlassUF.Frames.byUnit.targettarget

local tott = GlassUF.Frames.byUnit.targettargettarget

tot:Hide(); tott:Hide(); V.Reanchor()

eq(V.window._points[1][2], GlassUF.Frames.EdgeVisual(target, "right"), "reset anchors to outer target visual")

eq(V.window._points[1][4], 8, "eight units beyond target outer edge")
local dockY = V.window._points[1][5]
local portraitMode = target.portraitMode
GlassUF.Frames.SetPortraitMode("target", "none")
eq(V.window._points[1][2], target.body, "no portrait docks at body edge")
GlassUF.Frames.SetPortraitMode("target", portraitMode)
eq(V.window._points[1][2], GlassUF.Frames.EdgeVisual(target, "right"), "restoring portrait moves dock outside portrait")

command("preview compact")

eq(V.compact._points[1][2], V.window._points[1][2], "both default modes share target anchor")

eq(V.compact._points[1][5], V.window._points[1][5], "both default modes share clearance")

target.body._center = { 700, 300 }; tot.body._center = { 700, 360 }

tot:Show(); V.Reanchor()

eq(V.compact._points[1][5], dockY, "target-of-target visibility does not shift side dock")

tot:Hide(); V.Reanchor()

eq(V.compact._points[1][5], dockY, "follower hide does not shift side dock")

GlassUF.Frames.SetPosition("target", 50, 60)

eq(V.compact._points[1][2], GlassUF.Frames.EdgeVisual(target, "right"), "moving target preserves native relative attachment")

command("preview off")



check(V.window.clamped and V.compact.clamped and V.tooltip.clamped, "both views and tooltip request screen clamping")
command("preview compact"); V.compact._scripts.OnEnter()
local allocated = #WoW.frames
for i = 1, 20 do refresh() end
eq(#WoW.frames, allocated, "steady tooltip updates reuse frames")
S.SetFont("friz")
local path = V.compactText:GetFont()
eq(path, GlassUF.Glass.FONTS.friz.file, "threat typography follows unit-frame font changes")
command("preview off")

-- Native methods used by the new view must be present in the measured API dump.
-- Color changes continuously without changing the warning threshold or tank rules.
local function feedbackAt(pct)
    local snapshot = { player = { tank = false, status = 0, scaled = pct } }
    local danger = T.Feedback(snapshot, false)
    return snapshot.color, danger
end
local low, lowDanger = feedbackAt(0)
local middle, middleDanger = feedbackAt(45)
local warning, warningDanger = feedbackAt(90)
local high = feedbackAt(95)
eq(low[1], T.COLORS[1][1], "zero starts mint")
check(middle[1] > low[1] and middle[3] < low[3], "percentage progressively warms safe state")
eq(warning[2], T.COLORS[2][2], "existing 90 percent warning point is amber")
check(high[2] < warning[2], "above warning progresses toward coral")
check(not lowDanger and not middleDanger and warningDanger, "visual gradient does not alter warning threshold")
local restricted = { player = { tank = false, scaled = secret } }
T.Feedback(restricted, false)
eq(restricted.color, T.UNKNOWN, "secret percentage is never interpolated")

-- Side docking stays stationary across cast visibility and geometry changes.
command("preview compact"); command("reset")
local cast = GlassUF.Castbar.bars.target
local geometry = GlassUF.Castbar.EffectiveGeometry
local castX = 188
GlassUF.Castbar.EffectiveGeometry = function(unit)
    if unit == "target" then return castX, 0, 200, 20, true, 1.5 end
    return geometry(unit)
end
cast.host:Hide(); V.Reanchor()
local reserved = V.compact._points[1][5]
eq(reserved, dockY, "cast destination does not lift side dock")
cast.host:Show()
eq(V.compact._points[1][5], reserved, "cast start does not shift reserved placement")
cast.host:Hide()
eq(V.compact._points[1][5], reserved, "cast end retains reserved placement")
castX = -800; GlassUF.Castbar.Place(cast)
eq(V.compact._points[1][5], dockY, "moving cast does not shift side dock")
T.SaveGeometry("anchor", { x = 20, y = 40 })
castX = 188; V.Reanchor()
eq(V.compact._points[1][4], 20, "custom anchor remains owner-controlled")
eq(V.compact._points[1][5], 40, "cast avoidance does not overwrite custom placement")
GlassUF.Castbar.EffectiveGeometry = geometry
command("reset"); command("preview off")

-- Freeze the last meaningful combat snapshot, including when the kill clears APIs
-- before PLAYER_REGEN_ENABLED. Never carry it across a target change or new fight.
command("on"); command("view compact"); command("delay 3")
grouped, hostile = true, true
WoW.units.target = savedTarget; WoW.units.target.dead = false
fight(true)
data = { player = { false, 0, 48, 62, 100 }, party1 = { true, 3, 100, 100, 200 } }
refresh(); V.compact._scripts.OnUpdate(V.compact, 0.25)
local finalCombat = T.snapshot
WoW.units.target.dead = true; data = {}; refresh()
fight(false)
eq(T.snapshot, finalCombat, "combat exit retains last meaningful values before target death")
eq(V.compactText._text, "48%", "post-combat compact freezes percentage")
eq(V.compactFill:GetValue(), 48, "post-combat fill freezes same metric")
command("view expanded")
eq(V.rows[2].value._text, "48%", "expanding after combat uses frozen ranking")
WoW.now = WoW.now + 3.1; refresh()
V.window._scripts.OnUpdate(V.window, 0.125)
eq(V.rows[2].value._text, "48%", "values survive through reverse animation")
V.window._scripts.OnUpdate(V.window, 0.125)
check(not V.window:IsShown(), "frozen panel hides after fade")
WoW.units.target.dead = false; fight(true)
data = { player = { false, 0, 12, 15, 20 } }; refresh(); fight(false)
WoW.fire("PLAYER_TARGET_CHANGED")
check(T.snapshot == nil, "changing target discards frozen snapshot")
V.window._scripts.OnUpdate(V.window, 0.25)
check(not V.window:IsShown(), "new target does not inherit post-combat display")
fight(true); refresh(); fight(false)
WoW.units.target = nil; WoW.fire("PLAYER_TARGET_CHANGED")
check(not V.window:IsShown() and not V.compact:IsShown(), "clearing target during grace hides immediately")
WoW.units.target = savedTarget
fight(true); data = {}; refresh()
check(T.snapshot.player == nil, "new fight cannot reuse prior combat values")
fight(false); command("off")

-- Reveal direction follows the attachment position, with the near edge fixed.
command("off"); command("preview compact")
local targetBody = GlassUF.Frames.byUnit.target.body
local tx, ty = targetBody:GetCenter()
local ux, uy = UIParent:GetCenter()
local k = targetBody:GetEffectiveScale() / UIParent:GetEffectiveScale()
local cx, cy = tx * k - ux, ty * k - uy
for _, spec in ipairs({ { "right", 300, 0 }, { "left", -300, 0 }, { "up", 0, 300 }, { "down", 0, -300 } }) do
    V.Hide()
    T.SaveGeometry("anchor", { x = cx + spec[2] - 56, y = cy + spec[3] - 11 })
    refresh()
    eq(V.compact.direction, spec[1], "direction inferred for " .. spec[1])
    V.compact._scripts.OnUpdate(V.compact, 0.125)
    local horizontal = spec[1] == "right" or spec[1] == "left"
    eq(V.compact:GetWidth(), horizontal and 56 or 112, "halfway width for " .. spec[1])
    eq(V.compact:GetHeight(), horizontal and 22 or 11, "halfway height for " .. spec[1])
    local point = V.compact._points[1]
    eq(point[4], cx + spec[2] - 56 + (spec[1] == "left" and 56 or 0), "horizontal attachment held for " .. spec[1])
    eq(point[5], cy + spec[3] - 11 + (spec[1] == "down" and 11 or 0), "vertical attachment held for " .. spec[1])
    V.compact._scripts.OnUpdate(V.compact, 0.125)
end
command("reset"); command("preview off")

-- Compact and expanded placements are independent; old shared saves survive.
command("off"); command("reset")
T.SaveGeometry("anchor", { x = 100, y = 50 })
command("preview compact")
V.compact._scripts.OnUpdate(V.compact, 0.25)
local compactBefore = V.compact.dockPoint
command("preview expanded")
V.window._scripts.OnUpdate(V.window, 0.25)
V.window._center = { 700, 180 }
V.window._scripts.OnDragStart(V.window); V.window._scripts.OnDragStop(V.window)
local expandedSaved = T.Geometry("expandedAnchor")
check(expandedSaved ~= nil, "expanded drag saves its own placement")
eq(T.Geometry("compactAnchor"), nil, "expanded drag does not write compact placement")
eq(T.Geometry("anchor").x, 100, "old shared anchor retained for unmoved compact")
command("preview compact")
eq(V.compact.dockPoint.x, compactBefore.x, "expanding and dragging leaves compact x unchanged")
eq(V.compact.dockPoint.y, compactBefore.y, "expanding and dragging leaves compact y unchanged")
V.compact._center = { 300, 420 }
V.compact._scripts.OnDragStart(V.compact); V.compact._scripts.OnDragStop(V.compact)
check(T.Geometry("compactAnchor") ~= nil, "compact drag saves separate position")
eq(T.Geometry("expandedAnchor"), expandedSaved, "compact drag preserves expanded save")
T.Configure(GlassUnitFramesDB)
command("preview expanded")
eq(V.window.dockPoint.x, expandedSaved.x, "expanded placement restored from settings")
eq(V.window.dockPoint.y, expandedSaved.y, "expanded placement restored vertically")
command("reset")
eq(T.Geometry("compactAnchor"), nil, "reset clears compact placement")
eq(T.Geometry("expandedAnchor"), nil, "reset clears expanded placement")
eq(T.Geometry("anchor"), nil, "reset clears shared migration fallback")
command("preview off")

local dump = io.open("C:/Projects/WoW/References/Forever/api/forever-api-1.60.1.70450.md", "r")
if dump then
    local methods = {}
    for line in dump:lines() do local name = line:match("^(%a+:%a+)%s*$"); if name then methods[name] = true end end
    dump:close()
    local missing = {}
    for name in pairs(WoW.methodsCalled) do
        local kind = name:match("^(%a+):")
        if (kind == "Frame" or kind == "Button" or kind == "Texture" or kind == "FontString" or kind == "StatusBar") and not methods[name] then
            missing[#missing + 1] = name
        end
    end
    eq(#missing, 0, "view's native widget methods exist: " .. table.concat(missing, ", "))
else
    io.write("threat widget method audit skipped: local API dump unavailable\n")
end

eq(next(GlassUF.paintFailures), nil, "no swallowed errors")

eq(#WoW.blocked, 0, "no protected mutations in combat")

local soundFile = assert(io.open("Sounds/BoxingArenaSound.ogg", "rb"))

eq(soundFile:read(4), "OggS", "bundled sound is an Ogg file"); soundFile:close()

done("test_threat")
