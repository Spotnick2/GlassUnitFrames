-- Combat zoom (#89): in combat, a bar with its zoom on is laid out detached at
-- its zoom spot (an effective detach), gliding there when visible, snapping
-- when docked inside or hidden; home again when combat ends. Global settings
-- with per-role overrides; zoom-aware SetPosition; the zoom-spot movers.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
WoW.units.player.guid = "Player-1-00000001"
loadAddon()
WoW.fire("PLAYER_LOGIN")
UIParent._center = { 683, 384 }
local Zoom, Castbar, S, M = GlassUF.Zoom, GlassUF.Castbar, GlassUF.Settings, GlassUF.Movers
local pl, tg = button("player"), button("target")
local pc, tc = pl.cast, tg.cast
local glides = Zoom._test.glides
local DUR = Zoom._test.DURATION

local function combat(on)
    WoW.combat = on
    WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
local function point(c) return c.host._points[1] end
local n = 0
local function targetCast()
    n = n + 1
    local g = "Cast-3-1-1-1-133-" .. n
    WoW.units.target.casting = { name = "Fireball", guid = g, spellID = 133, total = 3, remaining = 2,
                                 startMs = WoW.now * 1000, endMs = (WoW.now + 3) * 1000, delayMs = 0 }
    WoW.fire("UNIT_SPELLCAST_START", "target", g, 133, "CastBar-1")
    return g
end
local function targetStop(g)
    WoW.units.target.casting = nil
    WoW.fire("UNIT_SPELLCAST_STOP", "target", g, 133, "CastBar-1")
    WoW.flushTimers()
end

-- Off by default: combat moves nothing.
check(not Zoom.Enabled("player"), "zoom off by default")
combat(true)
eq(point(pc)[1], "ALL", "the player's row stays docked in combat")
combat(false)

-- The docked player row: snaps out to its zoom spot, the body gets its room back.
check(S.SetZoom("player", true), "player zoom on")
eq(GlassUnitFramesDB.zoom.global.player.on, true, "saved in the global table")
-- Mid-cast, with a readable rect: still a snap, its home is the body.
WoW.units.player.casting = { name = "Heal", guid = "Cast-3-1-1-1-2050-1", spellID = 2050, total = 2.5, remaining = 1,
                             startMs = WoW.now * 1000, endMs = (WoW.now + 2.5) * 1000, delayMs = 0 }
WoW.fire("UNIT_SPELLCAST_START", "player", "Cast-3-1-1-1-2050-1", 2050, "CastBar-1")
check(pc.host:IsVisible(), "the docked row shows (casting)")
pc.host._center = { 400, 300 }
combat(true)
check(pc.detached, "in combat: effectively detached")
eq(GlassUnitFramesDB.castBars, nil, "the saved detach is untouched")
eq(point(pc)[1], "CENTER", "at its zoom spot")
check(near(point(pc)[5], -120 / 1.25), "its default spot, in its own scaled units")
eq(pc.host:GetScale(), 1.25, "at the zoom scale")
check(pc.skin._shown, "with its own pill")
check(not pl.castShown, "the docked row leaves the body")
eq(pl.health:GetHeight(), pl.rows.idle.health, "health at its idle height")
check(next(glides) == nil, "a docked row snaps (no glide), even visible")
combat(false)
check(next(glides) == nil, "and snaps home")
pc.host._center = nil
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-1-1-1-2050-1", 2050, "CastBar-1")
WoW.flushTimers()
eq(point(pc)[1], "ALL", "combat over: docked again")
check(not pc.detached, "not detached any more")
eq(pc.host:GetScale(), 1, "its scale back")

-- A detached, visible bar glides there and back.
check(S.SetCastDetached("target", true), "the target's bar detached")
check(S.SetZoom("target", true), "target zoom on")
local g = targetCast()
check(tc.host:IsVisible(), "casting: visible")
combat(true)
check(glides.target ~= nil, "a visible bar glides")
check(near(point(tc)[5], -23), "starting from home")
WoW.tick(DUR / 2)
local e = 1 - 0.5 ^ 3
local midY, midS = -23 + (-90 + 23) * e, 1 + 0.25 * e
check(near(tc.host:GetScale(), midS), "half way: the scale eases out")
check(near(point(tc)[5], midY / midS), "half way: the centre eases out")
WoW.tick(DUR)
check(glides.target == nil, "the glide ends")
check(near(point(tc)[5], -90 / 1.25) and tc.host:GetScale() == 1.25, "exactly at the zoom spot")
-- A mode change mid-glide retargets from the point on screen.
WoW.combat = false
combat(false)
WoW.tick(DUR / 2)
local cur = { glides.target.cx, glides.target.cy }
-- The rect unreadable mid-glide (layout not resolved): the glide's own point still serves.
local realCenter = tc.host.GetCenter   -- the stub's method, before the override
rawset(tc.host, "GetCenter", function(self)
    -- Unreadable mid-glide (the start), readable once placed at the zoom scale (the target).
    if self:GetScale() ~= 1.25 then return nil end
    return realCenter(self)
end)
combat(true)
rawset(tc.host, "GetCenter", nil)
check(glides.target ~= nil, "retargeted, not snapped")
check(near(glides.target.fx, cur[1]) and near(glides.target.fy, cur[2]), "from the point on screen")
WoW.tick(DUR * 2)
-- Any other placement mid-glide cancels it and snaps.
combat(false)
WoW.tick(DUR / 3)
check(glides.target ~= nil, "gliding home")
check(S.SetCastSize("target", 300, nil), "resized mid-glide")
check(glides.target == nil, "the glide is cancelled")
check(near(point(tc)[5], -23) and tc.host:GetScale() == 1, "snapped home")
WoW.tick(DUR)
check(near(point(tc)[5], -23), "and no tick moves it back")

-- Centring (SetPosition) while zoomed: the home is saved, the host stays at the spot.
combat(true)
WoW.tick(DUR / 2)
check(glides.target ~= nil, "gliding to the spot")
check(Castbar.SetPosition("target", 50, -23), "a new home typed mid-glide")
eq(GlassUnitFramesDB.castBars.target.x, 50, "saved")
check(glides.target ~= nil, "the glide carries on")
WoW.tick(DUR)
check(near(point(tc)[1] == "CENTER" and point(tc)[4], 0), "at the zoom spot, not the new home")
check(S.CenterCast("target"), "centred in combat")
eq(GlassUnitFramesDB.castBars.target.x, 0, "the centred home is saved")
check(near(point(tc)[5], -90 / 1.25), "the host stays at its spot")
Castbar.SetPosition("target", 40, -23)
combat(false)
WoW.tick(DUR * 2)
check(near(point(tc)[4], 40), "combat over: the bar goes to the new home")
targetStop(g)

-- A hidden bar snaps.
check(not tc.host:IsVisible(), "not casting: hidden")
combat(true)
check(glides.target == nil, "a hidden bar snaps")
check(near(point(tc)[5], -90 / 1.25), "already at its spot")
combat(false)

-- At another UI scale the glide still lands on the spot.
WoW.uiScale = 0.9
g = targetCast()
combat(true)
WoW.tick(DUR * 2)
check(near(point(tc)[5], -90 / 1.25), "UI scale 0.9: the same spot")
local x, y = Zoom._test.rectOf(tc.host)
check(near(x, 0) and near(y, -90), "its rect, in UIParent units, is the spot")
combat(false)
WoW.tick(DUR * 2)
targetStop(g)
WoW.uiScale = 0.64

-- The swing rows: docked, they snap out; the body gets their room back.
check(S.SetZoom("swing", true), "swing zoom on")
local sw = Castbar.bars.swing
WoW.units.player.combat = true
combat(true)
WoW.fire("PLAYER_SWING", 2.5, 0)
check(sw.detached and sw.skin._shown, "in combat: the swing pill at its spot")
eq(pl.swingCount, 0, "no docked swing row")
check(near(sw.host._points[1][5], -142 / 1.25), "its default zoom spot")
combat(false)
check(not sw.detached, "combat over: docked again")
WoW.units.player.combat = false
WoW.fire("PLAYER_IN_COMBAT_CHANGED", false)
WoW.now = WoW.now + 3; WoW.tick(0.06)

-- Roles: global by default; a role's first edit starts from the global entry.
eq(Zoom.EditedKey(), "global", "no role: global")
check(S.SetZoomRole("healer"), "this character is a healer")
eq(GlassUnitFramesDB.zoomRole["Player-1-00000001"], "healer", "saved per GUID")
check(Zoom.Enabled("player"), "no healer entry yet: the global one")
check(S.SetZoomScale("player", 1.5), "the healer's scale")
local h = GlassUnitFramesDB.zoom.healer.player
eq(h.on, true, "the healer entry inherits the global on")
eq(h.scale, 1.5, "and takes its scale")
eq(Zoom.Entry("player").scale, 1.5, "used now")
eq(GlassUnitFramesDB.zoom.global.player.scale, nil, "the global one untouched")
check(S.SetZoom("target", false), "the healer turns the target's zoom off")
check(not Zoom.Enabled("target"), "off for healers")
check(S.SetZoomRole(nil), "back to global")
eq(GlassUnitFramesDB.zoomRole, nil, "nothing left to save")
check(Zoom.Enabled("target"), "global: the target still zooms")
eq(Zoom.Entry("player").scale, 1.25, "and the global scale")
check(not S.SetZoomRole("wizard"), "an unknown role is refused")

-- The zoom-spot movers: an outline at the spot; saving into the edited table.
check(M.Unlock(), "unlocked")
local zm = M._test.movers["zoom:player"]
check(zm and zm._shown, "the player's zoom spot has a mover")
local px = Zoom._test.proxies.player
check(px._shown, "over its outline")
eq(px:GetScale(), 1.25, "at the zoom scale")
check(near(px._points[1][5], -120 / 1.25), "at the spot")
zm._scripts.OnMouseUp(zm)
local np = M._test.panel()
check(np.s._shown and not np.w._shown, "its panel: a scale, no W/H")
eq(np.sizeRow[5]._points[1][1], "TOPLEFT", "the scale starts the row (not after the hidden H)")
check(S.SetZoomScale("player", 1.4), "the combat scale from the options page")
eq(np.s._text, "1.4", "the open panel follows (review, #90)")
local src = M._test.sources["zoom:player"]
check(src.set(10, -100, false), "moved")
eq(GlassUnitFramesDB.zoom.global.player.x, 10, "saved in the global table")
check(src.setScale(1.6), "scaled")
eq(Zoom.Entry("player").scale, 1.6, "the zoom scale")
check(src.reset(), "reset")
eq(Zoom.Entry("player").y, -120, "the default spot again")
eq(Zoom.Entry("player").scale, 1.25, "and scale")
check(Zoom.Enabled("player"), "reset keeps it on")
-- Turning the zoom off while its mover is selected: mover, outline and panel go.
check(S.SetZoom("player", false), "off while unlocked")
check(M._test.sources["zoom:player"] == nil, "its source goes")
check(not zm._shown, "its mover hides")
check(not px._shown, "its outline hides")
check(not np._shown, "the panel closes")
check(S.SetZoom("player", true), "on again while unlocked")
check(M._test.movers["zoom:player"]._shown, "its mover is back")
M.Lock()
check(not px._shown, "locked: no outline")

-- Reset frame positions also resets the zoom spots.
Zoom.SetSpot("player", 30, -30)
S.ResetPositions()
WoW.flushTimers()
eq(Zoom.Entry("player").x, 0, "reset: the default zoom spot")

-- A secret GUID: global.
WoW.secretFields.guid = true
Zoom.role = "tank"
Zoom._test.readRole()
check(Zoom.role == "tank", "an unreadable GUID changes nothing")
WoW.secretFields.guid = nil
Zoom.role = nil

-- The dispatcher: unlock locks before the zoom.
check(M.Unlock(), "unlocked")
combat(true)
check(not M.unlocked, "combat locks")
check(pc.detached, "then the bar zooms")
combat(false)

-- The options sub-page, after Cast bars.
local subs = WoW.settings.subs or {}
eq(subs[2] and subs[2].name, "Combat zoom", "its own sub-page, after Cast bars")
local zp = GlassUF.Options._test.zoomPage
zp._shown = true
zp._scripts.OnShow(zp)
local C = GlassUF.Options._test.controls
for _, bar in ipairs({ "player", "target", "focus", "pet", "swing" }) do
    check(C.zoomBars[bar] ~= nil, "a zoom checkbox: " .. bar)
end
check(C.zoomBars.player:GetChecked(), "player: on (set above)")
C.zoomBars.focus:SetChecked(true); C.zoomBars.focus._scripts.OnClick(C.zoomBars.focus)
check(Zoom.Enabled("focus"), "the checkbox turns a bar's zoom on")
C.zoomScale_focus:SetValue(1.8)
eq(Zoom.Entry("focus").scale, 1.8, "the slider sets its combat scale")
for _, rb in ipairs(C.zoomRole) do
    if rb.value == "tank" then rb._scripts.OnClick(rb) end
end
eq(Zoom.role, "tank", "the role radio")
check(textOf(C.zoomEditing):find("tank"), "says which settings are edited")
for _, rb in ipairs(C.zoomRole) do
    if rb.value == "global" then rb._scripts.OnClick(rb) end
end
eq(Zoom.role, nil, "back to global")
check(textOf(C.zoomEditing):find("global"), "editing the global settings")
zp._shown = false

-- A role's disabled override survives a reset, and later on/off edits (Codex, #90).
check(S.SetZoom("target", true), "target zoom on, globally")
check(S.SetZoomRole("healer"), "healer")
check(S.SetZoom("target", false), "the healer turns it off")
eq(GlassUnitFramesDB.zoom.healer.target.on, false, "stored as an explicit off")
S.ResetPositions(); WoW.flushTimers()
check(not Zoom.Enabled("target"), "reset keeps the healer's off (no fallback to global)")
check(GlassUnitFramesDB.zoom.healer.target ~= nil, "the role entry stays")
check(S.SetZoom("target", true) and S.SetZoom("target", false), "on and off again")
check(not Zoom.Enabled("target"), "still the healer's own off")
check(S.SetZoomRole(nil), "global")
check(Zoom.Enabled("target"), "the global on is untouched")

-- An emptied role entry is still the role's: a reset gives the defaults, not
-- the global spot (Codex, #90).
check(S.SetZoom("focus", false), "focus zoom off globally (so the copy below holds no on)")
check(Zoom.SetSpot("focus", 30, -30), "a custom global focus spot")
check(S.SetZoomRole("tank"), "tank")
check(S.SetZoomScale("focus", 1.1), "the tank's own focus entry")
eq(Zoom.Entry("focus").x, 30, "copied from global")
S.ResetPositions(); WoW.flushTimers()
eq(Zoom.Entry("focus").x, 0, "the tank's reset: the default spot, not the global 30")
check(S.SetZoomRole(nil), "global")
eq(Zoom.Entry("focus").x, 30, "the global spot untouched")
Zoom.ResetSpot("focus")

-- The combat outline follows a resize of its bar while unlocked (Codex, #90).
check(M.Unlock(), "unlocked")
local tpx = Zoom._test.proxies.target
check(tpx and tpx._shown, "the target's combat outline")
check(S.SetCastSize("target", 420, 30), "resized through the cast bar")
eq(tpx:GetWidth(), 420, "the outline's width follows")
eq(tpx:GetHeight(), 30, "and its height")
Castbar.ResetPosition("target")
eq(tpx:GetWidth(), 340, "a reset too")
M.Lock()

-- REGEN_ENABLED seen while lockdown is still reported: the bars still go home (review, #90).
combat(true)
check(pc.detached, "zoomed")
WoW.combat = true
WoW.fire("PLAYER_REGEN_ENABLED")
check(not Zoom.combat and not pc.detached, "home even with lockdown still reported")
WoW.combat = false

-- Turning a zoom on and off leaves nothing saved (review, #90).
check(S.SetZoom("pet", true) and S.SetZoom("pet", false), "pet zoom on and off")
check(not (GlassUnitFramesDB.zoom and GlassUnitFramesDB.zoom.global and GlassUnitFramesDB.zoom.global.pet),
      "no empty pet entry left behind")

-- A build deferred by combat past PLAYER_LOGIN still reads the saved role,
-- and the zoom page lists every bar before the build (review, #90).
do
    local keep = GlassUnitFramesDB
    keep.zoomRole = { ["Player-1-00000001"] = "tank" }
    WoW.reset(); standardUnits(); WoW.units.player.guid = "Player-1-00000001"; GlassUF = nil
    WoW.combat = true
    loadAddon({ db = keep })
    WoW.fire("PLAYER_LOGIN")
    check(next(GlassUF.Frames.byUnit) == nil, "the build waits for combat to end")
    local zp2 = GlassUF.Options._test.zoomPage
    zp2._shown = true
    zp2._scripts.OnShow(zp2)
    local n2 = 0
    for _ in pairs(GlassUF.Options._test.controls.zoomBars) do n2 = n2 + 1 end
    eq(n2, 5, "the zoom page lists every bar before the build")
    zp2._shown = false
    WoW.combat = false
    WoW.fire("PLAYER_REGEN_ENABLED")
    check(GlassUF.Frames.byUnit.player ~= nil, "built after combat")
    eq(GlassUF.Zoom.role, "tank", "the saved role is read")
    keep.zoomRole = nil
end

-- Saved junk falls back to the defaults.
local saved = GlassUnitFramesDB
saved.zoom = { global = { player = { on = "yes", x = 1 / 0, y = "far", scale = 9 } }, tank = "x" }
saved.zoomRole = { ["Player-1-00000001"] = "wizard" }
WoW.reset(); standardUnits(); WoW.units.player.guid = "Player-1-00000001"; GlassUF = nil
loadAddon({ db = saved })
WoW.fire("PLAYER_LOGIN")
local ej = GlassUF.Zoom.Entry("player")
check(not ej.on, "only true turns it on")
eq(ej.x, 0, "a bad x: the default")
eq(ej.y, -120, "a bad y: the default")
eq(ej.scale, 1.25, "a bad scale: the default")
eq(GlassUF.Zoom.role, nil, "an unknown saved role: global")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
GlassUnitFramesDB = nil
done("test_zoom")
