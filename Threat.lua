-- Live target threat (#86). Raw threat alone determines rank; scaled percent
-- is percent to pull. Measured plain in outdoor party combat on 70532.
-- Unknown/secret data never becomes zero or participates in sorting/sounds.
GlassUF = GlassUF or {}
local API = GlassUF.API
local T = { enabled = true, preview = nil, snapshot = nil }
GlassUF.Threat = T
T.COLORS = { { 0.72, 0.94, 0.82 }, { 1, 0.85, 0.48 }, { 1, 0.68, 0.44 }, { 1, 0.55, 0.49 } }
T.UNKNOWN = { 0.65, 0.65, 0.65 }
local db, combat, elapsed, alerted, lastSound = nil, false, 0, false, -math.huge
local endedAt, combatView
local lastCombatSnapshot
local MODES = { group = true, always = true, off = true }
local ROLES = { global = true, tank = true, healer = true, dps = true }
local function plain(v) if not API.IsSecret(v) then return v end end
local function number(v)
    return not API.IsSecret(v) and type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function truth(name, ...)
    local ok, value = API.ThreatCall(name, ...)
    return ok and plain(value) == true
end
local function config() return db and type(db.threat) == "table" and db.threat or {} end
local function edit() if type(db.threat) ~= "table" then db.threat = {} end; return db.threat end
function T.Mode() local m = config().mode; return MODES[m] and m or "group" end
function T.SoundEnabled() return config().sound ~= false end
function T.HideDelay()
    local delay = config().hideDelay
    return number(delay) and math.max(0, math.min(60, delay)) or 10
end
function T.SetHideDelay(delay)
    if not db or not number(delay) then return false end
    edit().hideDelay = math.max(0, math.min(60, delay))
    T.Refresh(); return true
end
function T.EditRole() return GlassUF.Zoom.role or "global" end
function T.Expand()
    local e = config().expand
    if type(e) ~= "table" then return true end
    local r = e[T.EditRole()]
    if type(r) == "boolean" then return r end
    return e.global ~= false
end
function T.IsTank()
    local role = GlassUF.Zoom.role
    if role then return role == "tank" end
    return API.ThreatTankRole()
end
function T.Geometry(key) return config()[key] end
function T.SaveGeometry(key, value) edit()[key] = value end
function T.Display()
    local v = config().view
    if v == "compact" or v == "expanded" or v == "auto" then return v end
    -- Retain explicitly configured role expansion from the original meter.
    return type(config().expand) == "table" and "auto" or "compact"
end
function T.SetDisplay(value)
    if not db or (value ~= "compact" and value ~= "expanded" and value ~= "auto") then return false end
    edit().view = value
    if T.preview then T.preview = value == "expanded" and "expanded" or "compact" end
    T.Refresh(); return true
end
function T.ViewKind()
    local v = T.Display()
    if config().view == nil and T.Mode() == "always" then return "expanded" end
    if v == "auto" then
        if not combat and endedAt and combatView then return combatView end
        return (T.Mode() == "always" or (combat and T.Expand())) and "expanded" or "compact"
    end
    return v
end
function T.SetMode(mode)
    if not db or not MODES[mode] then return false end
    edit().mode = mode ~= "group" and mode or nil
    T.enabled = mode ~= "off"
    T.preview, alerted = nil, false
    T.Refresh(); return true
end
function T.SetSound(on)
    if not db or type(on) ~= "boolean" then return false end
    if on then edit().sound = nil else edit().sound = false end
    return true
end
function T.SetExpand(on)
    if not db or type(on) ~= "boolean" then return false end
    local c, role = edit(), T.EditRole()
    if not ROLES[role] then return false end
    if type(c.expand) ~= "table" then c.expand = {} end
    c.expand[role] = on
    c.view = "auto"
    T.Refresh(); return true
end
function T.ResetPositions()
    if not db then return end
    edit().compact, edit().expanded, edit().anchor = nil, nil, nil
    edit().compactAnchor, edit().expandedAnchor = nil, nil
    GlassUF.ThreatView.ResetPositions(); T.Refresh()
end

local function roster()
    local raid = truth("IsInRaid")
    local units = raid and {} or { "player", "pet" }
    local grouped = raid or truth("IsInGroup")
    if grouped then
        for i = 1, raid and 40 or 4 do
            local unit = (raid and "raid" or "party") .. i
            if raid and truth("UnitIsUnit", unit, "player") then
                units[#units + 1] = "player"; units[#units + 1] = "pet"
            elseif not truth("UnitIsUnit", unit, "player") then
                units[#units + 1] = unit
                units[#units + 1] = (raid and "raidpet" or "partypet") .. i
            end
        end
    end
    return units, grouped
end

local function entry(unit, index)
    if not truth("UnitExists", unit) then return nil end
    local ok, tank, status, scaled, rawPct, raw = API.ThreatCall("UnitDetailedThreatSituation", unit, "target")
    local hasSecret = API.IsSecret(tank) or API.IsSecret(status) or API.IsSecret(scaled)
        or API.IsSecret(rawPct) or API.IsSecret(raw)
    if ok and not hasSecret and tank == nil and status == nil and scaled == nil and rawPct == nil and raw == nil then return nil end
    local e = { unit = unit, index = index, player = unit == "player", tank = plain(tank), status = plain(status),
        unknown = not ok or not number(raw) or (number(raw) and raw < 0) }
    if number(raw) and raw >= 0 then e.raw = raw end
    if API.IsSecret(scaled) or number(scaled) then e.scaled = scaled end
    local nameOK, name = API.ThreatCall("GetUnitName", unit, false)
    if nameOK and (API.IsSecret(name) or type(name) == "string") then e.name = name else e.name = unit end
    local classOK, _, class = API.ThreatCall("UnitClass", unit)
    if classOK and not API.IsSecret(class) and type(class) == "string" then e.class = class end
    if not number(e.status) or e.status % 1 ~= 0 or e.status < 0 or e.status > 3 then e.status = nil end
    return e
end

function T.Read()
    local units, grouped = roster()
    local s = { rows = {}, grouped = grouped, ranked = true, valid = false, color = T.UNKNOWN }
    if not truth("UnitExists", "target") or not truth("UnitCanAttack", "player", "target") or truth("UnitIsDeadOrGhost", "target") then
        s.message = "No hostile target"; return s
    end
    s.valid = true
    local nameOK, name = API.ThreatCall("GetUnitName", "target", false)
    if nameOK and (API.IsSecret(name) or type(name) == "string") then s.targetName = name end
    for i, unit in ipairs(units) do
        local e = entry(unit, i)
        if e then
            s.rows[#s.rows + 1] = e
            if e.unknown then s.ranked = false end
            if e.player then s.player = e end
        end
    end
    if s.ranked then
        table.sort(s.rows, function(a, b) if a.raw ~= b.raw then return a.raw > b.raw end; return a.index < b.index end)
        for i, e in ipairs(s.rows) do e.rank = i end
    end
    s.message = #s.rows == 0 and "No threat data" or nil
    local ok, lead = API.ThreatCall("UnitThreatLeadSituation", "player", "target")
    if ok and number(lead) and lead % 1 == 0 and lead >= 0 and lead <= 3 then s.lead = lead end
    return s
end

-- Role-aware feedback: tanks use Blizzard's threat lead state, never the
-- non-tank rule that would warn just because they correctly hold aggro.
function T.Feedback(s, tankRole)
    local p, severity = s.player, nil
    local danger, safe = false, false
    if tankRole then
        if number(s.lead) and s.lead >= 0 and s.lead <= 3 and p then
            severity = s.lead
            danger, safe = severity > 0, severity == 0
        end
    elseif p then
        if number(p.status) and p.status >= 0 and p.status <= 3 then severity = p.status end
        if p.tank == true then
            severity = 3
        elseif p.tank == false and number(p.scaled) then
            danger, safe = p.scaled >= 90, p.scaled < 85
            if danger then severity = math.max(severity or 0, 1) end
        end
    end
    s.color = severity and T.COLORS[severity + 1] or T.UNKNOWN
    if not tankRole and p and p.tank == false and number(p.scaled) and (not severity or severity < 2) then
        -- Continuous visual progression on the same percent-to-pull metric.
        -- The existing warning point (90%) is amber; pulling (100%) is coral.
        local pct = math.max(0, math.min(100, p.scaled))
        local from, to, t = T.COLORS[1], T.COLORS[2], pct / 90
        if pct > 90 then from, to, t = T.COLORS[2], T.COLORS[4], (pct - 90) / 10 end
        s.color = { from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t,
            from[3] + (to[3] - from[3]) * t }
    end
    return danger, safe
end

local function sample()
    return { valid = true, grouped = true, ranked = true, color = T.COLORS[1], rows = {
        { name = "Sample Tank", class = "WARRIOR", rank = 1, scaled = 100, tank = true },
        { name = "Sample Mage", class = "MAGE", rank = 2, scaled = 90 },
        { name = "You", class = "PRIEST", rank = 3, scaled = 82, player = true },
        { name = "Sample Rogue", class = "ROGUE", rank = 4, scaled = 65 },
        { name = "Sample Pet", class = "HUNTER", rank = 5, scaled = 40 },
    } }
end

function T.Refresh()
    if not db or not GlassUF.Frames.byUnit.player then return end
    local view = GlassUF.ThreatView
    if T.preview then
        local s = sample(); s.player = s.rows[3]
        s.player.tank, s.player.status = false, 0
        T.Feedback(s, false)
        view.Show(s, T.preview, true); return
    end
    local mode = T.Mode()
    if mode == "off" then T.snapshot, lastCombatSnapshot = nil, nil; view.Hide(); return end
    if not truth("UnitExists", "target") then
        T.snapshot, lastCombatSnapshot, endedAt = nil, nil, nil
        alerted = false; view.Hide(); return
    end
    local _, grouped = roster()
    if not grouped and mode ~= "always" then T.snapshot = nil; alerted = false; view.Hide(); return end
    if not combat and (not endedAt or GetTime() - endedAt >= T.HideDelay()) then
        T.snapshot, lastCombatSnapshot = nil, nil; alerted = false; view.Hide(true); return
    end
    if not combat and lastCombatSnapshot then
        T.snapshot = lastCombatSnapshot
        alerted = false
        view.Show(lastCombatSnapshot, T.ViewKind(), false); return
    end
    local s = T.Read()
    T.snapshot = s
    local danger, safe = T.Feedback(s, T.IsTank())
    if combat and s.valid then
        for _, row in ipairs(s.rows) do
            if API.IsSecret(row.scaled) or number(row.scaled) or number(row.raw) then
                lastCombatSnapshot = s; break
            end
        end
    end
    if safe or not s.valid or not combat then alerted = false end
    if danger and not alerted and combat and grouped and s.valid then
        alerted = true
        if T.SoundEnabled() and GetTime() - lastSound >= 5 then
            lastSound = GetTime()
            if not API.ThreatSound() then API.Fail("threat sound", "Boxing Arena Gong could not be played") end
        end
    end
    local kind = T.ViewKind()
    if combat then combatView = kind end
    view.Show(s, kind, false)
end

function T.Preview(which)
    if which ~= "off" and which ~= "compact" and which ~= "expanded" then return false end
    if which ~= "off" and InCombatLockdown() then return false end
    T.preview = which ~= "off" and which or nil
    T.Refresh(); return true
end

function T.Configure(saved)
    db = saved
    T.enabled = T.Mode() ~= "off"
    combat = InCombatLockdown()
    endedAt, combatView, lastCombatSnapshot = nil, nil, nil
    T.Refresh()
end
local frame = CreateFrame("Frame")
API.RegisterEvents(frame, { "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "UNIT_PET",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" })
frame:SetScript("OnEvent", function(_, event)
    if not db then return end
    if event == "PLAYER_REGEN_DISABLED" then
        combat = true; endedAt, lastCombatSnapshot = nil, nil; T.preview = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        if combat then endedAt = GetTime() end
        combat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        combat = InCombatLockdown(); endedAt, lastCombatSnapshot = nil, nil; T.preview = nil; alerted = false
    elseif event == "PLAYER_TARGET_CHANGED" then
        alerted = false
        lastCombatSnapshot = nil
        if not combat then endedAt = nil end
        GlassUF.ThreatView.Hide()
    end
    -- These must discard a stale roster/target immediately; ordinary threat
    -- events are serviced by the shared 0.2-second polling pass.
    if event ~= "UNIT_THREAT_LIST_UPDATE" and event ~= "UNIT_THREAT_SITUATION_UPDATE" then T.Refresh() end
end)
frame:SetScript("OnUpdate", function(_, dt)
    if not db or (T.Mode() == "off" and not T.preview) then return end
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    T.Refresh()
end)
T._test = { frame = frame, entry = entry, roster = roster }
