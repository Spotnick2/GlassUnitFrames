-- CastProbe, the DoT kill estimate's gates (#175, docs/DOT-KILL-PLAN.md
-- section 8). What the tracker will stand on, measured before it's built:
--   P1 UNIT_COMBAT on the target in combat: action, flags, amount, school,
--      plain or secret, and the timing of each hit after our DoT's cast;
--   P2 GetSpellBonusDamage(2..7), in and out of combat;
--   P3 combo points (UnitPower(player, 4)) at UNIT_SPELLCAST_SENT, in combat;
--   P4 our per-tick estimate (GUF's DotSpells + Dots) next to the damage
--      meter's per-spell totals read after the fight;
--   P5 UnitGUID("target") in an instance;
--   P6 (part) whether the client's tiling stripe texture is there.
-- A fifth file of the same module: /fp steps cast dots.

local Probe = ForeverProbe:Module("CastProbe", { api = 1, cmd = "cast" })

local function show(v) return Probe.Show(v, true) end
local function say(line) Probe:Say(line) return line end
local function plainNumber(v)
    local isSecret = rawget(_G, "issecretvalue")
    if type(isSecret) == "function" and isSecret(v) then return nil end
    return type(v) == "number" and v or nil
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "absent" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "ERR" end
    local parts = {}
    for i = 2, math.max(#r, 2) do parts[#parts + 1] = show(r[i]) end
    return table.concat(parts, ",")
end

local WATCHED = { target = true, focus = true }
local state = {
    lastDot = nil,      -- { name, at, school } of the last tracked DoT cast
    sent = {},          -- castGUID -> { combo, target }
    hits = 0,           -- UNIT_COMBAT lines on target/focus this fight
    meterDone = false,  -- the after-combat meter read finished
}

-- P2, P3, P5: the inputs, as one line.
local function readings()
    local sp = {}
    local bonus = rawget(_G, "GetSpellBonusDamage")
    for i = 2, 7 do sp[#sp + 1] = call(bonus, i) end
    local inst = { pcall(rawget(_G, "GetInstanceInfo")) }
    return string.format("dots combat=%s spellPower(2..7)=%s combo=%s attackPower=%s target=%s guid=%s focusGuid=%s instance=%s",
        show(InCombatLockdown()), table.concat(sp, "/"), call(rawget(_G, "UnitPower"), "player", 4),
        call(rawget(_G, "UnitAttackPower"), "player"), call(rawget(_G, "GetUnitName"), "target", false),
        call(UnitGUID, "target"), call(UnitGUID, "focus"), inst[1] and show(inst[3]) or "ERR")
end

local function read() return say(readings()) end

-- What GUF would estimate for a cast: its own data and arithmetic, fed the
-- plain reads only (a secret spell power is 0, unknown combo points are 1).
local function estimate(spellID, combo)
    local guf = rawget(_G, "GlassUF")
    local Dots = guf and guf.Dots
    if not (Dots and Dots.CastAura) then return nil end
    local ok, aura, auraID, travel = pcall(Dots.CastAura, spellID)
    if not ok or not aura then return nil end
    local bonus, sp = rawget(_G, "GetSpellBonusDamage"), nil
    for _, s in ipairs(aura.schools) do
        local okR, v = pcall(bonus, s)
        v = okR and plainNumber(v) or nil
        if v == nil then sp = nil break end
        sp = (sp == nil or v < sp) and v or sp
    end
    local level = plainNumber(UnitLevel("player")) or 1
    local okT, ticks = pcall(Dots.TickEstimates, aura, combo or 1, sp or 0, level)
    if not okT then return nil end
    return aura, auraID, travel, sp, ticks
end

-- P4 after the fight: the meter's per-spell totals for the player.
local function meterLine(label)
    local DM = rawget(_G, "C_DamageMeter")
    if type(DM) ~= "table" or type(DM.GetCombatSessionSourceFromType) ~= "function" then
        return say("meter " .. label .. " absent"), true
    end
    local E = rawget(_G, "Enum") or {}
    local sessions, types = E.DamageMeterSessionType or {}, E.DamageMeterType or {}
    local current, done = sessions.Current, types.DamageDone
    local ok, src = pcall(DM.GetCombatSessionSourceFromType, current or 1, done or 0, UnitGUID("player"))
    if not ok then return say(string.format("meter %s ERR (Current=%s DamageDone=%s)", label, show(current), show(done))), true end
    if type(src) ~= "table" then return say("meter " .. label .. " source=" .. show(src)), false end
    local okN, n = pcall(function() return #src.combatSpells end)
    if not okN or plainNumber(n) == nil then
        return say(string.format("meter %s total=%s spells=%s", label, show(src.totalAmount), okN and show(n) or "ERR")), false
    end
    local parts = {}
    for i = 1, n do
        local okS, s = pcall(function()
            local sp = src.combatSpells[i]
            local id = sp.spellID
            local name = plainNumber(id) and call(rawget(_G, "C_Spell") and C_Spell.GetSpellName, id) or "?"
            return string.format("%s %s=%s", show(id), name, show(sp.totalAmount))
        end)
        parts[#parts + 1] = okS and s or "ERR"
    end
    say(string.format("meter %s total=%s spells: %s", label, show(src.totalAmount), table.concat(parts, "; ")))
    return nil, plainNumber(src.totalAmount) ~= nil
end

local function readMeter(tries, waited)
    local _, finished = meterLine(string.format("+%.1fs", waited))
    if finished or tries <= 1 or InCombatLockdown() then
        state.meterDone = true
        return
    end
    C_Timer.After(0.5, function() readMeter(tries - 1, waited + 0.5) end)
end

local f = CreateFrame("Frame")
Probe:RegisterEvents(f, { "UNIT_COMBAT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
local spells = CreateFrame("Frame")
Probe:RegisterEvents(spells, { "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" })

f:SetScript("OnEvent", function(_, event, unit, action, flag, amount, school)
    if event == "PLAYER_REGEN_DISABLED" then
        state.hits, state.meterDone = 0, false
        say("dots fight start: " .. readings())
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        say(string.format("dots fight end: %d hits on target/focus; meter in 0.5 s", state.hits))
        C_Timer.After(0.5, function() readMeter(7, 0.5) end)
        return
    end
    local ok, watched = pcall(function() return WATCHED[unit] == true end)
    if not (ok and watched) then return end
    state.hits = state.hits + 1
    local since = ""
    if state.lastDot then
        since = string.format(" +%.2fs after %s", GetTime() - state.lastDot.at, state.lastDot.name)
    end
    say(string.format("HIT %s action=%s flag=%s amount=%s school=%s guid=%s%s", unit, show(action), show(flag),
        show(amount), show(school), call(UnitGUID, unit), since))
end)

spells:SetScript("OnEvent", function(_, event, unit, a, b, c)
    local okU, mine = pcall(function() return unit == "player" end)
    if not (okU and mine) then return end
    if event == "UNIT_SPELLCAST_SENT" then
        local targetName, castGUID, spellID = a, b, c
        local okC, combo = pcall(UnitPower, "player", 4)
        local key = plainNumber(spellID) and castGUID
        if type(key) == "string" then
            state.sent[key] = { combo = okC and plainNumber(combo) or nil }
        end
        if plainNumber(spellID) and estimate(spellID) then
            say(string.format("SENT %s -> %s combo=%s", show(spellID), show(targetName), okC and show(combo) or "ERR"))
        end
        return
    end
    local castGUID, spellID = a, b
    if not plainNumber(spellID) then return end
    local sent = type(castGUID) == "string" and state.sent[castGUID] or nil
    if sent then state.sent[castGUID] = nil end
    local aura, auraID, travel, sp, ticks = estimate(spellID, sent and sent.combo)
    if not aura then return end
    state.lastDot = { name = aura.name, at = GetTime() }
    say(string.format("DOT %s cast=%d aura=%d every %ss travel=%s spellPower=%s combo=%s ticks=%s",
        aura.name, spellID, auraID, tostring(aura.period), tostring(travel), sp and tostring(sp) or "none",
        sent and sent.combo and tostring(sent.combo) or "unknown", table.concat(ticks, ",")))
end)

-- P6 (part): the client's tiling stripes, each tinted on a green strip above
-- the screen centre, top to bottom. Run #108 (70862): the Absorb-Overlay file
-- is absent (nothing drew, GetTexture nil); the atlases Blizzard's raid frames
-- use and the shield file are the candidates left.
local STRIPES = {
    { label = "file Interface\\RaidFrame\\Absorb-Overlay", file = "Interface\\RaidFrame\\Absorb-Overlay" },
    { label = "atlas RaidFrame-Absorb-Overlay", atlas = "RaidFrame-Absorb-Overlay" },
    { label = "atlas RaidFrame-Shield-Overlay", atlas = "RaidFrame-Shield-Overlay" },
    { label = "file Interface\\RaidFrame\\Shield-Overlay", file = "Interface\\RaidFrame\\Shield-Overlay" },
}
local sample
local function atlasInfo(name)
    local ct = rawget(_G, "C_Texture")
    if type(ct) ~= "table" or type(ct.GetAtlasInfo) ~= "function" then return "absent" end
    local ok, info = pcall(ct.GetAtlasInfo, name)
    if not ok then return "ERR" end
    if type(info) ~= "table" then return show(info) end
    return string.format("{w=%s h=%s file=%s tilesH=%s tilesV=%s}", show(info.width), show(info.height),
        show(info.file), show(info.tilesHorizontally), show(info.tilesVertically))
end
local function showStripe(on)
    if not sample then
        sample = CreateFrame("Frame", nil, UIParent)
        sample:SetSize(240, #STRIPES * 30)
        sample:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        sample:SetFrameStrata("HIGH")
        sample.rows = {}
        for i, s in ipairs(STRIPES) do
            local bg = sample:CreateTexture(nil, "BACKGROUND")
            bg:SetSize(240, 24)
            bg:SetPoint("TOP", sample, "TOP", 0, -(i - 1) * 30)
            bg:SetColorTexture(0.1, 0.6, 0.2, 1)
            local t = sample:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints(bg)
            if s.atlas then
                pcall(t.SetAtlas, t, s.atlas, false, "LINEAR", "REPEAT", "REPEAT")
            else
                t:SetTexture(s.file, "REPEAT", "REPEAT")
            end
            t:SetHorizTile(true)
            t:SetVertTile(true)
            t:SetVertexColor(1, 0.2, 0.2, 0.9)
            sample.rows[i] = t
        end
    end
    sample:SetShown(on)
    if not on then return "stripe hidden" end
    local lines = {}
    for i, s in ipairs(STRIPES) do
        local t = sample.rows[i]
        lines[#lines + 1] = say(string.format("stripe %d %s texture=%s fileID=%s atlas=%s%s", i, s.label,
            call(t.GetTexture, t), call(t.GetTextureFileID, t), call(t.GetAtlas, t),
            s.atlas and (" info=" .. atlasInfo(s.atlas)) or ""))
    end
    return table.concat(lines, " | ")
end

Probe:Command("dots", function(arg)
    if arg == "meter" then return meterLine("now") end
    if arg == "stripe" then return showStripe(not (sample and sample:IsShown())) end
    read()
end, "DoT estimate inputs (spell power, combo points, GUIDs); 'meter' reads the damage meter, 'stripe' toggles the texture sample")

Probe:Steps("dots", {
    title = "Will my DoTs kill it? (#175)",
    rev = 2,
    { text = "Out of combat, outdoors: a first read of spell power, combo points and GUIDs. Nothing to do: Next.",
      auto = true, run = read },
    { text = "Target a mob and cast ONE of your DoTs on it (Corruption, Shadow Word: Pain, Rend, Serpent Sting, Moonfire...). Use nothing else of that school on it. While it ticks, press Run.",
      button = "Read", run = read, check = function() return InCombatLockdown(), "read in combat" end },
    { text = "Let that DoT tick to its end (or the mob die) without other attacks of its school. Then Next." },
    { text = "Two DoTs of the SAME school on one mob, ticking together (warlock: Corruption + Bane of Agony; priest: Shadow Word: Pain + Devouring Plague; druid: Rip + Rake). Not possible: Skip." },
    { text = "Recast a DoT while it's still ticking (a refresh), and let it tick at least twice more. Then Next." },
    { text = "Rogue or druid: spend a DoT finisher (Rupture, Rip). Type the combo points you spent in the Note, then Next. Otherwise Skip." },
    { text = "Hunter: Serpent Sting from far away (30+ yards). Otherwise Skip." },
    { text = "End the fight and wait. This step completes once the damage meter has been read after combat.",
      wait = function() return state.meterDone, "waiting for the end of combat and the meter read" end, timeout = 60 },
    { text = "The stripe texture samples: four green strips above the screen centre, numbered 1 to 4 from the top. Which ones show red stripes (not a flat colour)? Type their numbers in the Note, then Next.",
      auto = true, run = function() return showStripe(true) end, screenshot = "stripe texture" },
    { text = "Hiding the sample.", auto = true, run = function() return showStripe(false) end },
    { text = "In a dungeon (any instance): target a mob and press Run. Not in one now: Skip (it can be done another day with /fp cast dots).",
      button = "Read", run = read },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

local NS = select(2, ...)
if type(NS) == "table" and type(NS._test) == "table" then
    NS._test.dotsReadings = readings
    NS._test.dotsState = state
    NS._test.dotsMeter = meterLine
end
