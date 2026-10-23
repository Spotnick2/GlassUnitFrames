-- #86, milestone 1 only. Never shipped. Secrets are classified before any
-- inspection, and only sanitized strings reach ForeverProbe's bounded log.
local ADDON, NS = ...
local Probe = ForeverProbe:Module("ThreatProbe", { api = 1, cmd = "threat" })
NS.Probe = Probe
local API = GlassUF.API
local LOG_MAX, INTERVAL = 4000, 0.25
local watching, rendering, dirty = false, false, false
local elapsed, snapshots = 0, 0
local renderResults = {}
local reasons = {}
local function say(s) Probe:Say(s) end

local function classify(v)
    if API.IsSecret(v) then return "secret" end
    if v == nil then return "nil" end
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return (v:gsub("[\r\n|]", " "):sub(1, 100)) end
    return t
end
NS.Classify = classify

local function invoke(fn, ...)
    if type(fn) ~= "function" then return "missing API" end
    local results = { pcall(fn, ...) }
    if not results[1] then return "error" end
    return "ok", results
end
NS.Invoke = invoke

local function plainTrue(fn, ...)
    local state, r = invoke(fn, ...)
    return state == "ok" and not API.IsSecret(r[2]) and r[2] == true
end

-- Fixed roster order. Raid player aliases are deliberately retained by Scan
-- to compare token-dependent restrictions, but omitted from rendering.
local function roster(aliases)
    local out = { "player", "pet" }
    local raid = plainTrue(rawget(_G, "IsInRaid"))
    local grouped = raid or plainTrue(rawget(_G, "IsInGroup"))
    if grouped then
        for i = 1, raid and 40 or 4 do
            local u = (raid and "raid" or "party") .. i
            local p = (raid and "raidpet" or "partypet") .. i
            local self = plainTrue(rawget(_G, "UnitIsUnit"), u, "player")
            if aliases or not self then out[#out + 1] = u; out[#out + 1] = p end
        end
    end
    local present = {}
    for _, u in ipairs(out) do
        local state, r = invoke(rawget(_G, "UnitExists"), u)
        -- Unknown existence is included rather than tested in Lua.
        if state == "ok" and (API.IsSecret(r[2]) or r[2] == true) then present[#present + 1] = u end
    end
    return present, raid and "raid" or (grouped and "party" or "solo")
end
NS.Roster = roster

local QUERIES = {
    { "UnitThreatSituation", { "status" } },
    { "UnitDetailedThreatSituation", { "tanking", "status", "scaled", "rawPct", "rawThreat" } },
    { "UnitThreatLeadSituation", { "leadStatus" } },
    { "UnitThreatPercentageOfLead", { "leadPct" } },
}

local function report(label, fn, fields, ...)
    local state, r = invoke(fn, ...)
    if state ~= "ok" then say(label .. " " .. state); return end
    local parts = {}
    for i, field in ipairs(fields) do parts[#parts + 1] = field .. "=" .. classify(r[i + 1]) end
    say(label .. " " .. table.concat(parts, " "))
end

local function scan()
    snapshots = snapshots + 1
    local units, group = roster(true)
    say("snapshot " .. snapshots .. " build=" .. classify(API.ClientBuild()) .. " group=" .. group
        .. " combat=" .. classify(InCombatLockdown()))
    report("instance", rawget(_G, "IsInInstance"), { "inside", "type" })
    report("target", rawget(_G, "UnitExists"), { "exists" }, "target")
    report("target", rawget(_G, "UnitCanAttack"), { "attackable" }, "player", "target")
    local secrets = rawget(_G, "C_Secrets")
    for _, mob in ipairs({ "target", "targettargettarget" }) do
        report(mob, rawget(_G, "UnitIsUnit"), { "sameAsTarget" }, mob, "target")
        for _, u in ipairs(units) do
            local label = u .. " -> " .. mob
            for _, q in ipairs(QUERIES) do report(label .. " " .. q[1], rawget(_G, q[1]), q[2], u, mob) end
            for _, key in ipairs({ "ShouldUnitThreatStateBeSecret", "ShouldUnitThreatValuesBeSecret" }) do
                report(label .. " " .. key, type(secrets) == "table" and rawget(secrets, key), { "policy" }, u, mob)
            end
            report(label, rawget(_G, "UnitIsUnit"), { "currentVictim" }, u, mob .. "target")
        end
    end
    report("player (no mob)", rawget(_G, "UnitThreatSituation"), { "status" }, "player")
end
NS.Scan = scan

local function outcome(key, ok)
    local result = ok and "ok" or "error"
    if renderResults[key] ~= result then
        renderResults[key] = result
        say("render " .. key .. "=" .. result)
    end
end

-- Secrets exist only in this call and native widgets. They are never cached
-- in a row, sorted, formatted by Lua, or used for visibility.
local function render()
    local units = roster(false)
    NS.UI.ShowDiagnostic(units)
    for i, u in ipairs(units) do
        local row = NS.UI.rows[i]
        NS.UI.ClearRow(row)
        local state, r = invoke(rawget(_G, "UnitDetailedThreatSituation"), u, "target")
        if state == "ok" then
            local pct = r[4] -- pcall success, tanking, status, scaled, rawPct, rawThreat
            if API.IsSecret(pct) or type(pct) == "number" then
                outcome(u .. ":SetValue", pcall(row.bar.SetValue, row.bar, pct))
                outcome(u .. ":SetFormattedText", pcall(row.value.SetFormattedText, row.value, "%.0f%%", pct))
            end
        end
        outcome(u .. ":detailedRead", state == "ok")
        local s, values = invoke(rawget(_G, "UnitThreatSituation"), u, "target")
        if s == "ok" then
            local status = values[2]
            if API.IsSecret(status) or type(status) == "number" then
                local colorState, c = invoke(rawget(_G, "GetThreatStatusColor"), status)
                outcome(u .. ":GetThreatStatusColor", colorState == "ok")
                if colorState == "ok" then
                    outcome(u .. ":SetStatusBarColor", pcall(row.bar.SetStatusBarColor, row.bar, c[2], c[3], c[4]))
                end
            end
        end
    end
end
NS.Render = render

local function stopRender()
    rendering = false
    if NS.UI then NS.UI.Hide() end
end
NS.StopRender = stopRender

Probe:Command("scan", scan, "snapshot threat APIs, policies and token aliases")
Probe:Command("watch", function(args)
    if args ~= "on" and args ~= "off" then say("watch on|off"); return end
    watching = args == "on"
    dirty = watching
    reasons = {}
    elapsed = 0
    say("watch " .. args)
end, "on|off: trace changes, at most four snapshots per second")
Probe:Command("render", function(args)
    if args ~= "on" and args ~= "off" then say("render on|off"); return end
    if args == "off" then stopRender() else
        NS.UI.Hide()
        rendering, renderResults = true, {}
        render()
    end
    say("diagnostic rendering " .. args .. " (group order, no rank)")
end, "on|off: test native rendering, including restricted values")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "clear the saved log")

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED", "UNIT_TARGET",
    "GROUP_ROSTER_UPDATE", "UNIT_PET" })
boot:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= ADDON then return end
        if type(rawget(_G, "ThreatProbeDB")) ~= "table" then ThreatProbeDB = {} end
        if type(ThreatProbeDB.log) ~= "table" then ThreatProbeDB.log = {} end
        Probe:Ready()
        Probe:UseLog(ThreatProbeDB.log, LOG_MAX)
        say("ready: /fp threat scan | watch on | preview expanded | render on. Samples and tracing start off.")
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        stopRender()
    elseif event == "PLAYER_REGEN_DISABLED" and NS.UI and NS.UI.mode == "preview" then
        NS.UI.Hide()
    end
    if watching then dirty = true; reasons[event] = true end
    -- Target/roster transitions clear old diagnostic values immediately.
    if rendering and (event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET") then
        NS.UI.ClearAll()
    end
end)
boot:SetScript("OnUpdate", function(_, dt)
    if not watching and not rendering then return end
    elapsed = elapsed + dt
    if elapsed < INTERVAL then return end
    elapsed = 0
    if watching and dirty then
        dirty = false
        local events = {}
        for event in pairs(reasons) do events[#events + 1] = event end
        table.sort(events)
        if #events > 0 then say("events " .. table.concat(events, ", ")) end
        reasons = {}
        scan()
    end
    if rendering then render() end
end)
NS._test = { Probe = Probe, boot = boot, classify = classify, roster = roster,
    state = function() return watching, rendering, snapshots end }
