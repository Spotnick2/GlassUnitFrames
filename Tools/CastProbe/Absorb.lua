-- CastProbe, the absorb bar's gate (#171): does Forever's server report a
-- Vanilla absorb (Power Word: Shield first) through UnitGetTotalAbsorbs, the
-- heal prediction calculator's damage absorbs and UNIT_ABSORB_AMOUNT_CHANGED?
-- Does the amount shrink as the shield soaks damage, and is it secret, in and
-- out of combat? A fourth file of the same module: /fp steps cast absorb.
-- If the server never reports it, #171 is reconsidered.

local Probe = ForeverProbe:Module("CastProbe", { api = 1, cmd = "cast" })

local function show(v) return Probe.Show(v, true) end
local function say(line) Probe:Say(line) return line end

local SHIELD = "Power Word: Shield"
local WATCHED = { player = true, target = true, focus = true, pet = true }
local seen = { player = 0, other = 0 }   -- UNIT_ABSORB_AMOUNT_CHANGED fires
local mark = 0                           -- seen.player when the last step read

-- A function's returns, each shown (secret-safe), or ERR / absent.
local function call(fn, ...)
    if type(fn) ~= "function" then return "absent" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "ERR" end
    local parts = {}
    for i = 2, math.max(#r, 2) do parts[#parts + 1] = show(r[i]) end
    return table.concat(parts, ",")
end

-- Our own calculator, made once: GUF's is configured for heals, and the
-- absorb clamp mode is part of what's measured.
local calc
local function calculator()
    if calc then return calc end
    local create = rawget(_G, "CreateUnitHealPredictionCalculator")
    if type(create) ~= "function" then return nil end
    local ok, c = pcall(create)
    if ok and c then calc = c end
    return calc
end

local function calcPart(unit)
    local c = calculator()
    local fill = rawget(_G, "UnitGetDetailedHealPrediction")
    if not c or type(fill) ~= "function" then return "calc=absent" end
    if not pcall(fill, unit, "player", c) then return "calc=ERR" end
    return string.format("calc{damage=%s total=%s maximum=%s clampMode=%s maxHealth=%s healAbsorbs=%s}",
        call(c.GetDamageAbsorbs, c), call(c.GetTotalDamageAbsorbs, c), call(c.GetMaximumDamageAbsorbs, c),
        call(c.GetDamageAbsorbClampMode, c), call(c.GetMaximumHealth, c), call(c.GetHealAbsorbs, c))
end

-- The shield's aura, by name: its points are the absorb in Retail's AuraData.
-- In combat this quietly returns nil (porting guide), so it's the out-of-combat
-- cross-check only.
local function auraPart(unit)
    local auras = rawget(_G, "C_UnitAuras")
    local byName = auras and auras.GetAuraDataBySpellName
    if type(byName) ~= "function" then return "aura=absent" end
    local ok, a = pcall(byName, unit, SHIELD, "HELPFUL")
    if not ok then return "aura=ERR" end
    if a == nil then return "aura=nil" end
    local okF, s = pcall(function()
        local pts = {}
        if type(a.points) == "table" then
            for i = 1, #a.points do pts[#pts + 1] = show(a.points[i]) end
        else
            pts[1] = show(a.points)
        end
        return string.format("aura{spell=%s points=%s duration=%s}", show(a.spellId), table.concat(pts, "/"),
            show(a.duration))
    end)
    return okF and s or "aura=ERR(fields)"
end

local function absorbLine(unit)
    unit = unit or "player"
    local maxHp = call(rawget(_G, "UnitHealthMax"), unit)
    return string.format("absorb %s exists=%s combat=%s total=%s healAbsorbs=%s maxHealth=%s %s %s events=%d/%d",
        unit, show(UnitExists(unit)), show(InCombatLockdown()), call(rawget(_G, "UnitGetTotalAbsorbs"), unit),
        call(rawget(_G, "UnitGetTotalHealAbsorbs"), unit), maxHp, calcPart(unit), auraPart(unit),
        seen.player, seen.other)
end

local function read(unit)
    mark = seen.player
    return say(absorbLine(unit))
end

-- Every change on a unit a frame shows, logged with a fresh read.
local f = CreateFrame("Frame")
Probe:RegisterEvents(f, { "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" })
f:SetScript("OnEvent", function(_, event, unit)
    local ok, watched = pcall(function() return WATCHED[unit] == true end)
    if not (ok and watched) then
        if event == "UNIT_ABSORB_AMOUNT_CHANGED" then seen.other = seen.other + 1 end
        return
    end
    if event == "UNIT_ABSORB_AMOUNT_CHANGED" and unit == "player" then seen.player = seen.player + 1 end
    say(event .. " -> " .. absorbLine(unit))
end)

Probe:Command("absorb", function(unit) read(unit ~= "" and unit or nil) end,
    "absorbs on a unit (default player): UnitGetTotalAbsorbs, the calculator, the shield's aura")

local function changedSinceRead()
    return seen.player > mark, "waiting for UNIT_ABSORB_AMOUNT_CHANGED on you (" .. seen.player .. " so far)"
end

Probe:Steps("absorb", {
    title = "Absorb shields (#171)",
    rev = 1,
    { text = "Before any shield: a first read. Nothing to do: Next.", auto = true, run = function() return read("player") end },
    { text = "Out of combat, cast Power Word: Shield on yourself (or have a priest do it). This step completes when the client announces the absorb; if nothing happens, it gives up after 30 seconds.",
      wait = changedSinceRead, timeout = 30 },
    { text = "With the shield up, out of combat: press Run.", button = "Read", run = function() return read("player") end },
    { text = "Let a mob hit you ONCE while shielded (the shield must not break yet), then press Run.",
      button = "Read", run = function() return read("player") end,
      check = function() return InCombatLockdown(), "read in combat" end },
    { text = "One more hit, still shielded: press Run.", button = "Read", run = function() return read("player") end,
      check = function() return InCombatLockdown(), "read in combat" end },
    { text = "Let the shield break (or run out), then press Run.", button = "Read", run = function() return read("player") end },
    { text = "Did the shield break from damage, or run out? Type it in the Note, then Next." },
    { text = "In a group: shield a party member (or ask for it), target them and press Run. Solo: Skip.",
      button = "Read target", run = function() return read("target") end },
    { text = "Any other absorb at hand (Ice Barrier, Mana Shield, a Voidwalker's Sacrifice, Fire or Frost Ward)? Put it up, press Run, and name it in the Note. None: Skip.",
      button = "Read", run = function() return read("player") end },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

local NS = select(2, ...)
if type(NS) == "table" and type(NS._test) == "table" then
    NS._test.absorbLine = absorbLine
    NS._test.absorbSeen = seen
end
