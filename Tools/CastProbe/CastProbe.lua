-- CastProbe: the event trace behind GlassUnitFrames' cast bars (#72 latency
-- and pushback), and the checks later PRs were gated on: swing events, the
-- shared range check, tradeskill batches (#91), mana and the five-second rule
-- (#94, #108), a UIParent cast host anchored to the secure player button.
-- Throwaway, never shipped (.pkgmeta ignores Tools). Every client value is
-- classified before it is logged: S = secret; nothing secret is compared,
-- formatted or concatenated.
--
-- A ForeverProbe module (#112): its lines go to the /fp console and its own
-- saved log, never to chat. /fp cast lists the commands. The gates of the
-- cast bar's roadmap extras are procedures: /fp steps cast gcd (#149), kick
-- (#150), range (#152).

local ADDON, NS = ...
local LOG_MAX = 4000

local Probe = ForeverProbe:Module("CastProbe", { api = 1, cmd = "cast" })

local isSecretFn = rawget(_G, "issecretvalue")
local function secret(v) return isSecretFn ~= nil and isSecretFn(v) == true end

local cdEvents = false   -- SPELL_UPDATE_COOLDOWN is noisy: off until asked for
local lastT
local sent = {}          -- castGUID -> GetTime() at SENT (plain guids only)
local failed = {}        -- registrations or hooks that didn't take

local function say(msg) Probe:Say(msg) end

local function fmt(v)
    local ok, s = pcall(function()
        if secret(v) then return "S" end
        local t = type(v)
        if t == "nil" then return "nil" end
        if t == "number" then
            if v == math.floor(v) then return tostring(v) end
            return string.format("%.3f", v)
        end
        if t == "string" then
            if #v > 44 then return v:sub(1, 20) .. "~" .. v:sub(-20) end
            return v
        end
        if t == "boolean" then return tostring(v) end
        return t
    end)
    return ok and s or "ERR"
end

local function pack(...) return { n = select("#", ...), ... } end

local function fmtArgs(a, first)
    local out = {}
    for i = first or 1, a.n do out[#out + 1] = fmt(a[i]) end
    return table.concat(out, " ")
end

-- A trace line: the host stamps the time; the gap since the previous trace
-- line goes first, which is what reading an event order needs.
local function log(line)
    local now = GetTime()
    local dt = lastT and string.format("+%.3f", now - lastT) or "     "
    lastT = now
    say(dt .. " " .. line)
end

-- A plain string, or nil (secret or not a string): safe to use as a key.
local function plainString(v)
    if secret(v) or type(v) ~= "string" then return nil end
    return v
end

--------------------------------------------------------------------------------
-- Snapshots
--------------------------------------------------------------------------------

-- UnitCastingInfo: name, displayName, texture, startMs, endMs, isTradeskill,
-- castID, notInterruptible, spellID, castBarID, delayTimeMs.
-- UnitChannelInfo: name, displayName, texture, startMs, endMs, isTradeskill,
-- notInterruptible, spellID, isEmpowered, numEmpowerStages, castBarID.
local function castSnapshot()
    local parts = {}
    local ok, err = pcall(function()
        local c = pack(UnitCastingInfo("player"))
        if secret(c[1]) or c[1] ~= nil then
            local span = "?"
            if not secret(c[4]) and not secret(c[5]) and type(c[4]) == "number" and type(c[5]) == "number" then
                span = string.format("%d", c[5] - c[4])
            end
            parts[#parts + 1] = string.format("cast{start=%s end=%s span=%s trade=%s guid=%s spell=%s delay=%s}",
                fmt(c[4]), fmt(c[5]), span, fmt(c[6]), fmt(c[7]), fmt(c[9]), fmt(c[11]))
        end
        local h = pack(UnitChannelInfo("player"))
        if secret(h[1]) or h[1] ~= nil then
            local span = "?"
            if not secret(h[4]) and not secret(h[5]) and type(h[4]) == "number" and type(h[5]) == "number" then
                span = string.format("%d", h[5] - h[4])
            end
            parts[#parts + 1] = string.format("chan{start=%s end=%s span=%s trade=%s spell=%s}",
                fmt(h[4]), fmt(h[5]), span, fmt(h[6]), fmt(h[8]))
        end
        for _, f in ipairs({ { "castDur", rawget(_G, "UnitCastingDuration") }, { "chanDur", rawget(_G, "UnitChannelDuration") } }) do
            local fn = f[2]
            local d = fn and fn("player")
            if d then
                local okS, hs = pcall(d.HasSecretValues, d)
                local okT, total = pcall(d.GetTotalDuration, d)
                local okR, rem = pcall(d.GetRemainingDuration, d)
                parts[#parts + 1] = string.format("%s{secretVals=%s total=%s rem=%s}", f[1],
                    okS and fmt(hs) or "ERR", okT and fmt(total) or "ERR", okR and fmt(rem) or "ERR")
            end
        end
    end)
    if not ok then parts[#parts + 1] = "snapshot ERR " .. tostring(err) end
    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local UNIT_EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_ATTACK_SPEED",
    -- #94 (five-second rule): mana changes, as the client reports them.
    "UNIT_POWER_UPDATE",
    -- #108: ticks or continuous? Counted, logged with the next UPDATE.
    "UNIT_POWER_FREQUENT",
}
local WORLD_EVENTS = {
    -- ADDON_ACTION_BLOCKED / FORBIDDEN: the host's baseline logs them.
    "CURRENT_SPELL_CAST_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "WEAPON_SLOT_CHANGED",
    "MIRROR_TIMER_START", "MIRROR_TIMER_PAUSE", "MIRROR_TIMER_STOP",
    "SPELL_UPDATE_COOLDOWN",
    -- PR 5 (tradeskill): the batch, as the client tracks it.
    "TRADE_SKILL_CRAFT_BEGIN", "UPDATE_TRADESKILL_CAST_STOPPED", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
}
local SNAPSHOT = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    -- PR 5: which cast is live at a failure and at the craft events.
    UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_FAILED_QUIET = true,
    TRADE_SKILL_CRAFT_BEGIN = true, UPDATE_TRADESKILL_CAST_STOPPED = true,
}
local SHORT = {}
for _, e in ipairs(UNIT_EVENTS) do SHORT[e] = e:gsub("^UNIT_SPELLCAST_", "") end

-- The GUID of the cast in a unit-spellcast payload: SENT is (unit, target,
-- castGUID, spellID); every other one is (unit, castGUID, spellID, ...).
local function castGUIDOf(event, a)
    if event == "UNIT_SPELLCAST_SENT" then return a[3] end
    return a[2]
end

local f = CreateFrame("Frame")

local freqMana, freqLast = 0, nil   -- #108: FREQUENT(MANA) since the last UPDATE(MANA)

--------------------------------------------------------------------------------
-- #149 / #150 / #152: what the GCD line, the interrupter name and the range
-- colour rely on, read where the client says to trust it.
--------------------------------------------------------------------------------

local GCD_SPELL = 61304
local seen = { gcd = 0, gcdOn = 0, gcdCombat = 0, kicks = 0, kickBy = 0, targetKicks = 0 }
local lastSpell, lastSentAt, lastSentTo   -- the player's last SENT, plain only

-- GetSpellCooldown's fields and GetSpellCooldownDuration's, every value
-- classified (isOnGCD is NeverSecret and trusted only inside
-- SPELL_UPDATE_COOLDOWN: this runs there).
local function cooldownLine(id)
    local parts = { "id=" .. fmt(id) }
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if not ok then
        parts[#parts + 1] = "info=ERR"
    elseif secret(cd) or type(cd) ~= "table" then
        parts[#parts + 1] = "info=" .. fmt(cd)
    else
        for _, k in ipairs({ "startTime", "duration", "isEnabled", "isActive", "isOnGCD", "modRate",
                             "activeCategory", "timeUntilEndOfStartRecovery" }) do
            parts[#parts + 1] = k .. "=" .. fmt(cd[k])
        end
    end
    local okD, d = pcall(C_Spell.GetSpellCooldownDuration, id)
    if not okD then
        parts[#parts + 1] = "dur=ERR"
    elseif d == nil or secret(d) then
        parts[#parts + 1] = "dur=" .. fmt(d)
    else
        local okS, hs = pcall(d.HasSecretValues, d)
        local okT, t = pcall(d.GetTotalDuration, d)
        local okR, r = pcall(d.GetRemainingDuration, d)
        parts[#parts + 1] = string.format("dur{secretVals=%s total=%s rem=%s}", okS and fmt(hs) or "ERR",
            okT and fmt(t) or "ERR", okR and fmt(r) or "ERR")
    end
    return table.concat(parts, " "), ok and not secret(cd) and type(cd) == "table" and cd or nil
end

local function onCooldownUpdate(...)
    local fresh = lastSentAt and GetTime() - lastSentAt <= 0.5
    if not fresh then return end   -- only the update that follows a SENT
    seen.gcd = seen.gcd + 1
    local combat = InCombatLockdown()
    if combat then seen.gcdCombat = seen.gcdCombat + 1 end
    local gl = cooldownLine(GCD_SPELL)
    local sl, cd = cooldownLine(lastSpell)
    if cd and not secret(cd.isOnGCD) and cd.isOnGCD == true then seen.gcdOn = seen.gcdOn + 1 end
    log("GCD payload=" .. fmtArgs(pack(...)) .. " combat=" .. fmt(combat) .. " || gcdSpell " .. gl .. " || sent " .. sl)
    lastSentAt = nil   -- one line per SENT
end

local function onEvent(_, event, ...)
    if event == "SPELL_UPDATE_COOLDOWN" then
        local ok, err = pcall(onCooldownUpdate, ...)
        if not ok then log("GCD ERR " .. tostring(err)) end
        if not cdEvents then return end
    end
    if event == "UNIT_POWER_FREQUENT" then
        local token = select(2, ...)
        if not secret(token) and token == "MANA" then
            freqMana = freqMana + 1
            freqLast = GetTime()
        end
        return
    end
    local a = pack(...)
    local ok, err = pcall(function()
        local line = (SHORT[event] or event) .. " " .. fmtArgs(a)
        local guid = SHORT[event] and plainString(castGUIDOf(event, a))
        if event == "UNIT_SPELLCAST_SENT" then
            lastSpell = (not secret(a[4]) and type(a[4]) == "number") and a[4] or nil
            lastSentTo = plainString(a[2])
            lastSentAt = lastSpell and GetTime() or nil
        end
        if event == "UNIT_SPELLCAST_SENT" and guid then
            sent[guid] = GetTime()
        elseif (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START") and guid then
            local s = sent[guid]
            line = line .. (s and string.format(" sent->start=%dms", (GetTime() - s) * 1000) or " (no SENT for this guid)")
            sent[guid] = nil
        elseif (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET") and guid then
            sent[guid] = nil
        end
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            local by = a[4]   -- interruptedBy:WOWGUID (before castBarID)
            -- Secrecy first: comparing a secret aborts the line (Codex, PR 5).
            if not secret(by) and type(by) == "string" and by ~= "" then
                local okP, name = pcall(function() return select(6, GetPlayerInfoByGUID(by)) end)
                line = line .. " interruptedByName=" .. (okP and fmt(name) or "ERR")
                -- #150: what GUF would show (a token's name first).
                local GUF = rawget(_G, "GlassUF")
                if GUF and GUF.Castbar and GUF.Castbar.InterrupterName then
                    local okG, gn = pcall(GUF.Castbar.InterrupterName, by)
                    line = line .. " gufName=" .. (okG and fmt(gn) or "ERR")
                end
                if event == "UNIT_SPELLCAST_INTERRUPTED" then seen.kickBy = seen.kickBy + 1 end
            end
            if event == "UNIT_SPELLCAST_INTERRUPTED" then seen.kicks = seen.kicks + 1 end
        end
        if SNAPSHOT[event] then line = line .. " || " .. castSnapshot() end
        -- PR 5: the client's batch state on every cast event and craft event.
        if SHORT[event] or event:find("TRADE") then
            local ts = rawget(_G, "C_TradeSkillUI")
            if ts and ts.GetRemainingRecasts then
                local okR, r = pcall(ts.GetRemainingRecasts)
                local okP, rp = pcall(ts.IsRecipeRepeating)
                line = line .. " || recasts=" .. (okR and fmt(r) or "ERR") .. " repeating=" .. (okP and fmt(rp) or "ERR")
            end
        end
        if event == "PLAYER_SWING" or event == "UNIT_ATTACK_SPEED" or event == "WEAPON_SLOT_CHANGED" then
            line = line .. " || speeds=" .. fmtArgs(pack(UnitAttackSpeed("player")))
        end
        -- #94: is mana readable, is the spell's cost, is the regen API?
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_SPELLCAST_SUCCEEDED" then
            if event == "UNIT_POWER_UPDATE" and (secret(a[2]) or a[2] ~= "MANA") then return end
            local okP, mana = pcall(UnitPower, "player", 0)
            local okM, maxMana = pcall(UnitPowerMax, "player", 0)
            local okR, base, casting = pcall(GetManaRegen)
            if event == "UNIT_POWER_UPDATE" then
                line = line .. string.format(" || freq=%d", freqMana)
                    .. (freqLast and string.format(" (last %.3f ago)", GetTime() - freqLast) or "")
                freqMana = 0
            end
            line = line .. " || mana=" .. (okP and fmt(mana) or "ERR") .. "/" .. (okM and fmt(maxMana) or "ERR")
                .. " regen=" .. (okR and (fmt(base) .. "," .. fmt(casting)) or "ERR")
            if event == "UNIT_SPELLCAST_SUCCEEDED" and not secret(a[3]) and type(a[3]) == "number" then
                local okC, costs = pcall(C_Spell.GetSpellPowerCost, a[3])
                if not okC then
                    line = line .. " cost=ERR"
                elseif secret(costs) then
                    line = line .. " cost=S"
                elseif type(costs) ~= "table" then
                    line = line .. " cost=" .. fmt(costs)
                else
                    local parts = {}
                    for _, c in ipairs(costs) do
                        if secret(c) or type(c) ~= "table" then
                            parts[#parts + 1] = "?"
                        else
                            parts[#parts + 1] = fmt(c.type) .. ":" .. fmt(c.cost) .. "/" .. fmt(c.minCost)
                        end
                    end
                    line = line .. " cost={" .. table.concat(parts, " ") .. "}"
                end
            end
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            line = line .. " lockdown=" .. fmt(InCombatLockdown())
        end
        log(line)
    end)
    if not ok then log("handler ERR " .. event .. ": " .. tostring(err)) end
end
f:SetScript("OnEvent", onEvent)

-- #150: the target's interrupts (your kick on its cast): interruptedBy, and
-- the name GUF would show. Its own frame, the player's trace stays the same.
local tf = CreateFrame("Frame")
local TARGET_EVENTS = { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }
tf:SetScript("OnEvent", function(_, event, ...)
    local a = pack(...)
    local ok, err = pcall(function()
        local line = "TARGET " .. SHORT[event] .. " " .. fmtArgs(a)
        local by = a[4]
        if not secret(by) and type(by) == "string" and by ~= "" then
            local GUF = rawget(_G, "GlassUF")
            if GUF and GUF.Castbar and GUF.Castbar.InterrupterName then
                local okG, gn = pcall(GUF.Castbar.InterrupterName, by)
                line = line .. " gufName=" .. (okG and fmt(gn) or "ERR")
            end
            line = line .. " isPlayer=" .. fmt(by == UnitGUID("player"))
        end
        if event == "UNIT_SPELLCAST_INTERRUPTED" then seen.targetKicks = seen.targetKicks + 1 end
        log(line)
    end)
    if not ok then log("TARGET ERR " .. tostring(err)) end
end)

-- #152: can the last spell SENT reach the target, and is the answer plain?
-- Also whether SENT's target name is the one GetUnitName gives (GUF binds the
-- cast's recipient by that match).
local function rangeLine()
    if not lastSpell then return "no spell sent yet: cast one at your target first" end
    local ok, r = pcall(C_Spell.IsSpellInRange, lastSpell, "target")
    local okN, tn = pcall(GetUnitName, "target", false)
    return string.format("range spell=%s target=%s inRange=%s combat=%s sentTo=%s getUnitName=%s match=%s",
        fmt(lastSpell), Probe.Shape(UnitName("target")), ok and fmt(r) or "ERR", fmt(InCombatLockdown()),
        Probe.Shape(lastSentTo), okN and Probe.Shape(tn) or "ERR",
        fmt(okN and lastSentTo ~= nil and not secret(tn) and tn == lastSentTo))
end

-- World events through the host's helper (it logs a throw or a refusal);
-- unit events by hand: the host has no RegisterUnitEvent.
local function register()
    for _, e in ipairs(UNIT_EVENTS) do
        local ok, res = pcall(f.RegisterUnitEvent, f, e, "player")
        if not ok or res == false then failed[#failed + 1] = e .. (ok and " refused" or (": " .. tostring(res))) end
    end
    for _, e in ipairs(TARGET_EVENTS) do
        local ok, res = pcall(tf.RegisterUnitEvent, tf, e, "target")
        if not ok or res == false then failed[#failed + 1] = "target " .. e .. (ok and " refused" or (": " .. tostring(res))) end
    end
    if not Probe:RegisterEvents(f, WORLD_EVENTS) then failed[#failed + 1] = "a world event (see the lines above)" end
end

-- Post-hooks: they observe, never replace. A missing namespace is a failure line.
local function hook(nsName, fnName, label)
    local ns = rawget(_G, nsName)
    if type(ns) ~= "table" or type(ns[fnName]) ~= "function" then
        failed[#failed + 1] = "hook " .. nsName .. "." .. fnName .. ": absent"
        return
    end
    local ok, err = pcall(hooksecurefunc, ns, fnName, function(...)
        local a = pack(...)
        pcall(log, "HOOK " .. label .. " " .. fmtArgs(a))
    end)
    if not ok then failed[#failed + 1] = "hook " .. label .. ": " .. tostring(err) end
end

--------------------------------------------------------------------------------
-- PR 2 gate: an insecure UIParent host anchored TO the secure player button,
-- moved, scaled, hidden and re-docked on demand (run it in combat too).
--------------------------------------------------------------------------------

local hier
local function buildHier()
    local owner = rawget(_G, "GlassUF_player")
    if not owner then say("GlassUF_player not found (is GlassUnitFrames loaded?)") return nil end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(200, 14)
    host:SetPoint("TOP", owner, "BOTTOM", 0, -40)
    host:SetFrameStrata(owner:GetFrameStrata())
    local tex = host:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(host)
    tex:SetColorTexture(1, 0.3, 0.1, 0.6)
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetAllPoints(host)
    local txt = CreateFrame("Frame", nil, host)
    txt:SetAllPoints(bar)
    host:EnableMouse(false)
    return { owner = owner, host = host, bar = bar, txt = txt }
end

local function step(name, fn)
    local ok, err = pcall(fn)
    log(string.format("hier %s: %s", name, ok and "ok" or ("ERR " .. tostring(err))))
end

local function runHier()
    if not hier then
        if InCombatLockdown() then say("build it once out of combat first: /fp cast hier") return end
        hier = buildHier()
        if not hier then return end
    end
    local h = hier
    log(string.format("hier start lockdown=%s ownerProtected=%s hostProtected=%s barProtected=%s",
        fmt(InCombatLockdown()), fmt(h.owner:IsProtected()), fmt(h.host:IsProtected()), fmt(h.bar:IsProtected())))
    step("move to centre", function() h.host:ClearAllPoints() h.host:SetPoint("CENTER", UIParent, "CENTER", 0, -120) end)
    step("scale 1.25", function() h.host:SetScale(1.25) end)
    step("resize 340x20", function() h.host:SetSize(340, 20) end)
    step("hide", function() h.host:Hide() end)
    step("show", function() h.host:Show() end)
    step("scale 1", function() h.host:SetScale(1) end)
    step("resize 200x14", function() h.host:SetSize(200, 14) end)
    step("re-dock", function() h.host:ClearAllPoints() h.host:SetPoint("TOP", h.owner, "BOTTOM", 0, -40) end)
    log(string.format("hier end hostProtected=%s ownerProtected=%s (watch for ADDON_ACTION_BLOCKED lines)",
        fmt(h.host:IsProtected()), fmt(h.owner:IsProtected())))
end

--------------------------------------------------------------------------------
-- Status and slash commands
--------------------------------------------------------------------------------

local function status()
    local parts = { "status build=" .. fmt((GetBuildInfo())) .. "/" .. fmt(select(2, GetBuildInfo())),
        "lockdown=" .. fmt(InCombatLockdown()) }
    local cs = rawget(_G, "C_Secrets")
    if cs and cs.ShouldUnitSpellCastingBeSecret then
        local ok, v = pcall(cs.ShouldUnitSpellCastingBeSecret, "player")
        parts[#parts + 1] = "castSecretPolicy=" .. (ok and fmt(v) or "ERR")
    end
    local okN, n = pcall(function() return pack(GetNetStats()) end)
    parts[#parts + 1] = "netStats=" .. (okN and fmtArgs(n) or "ERR")
    local okC, cv = pcall(function() return C_CVar.GetCVar("showSwingTimer") end)
    parts[#parts + 1] = "showSwingTimer=" .. (okC and fmt(cv) or "ERR")
    local okA, sp = pcall(function() return pack(UnitAttackSpeed("player")) end)
    parts[#parts + 1] = "speeds=" .. (okA and fmtArgs(sp) or "ERR")
    log(table.concat(parts, " "))
    log("snapshot " .. castSnapshot())
    if #failed > 0 then
        for _, e in ipairs(failed) do log("not registered " .. e) end
    else
        log("all events and hooks registered")
    end
end

Probe:Command("status", status, "build, cast secrecy policy, GetNetStats, swing CVar, attack speeds, failures")
Probe:Command("mark", function(args)
    log("==== " .. ((args and args ~= "") and args or "mark") .. " ====")
end, "<text>: label the next test case in the log")
Probe:Command("cd", function()
    cdEvents = not cdEvents
    say("SPELL_UPDATE_COOLDOWN logging " .. (cdEvents and "on" or "off"))
end, "toggle SPELL_UPDATE_COOLDOWN logging (noisy)")
Probe:Command("hier", runHier, "move/scale/hide a UIParent host anchored to GlassUF_player (run it in combat too)")
Probe:Command("clear", function()
    Probe:ClearLog()
    say("log cleared")
end, "empty the saved log (CastProbeDB.log, written on /reload or logout)")

--------------------------------------------------------------------------------
-- Procedures (/fp steps cast <name>): the in-game gates for #149, #150, #152,
-- and the check of what GUF built on them. Every result is a log line too.
--------------------------------------------------------------------------------

-- A wait that completes once a counter moves past where it was when the step
-- first polled (a fresh closure per step, so a resumed run starts over).
local function after(key, label)
    local base
    return function()
        base = base or seen[key]
        if seen[key] > base then return true, label .. " seen (" .. seen[key] .. ")" end
        return false, "waiting for " .. label
    end
end

Probe:Steps("gcd", {
    title = "The global cooldown (#149)",
    rev = 1,
    { text = "Out of combat, cast an instant spell that has NO cooldown of its own (a buff, a heal over time, a shout).",
      wait = after("gcd", "a cooldown update after your cast"), timeout = 180 },
    { text = "Did a thin line run along the top of your power bar (or under your detached cast bar) for about 1.5 s?",
      ask = true },
    { text = "Cast a spell that HAS a cooldown of its own (Mind Blast, Mortal Strike, a shock), out of combat.",
      wait = after("gcd", "a cooldown update after your cast"), timeout = 180 },
    { text = "Did the line stay away this time? (Yes = no line.)", ask = true },
    { text = "Now pull a mob and, in combat, cast an instant with no cooldown of its own.",
      wait = after("gcdCombat", "a cooldown update in combat"), timeout = 300 },
    { text = "Did the line run in combat too?", ask = true },
    { text = "Was the GCD spell (61304) or your spell marked active? Read below, nothing to do: Next.", auto = true,
      run = function() return "GCD updates " .. seen.gcd, "isOnGCD true " .. seen.gcdOn, "in combat " .. seen.gcdCombat end,
      check = function() return seen.gcdOn > 0, "isOnGCD true at least once" end },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

Probe:Steps("kick", {
    title = "Who interrupted a cast (#150)",
    rev = 1,
    { text = "Start a hard cast and move (or jump) to cancel it: the control, interruptedBy should be empty.",
      wait = after("kicks", "an INTERRUPTED"), timeout = 180 },
    { text = "Get a cast interrupted by a mob that kicks or silences (a caster mob, a Defias, a murloc oracle). Keep casting near it.",
      wait = after("kicks", "an INTERRUPTED"), timeout = 900 },
    { text = "Did your cast bar say \"Interrupted by <the mob>\"? (Plain \"Interrupted\" = No.)", ask = true, screenshot = "kicked" },
    { text = "If your class can interrupt (Kick, Pummel, Earth Shock, Counterspell), interrupt your target's cast. Else Skip.",
      wait = after("targetKicks", "your target's INTERRUPTED"), timeout = 900 },
    { text = "Did the target's cast bar say \"Interrupted by <you>\"?", ask = true },
    { text = "How many interrupts carried interruptedBy? Read below: Next.", auto = true,
      run = function() return "player INTERRUPTED " .. seen.kicks, "with interruptedBy " .. seen.kickBy,
                              "target INTERRUPTED " .. seen.targetKicks end,
      check = function() return seen.kickBy > 0, "interruptedBy readable at least once" end },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

Probe:Steps("range", {
    title = "The out-of-range cast bar (#152)",
    rev = 1,
    { text = "Target a mob or a friend in range of a ranged spell, cast it at the target once, then press Run.",
      button = "Read range", run = function() local l = rangeLine(); say(l); return l end,
      check = function() return lastSpell ~= nil and C_Spell.IsSpellInRange(lastSpell, "target") == true, "in range: true" end },
    { text = "Keep the target and walk out of that spell's range, then press Run.",
      button = "Read range", run = function() local l = rangeLine(); say(l); return l end,
      check = function() return lastSpell ~= nil and C_Spell.IsSpellInRange(lastSpell, "target") == false, "out of range: false" end },
    { text = "Pull a mob, keep it targeted, cast that spell at it once, and press Run in combat (in range or not).",
      button = "Read range", run = function() local l = rangeLine(); say(l); return l end,
      check = function()
          local ok, r = pcall(C_Spell.IsSpellInRange, lastSpell, "target")
          return ok and InCombatLockdown() and not secret(r) and type(r) == "boolean", "plain in combat"
      end },
    { text = "Cast at a target that leaves range DURING the cast (a fleeing mob, a friend running off). Did your cast bar turn grey?",
      ask = true, screenshot = "out of range" },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    Probe:Ready()
    -- Saved tables only now: the client loads SavedVariables after our files.
    if type(rawget(_G, "CastProbeDB")) ~= "table" then CastProbeDB = {} end
    if type(CastProbeDB.log) ~= "table" then CastProbeDB.log = {} end
    Probe:UseLog(CastProbeDB.log, LOG_MAX)
    register()
    hook("C_SwingTimer", "EnableRangeCheck", "EnableRangeCheck")
    hook("C_TradeSkillUI", "CraftRecipe", "CraftRecipe")
    hook("C_TradeSkillUI", "CraftEnchant", "CraftEnchant")
    hook("C_TradeSkillUI", "StopRecipeRepeat", "StopRecipeRepeat")
    log("==== session start ====")
    say("loaded. /fp cast for the commands. " .. (#failed > 0 and (#failed .. " registration(s) failed, see /fp cast status") or "all registered"))
end)

NS._test = { Probe = Probe, onEvent = onEvent, failed = failed, seen = seen, rangeLine = rangeLine }
