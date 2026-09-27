-- GlassUnitFrames.lua: bootstrap, saved settings, combat-deferred actions and
-- the /glass command.

local ADDON = ...
GlassUF = GlassUF or {}
local API, Glass, Frames, Blizzard = GlassUF.API, GlassUF.Glass, GlassUF.Frames, GlassUF.Blizzard
local say = API.Print

local DEFAULTS = { font = "arial", hideBlizzard = true, fill = Glass.STYLE.fillAlpha }

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
    if not Glass.SetFillAlpha(db.fill) then db.fill = DEFAULTS.fill; Glass.SetFillAlpha(db.fill) end
    return db
end

-- Anything that touches the secure frames waits for combat to end. The queue
-- is ordered (a repeated key keeps its slot, newest function wins) and the
-- build always runs first: every other action assumes the frames exist.
local pending, order = {}, {}

-- message: text to print when deferred; nil = a default; false = silent.
local function whenOutOfCombat(key, fn, message)
    if InCombatLockdown() then
        if not pending[key] then order[#order + 1] = key end
        pending[key] = fn
        if message ~= false then say(message or "will do that when combat ends") end
        return
    end
    fn()
end
GlassUF.WhenOutOfCombat = whenOutOfCombat   -- the addon's one combat queue (Blizzard.lua uses it)

local function runPending()
    local run, keys = pending, order
    pending, order = {}, {}
    if run.build then run.build() end
    for _, key in ipairs(keys) do
        if key ~= "build" then run[key]() end
    end
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
    { "mark",   function(u) return GetRaidTargetIndex(u) end },
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
            -- What the raid-mark icon on this frame is actually doing.
            local f = Frames.byUnit[u]
            local icon = f and f.indicators and f.indicators.raidTarget
            if icon then parts[#parts + 1] = "markIcon=" .. (icon:IsShown() and "shown" or "hidden") end
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
-- /glass totem: where Blizzard's TotemFrame lives on this client (#18). Works
-- on any class; the answer decides how a shaman's totem bar survives hiding
-- PlayerFrame.
--------------------------------------------------------------------------------

-- Every client call guarded the same way: a report that throws prints nothing.
local function safe(f, method, ...)
    local fn = f and f[method]
    if type(fn) ~= "function" then return nil end
    return select(2, pcall(fn, f, ...))
end

local function frameName(f)
    if f == Blizzard.hiddenParent then return "GlassUF.hiddenParent" end
    return safe(f, "GetName") or ((safe(f, "GetObjectType") or "?") .. "(anonymous)")
end

-- Where a Blizzard frame lives: parent chain, first anchor, protection,
-- visibility. /glass totem is this for TotemFrame; /glass frame <Name> for
-- any global frame (names are case sensitive), e.g. PetActionBar.
local function frameReport(name, label)
    local tf = rawget(_G, name)
    if type(tf) ~= "table" then
        say(label .. ": no " .. name .. " global on this client")
        return
    end
    local chain, p, underHidden = {}, tf, false
    for _ = 1, 8 do
        local parent = safe(p, "GetParent")
        if not parent then break end
        if parent == Blizzard.hiddenParent then underHidden = true end
        chain[#chain + 1] = frameName(parent)
        p = parent
    end
    if #chain == 0 then chain[1] = "(none)"
    elseif safe(p, "GetParent") then chain[#chain + 1] = "..." end
    -- IsProtected returns (protected, explicitly): explicit means the frame
    -- itself is secure (reparenting it is combat-locked), implicit means only
    -- through its relationships.
    -- Every read and every formatting of a client value inside pcall: a
    -- restricted frame can hand back secret offsets, which tostring rejects.
    local okP, prot, explicit = pcall(function() return tf:IsProtected() end)
    local okA, anchor = pcall(function()
        local point, anchorTo, relPoint, x, y = tf:GetPoint(1)
        if not point then return "(no anchor)" end
        return string.format("to %s (%s on %s, %s, %s)",
            (type(anchorTo) == "table") and frameName(anchorTo) or tostring(anchorTo or "screen"),
            tostring(point), tostring(relPoint), tostring(x), tostring(y))
    end)
    if not okA then anchor = "(unreadable anchor)" end
    local okC, n = pcall(function() return select("#", tf:GetChildren()) end)
    say(label .. ": " .. name .. " parent chain: " .. table.concat(chain, " > "))
    say(string.format("%s: anchored %s; points=%s; protected=%s explicitly=%s; shown=%s visible=%s; children=%s; under GlassUF's hidden parent=%s",
        label, anchor, tostring(safe(tf, "GetNumPoints")), tostring(okP and prot), tostring(okP and explicit),
        tostring(safe(tf, "IsShown")), tostring(safe(tf, "IsVisible")), tostring(okC and n or "?"), tostring(underHidden)))
end

local HELP = {
    "font arial|friz  - text font (saved)",
    "fill 0.2-1  - bar fill opacity; text stays opaque (saved)",
    "reset  - move frames back to the default layout (after combat if in combat)",
    "blizzard show|hide  - Blizzard's own frames for the units GlassUF draws (after /reload)",
    "secrets  - which unit values are secret right now, plus any paint failures",
    "totem  - where Blizzard's totem bar lives (measurement for shaman support)",
    "frame <Name>  - where any Blizzard frame lives, e.g. /glass frame PetActionBar",
    "Shift-drag a frame to move it (out of combat).",
}

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local rawArg = arg
    cmd, arg = cmd:lower(), arg:lower()
    if cmd == "font" then
        if Glass.SetFont(arg) then
            GlassUnitFramesDB.font = arg
            say("font " .. arg)
        else
            say("font arial|friz")
        end
    elseif cmd == "fill" then
        local a = tonumber(arg)
        if Glass.SetFillAlpha(a) then
            GlassUnitFramesDB.fill = a
            say("bar fill opacity " .. arg)
        else
            say("fill 0.2-1 (now " .. Glass.STYLE.fillAlpha .. ")")
        end
    elseif cmd == "reset" then
        whenOutOfCombat("reset", function() Frames.ResetPositions(); say("positions reset") end)
    elseif cmd == "blizzard" then
        -- Named for what happens to BLIZZARD's frames: "show" brings them back.
        if arg == "show" or arg == "hide" then
            GlassUnitFramesDB.hideBlizzard = (arg == "hide")
            say("Blizzard's frames will be " .. (arg == "hide" and "hidden" or "shown") .. " after /reload")
        else
            -- What is on screen now vs what the next /reload will do.
            local now = Blizzard.active and "hidden" or "shown"
            local next = GlassUnitFramesDB.hideBlizzard and "hidden" or "shown"
            say("Blizzard's frames are " .. now
                .. (now == next and "" or (", " .. next .. " after /reload"))
                .. ". /glass blizzard show|hide, then /reload")
        end
    elseif cmd == "secrets" then
        secretsReport()
    elseif cmd == "totem" then
        frameReport("TotemFrame", "totem")
    elseif cmd == "frame" and rawArg ~= "" then
        frameReport(rawArg, "frame")
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
        -- Secure frames cannot be set up under lockdown. Loading normally runs
        -- before it applies, but do not bet the whole addon on that.
        whenOutOfCombat("build", function()
            Frames.Build(db)
            if db.hideBlizzard then Blizzard.HideFor(Frames.byUnit) end
        end, "frames will appear when combat ends")
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
        Frames.StopMoving()                     -- finish a drag combat caught mid-way
        runPending()
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
