-- A taxi flight on the player's cast bar (#148), Quartz's Flight: drawn from
-- Glass Panel's flight timer (GlassPanel.Flight, API 1: Current() and the
-- "GlassPanel.Flight.Changed" event), never hidden for its zoomed bar, taken
-- by a real cast and given back after it, and zoomed like combat when the
-- player's zoom is on.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local cur, api, throws = nil, 1, false
local zoomedAsked = 0
local function glassPanel()
    rawset(_G, "GlassPanel", { Flight = {
        API = api,
        Current = function()
            if throws then error("GlassPanel broke") end
            if not cur then return nil end
            local t = {}
            for k, v in pairs(cur) do t[k] = v end
            return t
        end,
        -- Zoomed all the time: ours never steps aside, so it's never asked.
        Zoomed = function() zoomedAsked = zoomedAsked + 1; return true end,
    } })
end
local function changed() EventRegistry:TriggerEvent("GlassPanel.Flight.Changed"); WoW.tick() end
local function boot(db)
    WoW.reset(); standardUnits(); GlassUF = nil
    glassPanel()
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

-- Takeoff: "Flight to ...", the flight master's icon, emptying like a channel.
cur = copy(ORG); cur.start = WoW.now
changed()
check(pc.host._shown, "takeoff: the flight shows on the player's cast bar")
eq(pc.spell._text, "Flight to Orgrimmar, Durotar", "its destination")
eq(pc.icon._file, Flight.ICON, "the flight master's icon")
eq(pc.bar._timer.dir, GlassUF.API.TimerDirection(true), "it empties like a channel")
eq(pc.bar._timer.duration:GetRemainingDuration(), 120, "from Glass Panel's start and total")
check(zoomedAsked == 0, "Glass Panel's zoomed bar never hides ours")
WoW.now = WoW.now + 29.6
WoW.tick(0.06)
eq(pc.time._text, "1:31", "the time left as m:ss")
cur.source = "estimate"; changed(); WoW.tick(0.06)
eq(pc.time._text, "~1:31", "an estimate: ~")

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

-- Anything but Glass Panel's API 1: no flight, and no failure.
api = 2; glassPanel(); changed()
check(not pc.host._shown, "another API version: nothing")
api = 1; throws = true; glassPanel(); changed()
check(not pc.host._shown, "Current() throwing: nothing")
throws = false
rawset(_G, "GlassPanel", nil); changed()
check(not pc.host._shown, "no Glass Panel: nothing")
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

done("test_flight")
