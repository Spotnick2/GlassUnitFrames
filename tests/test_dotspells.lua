-- test_dotspells.lua: the generated spell data (DotSpells.lua, from
-- Tools/dot_spells.py) and the per-tick estimate in Dots.lua (#175, plan
-- section 5). The fixtures are the client's own numbers at the file's build:
-- a failing one after a regeneration means the data changed meaning. Read the
-- rows, don't loosen the test.

dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
standardUnits()
loadAddon()
local D, Dots = GlassUF.DotSpells, GlassUF.Dots

check(type(D.build) == "string" and D.build:match("^%d+%.%d+%.%d+%.%d+$"), "the header's build")

-- The newest saved table set, when the References checkout is there: a newer
-- one means the file may be stale (a warning: regenerate, then read the diff).
local function later(a, b)
    local x, y = {}, {}
    for n in a:gmatch("%d+") do x[#x + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do y[#y + 1] = tonumber(n) end
    for i = 1, 4 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end
do
    local newest
    local windows = package.config:sub(1, 1) == "\\"
    local p = io.popen(windows and 'dir /b "..\\References\\Forever\\db\\forever-spelleffect-*.csv" 2>nul'
        or 'ls ../References/Forever/db/forever-spelleffect-*.csv 2>/dev/null')
    if p then
        for line in p:lines() do
            local b = line:match("(%d+%.%d+%.%d+%.%d+)%.csv$")
            if b and (not newest or later(b, newest)) then newest = b end
        end
        p:close()
    end
    if newest and newest ~= D.build then
        io.write("  WARNING: DotSpells.lua is from " .. D.build .. ", the newest tables are " .. newest
            .. ": python Tools/dot_spells.py\n")
    end
end

-- Every row's shape.
local byName, auras = {}, 0
for id, a in pairs(D.aura) do
    auras = auras + 1
    local where = (a.name or "?") .. " " .. id
    check(type(a.name) == "string" and a.name ~= "", where .. ": name")
    check(D.aura[a.family] and D.aura[a.family].name == a.name and a.family <= id, where .. ": family is its lowest rank")
    check(a.period > 0 and a.duration > 0 and a.maxDuration >= a.duration, where .. ": timing")
    check(a.durationPerCombo >= 0 and a.base >= 0 and a.perCombo >= 0 and a.coef >= 0 and a.perLevel >= 0,
        where .. ": no negative term")
    check(Dots.TickCount(a, 1) >= 1, where .. ": at least one tick")
    local mask = 0
    for _, s in ipairs(a.schools) do
        check(s >= 1 and s <= 7, where .. ": a GetSpellBonusDamage index")
        mask = mask + 2 ^ (s - 1)
    end
    eq(mask, a.schoolMask, where .. ": schools match the mask")
    byName[a.name] = byName[a.name] or id
end
check(auras > 0, "auras generated")
for id, c in pairs(D.cast) do
    check(D.aura[c[1]] ~= nil, "cast " .. id .. " applies a generated aura")
    check(type(c[2]) == "boolean", "cast " .. id .. ": travel flag")
end
for _, name in ipairs({ "Corruption", "Shadow Word: Pain", "Bane of Agony", "Immolate", "Siphon Life",
        "Moonfire", "Insect Swarm", "Rend", "Rip", "Rupture", "Garrote", "Rake", "Pounce Bleed",
        "Serpent Sting", "Flame Shock", "Devouring Plague", "Holy Fire" }) do
    check(byName[name] ~= nil, "supported family present: " .. name)
end
for _, name in ipairs({ "Living Bomb", "Sunfire", "Void Plague", "Drain Life", "Mind Flay", "Immolation Trap" }) do
    check(byName[name] == nil, "left out (own scaling, channel or trap): " .. name)
end
check(D.aura[18376] == nil, "Corruption 18376, an NPC spell, is no rank")

local function ticks(t) return table.concat(t, ",") end

-- Corruption rank 1: 4 ticks of 10 every 3 s, 0.2 of spell power per tick, Shadow.
local a, aura, travel = Dots.CastAura(172)
eq(aura, 172, "Corruption applies itself")
eq(travel, false, "Corruption: no travel")
eq(a.period, 3, "Corruption: every 3 s")
eq(a.schools[1], 6, "Corruption: Shadow is index 6")
eq(ticks(Dots.TickEstimates(a, nil, 0, 60)), "10,10,10,10", "Corruption: four ticks of 10")
eq(ticks(Dots.TickEstimates(a, nil, 100, 60)), "30,30,30,30", "Corruption with 100 spell power")
eq(ticks(Dots.TickEstimates(a, nil, nil, 60)), "10,10,10,10", "no spell power read means 0")

-- Rip rank 1: 6 ticks every 2 s, 4 + 5.5 per point, rounded down.
a = Dots.CastAura(1079)
eq(ticks(Dots.TickEstimates(a, 1, 0, 60)), "9,9,9,9,9,9", "Rip at 1 point: 9.5 rounds down")
eq(ticks(Dots.TickEstimates(a, 5, 0, 60)), "31,31,31,31,31,31", "Rip at 5 points")
eq(ticks(Dots.TickEstimates(a, nil, 0, 60)), "9,9,9,9,9,9", "unknown points take 1")
eq(ticks(Dots.TickEstimates(a, 5, 500, 60)), "31,31,31,31,31,31", "spell power doesn't scale a bleed (coef 0)")

-- Rupture rank 1: 6 s + 2 s per point (max 16 s), every 2 s, 5 + 1.18 per point.
a = Dots.CastAura(1943)
eq(ticks(Dots.TickEstimates(a, 1, 0, 60)), "6,6,6,6", "Rupture at 1 point: 8 s, 4 ticks")
eq(ticks(Dots.TickEstimates(a, 5, 0, 60)), "10,10,10,10,10,10,10,10", "Rupture at 5 points: 16 s, 8 ticks")
eq(Dots.TickCount(a, 7), 8, "Rupture's duration is capped at 16 s")

-- Pounce triggers Pounce Bleed: the bleed's own 18 s, not the stun's 2 s.
a, aura = Dots.CastAura(9005)
eq(aura, 9007, "Pounce applies Pounce Bleed")
eq(ticks(Dots.TickEstimates(a, nil, 0, 60)), "19,19,19,19,19,19", "Pounce Bleed: 6 ticks of 19")

-- Immolate rank 1: the periodic part only, 5 ticks of 3, 0.13 per tick.
a = Dots.CastAura(348)
eq(ticks(Dots.TickEstimates(a, nil, 0, 60)), "3,3,3,3,3", "Immolate: 5 ticks of 3")
eq(ticks(Dots.TickEstimates(a, nil, 100, 60)), "16,16,16,16,16",
    "Immolate with 100 spell power: 3 + 0.1299999952 * 100 is 16, not 15")

-- Serpent Sting rank 1: 5 ticks of 3, no spell power, a projectile.
a, aura, travel = Dots.CastAura(1978)
eq(travel, true, "Serpent Sting travels")
eq(ticks(Dots.TickEstimates(a, nil, 300, 60)), "3,3,3,3,3", "Serpent Sting: 5 ticks of 3")

-- Bane of Agony: twelve back-loaded ticks, each rounded down after its factor.
a = D.aura[byName["Bane of Agony"]]
local n = Dots.TickCount(a, 0)
eq(n, 12, "Agony: 12 ticks")
local t, sum, expect = Dots.TickEstimates(a, nil, 0, 60), 0, {}
for k = 1, n do
    expect[k] = math.floor(a.base * Dots.SHAPES["Bane of Agony"][k] + 1e-6)
    sum = sum + t[k]
end
eq(ticks(t), ticks(expect), "Agony: each tick is floor(base * factor)")
check(t[1] < t[12], "Agony: back-loaded")
check(sum <= a.base * 12, "Agony: rounding never adds damage")

-- Nothing unsupported is estimated.
eq(Dots.CastAura(133), nil, "Fireball isn't tracked")
eq(Dots.CastAura(nil), nil, "no spell")

-- The level term, on synthetic rows (every periodic row has perLevel 0 today).
local function row(over)
    local r = { name = "Test", base = 10, perLevel = 2, perCombo = 0, coef = 0, period = 3, duration = 12,
        maxDuration = 12, durationPerCombo = 0, spellLevel = 10, baseLevel = 10, maxLevel = 20 }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end
eq(Dots.LevelSteps(row(), 5), 0, "below SpellLevel: no steps")
eq(Dots.LevelSteps(row(), 15), 5, "between: level - SpellLevel")
eq(Dots.LevelSteps(row(), 60), 10, "capped at MaxLevel")
eq(Dots.LevelSteps(row({ maxLevel = 0 }), 60), 50, "MaxLevel 0: no cap")
eq(Dots.LevelSteps(row({ perLevel = 0 }), 60), 0, "no per-level points: no steps")
eq(ticks(Dots.TickEstimates(row(), nil, 0, 15)), "20,20,20,20", "10 + 2 * 5 per tick")

-- The shape is inside the floor: an odd base halves to a fraction, rounded down.
eq(ticks(Dots.TickEstimates(row({ name = "Bane of Agony", base = 7, perLevel = 0, period = 2, duration = 24,
    maxDuration = 24 }), nil, 0, 60)), "3,3,3,3,7,7,7,7,10,10,10,10", "floor(7 * 0.5) is 3, floor(7 * 1.5) is 10")

done("test_dotspells")
