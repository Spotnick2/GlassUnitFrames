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
local function boot(db, opts, loading)
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
    -- The loading screen lifts after the load, unless a test holds it up.
    -- GRF announces again as it lifts (the party listed by then).
    if not loading then
        WoW.fire("LOADING_SCREEN_DISABLED")
        if grfState then announce(grfState) end
    end
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
check(pt == "CENTER" and rel == UIParent and rpt == "CENTER" and x == -304 and y == -272, "the player's own default spot")
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

-- At login (GlassUI#39): GRF can announce a partial grid before the party is
-- listed. Every place before the loading screen lifts snaps, and the first one
-- after it; then they glide.
grfState = nil
boot({}, nil, true)
local partial = copy(HUD); partial.l, partial.w = 600, 166   -- one cell: the party not listed yet
announce(partial)
check(GlassUF.Link.Placing(), "a partial grid places")
eq(next(GlassUF.Link._test.glides), nil, "before the loading screen lifts: snaps")
announce(HUD)
eq(next(GlassUF.Link._test.glides), nil, "again before it lifts: snaps")
WoW.fire("LOADING_SCREEN_DISABLED")
local real = copy(HUD); real.l = 350
announce(real)
eq(next(GlassUF.Link._test.glides), nil, "the first place after it lifts: snaps")
announce(HUD)
check(next(GlassUF.Link._test.glides) ~= nil, "the next one glides")
-- Any later loading screen (entering an instance) holds the glide again, and
-- one starting mid-glide stops it, the followers' too (Codex, #137).
local petBody = button("pet").body
check(GlassUF.Link._test.glides[petBody] ~= nil, "the riding pet is mid-glide")
WoW.fire("LOADING_SCREEN_ENABLED")
announce(real)
eq(next(GlassUF.Link._test.glides), nil, "behind a later loading screen: snaps, every glide stopped")
check(petBody._points[1][2] == button("pet") and petBody._points[1][4] == 0 and petBody._points[1][5] == 0,
      "the pet's body back on its button, no offset")
announce(HUD)
eq(next(GlassUF.Link._test.glides), nil, "every place while it's up")
WoW.fire("LOADING_SCREEN_DISABLED")
announce(real)
eq(next(GlassUF.Link._test.glides), nil, "the first after it lifts")
announce(HUD)
check(next(GlassUF.Link._test.glides) ~= nil, "then they glide again")
WoW.tick(1)

-- GRF built first: its state is read after our build, and the first place snaps.
grfState = HUD
-- The player's cast bar detached by its own save, the target's docked (the
-- default). The link only lifts a detached bar clear of the grid (#142).
local DOCKED = { player = { detached = true, x = 10, y = -150 } }
boot({ castBars = copy(DOCKED) })
Link, Frames, Castbar, S = GlassUF.Link, GlassUF.Frames, GlassUF.Castbar, GlassUF.Settings
pl, tg = button("player"), button("target")
check(Link.Placing(), "GRF's hud state read after the build")
pt, rel, rpt, x, y = pointOf(pl)
check(pt == "CENTER" and rel == UIParent and rpt == "LEFT", "the player: centre from UIParent's left edge")
check(near(x, 400 - 24 - 365 / 2), "its right edge 24 left of the union")
eq(y, -272, "horizontally only: its own default height (GlassUI#32)")
local cx, cy = pl:GetCenter()
check(near(cx + 365 / 2, 400 - 24), "laid out: the right edge is 24 left of the union")
check(near(cy, 384 - 272), "laid out: the height it had")
pt, rel, rpt, x, y = pointOf(tg)
check(near(x, 400 + 566 + 24 + 365 / 2) and y == -272, "the target: its left edge 24 right of the union, its own height")
eq(next(Link._test.glides), nil, "the first place after the build snaps")
eq(next(GlassUnitFramesDB.pos), nil, "nothing saved")
eq(lastReport().layout.placing, true, "Report: placing")
-- Our announcement (section 5b): linked, player l b w h, pet l b w h, the player's dx, the pet's.
local a = lastHeard()
check(a and a[1] == true, "announced: linked")
check(a and near(a[2], 400 - 24 - 365) and near(a[3], 384 - 272 - 31) and a[4] == 365 and a[5] == 62,
      "the player's rect, UIParent units from its bottom-left")
local petCX = (683 - 304) - 365 / 2 + 365 / 2   -- the pet rides the player, centred on it
check(a and a[6] ~= nil and near(a[6] + a[8] / 2, (400 - 24 - 365 / 2)) and a[8] == 365 and a[9] == 32,
      "the pet's rect, carried with the player")
check(a and near(a[10], (400 - 24 - 365 / 2) - (683 - 304)), "dx: how far the link moved the player")
check(a and near(a[11], (400 - 24 - 365 / 2) - petCX), "petDx: the pet rides it, the same move")
local st = GlassUF.LayoutState()
check(st.linked == true and near(st.dx, a[10]) and near(st.petDx, a[11]) and st.player.w == 365 and st.pet.h == 32,
      "LayoutState answers the same")
check(GlassUF.LayoutState() ~= st, "a fresh table each time")
-- Followers ride their leader.
check(button("pet")._points[1][2] == pl and button("focus")._points[1][2] == tg, "pet and focus ride their leaders")

-- A detached cast bar keeps its own spot, size and scale, lifted so its
-- bottom clears the grid's top (382, i.e. -2 from the centre) by Link.CLEAR.
local TOP = 382 - 384
local px, py, pw, ph, pdet, ps = Castbar.EffectiveGeometry("player")
check(px == 10 and pw == 340 and ph == 20 and pdet and ps == 1.5, "the player's bar: its own spot, size and scale")
check(near(py - 20 * 1.5 / 2, TOP + Link.CLEAR), "lifted: its bottom Link.CLEAR over the grid's top")
-- A docked one stays docked (#142).
check(not select(5, Castbar.EffectiveGeometry("target")), "the docked target bar stays docked")
check(Castbar.SetDetached("target", true), "detaching it")
local tx, ty = Castbar.EffectiveGeometry("target")
px, py = Castbar.EffectiveGeometry("player")
check(near(ty - py, -152 - (-150)), "one lift for both: the pair keeps its spacing")
check(near(pl.cast.host._points[1][5], py / 1.5), "the player's host re-placed with the new lift")
check(near(ty - 15, TOP + Link.CLEAR), "the lowest (the target's) clears the grid")
check(Castbar.SetDetached("target", false), "and docking it again")
px, py = Castbar.EffectiveGeometry("player")
check(near(py - 15, TOP + Link.CLEAR), "the player's lift follows")
eq(GlassUnitFramesDB.castBars.target, nil, "nothing left saved for it")
-- Nothing set aside: its writes are its own.
check(Castbar.SetPosition("player", 12, -150), "its spot is yours while linked")
eq(GlassUnitFramesDB.castBars.player.x, 12, "saved")
check(Castbar.SetPosition("player", 10, -150), "and back")
eq(pl.cast.host._points[1][2], UIParent, "placed detached")
check(same(GlassUnitFramesDB.castBars, DOCKED), "the cast bar saves are untouched")
eq(Castbar.EffectiveGeometry("focus"), select(1, Castbar.Geometry("focus")), "other bars keep their own")

-- Set aside: every write refused, nothing saved.
check(not Frames.SetPosition("player", 1, 2), "SetPosition refused")
check(not Frames.SavePosition("target", 1, 2), "SavePosition refused")
check(not Frames.ResetPosition("player"), "ResetPosition refused")
eq(next(GlassUnitFramesDB.pos), nil, "still nothing saved")
check(same(GlassUnitFramesDB.castBars, DOCKED), "nor any cast bar")
check(Castbar.SetIconSide("player", "right"), "the icon side is still yours")
Castbar.SetIconSide("player", "left")
check(Castbar.SetDetached("player", false), "attach while linked")
check(not select(5, Castbar.EffectiveGeometry("player")), "docked again")
check(Castbar.SetDetached("player", true), "and detached: lifted again")
check(near(select(2, Castbar.EffectiveGeometry("player")) - 15, TOP + Link.CLEAR), "clear of the grid")
check(same(GlassUnitFramesDB.castBars, DOCKED), "its save as it was")

-- A placed frame's width changes (its portrait hidden): it keeps its edge.
local n = #heard
S.SetPortraitMode("player", "none")
pt, rel, rpt, x = pointOf(pl)
check(near(x, 400 - 24 - 300 / 2), "no portrait: the 300 body's right edge stays 24 left")
check(#heard == n + 1 and near(lastHeard()[10], (400 - 24 - 300 / 2) - (683 - 304)), "announced again: the pet's dx follows")
S.SetPortraitMode("player", "3d")
check(near(select(4, pointOf(pl)), 400 - 24 - 365 / 2), "the portrait back: the 365 width again")

-- A new state glides: the buttons snap, their visuals ease from where they were.
local wider = copy(HUD)
wider.l = 300
announce(wider)
check(near(select(4, pointOf(pl)), 300 - 24 - 365 / 2), "the button snapped to its new place")
eq(select(5, pointOf(pl)), -272, "at the same height")
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
check(M._test.movers["cast:player"] ~= nil, "the detached cast bar has its mover")
local cm = M._test.movers["cast:player"]
cm._scripts.OnMouseUp(cm)
check(M._test.panel().buttons.reset:IsEnabled() and M._test.panel().buttons.up:IsEnabled(),
      "not locked: the layout only lifts it (#142)")
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
-- Reset frame positions (above) reset the bar's spot too: nothing is set aside (#142).
check(same(GlassUnitFramesDB.castBars, { player = { detached = true } }), "the cast bars' own saves")
px, py = Castbar.EffectiveGeometry("player")
check(px == 0 and py == -182, "the player's cast bar at its own (default) detached spot, no lift")
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

-- The zoom comes first: in combat, a zoomed bar goes above the grid while
-- linked (#142), at the zoom's scale, its heights above the grid scaled too.
-- Docked out of combat.
boot({ zoom = { global = { player = { on = true, x = 5, y = -200, scale = 1.5 } } } })
Link, Castbar = GlassUF.Link, GlassUF.Castbar
check(Link.Placing(), "linked")
check(not select(5, Castbar.EffectiveGeometry("player")), "out of combat: docked")
combat(true)
px, py, pw, ph, pdet, ps = Castbar.EffectiveGeometry("player")
check(px == 5 and ps == 1.5 and pdet, "in combat: its zoom spot and scale")
check(near(py - 15, (382 - 384) + Link.CLEAR), "lifted clear of the grid (the lowest of the pair)")
check(pw == 340 and ph == 20, "at its own size")
combat(false)
check(not select(5, Castbar.EffectiveGeometry("player")), "after combat: docked again")

-- Options: the checkbox and the dimmed cast bar controls.
local O = GlassUF.Options._test
O.panel._scripts.OnShow(O.panel)
check(O.controls.groupLink:GetChecked(), "the link checkbox is on")
check(O.controls.linkNote._text:find("Placing", 1, true) ~= nil, "the note says it's placing")
O.castPage._scripts.OnShow(O.castPage)
check(O.controls.castDetach:IsEnabled() and O.controls.castWidth:IsEnabled(), "a docked bar's controls are its own")
S.SetCastDetached("player", true)
O.controls.refreshAll()
check(O.controls.castDetach:IsEnabled() and O.controls.castWidth:IsEnabled(),
      "detached while linked: still all its own (#142)")
O.controls.groupLink:SetChecked(false)
O.controls.groupLink._scripts.OnClick(O.controls.groupLink)
check(not Link.Placing(), "the checkbox turns it off")
O.controls.refreshAll()
check(O.controls.castDetach:IsEnabled() and O.controls.castWidth:IsEnabled(), "the bar's controls are back")

-- A zoom setting that changes the shared lift re-places the partner too
-- (Codex, #143). The player's bar docked, the target's detached; both zoom on
-- (the default). In combat the player's zoom spot (bottom -197) sets the lift.
boot({ castBars = { target = { detached = true } } })
Link, Castbar, S = GlassUF.Link, GlassUF.Castbar, GlassUF.Settings
combat(true)
local _, tz = Castbar.EffectiveGeometry("target")
check(near(tz, -152 + 201), "in combat: the target lifted by the player's zoom spot")
S.SetZoom("player", false)
_, tz = Castbar.EffectiveGeometry("target")
check(near(tz, -152 + 171), "the player's zoom off: the target's own lift")
check(near(button("target").cast.host._points[1][5], tz / 1.5), "and its host re-placed")
combat(false)

-- Movers work where a bar shows; a drop is measured against its partner's
-- lift alone, so it lands where it was dropped (Codex, #143). Both bars
-- detached at their defaults: the grid's top (-2) lifts the pair by 201.
boot({ castBars = { player = { detached = true }, target = { detached = true } } })
Link, Castbar, S = GlassUF.Link, GlassUF.Castbar, GlassUF.Settings
local src = Castbar.MoverSource("player")
local _, sy = src.position()
check(near(sy, -182 + 201), "the mover's position: where the bar shows")
check(src.set(0, 25, true), "a drag in flight")
check(near(button("player").cast.host._points[1][5], 25 / 1.5), "the host under the cursor")
check(src.set(0, 20), "dropped")
px, py = Castbar.EffectiveGeometry("player")
check(near(py, 20), "it lands where it was dropped")
eq(GlassUnitFramesDB.castBars.player.y, 20 - 171, "saved against the target's lift alone")
_, sy = src.position()
check(near(sy, 20), "the mover reads it back")
local _, ty3 = Castbar.EffectiveGeometry("target")
check(near(button("target").cast.host._points[1][5], ty3 / 1.5), "the target re-placed with the new lift")
-- The combat outline the same way.
local zsrc = GlassUF.Zoom.MoverSource("player")
local _, zy = zsrc.position()
check(near(zy, -182 + 201), "the outline's position: where it shows (lifted as in combat)")
check(zsrc.set(0, 20), "the outline dropped")
eq(GlassUF.Zoom.Entry("player").y, 20 - 171, "its spot saved against the target's lift")
_, zy = zsrc.position()
check(near(zy, 20), "and it shows where it was dropped")
eq(next(GlassUF.paintFailures), nil, "no failures")
rawset(_G, "GlassRaidFrames", nil)
rawset(_G, "GlassUI", nil)
GlassUnitFramesDB = nil
done("test_link")
