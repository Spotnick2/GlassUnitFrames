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
--
-- The regen segment (#118): a faint bar past the mana fill, as wide as the
-- next 2 s of regen. It shares the strip's window (inside it, the casting
-- rate applies), bar choice and events, so it lives here. GetManaRegen() is
-- secret in combat and mana is always secret, so nothing is computed: the
-- segment is twice the bar's width with the range (0, max mana) and the rate
-- as its value, so it draws rate / max * 2W, 2 s of regen in the bar's units.
-- Its clip ends at the bar's end. The events and the window are kept while
-- either the strip or the segment is on.

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
FiveSecond.regen = true         -- db.manaRegen == false turns the regen segment off

local REGEN_COLOR = { 0.55, 0.80, 1.00, 0.55 }

local S = { state = "idle", gen = 0 }   -- state: idle | window; preview: the sample loop (#109)
local strips, segs, dur, ev
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

-- The mana bar in use: "power", or for a druid in a form "druid" (the druid
-- mana strip). nil when unknown.
local function currentKey()
    if not strips then return nil end
    if class ~= "DRUID" then return "power" end
    local ok, _, token = pcall(UnitPowerType, "player")
    if not ok or not plain(token) or token == nil then return nil end
    if token == "MANA" then return "power" end
    return "druid"
end

-- The strip in use.
local function current()
    local key = currentKey()
    return key and strips[key]
end

local function tracking() return FiveSecond.enabled or FiveSecond.regen end

-- Hidden at full mana: an alpha the client computes (1 below full, 0 at full).
local function fullAlpha(clip, key)
    local ok, a = pcall(API.ManaAlpha, "player")
    if ok and (API.IsSecret(a) or type(a) == "number") then
        if attempt(key, clip.SetAlpha, clip, a) then return end
    end
    clip:SetAlpha(1)
end

local function setAlpha(s)
    -- The preview shows at full mana too.
    if S.preview then s.clip:SetAlpha(1) return end
    fullAlpha(s.clip, "fsr alpha")
end

local function dead()
    local ok, v = pcall(UnitIsDeadOrGhost, "player")
    return ok and plain(v) and v == true
end

-- The regen segment on the bar in use. Inside the window the casting rate
-- applies, else the base rate: picked by our own plain state, never by
-- `a and b or c` (the returns are secret in combat, and a truth test on a
-- secret throws). No preview override at full mana: the segment is then past
-- the bar's end anyway.
local function paintRegen()
    if not segs then return end
    local key = FiveSecond.regen and not dead() and currentKey() or nil
    -- In a preview the druid strip shows a fixed 60%: a live segment past it would lie.
    if key == "druid" and S.preview then key = nil end
    for k, g in pairs(segs) do
        if k ~= key then g.clip:Hide() end
    end
    local g = key and segs[key]
    if not g then return end
    local painted = attempt("regen", function()
        local base, casting = GetManaRegen()
        local rate = base
        if S.state == "window" then rate = casting end
        g.bar:SetMinMaxValues(0, UnitPowerMax("player", manaType()))
        g.bar:SetValue(rate)
    end)
    if not painted then g.clip:Hide() return end
    fullAlpha(g.clip, "regen alpha")
    g.clip:Show()
end

local function paint()
    if not strips then return end
    paintRegen()
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

-- Mana changed: the strip's full-mana alpha (a potion, mp5), and the
-- segment (its alpha, and the rate: a spirit buff).
local function onManaUpdate()
    paintRegen()
    local cur = current()
    if cur and cur.clip:IsShown() then setAlpha(cur) end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
                 "PLAYER_ALIVE", "PLAYER_UNGHOST" }

-- The events the regen segment repaints on (a2 = the power type's token).
local function regenEvent(event, a2)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then return plain(a2) and a2 == "MANA" end
    return event == "UNIT_DISPLAYPOWER" or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE"
        or event == "PLAYER_UNGHOST"
end

local function onEvent(_, event, a1, a2, a3)
    if S.preview then
        -- The sample owns the strip; combat is still tracked, so a real
        -- spend right after the preview knows where it stands. The regen
        -- segment stays live.
        if event == "PLAYER_REGEN_DISABLED" then combat = true
        elseif event == "PLAYER_REGEN_ENABLED" then combat = false
        elseif event == "PLAYER_ENTERING_WORLD" then readCombat()
        elseif regenEvent(event, a2) then paintRegen() end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a1 = unit, a2 = castGUID, a3 = spellID
        if costsMana(a3) then startWindow(GetTime()) end
    elseif event == "UNIT_POWER_UPDATE" then
        -- a2 = the power type's token
        if plain(a2) and a2 == "MANA" then onManaUpdate() end
    elseif event == "UNIT_MAXPOWER" then
        if plain(a2) and a2 == "MANA" then paintRegen() end
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
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        paint()
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

-- The regen segment on `base` (`width` wide): twice its width, from the
-- fill's moving edge (top and bottom, so it follows the row's height),
-- clipped at the bar's end.
local function segment(base, width)
    local bar = Frames.OverlayBar(base, REGEN_COLOR, 3, false)
    local fill = base:GetStatusBarTexture()
    bar:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    bar:SetWidth(2 * width)
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
    FiveSecond.regen = db.manaRegen ~= false
    dur = C_DurationUtil.CreateDuration()
    strips = { power = strip(b.power) }
    segs = { power = segment(b.power, b.healthWidth) }
    if b.druidMana then
        strips.druid = strip(b.druidMana.bar)
        segs.druid = segment(b.druidMana.bar, b.druidMana.width)
    end
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", onEvent)
    if tracking() then register() end
    paint()
    return strips
end

function FiveSecond.Built() return strips ~= nil end

-- The strip or the segment turned on or off. The events and the window serve
-- both: the last one off unregisters and idles; the first one on registers,
-- re-reads combat (it may have changed unseen) and idles (a spend may have
-- been missed); otherwise the window is kept and only the looks change.
local function retrack(was)
    if tracking() and not was then register(); readCombat(); toIdle()
    elseif not tracking() then ev:UnregisterAllEvents(); toIdle()
    else paint() end
end

function FiveSecond.SetEnabled(on)
    local was = tracking()
    FiveSecond.enabled = on and true or false
    if not strips then return false end
    retrack(was)
    -- During a preview (#109) the sample loop is the strip's: on restarts it,
    -- off ends it (the new generation drops its pending callbacks).
    if S.preview then
        if FiveSecond.enabled then return FiveSecond.SetPreview(true) end
        toIdle()
    end
    return true
end

function FiveSecond.SetRegen(on)
    local was = tracking()
    FiveSecond.regen = on and true or false
    if not strips then return false end
    retrack(was)
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

FiveSecond._test = { state = S, strips = function() return strips end, segs = function() return segs end,
                     dur = function() return dur end,
                     costsMana = costsMana, current = current,
                     onEvent = onEvent, combat = function() return combat end,
                     reset = function() S.state = "idle"; S.gen = S.gen + 1; combat = false end }
