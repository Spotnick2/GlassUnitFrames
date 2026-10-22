-- GlassUnitFrames: taxi flight progress on the player's cast bar (#148),
-- Quartz's Flight. GlassPanel's flight timer owns the timing (GlassPanel
-- #124 / #125); we only draw it, so without GlassPanel there is no flight bar.
--
-- GlassPanel.Flight (API 1, read-only):
-- - Current() -> nil off a flight, else a fresh { to, from, start, total,
--   source, early }: names (nil: an unknown route), start in GetTime()
--   seconds, total in seconds (nil: unknown, or landing early), source
--   "learned" | "route" | "estimate".
-- - EventRegistry "GlassPanel.Flight.Changed" () at takeoff, landing, an
--   early landing and a forget: we repaint; nothing is read once and kept.
-- Ours shows even while GlassPanel's zoomed bar does (owner, 2026-10-22: two
-- similar bars are fine). A real cast takes the bar; the flight comes back
-- when it ends (Castbar's idle path asks Flight.Current()). A flight counts
-- as zoom time for the player's bar when its zoom is on (Zoom.SetFlying).
-- Timing of our own, for players without GlassPanel, waits on a shared
-- embedded library (#153).

GlassUF = GlassUF or {}
local API = GlassUF.API

local Flight = {}
GlassUF.Flight = Flight

Flight.EVENT = "GlassPanel.Flight.Changed"
Flight.ICON = "Interface\\Minimap\\Tracking\\FlightMaster"   -- GlassPanel's flight icon
Flight.enabled = true   -- db.flightBar ~= false
local db

local function plain(v)
    return type(v) == "number" and not API.IsSecret(v) and v == v and v > -math.huge and v < math.huge
end

-- GlassPanel's contract, or nil: exactly API 1, with Current.
local function contract()
    local gp = rawget(_G, "GlassPanel")
    local f = type(gp) == "table" and rawget(gp, "Flight")
    if type(f) ~= "table" or rawget(f, "API") ~= 1 then return nil end
    if type(f.Current) ~= "function" then return nil end
    return f
end

-- The flight to draw now, or nil: off, in a preview, no GlassPanel, or
-- anything unreadable. A plain copy, each field checked: { to, start, total
-- (nil: none to show), estimate, early }.
function Flight.Current()
    if not Flight.enabled then return nil end
    if GlassUF.Preview and GlassUF.Preview.active then return nil end
    local f = contract()
    if not f then return nil end
    local ok, cur = pcall(f.Current)
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

function Flight.Configure(saved)
    db = saved
    Flight.enabled = db.flightBar ~= false
end

-- The setting (GlassUF.Settings.SetFlightBar saves it). Idempotent.
function Flight.SetEnabled(on)
    Flight.enabled = on and true or false
    repaint()
    return true
end

Flight._test = { contract = contract }
