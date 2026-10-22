-- The real LibTaxiTime-1.0 (#153), embedded from its checkout ($LIBTAXITIME,
-- else ../LibTaxiTime) as the client loads it: our store handed over at
-- ADDON_LOADED, the library started by it, and its flight on the player's
-- cast bar. The library's own tests cover its tracker; this proves the wiring.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({ db = { zoom = { global = { player = { on = false } } } } })
local LTT = LibStub("LibTaxiTime-1.0")
eq(LTT.MINOR, 1, "the pinned library (r1, MINOR 1)")
check(LTT.stores[1] == GlassUnitFramesDB.flight, "our store (GlassUnitFramesDB.flight) is the library's")
check(LTT.frame ~= nil, "started by it: its events registered")
eq(next(LTT.errors), nil, "no library errors at load")
local pc = GlassUF.Castbar.bars.player
check(not pc.host._shown, "no flight: the bar stays hidden")

-- A flight the map didn't record (a quest's): control lost, and on a taxi a
-- second later.
WoW.onTaxi = true
WoW.fire("PLAYER_CONTROL_LOST")
WoW.now = WoW.now + 1
WoW.flushTimers(); WoW.tick()
check(LTT:Current() ~= nil, "the library sees the flight")
check(pc.host._shown and pc.spell._text == "Flight", "an unknown flight on our cast bar")
check(pc.time._text == "", "with no time to show")

-- Landing: control back, off the taxi.
WoW.now = WoW.now + 30
WoW.onTaxi = false
WoW.fire("PLAYER_CONTROL_GAINED")
WoW.tickTickers(); WoW.flushTimers(); WoW.tick()
eq(LTT:Current(), nil, "the library lands it")
check(not pc.host._shown, "the bar hides")

eq(next(LTT.errors), nil, "no library errors")
eq(next(GlassUF.paintFailures), nil, "no paint failures")
done("test_taxitime")
