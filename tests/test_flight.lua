-- A taxi flight on the player's cast bar (#148), Quartz's Flight: drawn from
-- LibTaxiTime-1.0's Current() and its "LibTaxiTime.Changed" event (#153), taken
-- by a real cast and given back after it, and zoomed like combat when the
-- player's zoom is on. The library here is a fake registered through LibStub
-- at a higher MINOR before the addon loads, so the real copy defers to it
-- (LibStub's rule); test_taxitime.lua runs the real one.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

dofile(libGlassRoot() .. "/LibStub/LibStub.lua")
local cur, throws = nil, false
local stores = {}
local LTT = LibStub:NewLibrary("LibTaxiTime-1.0", 1000)
function LTT:AddStore(t) stores[#stores + 1] = t; return true end
function LTT:Current()
    if throws then error("LibTaxiTime broke") end
    if not cur then return nil end
    local t = {}
    for k, v in pairs(cur) do t[k] = v end
    return t
end
local function changed() EventRegistry:TriggerEvent("LibTaxiTime.Changed"); WoW.tick() end
local function boot(db)
    WoW.reset(); standardUnits(); GlassUF = nil
    loadAddon({ db = db })
end
local NOZOOM = { zoom = { global = { player = { on = false } } } }
local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local ORG = { to = "Orgrimmar, Durotar", from = "Crossroads, The Barrens", total = 120, source = "route" }

-- No flight: nothing on the bar.
boot(copy(NOZOOM))
local Castbar, Flight, Zoom, S = GlassUF.Castbar, GlassUF.Flight, GlassUF.Zoom, GlassUF.Settings
local pc = Castbar.bars.player
check(not pc.host._shown, "no flight: the bar stays hidden")
check(stores[#stores] == GlassUnitFramesDB.flight and type(stores[#stores]) == "table",
      "our store (GlassUnitFramesDB.flight) handed to the library at load")

-- Takeoff: "Flight to ...", the flight master's icon, emptying like a channel.
cur = copy(ORG); cur.start = WoW.now
changed()
check(pc.host._shown, "takeoff: the flight shows on the player's cast bar")
eq(pc.spell._text, "Flight to Orgrimmar, Durotar", "its destination")
eq(pc.icon._file, Flight.ICON, "the flight master's icon")
eq(pc.bar._timer.dir, GlassUF.API.TimerDirection(true), "it empties like a channel")
eq(pc.bar._timer.duration:GetRemainingDuration(), 120, "from the library's start and total")
WoW.now = WoW.now + 29.6
WoW.tick(0.06)
eq(pc.time._text, "1:31", "the time left as m:ss")
cur.source = "estimate"; changed(); WoW.tick(0.06)
eq(pc.time._text, "~1:31", "an estimate: ~")
WoW.now = WoW.now + 97.4; WoW.tick(0.06)
eq(pc.time._text, "+0:07", "past the prediction (total stays it): the overtime")
WoW.now = WoW.now - 97.4

-- An unrelated STOP while flying: no "complete" flash, the flight stays.
WoW.fire("UNIT_SPELLCAST_STOP", "player"); WoW.tick()
check(not pc.flashing and pc.spell._text == "Flight to Orgrimmar, Durotar", "a STOP never flashes the flight")

-- A real cast takes the bar; the flight comes back after its flash.
WoW.units.player.casting = { name = "Hearthstone", remaining = 10 }
WoW.fire("UNIT_SPELLCAST_START", "player"); WoW.tick()
eq(pc.spell._text, "Hearthstone", "a real cast takes the bar")
check(pc.flight == nil, "no flight state under it")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player"); WoW.tick()
check(pc.flashing, "its interrupt flash")
WoW.flushTimers()
eq(pc.spell._text, "Flight to Orgrimmar, Durotar", "the flight back after the flash")

-- No known duration, an early landing, an unknown route.
cur.total = nil; changed()
check(pc.bar._value == 1 and pc.time._text == "" and not pc.spark._shown, "no total: a full bar, no time")
cur.total, cur.early = 100, true; changed()
eq(pc.spell._text, "Landing at the next stop", "landing early")
check(pc.time._text == "", "and no time")
cur.early, cur.to = nil, nil; changed()
eq(pc.spell._text, "Flight", "an unknown route")

-- Landing.
cur = nil; changed()
check(not pc.host._shown, "landing: the bar hides")

-- The setting: off hides it and is saved; on brings it back.
cur = copy(ORG); cur.start = WoW.now; changed()
SlashCmdList.GLASSUNITFRAMES("flight off"); WoW.tick()   -- repaints flush once a frame
check(not pc.host._shown, "/glass flight off: hidden")
eq(GlassUnitFramesDB.flightBar, false, "saved")
check(S.SetFlightBar(true), "on again"); WoW.tick()
check(pc.host._shown, "the flight back")
eq(GlassUnitFramesDB.flightBar, nil, "on is the default, not saved")

-- Preview owns the bar; the flight comes back when it ends.
check(S.SetPreview(true), "preview on")
check(pc.spell._text ~= "Flight to Orgrimmar, Durotar", "a preview sample, not the flight")
-- A sample's flash ending (idle) must not put the flight on the preview bar.
check(GlassUF.Flight.Current() == nil, "no flight to draw during a preview")
S.SetPreview(false); WoW.tick()
eq(pc.spell._text, "Flight to Orgrimmar, Durotar", "after the preview: the flight")

-- A broken or missing library: no flight, and no paint failure.
throws = true; changed()
check(not pc.host._shown, "Current() throwing: nothing")
throws = false
LibStub.libs["LibTaxiTime-1.0"] = nil; changed()
check(not pc.host._shown, "no library: nothing")
LibStub.libs["LibTaxiTime-1.0"] = LTT
eq(next(GlassUF.paintFailures), nil, "no paint failures")

-- The player's zoom on (the default): a flight zooms the bar like combat,
-- and a /reload mid-flight comes back zoomed.
cur = copy(ORG); cur.start = WoW.now
boot({})
Castbar, Zoom = GlassUF.Castbar, GlassUF.Zoom
pc = Castbar.bars.player
check(pc.host._shown and pc.spell._text == "Flight to Orgrimmar, Durotar", "loaded mid-flight: the flight shows")
check(Zoom.flying, "and zooms")
local x, y, _, _, detached, scale = Castbar.EffectiveGeometry("player")
check(detached and x == 0 and y == -182 and scale == 1.5, "at the player's zoom spot and scale")
cur = nil; changed(); WoW.tick(1)
check(not Zoom.flying, "landing: the zoom ends")
check(not select(5, Castbar.EffectiveGeometry("player")), "home: docked")

-- Under the group layout, a takeoff or landing changes the lift both bars
-- share: the detached target bar moves with it (Codex, #154). The grid's top
-- at 382 (-2 from the centre); the target's bar alone lifts by 171, the
-- player's zoom spot by 201.
cur = nil
WoW.reset(); standardUnits(); GlassUF = nil
WoW.layout = true
UIParent._center, UIParent._width, UIParent._height = { 683, 384 }, 1366, 768
rawset(_G, "GlassRaidFrames", { LayoutState = function()
    return { role = "healer", l = 400, b = 228, w = 566, h = 154, top = 382, base = 160, mode = "hud" }
end })
loadAddon({ db = { castBars = { target = { detached = true } } } })
WoW.fire("LOADING_SCREEN_DISABLED")
Castbar = GlassUF.Castbar
local tc = Castbar.bars.target
check(GlassUF.Link.Placing(), "linked")
eq(tc.host._points[1][5], (-152 + 171) / 1.5, "the target's bar, lifted on its own")
cur = copy(ORG); cur.start = WoW.now; changed(); WoW.tick(1)
eq(tc.host._points[1][5], (-152 + 201) / 1.5, "takeoff: lifted with the player's zoomed bar")
cur = nil; changed(); WoW.tick(1)
eq(tc.host._points[1][5], (-152 + 171) / 1.5, "landing: back")
rawset(_G, "GlassRaidFrames", nil)

done("test_flight")
