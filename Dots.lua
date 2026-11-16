-- Dots.lua: will my DoTs kill it? (#175, docs/DOT-KILL-PLAN.md)
--
-- Two parts:
-- - the estimate: plain arithmetic on the generated spell data (DotSpells.lua)
--   and our own inputs;
-- - the tracker (plan section 6): our casts, their outcomes and their inferred
--   ticks, per mob, with its own event frame (it needs every payload in order,
--   which Engine's dirty channels discard). DotView.lua draws what it hands out.
--
-- Every number errs low (plan section 2): a tick is rounded down, nothing the
-- tables don't state is added, and an unknown input is the smallest one.
-- Measured facts it stands on: the porting guide's "Damage over time" (run
-- #108, 70862).

GlassUF = GlassUF or {}
local API = GlassUF.API
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

--------------------------------------------------------------------------------
-- The tracker (plan section 6)
--------------------------------------------------------------------------------

Dots.WINDOW = 0.45      -- a tick slot's window either side of its time (ticks measured within 0.05)
Dots.TRAVEL = 1.5       -- a projectile's first tick may come this much later
Dots.SHIFT_MAX = 0.25   -- matched ticks may move the rhythm this much in total
Dots.OUTCOME = 0.4      -- a cast's resist arrives within this after SUCCEEDED...
Dots.LOOKBACK = 0.25    -- ...or this much before it
Dots.SENT_TTL = 10      -- a SENT never followed by its SUCCEEDED is forgotten
Dots.PASS = 0.25        -- the pass while anything is tracked
Dots.MAX_TICKS = 12     -- upcoming ticks handed out for the tick lines

Dots.enabled = true     -- off: nothing tracked (DotView.Configure sets it)

local WATCHED = { "target", "focus" }
local AVOIDED = { RESIST = true, IMMUNE = true, MISS = true, EVADE = true, REFLECT = true, DEFLECT = true }
local MELEE_ONLY = { DODGE = true, PARRY = true }   -- spells can't be dodged or parried
local HITS = { WOUND = true, ABSORB = true }        -- an absorbed tick still landed
local PHYSICAL = 1

local apps = {}         -- key -> { [family] = application }, confirmed
local pending = {}      -- applications waiting out their outcome window
local sent = {}         -- castGUID -> { key, unit, gen, points, sp, at }
local gen = { target = 0, focus = 0 }
local observed = {}     -- key -> since when target or focus has shown it
local lastAvoid = {}    -- key -> { all, melee }: the newest avoid of each rule
local snapshot          -- this fight's spell power by school index (plan section 2)

local function plainString(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end
local function plainNumber(v)
    if API.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end
local function plainTrue(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and not API.IsSecret(v) and v == true
end

-- The mob behind a token: its GUID when plain, else the token with its
-- generation ("target#7"), which a token change retires. nil: nothing there.
local function keyFor(unit)
    if not plainTrue(UnitExists, unit) then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and plainString(guid)
    if guid then return guid end
    return unit .. "#" .. gen[unit]
end
Dots.KeyFor = keyFor

-- A record made for a token key whose token has changed since.
local function stale(rec)
    return rec.key:find("#", 1, true) ~= nil and gen[rec.unit] ~= rec.gen
end

-- The lowest plain read over a spell's schools, nil if any is unreadable.
local function lowest(read, schools)
    local best
    for _, s in ipairs(schools) do
        local v = read(s)
        if v == nil then return nil end
        if best == nil or v < best then best = v end
    end
    return best
end

-- Spell power for a cast: its own plain read, else this fight's snapshot,
-- else 0 (plan section 2; P2 measured it secret in combat).
local function spellPower(aura)
    return lowest(API.SpellPower, aura.schools)
        or (snapshot and lowest(function(s) return snapshot[s] end, aura.schools))
        or 0
end

local runner   -- the pass's frame, idle while nothing is tracked
local function activate() if runner then runner:Show() end end

local function changed()
    if Dots.OnChange then Dots.OnChange() end
end

local function plainBool(fn, ...)   -- true / false when plain, else nil
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end

-- Does a unit answer to the name? true / false, or nil when a name form we
-- couldn't read might have matched (API.IsNameOf's forms, read under pcall).
local function sameName(unit, name)
    local okF, full = pcall(GetUnitName, unit, false)
    local okU, first, surname = pcall(UnitName, unit)
    full = okF and plainString(full) or nil
    local f = okU and plainString(first) or nil
    local s = okU and plainString(surname) or nil
    if name == full or name == f or (f and s and name == f .. " " .. s) then return true end
    if full and f and not API.IsSecret(surname) and (surname == nil or s) then return false end
    return nil
end

-- Plan 12.3: a same-name, attackable mob under the cursor that isn't the bound
-- unit may be where the cast went (a [@mouseover] macro, mouseover casting).
-- Only plain reads clear it; anything unreadable leaves the cast untracked.
-- Measured plain in combat (70888, run #255).
local function mouseoverElsewhere(unit, name)
    local exists = plainBool(UnitExists, "mouseover")
    if exists ~= true then return exists == nil end
    if plainBool(UnitIsUnit, "mouseover", unit) == true then return false end
    if sameName("mouseover", name) == false then return false end
    return plainBool(UnitCanAttack, "player", "mouseover") ~= false
end

-- UNIT_SPELLCAST_SENT: which watched mob the cast is for. Exactly one of
-- target and focus must carry its name and be attackable; two different mobs,
-- or none, means it isn't tracked (plan 6.2). Neither is a cast the mouseover
-- may have taken (12.3).
local function onSent(targetName, castGUID, spellID)
    local t = GetTime()
    for g, s in pairs(sent) do
        if t - s.at > Dots.SENT_TTL then sent[g] = nil end
    end
    castGUID, spellID, targetName = plainString(castGUID), plainNumber(spellID), plainString(targetName)
    if not (castGUID and spellID and targetName) then return end
    local aura = Dots.CastAura(spellID)
    if not aura then return end
    local key, unit
    for _, u in ipairs(WATCHED) do
        if API.IsNameOf(u, targetName) and API.CanAttack(u) then
            local k = keyFor(u)
            if k then
                if key and key ~= k then return end   -- two mobs answer to the name
                key, unit = key or k, unit or u
            end
        end
    end
    if not key or mouseoverElsewhere(unit, targetName) then return end
    local points = API.ComboPoints()
    sent[castGUID] = { key = key, unit = unit, gen = gen[unit], at = t, sp = spellPower(aura),
                       points = (points and points >= 1) and points or nil }
    activate()
end

local function avoids(app, action)
    return AVOIDED[action] or (MELEE_ONLY[action] and app.schoolMask == PHYSICAL) or false
end

-- The lookback: an avoid of either rule within LOOKBACK before the cast event.
-- Each rule keeps its own newest time, so a newer avoid that doesn't apply (a
-- dodge, for a spell) never hides an older one that does (plan 12.1).
local function avoidedBefore(app, a, t)
    if not a then return false end
    local function recent(at) return at ~= nil and t - at <= Dots.LOOKBACK end
    return recent(a.all) or (recent(a.melee) and avoids(app, "DODGE"))
end

-- UNIT_SPELLCAST_SUCCEEDED: a pending application, fixed now (plan 6.2).
local function onSucceeded(castGUID, spellID)
    castGUID = plainString(castGUID)
    local s = castGUID and sent[castGUID]
    if not s then return end
    sent[castGUID] = nil
    if stale(s) then return end
    local aura, auraID, travel = Dots.CastAura(plainNumber(spellID))
    if not aura then return end
    local t = GetTime()
    local okL, level = pcall(UnitLevel, "player")
    local ticks = Dots.TickEstimates(aura, s.points, s.sp, okL and plainNumber(level) or 1)
    local app = { key = s.key, unit = s.unit, gen = s.gen, family = aura.family, auraID = auraID,
                  name = aura.name, schoolMask = aura.schoolMask, castAt = t, travel = travel,
                  slots = {}, shift = 0, misses = 0, committed = false }
    for k, est in ipairs(ticks) do app.slots[k] = { t = t + k * aura.period, est = est } end
    if avoidedBefore(app, lastAvoid[s.key], t) then return end
    pending[#pending + 1] = app
    activate()
end

-- An avoid on a mob: the newest pending cast on it that it applies to fails
-- (someone else's resist in that window drops ours: a lost DoT, never a
-- false kill). A failed refresh leaves the old application ticking.
local function onAvoided(key, action)
    local t = GetTime()
    local a = lastAvoid[key] or {}
    if AVOIDED[action] then a.all = t elseif MELEE_ONLY[action] then a.melee = t end
    lastAvoid[key] = a
    for i = #pending, 1, -1 do
        local app = pending[i]
        if app.key == key and t - app.castAt <= Dots.OUTCOME and avoids(app, action) then
            table.remove(pending, i)
            return
        end
    end
end

-- Pending applications whose window passed: confirmed, replacing the same
-- family on that mob (Vanilla refresh: the rhythm restarts, measured).
local function confirm(t)
    for i = #pending, 1, -1 do
        local app = pending[i]
        if stale(app) then
            table.remove(pending, i)
        elseif t - app.castAt >= Dots.OUTCOME then
            table.remove(pending, i)
            apps[app.key] = apps[app.key] or {}
            apps[app.key][app.family] = app
        end
    end
end

local function evidenceEnd(app, k, slot)
    return slot.t + Dots.WINDOW + ((k == 1 and app.travel) and Dots.TRAVEL or 0)
end

-- Who target and focus show now, and since when (a missed slot counts only
-- if its mob was watched through the slot's whole window).
local function updateObserved(t)
    local seen = {}
    for _, u in ipairs(WATCHED) do
        local k = keyFor(u)
        if k then seen[k] = true end
    end
    for k in pairs(observed) do
        if not seen[k] then observed[k] = nil end
    end
    for k in pairs(seen) do observed[k] = observed[k] or t end
end

-- The two cutoffs (plan 6.2): a slot's damage stops counting at its window's
-- start (it may land unseen from then on) or at a match; its evidence window
-- closes at its end, where an observed miss counts. Two observed misses in a
-- row drop the application; one with every slot closed is done.
local function retire(t)
    for key, list in pairs(apps) do
        for family, app in pairs(list) do
            local open = false
            for k, slot in ipairs(app.slots) do
                if not slot.gone and t >= slot.t - Dots.WINDOW then slot.gone = true end
                if not slot.closed then
                    local e = evidenceEnd(app, k, slot)
                    if t > e then
                        slot.closed = true
                        local since = observed[key]
                        if not slot.filled and since and since <= slot.t - Dots.WINDOW then
                            app.misses = app.misses + 1
                        end
                    else
                        open = true
                    end
                end
            end
            if app.misses >= 2 or stale(app) or not open then list[family] = nil end
        end
        if next(list) == nil then apps[key] = nil end
    end
end

-- A hit in a school on a watched mob: at most one slot of one application,
-- the earliest unfilled slot whose window holds it; among applications, the
-- nearest slot time, ties to the oldest (plan 6.5).
local function onHit(key, school)
    local list = apps[key]
    if not list then return end
    local t = GetTime()
    local best, bestK, bestD
    for _, app in pairs(list) do
        if app.schoolMask == school then
            for k, slot in ipairs(app.slots) do
                if not slot.filled and not slot.closed and t >= slot.t - Dots.WINDOW
                    and t <= evidenceEnd(app, k, slot) then
                    local d = math.abs(t - slot.t)
                    if not best or d < bestD or (d == bestD and app.castAt < best.castAt) then
                        best, bestK, bestD = app, k, d
                    end
                    break
                end
            end
        end
    end
    if not best then return end
    local slot = best.slots[bestK]
    slot.filled, slot.gone = true, true   -- a gone slot never counts again
    best.committed = true
    best.misses = 0
    -- The rhythm follows the tick, within SHIFT_MAX in total: later slots
    -- move, their count never does, and a gone slot stays gone.
    local total = math.max(-Dots.SHIFT_MAX, math.min(Dots.SHIFT_MAX, best.shift + (t - slot.t)))
    local delta = total - best.shift
    best.shift = total
    if delta ~= 0 then
        for k = bestK + 1, #best.slots do
            local s = best.slots[k]
            if not s.gone then s.t = s.t + delta end
        end
    end
end

local function onCombat(unit, action, school)
    local okU, watched = pcall(function() return unit == "target" or unit == "focus" end)
    if not (okU and watched) then return end
    action, school = plainString(action), plainNumber(school)
    if not action then return end
    local key = keyFor(unit)
    if not key then return end
    -- One canonical token per mob: the target's events when it shows that mob.
    if unit == "focus" and keyFor("target") == key then return end
    if AVOIDED[action] or MELEE_ONLY[action] then
        onAvoided(key, action)
    elseif HITS[action] and school then
        onHit(key, school)
    end
end

local function dropKey(key)
    apps[key], observed[key], lastAvoid[key] = nil, nil, nil
end

local function forget()
    apps, pending, sent, observed, lastAvoid = {}, {}, {}, {}, {}
end

local function tracking()
    return next(apps) ~= nil or #pending > 0 or next(sent) ~= nil
end

-- A token now shows another unit (Engine.OnTokenChanged): a per-token key's
-- state is the old unit's (plan 6.1). GUID keys stay: the mob may come back.
function Dots.TokenChanged(base)
    if gen[base] == nil then return end
    gen[base] = gen[base] + 1
    local prefix = base .. "#"
    for key in pairs(apps) do
        if key:sub(1, #prefix) == prefix then dropKey(key) end
    end
    updateObserved(GetTime())
    changed()
end

-- What the view draws for a unit: shown (confirmed applications), committed
-- (those seen ticking), and the next ticks' running totals in time order.
-- The cutoffs apply first, so a health repaint between passes is current.
local NONE = {}
function Dots.Estimate(unit)
    if not Dots.enabled then return 0, 0, NONE end
    local t = GetTime()
    confirm(t)
    retire(t)
    local key = keyFor(unit)
    local list = key and apps[key]
    if not list then return 0, 0, NONE end
    local shown, committed, upcoming = 0, 0, {}
    for _, app in pairs(list) do
        for _, slot in ipairs(app.slots) do
            if not slot.gone then
                shown = shown + slot.est
                if app.committed then committed = committed + slot.est end
                upcoming[#upcoming + 1] = slot
            end
        end
    end
    table.sort(upcoming, function(a, b) return a.t < b.t end)
    local running, cum = 0, {}
    for i = 1, math.min(#upcoming, Dots.MAX_TICKS) do
        running = running + upcoming[i].est
        cum[i] = running
    end
    return shown, committed, cum
end

-- Turn tracking on or off (the options); off forgets everything.
function Dots.SetEnabled(on)
    Dots.enabled = on and true or false
    if not Dots.enabled then forget() end
    changed()
end

runner = CreateFrame("Frame")
runner:Hide()
local elapsedSince = 0
runner:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < Dots.PASS then return end
    elapsedSince = 0
    local t = GetTime()
    updateObserved(t)
    for _, u in ipairs(WATCHED) do
        if plainTrue(UnitIsDeadOrGhost, u) then
            local k = keyFor(u)
            if k then dropKey(k) end
        end
    end
    confirm(t)
    retire(t)
    changed()
    if not tracking() then self:Hide() end
end)

local events = CreateFrame("Frame")
API.RegisterUnitEvents(events, { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }, "player")
API.RegisterEvents(events, { "UNIT_COMBAT", "UNIT_DIED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                             "PLAYER_ENTERING_WORLD" })
events:SetScript("OnEvent", function(_, event, a, b, c, d, e)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Measured plain inside this handler (run #108): this fight's snapshot.
        snapshot = {}
        for i = 1, 7 do snapshot[i] = API.SpellPower(i) end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        snapshot = nil
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        forget()
        changed()
        return
    end
    if not Dots.enabled then return end
    if event == "UNIT_SPELLCAST_SENT" then
        onSent(b, c, d)                     -- unit, targetName, castGUID, spellID
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        onSucceeded(b, c)                   -- unit, castGUID, spellID
        changed()
    elseif event == "UNIT_COMBAT" then
        onCombat(a, b, e)                   -- unit, action, flag, amount (never read), school
    elseif event == "UNIT_DIED" then
        local guid = plainString(a)
        if guid and apps[guid] then
            dropKey(guid)
            changed()
        end
    end
end)

Dots._test = {
    state = function() return { apps = apps, pending = pending, sent = sent, gen = gen, observed = observed,
                                 snapshot = snapshot } end,
    runner = runner,
    events = events,
    forget = forget,
}
