-- GlassUnitFrames: the five-second rule (#94). A 2 px strip on the bottom
-- edge of the player's mana bar (a druid in a form: the druid mana strip):
-- red, draining, for the 5 s after a spell that costs mana; then blue, filling
-- toward the next mana tick. Mana users only.
--
-- Mana is SECRET on Forever, in and out of combat (measured, #94), so nothing
-- here reads or compares it. The signals instead:
--   * a spend is a player UNIT_SPELLCAST_SUCCEEDED whose spell has a mana cost
--     (C_Spell.GetSpellPowerCost, measured plain). A likely spend, not proof:
--     a waived cost or a free proc can start the window wrongly;
--   * a tick is a UNIT_POWER_UPDATE("MANA"). It says mana changed, not why,
--     so the blue sweep is an estimate. Measured: one update per regen tick,
--     1.83-2.03 s apart, plus echoes 0.07-0.13 s after some; the first one
--     5.2-6.3 s after a spend; a spend's own update up to 0.115 s after its
--     SUCCEEDED (inside the window, ignored).
-- An update at least REANCHOR after the last anchor restarts the sweep from
-- it (follows the server's tick); an earlier one only keeps the cycle alive.
-- With no update for IDLE_AFTER at a sweep's end, the cycle stops. Full mana
-- hides the strip through a client-computed alpha (API.ManaAlpha).
--
-- Its own event frame, so the timing follows the client's event order, not
-- Engine's once-per-frame repaint. The fill is a LuaDurationObject on
-- StatusBar:SetTimerDuration: no Lua runs per frame.

GlassUF = GlassUF or {}
local API, Frames = GlassUF.API, GlassUF.Frames
local attempt = Frames.attempt

local FiveSecond = {}
GlassUF.FiveSecond = FiveSecond

local WINDOW = 5.0        -- the rule
local TICK = 2.0          -- the regen tick
local REANCHOR = 1.5      -- an update this long after the anchor is a tick
local IDLE_AFTER = 2.5    -- no update this long at a sweep's end: idle
local PENDING_MAX = 2 * TICK
FiveSecond.WINDOW, FiveSecond.TICK, FiveSecond.REANCHOR = WINDOW, TICK, REANCHOR

local RED = { 1.00, 0.30, 0.25 }
local BLUE = { 0.55, 0.85, 1.00 }   -- lighter than the mana fill, so it reads on it
local MANA_CLASSES = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true,
                       SHAMAN = true, WARLOCK = true }

FiveSecond.enabled = true       -- db.fiveSecondRule == false turns it off
FiveSecond.combatOnly = true    -- db.fsrCombatOnly == false shows it out of combat too

local S = { state = "idle", gen = 0 }   -- state: idle | window | pending | sweep
local strips, dur, ev
local class
local combat = false

local function plain(v) return not API.IsSecret(v) end

local function manaType()
    local pt = Enum and Enum.PowerType
    return (pt and plain(pt.Mana) and pt.Mana) or 0
end

-- Does this spell cost mana? Every step of the traversal is checked for
-- secrecy before it's indexed or compared; a secret table or entry, or an
-- error, is "unknown", which is not a spend. A secret amount in a plain mana
-- entry counts (only a plain 0 is free).
local function costsMana(spellID)
    if not plain(spellID) or type(spellID) ~= "number" then return false end
    local cs = rawget(_G, "C_Spell")
    if not (cs and cs.GetSpellPowerCost) then return false end
    local ok, spend = pcall(function()
        local costs = cs.GetSpellPowerCost(spellID)
        if not plain(costs) or type(costs) ~= "table" then return false end
        local mana = manaType()
        for i = 1, #costs do
            local e = costs[i]
            if not plain(e) or type(e) ~= "table" then return false end
            local t = e.type
            if plain(t) and t == mana then
                for _, field in ipairs({ "cost", "costPerSec" }) do
                    local v = e[field]
                    if not plain(v) then return true end
                    if type(v) == "number" and v > 0 then return true end
                end
            end
        end
        return false
    end)
    return ok and spend == true
end

-- The strip in use: the power bar, or for a druid in a form the druid mana
-- strip. nil when unknown.
local function current()
    if not strips then return nil end
    if class ~= "DRUID" then return strips.power end
    local ok, _, token = pcall(UnitPowerType, "player")
    if not ok or not plain(token) or token == nil then return nil end
    if token == "MANA" then return strips.power end
    return strips.druid
end

local function setAlpha(s)
    local ok, a = pcall(API.ManaAlpha, "player")
    if ok and (API.IsSecret(a) or type(a) == "number") then
        if attempt("fsr alpha", s.clip.SetAlpha, s.clip, a) then return end
    end
    s.clip:SetAlpha(1)
end

local function paint()
    if not strips then return end
    local cur = current()
    local live = S.state == "window" or S.state == "sweep"
    local show = FiveSecond.enabled and live and cur ~= nil and (combat or not FiveSecond.combatOnly)
    for _, s in pairs(strips) do
        if s ~= cur or not show then s.clip:Hide() end
    end
    if not show then return end
    local window = S.state == "window"
    local col = window and RED or BLUE
    cur.bar:SetStatusBarColor(col[1], col[2], col[3])
    -- Red drains (RemainingTime); blue fills (ElapsedTime).
    attempt("fsr timer", cur.bar.SetTimerDuration, cur.bar, dur, nil, API.TimerDirection(window))
    setAlpha(cur)
    cur.clip:Show()
end

local function setState(state, start, length)
    S.gen = S.gen + 1
    S.state = state
    if start then attempt("fsr duration", dur.SetTimeFromStart, dur, start, length) end
    paint()
    return S.gen
end

local function after(delay, gen, fn)
    C_Timer.After(math.max(0, delay), function()
        if S.gen == gen then fn() end
    end)
end

local function toIdle() setState("idle") end

local function toPending()
    local gen = setState("pending")
    after(PENDING_MAX, gen, toIdle)
end

local sweepEnd
local function startSweep(t)
    S.sweepStart = t
    local gen = setState("sweep", t, TICK)
    after(t + TICK - GetTime(), gen, sweepEnd)
end

-- Back to back while updates keep coming; idle once they stop.
function sweepEnd()
    if S.lastUpdate and GetTime() - S.lastUpdate < IDLE_AFTER then
        startSweep(S.sweepStart + TICK)
    else
        toIdle()
    end
end

local function startWindow(now)
    local gen = setState("window", now, WINDOW)
    after(WINDOW, gen, toPending)
end

local function onManaUpdate()
    local now = GetTime()
    if S.state == "window" then
        if strips then local cur = current(); if cur and cur.clip:IsShown() then setAlpha(cur) end end
        return
    end
    S.lastUpdate = now
    if S.state == "sweep" and now - S.anchor < REANCHOR then
        local cur = current()
        if cur and cur.clip:IsShown() then setAlpha(cur) end
        return
    end
    S.anchor = now
    startSweep(now)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER" }
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD" }

local function onEvent(_, event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a1 = unit, a2 = castGUID, a3 = spellID
        if costsMana(a3) then startWindow(GetTime()) end
    elseif event == "UNIT_POWER_UPDATE" then
        -- a2 = the power type's token
        if plain(a2) and a2 == "MANA" then onManaUpdate() end
    elseif event == "UNIT_DISPLAYPOWER" then
        paint()   -- a druid's form: the other strip
    elseif event == "PLAYER_REGEN_DISABLED" then
        combat = true
        paint()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combat = false
        -- Measured twice: regen resumed about 2 s after a killing spend, inside
        -- the 5 s. A wrong guess only shows an empty strip until the next tick.
        if S.state == "window" then toPending() else paint() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local ok, v = pcall(InCombatLockdown)
        combat = ok and plain(v) and v == true
        paint()
    elseif event == "PLAYER_DEAD" then
        toIdle()
    end
end

local function register()
    API.RegisterUnitEvents(ev, UNIT_EVENTS, "player")
    API.RegisterEvents(ev, EVENTS)
end

--------------------------------------------------------------------------------
-- Building and settings
--------------------------------------------------------------------------------

-- A 2 px strip along the bottom of `base`, inside its rounded mask.
local function strip(base)
    local bar = Frames.OverlayBar(base, { BLUE[1], BLUE[2], BLUE[3], 1 }, 4, false)
    bar:SetPoint("BOTTOMLEFT", base, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(2)
    local clip = bar:GetParent()
    clip:Hide()
    return { bar = bar, clip = clip }
end

-- Called by Frames.Build for the player's frame, after the druid mana strip.
function FiveSecond.Build(b, db)
    local ok, _, cls = pcall(UnitClass, "player")
    if not (ok and plain(cls) and MANA_CLASSES[cls]) then return end
    if not (b and b.power and rawget(_G, "C_DurationUtil")) then return end
    class = cls
    FiveSecond.enabled = db.fiveSecondRule ~= false
    FiveSecond.combatOnly = db.fsrCombatOnly ~= false
    dur = C_DurationUtil.CreateDuration()
    strips = { power = strip(b.power) }
    if b.druidMana then strips.druid = strip(b.druidMana.bar) end
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", onEvent)
    if FiveSecond.enabled then register() end
    return strips
end

function FiveSecond.Built() return strips ~= nil end

-- Off: idle, hidden, no events.
function FiveSecond.SetEnabled(on)
    FiveSecond.enabled = on and true or false
    if not strips then return false end
    if FiveSecond.enabled then register() else ev:UnregisterAllEvents() end
    toIdle()
    return true
end

function FiveSecond.SetCombatOnly(on)
    FiveSecond.combatOnly = on and true or false
    paint()
    return strips ~= nil
end

FiveSecond._test = { state = S, strips = function() return strips end, dur = function() return dur end,
                     costsMana = costsMana, current = current,
                     reset = function() S.state, S.anchor, S.lastUpdate, S.sweepStart = "idle", nil, nil, nil
                                        S.gen = S.gen + 1; combat = false end }
