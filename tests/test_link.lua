-- The group layout link (#132, GlassUI's docs/GROUP-LAYOUT.md sections 4-5):
-- while Glass Raid Frames shows its centred layout ("hud"), player and target
-- sit 24 left and right of its grid's union, at their own height (GlassUI#32), their cast
-- bars detached 360x22 above it; a session-only override, the saves set aside
-- and kept intact; out of combat; the visuals glide while the buttons snap.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- GRF's state (UIParent units from its bottom-left). A party: grid 400..966
-- wide, its top at 382, the baseline at 160.
local HUD = { role = "healer", l = 400, b = 228, w = 566, h = 154, top = 382, base = 160, mode = "hud" }
local function announce(s)
    EventRegistry:TriggerEvent("GlassRaidFrames.LayoutChanged", s.role, s.l, s.b, s.w, s.h, s.top, s.base, s.mode)
end
local grfState
local reports
local heard   -- our own announcements (section 5b): GlassActionBars listens
local function lastHeard() return heard[#heard] end
local function boot(db, opts)
    WoW.reset(); standardUnits(); GlassUF = nil
    WoW.layout = true
    UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
    reports = {}
    heard = {}
    EventRegistry:RegisterCallback("GlassUnitFrames.LayoutChanged", function(_, ...)
        heard[#heard + 1] = { ... }
    end, {})
    rawset(_G, "GlassRaidFrames", { LayoutState = function() return grfState and copy(grfState) end })
    rawset(_G, "GlassUI", { Suite = { API = 1, Theme = function() return nil end,
                                      Report = function(_, st) reports[#reports + 1] = st end } })
    opts = opts or {}
    opts.db = db
    loadAddon(opts)
end
local function combat(on)
    WoW.combat = on
    WoW.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
local function pointOf(b) local p = b._points[1]; return p[1], p[2], p[3], p[4], p[5] end
local function lastReport() return reports[#reports] end

-- Without Glass Raid Frames' state: today's positions exactly.
grfState = nil
boot({})
local Link, Frames, Castbar, S = GlassUF.Link, GlassUF.Frames, GlassUF.Castbar, GlassUF.Settings
local pl, tg = button("player"), button("target")
check(not Link.Placing(), "no state: nothing placed")
local pt, rel, rpt, x, y = pointOf(pl)
check(pt == "CENTER" and rel == UIParent and rpt == "CENTER" and x == -300 and y == -110, "the player's own default spot")
eq(lastReport().layout.linked, true, "Report: linked (on by default)")
eq(lastReport().layout.placing, false, "Report: not placing")

-- GRF announcing late (it waits for UIParent's real size, GlassUI#38): the
-- session's first place still snaps, the cast bars too, even one on screen.
grfState = nil
boot({})
GlassUF.Castbar.SetDetached("player", true)   -- a detached bar, shown (mid-cast)
button("player").cast.host:Show()
check(not GlassUF.Link.Placing(), "nothing yet")
announce(HUD)
check(GlassUF.Link.Placing(), "placed when GRF announces")
eq(next(GlassUF.Link._test.glides), nil, "the first place: the frames snap")
eq(next(GlassUF.Zoom._test.glides), nil, "and the cast bar snaps")
local later = copy(HUD); later.l = 300
announce(later)
check(next(GlassUF.Link._test.glides) ~= nil and next(GlassUF.Zoom._test.glides) ~= nil, "the next place glides")

-- GRF built first: its state is read after our build, and the first place snaps.
grfState = HUD
boot({})
Link, Frames, Castbar, S = GlassUF.Link, GlassUF.Frames, GlassUF.Castbar, GlassUF.Settings
pl, tg = button("player"), button("target")
check(Link.Placing(), "GRF's hud state read after the build")
pt, rel, rpt, x, y = pointOf(pl)
check(pt == "CENTER" and rel == UIParent and rpt == "LEFT", "the player: centre from UIParent's left edge")
check(near(x, 400 - 24 - 365 / 2), "its right edge 24 left of the union")
eq(y, -110, "horizontally only: its own default height (GlassUI#32)")
local cx, cy = pl:GetCenter()
check(near(cx + 365 / 2, 400 - 24), "laid out: the right edge is 24 left of the union")
check(near(cy, 384 - 110), "laid out: the height it had")
pt, rel, rpt, x, y = pointOf(tg)
check(near(x, 400 + 566 + 24 + 365 / 2) and y == -110, "the target: its left edge 24 right of the union, its own height")
eq(next(Link._test.glides), nil, "the first place after the build snaps")
eq(next(GlassUnitFramesDB.pos), nil, "nothing saved")
eq(lastReport().layout.placing, true, "Report: placing")
-- Our announcement (section 5b): linked, player l b w h, pet l b w h, the player's dx, the pet's.
local a = lastHeard()
check(a and a[1] == true, "announced: linked")
check(a and near(a[2], 400 - 24 - 365) and near(a[3], 384 - 110 - 31) and a[4] == 365 and a[5] == 62,
      "the player's rect, UIParent units from its bottom-left")
local petCX = (683 - 300) - 365 / 2 + 365 / 2   -- the pet rides the player, centred on it
check(a and a[6] ~= nil and near(a[6] + a[8] / 2, (400 - 24 - 365 / 2)) and a[8] == 365 and a[9] == 32,
      "the pet's rect, carried with the player")
check(a and near(a[10], (400 - 24 - 365 / 2) - (683 - 300)), "dx: how far the link moved the player")
check(a and near(a[11], (400 - 24 - 365 / 2) - petCX), "petDx: the pet rides it, the same move")
local st = GlassUF.LayoutState()
check(st.linked == true and near(st.dx, a[10]) and near(st.petDx, a[11]) and st.player.w == 365 and st.pet.h == 32,
      "LayoutState answers the same")
check(GlassUF.LayoutState() ~= st, "a fresh table each time")
-- Followers ride their leader.
check(button("pet")._points[1][2] == pl and button("focus")._points[1][2] == tg, "pet and focus ride their leaders")

-- The cast bars: detached, 360x22, centred on the union above the grid.
local px, py, pw, ph, pdet, ps = Castbar.EffectiveGeometry("player")
check(near(px, 683 - 683) and near(py, 382 + 73 - 384) and pw == 360 and ph == 22 and pdet and ps == 1,
      "the player's cast bar: centre at top + 73, 360x22")
local tx, ty = Castbar.EffectiveGeometry("target")
check(near(tx, 0) and near(ty, 382 + 41 - 384), "the target's: centre at top + 41")
eq(pl.cast.host._points[1][2], UIParent, "placed detached")
eq(GlassUnitFramesDB.castBars, nil, "the cast bar saves are untouched")
eq(Castbar.EffectiveGeometry("focus"), select(1, Castbar.Geometry("focus")), "other bars keep their own")

-- Set aside: every write refused, nothing saved.
check(not Frames.SetPosition("player", 1, 2), "SetPosition refused")
check(not Frames.SavePosition("target", 1, 2), "SavePosition refused")
check(not Frames.ResetPosition("player"), "ResetPosition refused")
for _, f in ipairs({ function() return Castbar.SetDetached("player", false) end,
                     function() return Castbar.SetSize("player", 200, 30) end,
                     function() return Castbar.SetScale("target", 1.5) end,
                     function() return Castbar.SetPosition("player", 10, 10) end,
                     function() return Castbar.SavePosition("player", 10, 10) end,
                     function() return Castbar.CenterX("target") end,
                     function() return Castbar.ResetPosition("player") end }) do
    check(not f(), "a cast bar write refused")
end
eq(next(GlassUnitFramesDB.pos), nil, "still nothing saved")
eq(GlassUnitFramesDB.castBars, nil, "nor any cast bar")
check(Castbar.SetIconSide("player", "right"), "the icon side is still yours")
Castbar.SetIconSide("player", "left")

-- A placed frame's width changes (its portrait hidden): it keeps its edge.
local n = #heard
S.SetPortraitMode("player", "none")
pt, rel, rpt, x = pointOf(pl)
check(near(x, 400 - 24 - 300 / 2), "no portrait: the 300 body's right edge stays 24 left")
check(#heard == n + 1 and near(lastHeard()[10], (400 - 24 - 300 / 2) - (683 - 300)), "announced again: the pet's dx follows")
S.SetPortraitMode("player", "3d")
check(near(select(4, pointOf(pl)), 400 - 24 - 365 / 2), "the portrait back: the 365 width again")

-- A new state glides: the buttons snap, their visuals ease from where they were.
local wider = copy(HUD)
wider.l = 300
announce(wider)
check(near(select(4, pointOf(pl)), 300 - 24 - 365 / 2), "the button snapped to its new place")
eq(select(5, pointOf(pl)), -110, "at the same height")
local g = Link._test.glides[pl.body]
check(g ~= nil, "the player's body glides")
check(g and near(g.dx, 100) and near(g.dy, 0), "from where it was: 100 to the right")
local bp = pl.body._points[1]
check(bp[1] == "RIGHT" and bp[2] == pl and near(bp[4], 100), "the body starts at its old place")
check(Link._test.glides[pl.tile] ~= nil and Link._test.glides[tg.body] ~= nil, "the tile and the target glide too")
check(Link._test.glides[button("pet").body] ~= nil, "the riding pet glides with them")
WoW.tick(Link._test.DURATION / 2)
check(near(pl.body._points[1][4], 100 * 0.125), "halfway: the cubic ease-out")
WoW.tick(Link._test.DURATION)
check(near(pl.body._points[1][4], 0) and pl.body._points[1][2] == pl, "home: on its button, no offset")
eq(next(Link._test.glides), nil, "the glide is over")
-- No protected frame anchors to a visual.
for unit, b in pairs(Frames.byUnit) do
    local r = b._points[1] and b._points[1][2]
    check(r == UIParent or r == "UIParent" or Frames.byUnit[r] ~= nil or r == pl or r == tg
          or (type(r) == "table" and r._protected), unit .. ": anchored to UIParent or a button")
end

-- Reset frame positions keeps the set-aside saves.
local db = GlassUnitFramesDB
db.pos.player = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 10, 700 }   -- an older save
db.pos.pet = { "CENTER", "UIParent", "CENTER", -300, -190 }       -- a follower saved on the screen
local savedPlayer, savedPet = copy(db.pos.player), copy(db.pos.pet)
Frames.ApplyPosition("player")   -- as a load applies it
pt, rel, rpt, x, y = pointOf(pl)
check(pt == "TOP" and rpt == "BOTTOMLEFT" and near(x, 300 - 24 - 365 / 2) and y == 700,
      "an older save: its own vertical anchor (top 700 up), the layout's x")
check(near(Frames.OwnCenterX("player"), 10 + 365 / 2), "its own centre x: the TOPLEFT save's left edge plus half its width")
S.ResetPositions()
check(same(db.pos.player, savedPlayer), "reset: the player's save is kept")
eq(db.pos.pet, nil, "reset: the pet's goes")
db.pos.pet = copy(savedPet)
Frames.ApplyPosition("pet")   -- as a load applies it: on the screen, not on its leader

-- Unlock: the linked movers are locked, and NormalizeSaves leaves the set-aside saves alone.
local M = GlassUF.Movers
check(S.Unlock(), "unlocked")
check(same(db.pos.player, savedPlayer), "normalize: the player's older save untouched")
check(same(db.pos.pet, savedPet), "normalize: the absolute follower save untouched while its leader is linked")
local mv = M._test.movers.player
mv._scripts.OnDragStart(mv)
check(not mv._moving, "the player's mover doesn't drag")
eq(M._test.selected(), "player", "but it selects")
eq(M._test.panel().sub._text, Link.NOTE, "the panel says who places it")
check(not M._test.panel().buttons.reset:IsEnabled(), "Reset off")
check(not M._test.panel().buttons.center:IsEnabled(), "Center X off")
local before = { pointOf(pl) }
M._test.nudge(1, 0)
check(same({ pointOf(pl) }, before), "a nudge moves nothing")
M._test.panel().buttons.reset._scripts.OnClick(M._test.panel().buttons.reset)
check(same(db.pos.player, savedPlayer), "Reset changes nothing")
check(M._test.movers["cast:player"] ~= nil, "the linked cast bar has its (locked) mover")
M.Lock()

-- In combat: nothing moves, nothing is blocked; the place waits for combat's end.
combat(true)
n = #heard
announce(HUD)
check(near(select(4, pointOf(pl)), 300 - 24 - 365 / 2), "in combat: the frames stay")
eq(#WoW.blocked, 0, "nothing blocked")
eq(#heard, n, "nothing announced in combat")
combat(false)
check(near(select(4, pointOf(pl)), 400 - 24 - 365 / 2), "after combat: placed")
eq(#heard, n + 1, "announced once after combat")
eq(lastHeard()[11], 0, "an absolute pet save: the link doesn't move it, petDx 0")
check(near(lastHeard()[10], (400 - 24 - 365 / 2) - (10 + 365 / 2)), "while the player's dx is its own move (from its TOPLEFT save)")
-- The pet's save reset (or moved) while linked: it rides the player now, and
-- that's announced (Codex, #133).
local playerDx = lastHeard()[10]
n = #heard
check(Frames.ResetPosition("pet"), "the pet's own position reset")
check(#heard == n + 1 and near(lastHeard()[11], playerDx), "announced: the pet rides the player, petDx = dx")
GlassUnitFramesDB.pos.pet = copy(savedPet); Frames.ApplyPosition("pet")
n = #heard
S.ResetPositions()
check(#heard == n + 1 and near(lastHeard()[11], playerDx), "Reset frame positions: announced the same")
GlassUnitFramesDB.pos.pet = copy(savedPet); Frames.ApplyPosition("pet")
n = #heard
check(Frames.SetPosition("pet", 0, -52), "the pet dropped on its leader")
check(#heard == n + 1 and near(lastHeard()[11], playerDx), "a move on the leader: announced, petDx = dx")
check(Frames.SetPosition("pet", 0, -60, true), "a drag in flight")
eq(#heard, n + 1, "not announced until it's dropped")
GlassUnitFramesDB.pos.pet = copy(savedPet); Frames.ApplyPosition("pet")

-- Unlinking (GRF's layout off): each frame's original validated tuple, exactly.
local legacy = copy(HUD)
legacy.mode = "legacy"
announce(legacy)
check(not Link.Placing(), "legacy: not placing")
pt, rel, rpt, x, y = pointOf(pl)
check(pt == "TOPLEFT" and rel == UIParent and rpt == "BOTTOMLEFT" and x == 10 and y == 700, "the player's own (older) save, as it was")
pt, rel, rpt, x, y = pointOf(button("pet"))
check(pt == "CENTER" and rel == UIParent and x == -300 and y == -190, "the absolute follower where it was saved")
check(same(db.pos.player, savedPlayer) and same(db.pos.pet, savedPet), "both saves intact")
eq(GlassUnitFramesDB.castBars, nil, "the cast bars back to their own (docked)")
check(not Castbar.IsDetached("player"), "the player's cast bar docked again")
eq(lastReport().layout.placing, false, "Report: not placing")
check(lastHeard()[1] == false and lastHeard()[10] == 0 and lastHeard()[11] == 0, "announced: not linked, dx and petDx 0")
check(GlassUF.LayoutState().linked == false, "LayoutState: not linked")

-- An older GRF (five arguments, no mode) counts as none.
announce(HUD)
check(Link.Placing(), "hud again")
EventRegistry:TriggerEvent("GlassRaidFrames.LayoutChanged", "healer", 400, 228, 566, 154)
check(not Link.Placing(), "no mode: own positions")
-- Junk (a secret, a zero width) too.
local bad = copy(HUD); bad.w = 0
announce(HUD); announce(bad)
check(not Link.Placing(), "a zero width: own positions")
announce(HUD)
bad = copy(HUD); bad.l = WoW.Secret("l")
announce(bad)
check(not Link.Placing(), "a secret: own positions")

-- The setting: off, own positions (saved false); on, placed again (not saved).
announce(HUD)
SlashCmdList.GLASSUNITFRAMES("link off")
check(not Link.Placing(), "/glass link off: own positions")
eq(GlassUnitFramesDB.groupLink, false, "saved")
eq(lastReport().layout.linked, false, "Report: not linked")
check(Frames.SetPosition("player", -310, -110), "its own position is movable again")
n = #heard
check(Frames.SetPosition("pet", 0, -52), "the pet moved, unlinked")
eq(#heard, n, "not linked: no announcement (the bars have nothing to follow)")
SlashCmdList.GLASSUNITFRAMES("link on")
check(Link.Placing(), "/glass link on: placed")
eq(GlassUnitFramesDB.groupLink, nil, "on is the default, not saved")
check(GlassUnitFramesDB.pos.player[4] == -310, "the save made while unlinked is kept")
-- Off in combat waits.
combat(true)
S.SetGroupLink(false)
check(Link.Placing(), "in combat: still placed")
combat(false)
check(not Link.Placing(), "after combat: own positions")
S.SetGroupLink(true)

-- A saved "off" loads unlinked, whatever GRF says.
grfState = HUD
boot({ groupLink = false })
check(not GlassUF.Link.Placing(), "a saved off: own positions at load")
eq(lastReport().layout.linked, false, "Report: not linked")

-- The zoom comes first: in combat, a zoomed linked bar goes to its zoom spot.
boot({ zoom = { global = { player = { on = true, x = 5, y = -200, scale = 1.5 } } } })
Link, Castbar = GlassUF.Link, GlassUF.Castbar
check(Link.Placing(), "linked")
combat(true)
px, py, pw, ph, pdet, ps = Castbar.EffectiveGeometry("player")
check(px == 5 and py == -200 and ps == 1.5 and pdet, "in combat: the zoom spot and scale")
check(pw == 360 and ph == 22, "at the linked size")
combat(false)
px, py = Castbar.EffectiveGeometry("player")
check(near(py, 382 + 73 - 384), "after combat: the linked place")

-- Options: the checkbox and the dimmed cast bar controls.
local O = GlassUF.Options._test
O.panel._scripts.OnShow(O.panel)
check(O.controls.groupLink:GetChecked(), "the link checkbox is on")
check(O.controls.linkNote._text:find("Placing", 1, true) ~= nil, "the note says it's placing")
O.castPage._scripts.OnShow(O.castPage)
check(not O.controls.castDetach:IsEnabled() and not O.controls.castWidth:IsEnabled(), "the player's bar controls are off")
check(O.controls.castDetach.label._text:find(Link.NOTE, 1, true) ~= nil, "and say why")
O.controls.groupLink:SetChecked(false)
O.controls.groupLink._scripts.OnClick(O.controls.groupLink)
check(not Link.Placing(), "the checkbox turns it off")
O.controls.refreshAll()
check(O.controls.castDetach:IsEnabled() and O.controls.castWidth:IsEnabled(), "the bar's controls are back")

eq(next(GlassUF.paintFailures), nil, "no failures")
rawset(_G, "GlassRaidFrames", nil)
rawset(_G, "GlassUI", nil)
GlassUnitFramesDB = nil
done("test_link")
