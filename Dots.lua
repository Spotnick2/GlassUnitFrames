-- Dots.lua: will my DoTs kill it? (#175, docs/DOT-KILL-PLAN.md)
--
-- This first part is the estimate itself, plain arithmetic on the generated
-- spell data (DotSpells.lua) and our own inputs: no client value is read here.
-- The tracker (casts, inferred ticks, outcomes) and the view come once the
-- probe (`/fp steps cast dots`) has measured what they stand on.
--
-- Every number errs low (plan section 2): a tick is rounded down, nothing the
-- tables don't state is added, and an unknown input is the smallest one.

GlassUF = GlassUF or {}
local Dots = {}
GlassUF.Dots = Dots

-- Tick shapes the tables don't carry: factors per tick that average 1.
-- Bane of Agony is back-loaded, measured on Forever by another addon's logs
-- (ticks of 3,3,3,3 then 6,... then 9 over 24 s); P4 re-checks it.
Dots.SHAPES = {
    ["Bane of Agony"] = { 0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5, 1.5, 1.5, 1.5 },
}

-- A float32 coefficient times spell power lands just under a whole number
-- (3 + 0.1299999952 * 100): rounding down must not take the tick below it.
local EPSILON = 1e-6

local function data() return GlassUF.DotSpells end

-- The aura a cast applies, and whether it travels (a projectile: its first
-- tick may come late). nil for anything we don't track.
function Dots.CastAura(spellID)
    local d = data()
    local c = d and type(spellID) == "number" and d.cast[spellID]
    if not c then return nil end
    return d.aura[c[1]], c[1], c[2]
end

-- The level term: max(0, min(level, cap) - SpellLevel), where cap is MaxLevel
-- only when it's above 0 (0 means no cap).
function Dots.LevelSteps(aura, level)
    if aura.perLevel == 0 then return 0 end
    local l = level
    if aura.maxLevel > 0 and l > aura.maxLevel then l = aura.maxLevel end
    l = l - aura.spellLevel
    if l < 0 then return 0 end
    return l
end

-- How many ticks an application has: its duration (plus the per-combo part,
-- capped at the table's maximum) over its period, rounded down.
function Dots.TickCount(aura, points)
    local duration = aura.duration + aura.durationPerCombo * (points or 0)
    if duration > aura.maxDuration then duration = aura.maxDuration end
    return math.floor(duration / aura.period + EPSILON)
end

-- The factor for tick k of n (1 for an even DoT). A shape is stretched to the
-- tick count, so a talent-changed length keeps its proportions.
function Dots.ShapeFactor(aura, k, n)
    local shape = Dots.SHAPES[aura.name]
    if not shape then return 1 end
    local i = math.ceil(k / n * #shape)
    if i < 1 then i = 1 elseif i > #shape then i = #shape end
    return shape[i]
end

-- The estimate for every tick of one application, in order:
-- floor((base + perLevel * L + perCombo * points + coef * spellPower) * shape[k]).
-- points: the combo points spent (1 when unknown; only finishers use them).
-- spellPower: the plain read at the cast, 0 when there was none.
function Dots.TickEstimates(aura, points, spellPower, level)
    points = points or 1
    local raw = aura.base + aura.perLevel * Dots.LevelSteps(aura, level or 1)
        + aura.perCombo * points + aura.coef * (spellPower or 0)
    local n = Dots.TickCount(aura, points)
    local ticks = {}
    for k = 1, n do
        local v = math.floor(raw * Dots.ShapeFactor(aura, k, n) + EPSILON)
        ticks[k] = v > 0 and v or 0
    end
    return ticks
end
