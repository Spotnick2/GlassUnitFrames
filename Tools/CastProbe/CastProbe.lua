-- CastProbe: the phase-0 event trace for GlassUnitFrames #72 (cast latency and
-- pushback), plus the cheap checks later cast-bar PRs are gated on (swing
-- events, the shared range check, tradeskill requests, a UIParent cast host
-- anchored to the secure player button). Throwaway, never shipped (.pkgmeta
-- ignores Tools). Every client value is classified before it is printed:
-- S = secret; nothing secret is compared, formatted or concatenated.
--
-- /cprobe help

CastProbeDB = CastProbeDB or {}

local LOG_MAX = 4000
local PREFIX = "|cffffb347CastProbe|r "

local isSecretFn = rawget(_G, "issecretvalue")
local function secret(v) return isSecretFn ~= nil and isSecretFn(v) == true end

local chat = true        -- echo to chat as well as the log
local cdEvents = false   -- SPELL_UPDATE_COOLDOWN is noisy: off until asked for
local lastT
local sent = {}          -- castGUID -> GetTime() at SENT (plain guids only)
local failed = {}        -- registrations or hooks that didn't take

local function say(msg) print(PREFIX .. msg) end

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

local function log(line)
    local now = GetTime()
    local dt = lastT and string.format("+%.3f", now - lastT) or "     "
    lastT = now
    local full = string.format("%.3f %s %s", now, dt, line)
    local L = CastProbeDB.log
    L[#L + 1] = full
    if #L > LOG_MAX then table.remove(L, 1) end
    if chat then say(full) end
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
    "CURRENT_SPELL_CAST_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
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

local function onEvent(_, event, ...)
    if event == "SPELL_UPDATE_COOLDOWN" and not cdEvents then return end
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
        if event == "UNIT_SPELLCAST_SENT" and guid then
            sent[guid] = GetTime()
        elseif (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START") and guid then
            local s = sent[guid]
            line = line .. (s and string.format(" |cffff6060sent->start=%dms|r", (GetTime() - s) * 1000) or " (no SENT for this guid)")
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
            end
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
    if not ok then log("|cffff6060handler ERR|r " .. event .. ": " .. tostring(err)) end
end
f:SetScript("OnEvent", onEvent)

local function register()
    for _, e in ipairs(UNIT_EVENTS) do
        local ok, res = pcall(f.RegisterUnitEvent, f, e, "player")
        if not ok or res == false then failed[#failed + 1] = e .. (ok and " refused" or (": " .. tostring(res))) end
    end
    for _, e in ipairs(WORLD_EVENTS) do
        local ok, res = pcall(f.RegisterEvent, f, e)
        if not ok or res == false then failed[#failed + 1] = e .. (ok and " refused" or (": " .. tostring(res))) end
    end
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
    log(string.format("hier %s: %s", name, ok and "ok" or ("|cffff6060ERR|r " .. tostring(err))))
end

local function runHier()
    if not hier then
        if InCombatLockdown() then say("build it once out of combat first: /cprobe hier") return end
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
        for _, e in ipairs(failed) do log("|cffff6060not registered|r " .. e) end
    else
        log("all events and hooks registered")
    end
end

local HELP = {
    "/cprobe status   build, cast secrecy policy, GetNetStats, swing CVar, attack speeds, failures",
    "/cprobe mark <text>   label the next test case in the log",
    "/cprobe chat   toggle the chat echo (the log keeps everything)",
    "/cprobe cd   toggle SPELL_UPDATE_COOLDOWN logging (noisy)",
    "/cprobe hier   PR 2 gate: move/scale/hide a UIParent host anchored to GlassUF_player (run in combat too)",
    "/cprobe dump [n]   print the last n log lines (default 30)",
    "/cprobe clear   empty the log",
    "The log is CastProbeDB.log in SavedVariables (written on /reload or logout).",
}

SLASH_CASTPROBE1 = "/cprobe"
SlashCmdList.CASTPROBE = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "status" then
        status()
    elseif cmd == "mark" then
        log("|cff7fd4ff==== " .. (rest ~= "" and rest or "mark") .. " ====|r")
    elseif cmd == "chat" then
        chat = not chat
        say("chat echo " .. (chat and "on" or "off"))
    elseif cmd == "cd" then
        cdEvents = not cdEvents
        say("SPELL_UPDATE_COOLDOWN logging " .. (cdEvents and "on" or "off"))
    elseif cmd == "hier" then
        runHier()
    elseif cmd == "dump" then
        local n = tonumber(rest) or 30
        local L = CastProbeDB.log
        for i = math.max(1, #L - n + 1), #L do print(L[i]) end
    elseif cmd == "clear" then
        CastProbeDB.log = {}
        say("log cleared")
    else
        for _, line in ipairs(HELP) do say(line) end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
    if name ~= "CastProbe" then return end
    self:UnregisterEvent("ADDON_LOADED")
    CastProbeDB.log = CastProbeDB.log or {}
    register()
    hook("C_SwingTimer", "EnableRangeCheck", "EnableRangeCheck")
    hook("C_TradeSkillUI", "CraftRecipe", "CraftRecipe")
    hook("C_TradeSkillUI", "CraftEnchant", "CraftEnchant")
    hook("C_TradeSkillUI", "StopRecipeRepeat", "StopRecipeRepeat")
    log("|cff7fd4ff==== session start ====|r")
    say("loaded. /cprobe help, then /cprobe status. " .. (#failed > 0 and (#failed .. " registration(s) failed, see status") or "all registered"))
end)
