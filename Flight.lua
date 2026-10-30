-- GlassUnitFrames: taxi flight progress on the player's cast bar (#148).
-- The timing is LibTaxiTime-1.0's (#153), an embedded
-- library shared with GlassPanel's Flight plugin: the route lengths, the
-- tracker (takeoff, landing, early landing, a /reload mid-flight) and the
-- learned times. We draw it.
--
-- LibTaxiTime-1.0 (MINOR 1, colon-called; its LibTaxiTime.lua header is the
-- contract):
-- - lib:AddStore(tbl) at our ADDON_LOADED, with GlassUnitFramesDB.flight: the
--   library owns its `routes` and `current` keys. Nothing starts before it.
-- - lib:Current() -> nil off a flight, else a fresh { to, from, stops, start,
--   total, source, early, resumed }: start in GetTime() seconds, total in
--   seconds (nil: unknown, or landing early; it stays the prediction when the
--   flight runs longer), source "learned" | "route" | "estimate" | nil.
-- - EventRegistry "LibTaxiTime.Changed" (): a flight started, landed, landed
--   early, or its total changed. We repaint; nothing is read once and kept.
-- With both addons loaded, the newest copy runs and writes every store.
-- Ours shows even while GlassPanel's zoomed bar does (owner, 2026-10-22: two
-- similar bars are fine). A real cast takes the bar; the flight comes back
-- when it ends (Castbar's idle path asks Flight.Current()). A flight counts
-- as zoom time for the player's bar when its zoom is on (Zoom.SetFlying).

GlassUF = GlassUF or {}
local API = GlassUF.API

local Flight = {}
GlassUF.Flight = Flight

Flight.LIB = "LibTaxiTime-1.0"
Flight.EVENT = "LibTaxiTime.Changed"
Flight.ICON = "Interface\\Minimap\\Tracking\\FlightMaster"   -- GlassPanel's flight icon too
Flight.enabled = true   -- db.flightBar ~= false
local db

local function plain(v)
    return type(v) == "number" and not API.IsSecret(v) and v == v and v > -math.huge and v < math.huge
end

-- The library through LibStub, every time: a newer copy loaded later
-- upgrades the same table, so nothing is kept from file load.
local function lib()
    local LS = rawget(_G, "LibStub")
    if type(LS) ~= "table" then return nil end
    local ok, L = pcall(LS.GetLibrary, LS, Flight.LIB, true)
    if ok and type(L) == "table" then return L end
    return nil
end
Flight.Lib = lib

-- The flight to draw now, or nil: off, in a preview, no library, or anything
-- unreadable. A plain copy, each field checked: { to, start, total (nil:
-- none to show), estimate, early }.
function Flight.Current()
    if not Flight.enabled then return nil end
    if GlassUF.Preview and GlassUF.Preview.active then return nil end
    local L = lib()
    if not (L and type(L.Current) == "function") then return nil end
    local ok, cur = pcall(L.Current, L)
    if not ok or type(cur) ~= "table" then return nil end
    local start, total = cur.start, cur.total
    if not plain(start) then return nil end
    local early = cur.early == true
    if early or not (plain(total) and total > 0) then total = nil end
    return { to = type(cur.to) == "string" and cur.to or nil, start = start, total = total,
             estimate = cur.source == "estimate", early = early }
end

-- The player's cast bar shows the flight, or hides it, now (its zoom follows,
-- in Castbar's idle path).
local function repaint()
    local Castbar = GlassUF.Castbar
    if not (Castbar and Castbar.bars.player) then return end
    GlassUF.Engine.RepaintChannel("cast", function(f) return f.unit == "player" end)
end
Flight.Repaint = repaint

local reg = rawget(_G, "EventRegistry")
if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
    local ok, err = pcall(reg.RegisterCallback, reg, Flight.EVENT, repaint, Flight)
    if not ok then API.Fail("flight subscribe", err) end
end

-- At ADDON_LOADED (our SavedVariables are loaded): the setting, and our
-- store handed to the library, which starts it (hooks, events) on the first.
function Flight.Configure(saved)
    db = saved
    Flight.enabled = db.flightBar ~= false
    if type(db.flight) ~= "table" then db.flight = {} end
    local L = lib()
    if not (L and type(L.AddStore) == "function") then
        API.Fail("flight store", "no " .. Flight.LIB)
        return
    end
    local ok, added, why = pcall(L.AddStore, L, db.flight)
    if not ok then API.Fail("flight store", added)
    elseif not added then API.Fail("flight store", why or "refused") end
end

-- The setting (GlassUF.Settings.SetFlightBar saves it). Idempotent.
function Flight.SetEnabled(on)
    Flight.enabled = on and true or false
    repaint()
    return true
end
