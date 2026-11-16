-- CastProbe, the DoT tracker's open leads (#175, docs/DOT-KILL-PLAN.md
-- section 12), measured before anything more is built:
--   12.2 whose avoid it is: UNIT_COMBAT's action, flag and school on our own
--        failed DoT and on melee, wand or Auto Shot avoids, their timing
--        against our SENT, SUCCEEDED and swings (a projectile's late failure
--        included), and how many avoids land inside a cast's outcome window;
--   12.3 the mouseover at each DoT's SENT: its name, GUID, hostility and
--        UnitIsUnit against target and focus, plain or secret, in and out of
--        combat; the mouseover-cast CVar.
-- A sixth file of the same module: /fp steps cast avoids, /fp steps cast mouseover.

local Probe = ForeverProbe:Module("CastProbe", { api = 1, cmd = "cast" })

local function show(v) return Probe.Show(v, true) end
local function say(line) Probe:Say(line) return line end
local function isSecret(v)
    local fn = rawget(_G, "issecretvalue")
    return type(fn) == "function" and fn(v) == true
end
local function plainNumber(v)
    if isSecret(v) then return nil end
    return type(v) == "number" and v or nil
end
local function plainString(v)
    if isSecret(v) then return nil end
    return type(v) == "string" and v or nil
end
-- true / false when plain, nil when secret, absent or failed.
local function plainBool(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) or type(v) ~= "boolean" then return nil end
    return v
end
local function call(fn, ...)
    if type(fn) ~= "function" then return "absent" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "ERR" end
    local parts = {}
    for i = 2, math.max(#r, 2) do parts[#parts + 1] = show(r[i]) end
    return table.concat(parts, ",")
end
local function g(name) return rawget(_G, name) end

-- GUF's own windows (Dots.OUTCOME, Dots.LOOKBACK), read live when GUF is loaded.
local function windows()
    local guf = g("GlassUF")
    local D = guf and guf.Dots
    return (D and plainNumber(D.OUTCOME)) or 0.4, (D and plainNumber(D.LOOKBACK)) or 0.25
end

-- A DoT GUF tracks: its aura's name and school, or nil.
local function dotOf(spellID)
    local guf = g("GlassUF")
    local D = guf and guf.Dots
    if not (D and D.CastAura and plainNumber(spellID)) then return nil end
    local ok, aura = pcall(D.CastAura, spellID)
    if not ok or type(aura) ~= "table" then return nil end
    return aura
end

local AVOIDS = { MISS = true, DODGE = true, PARRY = true, RESIST = true, IMMUNE = true, EVADE = true,
                 REFLECT = true, DEFLECT = true, BLOCK = true, ABSORB = true }
local NEAR_SWING = 0.3      -- an avoid this close to our own melee swing is probably that swing's
local LATE = 3.0            -- how long after a cast an avoid is still listed against it

local state = {
    casts = {},         -- recent DoT casts, newest last: { name, school, guid, sent, succeeded }
    byGUID = {},        -- castGUID -> its cast record
    swing = {},         -- swing type name (MainHand, OffHand, Ranged) -> our newest PLAYER_SWING of it
    ownSpell = nil,     -- our newest non-DoT SUCCEEDED: { id, at } (Shoot, Auto Shot...)
    counts = {},        -- "ACTION/school" -> avoids seen on the watched mob
    inWindow = 0,       -- avoids inside a cast's outcome window (GUF would drop that cast)
    during = {},        -- avoids during a DoT cast, no swing of ours near (ours, when solo)
    melee = nil,        -- the first avoid next to one of our melee swings
    ranged = nil,       -- the first avoid after our own ranged attack, no melee swing near
    flagged = 0,        -- WOUNDs carrying a flag (a partial resist, a block...)
    seq = 0,            -- DoT SENTs seen
    checked = 0,        -- the seq the last mouseover check used
    mouse = nil,        -- the mouseover at the newest DoT SENT
}

local function reset()
    state.casts, state.byGUID, state.swing, state.ownSpell = {}, {}, {}, nil
    state.counts, state.inWindow, state.during, state.melee, state.ranged, state.flagged = {}, 0, {}, nil, nil, 0
    return say("avoids counting from now")
end

local function summary()
    local keys = {}
    for k in pairs(state.counts) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. state.counts[k] end
    local during = {}
    for _, o in ipairs(state.during) do during[#during + 1] = o.short end
    return say(string.format("avoids summary casts=%d inWindow=%d flaggedWounds=%d counts: %s | during a cast: %s | melee: %s | ranged: %s",
        #state.casts, state.inWindow, state.flagged, #parts > 0 and table.concat(parts, ", ") or "none",
        #during > 0 and table.concat(during, "; ") or "none", state.melee or "none", state.ranged or "none"))
end

-- 12.3: what's under the cursor, against the SENT's target name.
local function mouseLine(sentName)
    local guf = g("GlassUF")
    local isNameOf = guf and guf.API and guf.API.IsNameOf
    local match = "absent"
    if type(isNameOf) == "function" and sentName then match = call(isNameOf, "mouseover", sentName) end
    local cvar = g("C_CVar")
    return string.format("mouseover combat=%s exists=%s name=%s unitName=%s guid=%s canAttack=%s dead=%s isTarget=%s isFocus=%s sent=%s nameMatch=%s cvar=%s supported=%s",
        show(InCombatLockdown()), call(g("UnitExists"), "mouseover"), call(g("GetUnitName"), "mouseover", false),
        call(g("UnitName"), "mouseover"), call(g("UnitGUID"), "mouseover"), call(g("UnitCanAttack"), "player", "mouseover"),
        call(g("UnitIsDeadOrGhost"), "mouseover"), call(g("UnitIsUnit"), "mouseover", "target"),
        call(g("UnitIsUnit"), "mouseover", "focus"), show(sentName), match,
        call(type(cvar) == "table" and cvar.GetCVar, "enableMouseoverCast"), call(g("IsMouseoverCastSupported")))
end

local function readMouse() return say(mouseLine(nil)) end

-- Where an avoid sits against our casts and attacks, as plain deltas.
local function relate(t)
    local outcome, lookback = windows()
    local best
    for i = #state.casts, 1, -1 do
        local c = state.casts[i]
        local ref = c.succeeded or c.sent
        if t >= c.sent - lookback and t <= ref + LATE then best = c break end
    end
    local parts, inside = {}, false
    if best then
        parts[#parts + 1] = string.format("+%.3fs after SENT %s(school %s)", t - best.sent, best.name, tostring(best.school))
        if best.succeeded then
            local d = t - best.succeeded
            inside = d >= -lookback and d <= outcome
            parts[#parts + 1] = string.format("%+.3fs from SUCCEEDED (%s)", d, inside and "inside GUF's window" or "outside it")
        else
            inside = true
            parts[#parts + 1] = "before SUCCEEDED"
        end
    end
    local nearSwing
    for kind, at in pairs(state.swing) do
        local d = t - at
        if d >= -0.05 and d <= NEAR_SWING and (not nearSwing or d < nearSwing.d) then nearSwing = { kind = kind, d = d } end
    end
    if nearSwing then parts[#parts + 1] = string.format("our swing %s %+.3fs", tostring(nearSwing.kind), nearSwing.d) end
    local recentSpell = state.ownSpell ~= nil and t - state.ownSpell.at <= LATE
    if recentSpell then
        parts[#parts + 1] = string.format("our spell %s +%.3fs", tostring(state.ownSpell.id), t - state.ownSpell.at)
    end
    return best, inside, nearSwing, table.concat(parts, " "), recentSpell
end

-- PLAYER_SWING's type by its Enum.PlayerSwingType key (MainHand, OffHand, Ranged).
local function swingName(v)
    if isSecret(v) then return "?" end
    local E = g("Enum")
    for k, n in pairs(type(E) == "table" and type(E.PlayerSwingType) == "table" and E.PlayerSwingType or {}) do
        if n == v then return k end
    end
    return tostring(v)
end

local f = CreateFrame("Frame")
Probe:RegisterEvents(f, { "UNIT_COMBAT", "PLAYER_SWING", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" })

local function onCombat(unit, action, flag, school)
    local ok, watched = pcall(function() return unit == "target" or unit == "focus" end)
    if not (ok and watched) then return end
    -- One token per mob: the focus's events only when it isn't the target.
    if unit == "focus" and plainBool(g("UnitIsUnit"), "focus", "target") ~= false then return end
    action, flag = plainString(action), plainString(flag)
    if not action then return end
    local t = GetTime()
    if action == "WOUND" then
        if flag and flag ~= "" then
            state.flagged = state.flagged + 1
            local _, _, _, rel = relate(t)
            say(string.format("FLAGGED %s WOUND flag=%s school=%s %s", unit, flag, show(school), rel))
        end
        return
    end
    if not AVOIDS[action] then return end
    local key = action .. "/" .. show(school)
    state.counts[key] = (state.counts[key] or 0) + 1
    local cast, inside, nearSwing, rel, recentSpell = relate(t)
    if inside then state.inWindow = state.inWindow + 1 end
    local line = say(string.format("AVOID %s action=%s flag=%s school=%s guid=%s %s", unit, action, show(flag),
        show(school), call(g("UnitGUID"), unit), rel))
    if nearSwing and nearSwing.kind ~= "Ranged" then
        state.melee = state.melee or line
    elseif cast and not nearSwing then
        if #state.during < 10 then
            state.during[#state.during + 1] = { line = line, short = string.format("%s %s school=%s %s", cast.name, action, show(school), rel) }
        end
    elseif nearSwing or recentSpell then
        state.ranged = state.ranged or line
    end
end

local function onSent(targetName, castGUID, spellID)
    local aura = dotOf(spellID)
    if not aura then return end
    local t = GetTime()
    local c = { name = aura.name, school = aura.schoolMask, sent = t }
    state.casts[#state.casts + 1] = c
    if #state.casts > 20 then table.remove(state.casts, 1) end
    if plainString(castGUID) then state.byGUID[castGUID] = c end
    state.seq = state.seq + 1
    local exists = plainBool(g("UnitExists"), "mouseover")
    local isTarget = plainBool(g("UnitIsUnit"), "mouseover", "target")
    local line = say("SENT " .. aura.name .. " " .. mouseLine(plainString(targetName)))
    state.mouse = { seq = state.seq, combat = InCombatLockdown() == true, exists = exists, isTarget = isTarget, line = line }
end

f:SetScript("OnEvent", function(_, event, a, b, c, d, e)
    if event == "UNIT_COMBAT" then return onCombat(a, b, c, e) end
    if event == "PLAYER_SWING" then
        state.swing[swingName(b)] = GetTime()
        return
    end
    local okU, mine = pcall(function() return a == "player" end)
    if not (okU and mine) then return end
    if event == "UNIT_SPELLCAST_SENT" then return onSent(b, c, d) end
    local castGUID, spellID = b, c
    local cast = plainString(castGUID) and state.byGUID[castGUID]
    if cast then
        state.byGUID[castGUID] = nil
        cast.succeeded = GetTime()
        say(string.format("CAST %s school=%s sent->succeeded=%.3fs", cast.name, tostring(cast.school), cast.succeeded - cast.sent))
    elseif plainNumber(spellID) then
        state.ownSpell = { id = spellID, at = GetTime() }
    end
end)

-- Each mouseover check needs a new DoT SENT since the previous one.
local function mouseCheck(wantCombat, wantExists)
    return function()
        local m = state.mouse
        if not m or m.seq <= state.checked then return false, "no DoT cast since the last step" end
        state.checked = m.seq
        if m.combat ~= wantCombat then return false, (wantCombat and "not in combat: " or "in combat: ") .. m.line end
        if wantExists ~= nil and m.exists ~= wantExists then return false, "cursor not as asked: " .. m.line end
        return true, m.line
    end
end

Probe:Command("avoids", function(arg)
    if arg == "reset" then return reset() end
    return summary()
end, "the DoT tracker's avoids (plan 12.2): the summary; 'reset' starts counting again")
Probe:Command("mouseover", readMouse, "what's under the cursor now, and the mouseover-cast CVar (plan 12.3)")

Probe:Steps("avoids", {
    title = "Whose avoid is it? (#175, plan 12.2)",
    rev = 1,
    { text = "Counting starts now. Nothing to do: Next.", auto = true, run = reset },
    { text = "Solo, on a mob a few levels ABOVE you (orange): cast one of your DoTs on it, again on a fresh mob if needed, until one is resisted (\"Resist\" over the mob). Then Next. None after about 10 casts: Skip.",
      check = function() return #state.during > 0, state.during[1] and state.during[1].line or "no avoid during a DoT cast" end },
    { text = "Solo: melee a mob with your auto-attack only (no spells) until you see a Miss, Dodge or Parry. Then Next.",
      check = function() return state.melee ~= nil, state.melee or "no avoid next to one of your swings" end },
    { text = "A wand (Shoot) or a hunter's Auto Shot at a mob, until a shot misses. Then Next. Neither: Skip.",
      check = function() return state.ranged ~= nil, state.ranged or "no avoid after your own ranged attack" end },
    { text = "Hunter: Serpent Sting from 30+ yards until one misses or is resisted. Then Next. Not a hunter: Skip.",
      check = function()
          for _, o in ipairs(state.during) do if o.short:find("Serpent Sting", 1, true) then return true, o.line end end
          return false, "no avoid during a Serpent Sting"
      end },
    { text = "A mob immune to your DoT's school (\"Immune\" over it): cast the DoT once. Then Next. None around: Skip.",
      check = function()
          for _, o in ipairs(state.during) do if o.short:find(" IMMUNE ", 1, true) then return true, o.line end end
          return false, "no IMMUNE during a DoT cast"
      end },
    { text = "In a party, with a melee player (or a hunter) attacking the same mob: fight one or more pulls as usual with your DoTs, then Next once combat ends. Solo: Skip.",
      run = summary, button = "Summary" },
    { text = "The summary of everything counted. Nothing to do: Next.", auto = true, run = summary },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

Probe:Steps("mouseover", {
    title = "Mouseover casts (#175, plan 12.3)",
    rev = 1,
    { text = "A first read: the mouseover-cast setting and what's under the cursor. Nothing to do: Next.",
      auto = true, run = readMouse },
    { text = "Out of combat: target a mob, keep the cursor ON that mob, and cast one of your DoTs at it with its usual key. Then Next.",
      check = mouseCheck(false, true) },
    { text = "In combat now: keep the cursor ON your target and cast a DoT at it with its usual key. Then Next.",
      check = mouseCheck(true, true) },
    { text = "Still in combat: put the cursor on ANOTHER mob (one with your target's name if there is one), and cast a DoT at your TARGET with its usual key. Then Next. Type in the Note whether the two mobs shared a name.",
      check = mouseCheck(true, true) },
    { text = "A mouseover macro (/cast [@mouseover,harm,nodead] <your DoT>): in combat, cast it at a mob that is NOT your target. Then Next. No such macro: Skip.",
      check = mouseCheck(true, true) },
    { text = "In combat: cursor over nothing (the sky or the ground), cast a DoT at your target. Then Next.",
      check = mouseCheck(true, false) },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

local NS = select(2, ...)
if type(NS) == "table" and type(NS._test) == "table" then
    NS._test.leadsState = state
    NS._test.leadsSummary = summary
    NS._test.leadsMouse = mouseLine
end
