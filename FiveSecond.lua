-- GlassUnitFrames: the five-second rule (#94). A 2 px red strip on the
-- bottom edge of the player's mana bar (a druid in a form: the druid mana
-- strip), draining for the 5 s after a spell that costs mana: spirit regen is
-- paused until it runs out. Mana users only.
--
-- Mana is SECRET on Forever, in and out of combat (measured, #94), so nothing
-- here reads or compares it. A spend is a player UNIT_SPELLCAST_SUCCEEDED
-- whose spell has a mana cost (C_Spell.GetSpellPowerCost, measured plain): a
-- likely spend, not proof (a waived cost or a free proc can start it wrongly).
-- Measured: no UNIT_POWER_UPDATE("MANA") came inside the 5 s after a spend;
-- the first came 5.2-6.3 s after it. No tick timer: regen on Forever is
-- continuous (measured, #108: about 7 UNIT_POWER_FREQUENT per second while
-- regenerating, one per mana point at 6.5/s, and none inside the 5 s); the
-- ~2 s UNIT_POWER_UPDATE cadence is the server's sync, not a tick.
-- Full mana hides the strip through a client-computed alpha (API.ManaAlpha).
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
FiveSecond.WINDOW = WINDOW

local RED = { 1.00, 0.30, 0.25 }
local MANA_CLASSES = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true,
                       SHAMAN = true, WARLOCK = true }

FiveSecond.enabled = true       -- db.fiveSecondRule == false turns it off
FiveSecond.combatOnly = true    -- db.fsrCombatOnly == false shows it out of combat too

local S = { state = "idle", gen = 0 }   -- state: idle | window; preview: the sample loop (#109)
local strips, dur, ev
local class
local combat = false

local function plain(v) return not API.IsSecret(v) end

local function readCombat()
    local ok, v = pcall(InCombatLockdown)
    combat = ok and plain(v) and v == true
end

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
    -- The preview shows at full mana too.
    if S.preview then s.clip:SetAlpha(1) return end
    local ok, a = pcall(API.ManaAlpha, "player")
    if ok and (API.IsSecret(a) or type(a) == "number") then
        if attempt("fsr alpha", s.clip.SetAlpha, s.clip, a) then return end
    end
    s.clip:SetAlpha(1)
end

local function paint()
    if not strips then return end
    local cur = current()
    local show = FiveSecond.enabled and S.state == "window" and cur ~= nil
        and (S.preview or combat or not FiveSecond.combatOnly)
    for _, s in pairs(strips) do
        if s ~= cur or not show then s.clip:Hide() end
    end
    if not show then return end
    -- Drains: RemainingTime.
    attempt("fsr timer", cur.bar.SetTimerDuration, cur.bar, dur, nil, API.TimerDirection(true))
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

local function startWindow(now)
    local gen = setState("window", now, WINDOW)
    after(WINDOW, gen, toIdle)
end

-- Mana changed: only the full-mana alpha can change (a potion, mp5).
local function onManaUpdate()
    local cur = current()
    if cur and cur.clip:IsShown() then setAlpha(cur) end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER" }
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD" }

local function onEvent(_, event, a1, a2, a3)
    if S.preview then
        -- The sample owns the strip; combat is still tracked, so a real
        -- spend right after the preview knows where it stands.
        if event == "PLAYER_REGEN_DISABLED" then combat = true
        elseif event == "PLAYER_REGEN_ENABLED" then combat = false
        elseif event == "PLAYER_ENTERING_WORLD" then readCombat() end
        return
    end
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
        -- the 5 s, so leaving combat ends the window.
        if S.state == "window" then toIdle() else paint() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        readCombat()
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
    local bar = Frames.OverlayBar(base, { RED[1], RED[2], RED[3], 1 }, 4, false)
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

-- Off: idle, hidden, no events. On again: combat may have changed unseen, so
-- it's re-read.
function FiveSecond.SetEnabled(on)
    FiveSecond.enabled = on and true or false
    if not strips then return false end
    if FiveSecond.enabled then register(); readCombat() else ev:UnregisterAllEvents() end
    -- On again during a preview (#109): the sample loop restarts.
    if FiveSecond.enabled and S.preview then return FiveSecond.SetPreview(true) end
    toIdle()
    return true
end

function FiveSecond.SetCombatOnly(on)
    FiveSecond.combatOnly = on and true or false
    paint()
    return strips ~= nil
end

-- Preview (#109): the red window, 1 s empty, again; shown out of combat and
-- at full mana. Every switch bumps the generation: no real window's timer
-- ends a sample one, and no sample timer outlives the preview.
local function sampleLoop()
    local gen = setState("window", GetTime(), WINDOW)
    after(WINDOW, gen, function()
        after(1, setState("idle"), sampleLoop)
    end)
end

function FiveSecond.SetPreview(on)
    S.preview = on and true or false
    if not strips then return false end
    if S.preview and FiveSecond.enabled then sampleLoop() else toIdle() end
    return true
end

FiveSecond._test = { state = S, strips = function() return strips end, dur = function() return dur end,
                     costsMana = costsMana, current = current,
                     onEvent = onEvent, combat = function() return combat end,
                     reset = function() S.state = "idle"; S.gen = S.gen + 1; combat = false end }
