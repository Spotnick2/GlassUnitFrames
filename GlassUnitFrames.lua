-- GlassUnitFrames.lua: bootstrap, saved settings, combat-deferred actions and
-- the /glass command.

local ADDON = ...
GlassUF = GlassUF or {}
local API, Glass, Frames = GlassUF.API, GlassUF.Glass, GlassUF.Frames
local say = API.Print

local DEFAULTS = { font = "arial" }

-- Read settings, fill missing keys. Nothing may REQUIRE a value to have
-- survived: SavedVariables were broken on builds before 70009.
local function ensureDefaults()
    if type(GlassUnitFramesDB) ~= "table" then GlassUnitFramesDB = {} end
    local db = GlassUnitFramesDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    if type(db.pos) ~= "table" then db.pos = {} end
    if not Glass.FONTS[db.font] then db.font = DEFAULTS.font end
    return db
end

-- Anything that touches the secure frames waits for combat to end.
local pending = {}

local function whenOutOfCombat(key, fn)
    if InCombatLockdown() then
        pending[key] = fn
        say("will do that when combat ends")
        return
    end
    fn()
end

--------------------------------------------------------------------------------
-- /glass secrets: which unit values come back secret, in or out of combat.
--------------------------------------------------------------------------------

local SECRET_PROBES = {
    { "hp",     function(u) return UnitHealth(u) end },
    { "hpMax",  function(u) return UnitHealthMax(u) end },
    { "hpPct",  function(u) return API.HealthPercent(u) end },
    { "hpAbbr", function(u) return AbbreviateNumbers(UnitHealth(u)) end },
    { "pw",     function(u) return UnitPower(u) end },
    { "pwMax",  function(u) return UnitPowerMax(u) end },
    { "pwType", function(u) return select(2, UnitPowerType(u)) end },
    { "name",   function(u) return GetUnitName(u, false) end },
    { "class",  function(u) return select(2, UnitClass(u)) end },
    { "react",  function(u) return UnitReaction(u, "player") end },
    { "dead",   function(u) return UnitIsDeadOrGhost(u) end },
    { "cast",   function(u) return (API.CastDuration(u)) end },
}

local function classify(fn, u)
    local ok, v = pcall(fn, u)
    if not ok then return "ERR" end
    if API.IsSecret(v) then return "S" end
    if v == nil then return "nil" end
    return "ok"
end

local function secretsReport()
    say(string.format("secrets report, build %s, %s. S = secret, ok = plain, ERR = threw",
        API.ClientBuild(), InCombatLockdown() and "|cffff6060IN COMBAT|r" or "out of combat"))
    for _, u in ipairs(Frames.ORDER) do
        if UnitExists(u) then
            local parts = {}
            for _, p in ipairs(SECRET_PROBES) do parts[#parts + 1] = p[1] .. "=" .. classify(p[2], u) end
            say("  " .. u .. ": " .. table.concat(parts, " "))
        else
            say("  " .. u .. ": (no unit)")
        end
    end
    local any = false
    for step, err in pairs(GlassUF.paintFailures) do
        any = true
        say("  |cffff6060paint failed|r " .. step .. ": " .. err)
    end
    for _, e in ipairs(GlassUF.eventFailures) do
        any = true
        say("  |cffff6060event failed|r " .. e)
    end
    if not any then say("  no paint or event failures") end
end

--------------------------------------------------------------------------------

local HELP = {
    "font arial|friz  - text font (saved)",
    "reset  - move frames back to the default layout (after combat if in combat)",
    "secrets  - which unit values are secret right now, plus any paint failures",
    "Shift-drag a frame to move it (out of combat).",
}

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "font" then
        if Glass.SetFont(arg) then
            GlassUnitFramesDB.font = arg
            say("font " .. arg)
        else
            say("font arial|friz")
        end
    elseif cmd == "reset" then
        whenOutOfCombat("reset", function() Frames.ResetPositions(); say("positions reset") end)
    elseif cmd == "secrets" then
        secretsReport()
    else
        for _, line in ipairs(HELP) do say("/glass " .. line) end
    end
end

SLASH_GLASSUNITFRAMES1 = "/glass"
SlashCmdList.GLASSUNITFRAMES = slash

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        local db = ensureDefaults()
        Glass.SetFont(db.font)
        Frames.Build(db)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin: warn at a real login, never on /reload.
        if arg1 and API.ClientBuild() ~= GlassUF.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " is newer than the one this addon was measured on ("
                .. GlassUF.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Frames.StopMoving()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if InCombatLockdown() then return end   -- trust the lockdown state, not the event
        local run = pending
        pending = {}
        for _, fn in pairs(run) do fn() end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
