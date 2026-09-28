-- GlassUnitFrames.lua: bootstrap, saved settings, combat-deferred actions and
-- the /glass command.

local ADDON = ...
GlassUF = GlassUF or {}
local API, Glass, Frames, Blizzard = GlassUF.API, GlassUF.Glass, GlassUF.Frames, GlassUF.Blizzard
local say = API.Print

-- Live material tweaks (Glass.TUNABLES): /glass <key> <value>, saved only
-- once set, so a new default in Glass.STYLE still reaches everyone who never
-- touched it.
local TWEAKS = Glass.TUNABLES
local function rangeText(t) return string.format("%g-%g", t.min, t.max) end

local DEFAULTS = { font = "arial", hideBlizzard = true }

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
    for _, t in ipairs(TWEAKS) do
        if db[t.key] ~= nil and not t.set(db[t.key]) then db[t.key] = nil end
    end
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
    { "threat", function(u) return UnitThreatSituation("player", u) end, value = true },   -- #28: your threat on it
    { "combat", function(u) return UnitAffectingCombat(u) end },
    { "tgtMe",  function(u) return UnitIsUnit(u .. "target", "player") end },   -- #28: is it targeting you?
    { "pwAlpha", function(u) return API.PowerAlpha(u) end, value = true },   -- #27: the curve's opacity
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
    -- The hunter pet's happiness (1-3), once: C_PetInfo takes no unit.
    local ci = rawget(_G, "C_PetInfo")
    local okH, happy = pcall(function() return ci and ci.GetPetHappiness() end)
    say("  petHappiness=" .. ((not okH and "ERR") or (API.IsSecret(happy) and "S")
        or (happy == nil and "nil") or tostring(happy)))
    -- #29: the first combo pip's curve alpha (S = secret, 0/1 = plain), for rogues and druids.
    local okC, c1 = pcall(API.ComboAlpha, 1)
    say("  combo1=" .. ((not okC and "ERR") or (API.IsSecret(c1) and "S")
        or (c1 == nil and "nil") or tostring(c1)))
    -- The player's own threat state (as Blizzard's raid frames read it): once, not per frame.
    local okT, myThreat = pcall(UnitThreatSituation, "player")
    say("  myThreat=" .. ((not okT and "ERR") or (API.IsSecret(myThreat) and "S")
        or (myThreat == nil and "nil") or tostring(myThreat)))
    for _, u in ipairs(Frames.ORDER) do
        if UnitExists(u) then
            local parts = {}
            for _, p in ipairs(SECRET_PROBES) do
                local c = classify(p[2], u)
                -- A few probes are worth their plain value (0 or 1), not just "ok".
                if p.value and c == "ok" then
                    local ok, v = pcall(p[2], u)
                    if ok and type(v) == "number" then c = string.format("%.2f", v) end
                end
                parts[#parts + 1] = p[1] .. "=" .. c
            end
            -- What the raid-mark icon on this frame is actually doing.
            local f = Frames.byUnit[u]
            local icon = f and f.indicators and f.indicators.raidTarget
            if icon then parts[#parts + 1] = "markIcon=" .. (icon:IsShown() and "shown" or "hidden") end
            -- What the power bar's opacity ended up as (#27): 0.0 hidden, 1.0 shown.
            if f and f.power then
                local ok, a = pcall(f.power.GetAlpha, f.power)
                parts[#parts + 1] = "pwBar=" .. ((not ok and "ERR") or (API.IsSecret(a) and "S")
                    or string.format("%.1f", a))
            end
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
    "options  - open the options panel (Options > AddOns > Glass Unit Frames)",
    "font arial|friz  - text font (saved)",
    "level power|name|portrait  - where the target's level goes (saved)",
    "happiness left|right|under  - hunter pet happiness: left of the pet's portrait, right of the frame, or under the portrait (saved)",
    "text <unit> curhp|curmaxhp|perhp|curmaxhp_perhp  - a frame's health text (saved)",
    "mark name|top|right  - raid mark before the name, on the top edge, or right of the frame (saved)",
    "mirror on|off  - unlock mode: moving the player or target frame mirrors the other (saved)",
    "snap grid|align on|off  - unlock mode: snap to the grid / align to other frames (saved)",
    "unlock | lock  - move frames: drag (the target carries its group, the player its pet), click to nudge x/y",
    "reset  - move frames back to the default layout (after combat if in combat)",
    "blizzard show|hide  - Blizzard's own frames for the units GlassUF draws (after /reload)",
    "secrets  - which unit values are secret right now, plus any paint failures",
    "totem  - where Blizzard's totem bar lives (measurement for shaman support)",
    "frame <Name>  - where any Blizzard frame lives, e.g. /glass frame PetActionBar",
}

-- Apply-and-save, one helper per setting: the slash commands and the options
-- panel both go through these, so saving can't drift between them.
local Settings_ = {}
GlassUF.Settings = Settings_

function Settings_.SetFont(key)
    if not Glass.SetFont(key) then return false end
    GlassUnitFramesDB.font = key
    return true
end

function Settings_.SetMark(pos)
    if not Frames.SetMarkPosition(pos) then return false end
    GlassUnitFramesDB.mark = pos
    return true
end

-- A material knob (a Glass.TUNABLES entry), saved only once set.
function Settings_.SetTunable(t, v)
    if not t.set(v) then return false end
    GlassUnitFramesDB[t.key] = v
    return true
end

-- Every knob and the font back to the shipped defaults, saved values
-- forgotten so future default changes reach this player again.
function Settings_.ResetLook()
    for _, t in ipairs(Glass.TUNABLES) do
        t.set(t.default)
        GlassUnitFramesDB[t.key] = nil
    end
    Settings_.SetFont(DEFAULTS.font)
end

-- Unlock mode (movers + nudge panel). Unlock is refused in combat, never queued.
function Settings_.Unlock()
    local ok, why = GlassUF.Movers.Unlock()
    if ok then
        say("frames unlocked: drag to move (the target carries its group), click to nudge. /glass lock when done")
    elseif why == "combat" then
        say("can't unlock frames in combat")
    end
    return ok
end

-- Unlock-mode snapping ("snapGrid" / "snapAlign"), saved only when off.
function Settings_.SetSnap(key, on)
    if not GlassUF.Movers.SetSnap(key, on) then return false end
    if on then GlassUnitFramesDB[key] = nil else GlassUnitFramesDB[key] = false end
    return true
end

-- Mirror the player and target frames while moving them (saved only when off).
function Settings_.SetMirror(on)
    GlassUF.Movers.SetMirror(on)
    if on then GlassUnitFramesDB.mirror = nil else GlassUnitFramesDB.mirror = false end
end

function Settings_.Lock()
    GlassUF.Movers.Lock()
end

function Settings_.ResetPositions()
    whenOutOfCombat("reset", function()
        GlassUF.Movers.CancelDrag()   -- a drag in flight would re-save over the reset
        Frames.ResetPositions()
        GlassUF.Movers.Refresh()      -- the open nudge panel shows the new numbers
        say("positions reset")
    end)
end

function Settings_.SetHealthFormat(unit, kind)
    if not Frames.SetHealthFormat(unit, kind) then return false end
    GlassUnitFramesDB.healthText = GlassUnitFramesDB.healthText or {}
    GlassUnitFramesDB.healthText[unit] = kind
    return true
end

function Settings_.SetHappinessPosition(pos)
    if not Frames.SetHappinessPosition(pos) then return false end
    GlassUnitFramesDB.happiness = pos
    return true
end

function Settings_.SetLevelPosition(pos)
    if not Frames.SetLevelPosition(pos) then return false end
    GlassUnitFramesDB.level = pos
    return true
end

function Settings_.SetAggroRed(on)
    Frames.SetAggroRed(on)
    -- Saved only when turned off (the default is on). Not `(not on) and false
    -- or nil`: `false or nil` is nil, so "off" would never be saved.
    if on then GlassUnitFramesDB.aggroRed = nil else GlassUnitFramesDB.aggroRed = false end
end

-- "show" brings back everything GlassUF hides from Blizzard, the cast bar too.
function Settings_.SetHideBlizzard(hide)
    GlassUnitFramesDB.hideBlizzard = hide and true or false
    if not hide then GlassUnitFramesDB.hideBlizzardCast = nil end
end

local tweakByKey = {}
for _, t in ipairs(TWEAKS) do tweakByKey[t.key] = t end

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local rawArg = arg
    cmd, arg = cmd:lower(), arg:lower()
    if cmd == "font" then
        if Settings_.SetFont(arg) then
            say("font " .. arg)
        else
            say("font arial|friz")
        end
    elseif cmd == "options" or cmd == "config" then
        if not (GlassUF.Options and GlassUF.Options.Open()) then
            say("options are in Game Menu > Options > AddOns > Glass Unit Frames")
        end
    elseif cmd == "happiness" then
        if Settings_.SetHappinessPosition(arg) then
            say("pet happiness " .. arg)
        else
            say("happiness left|right|under (now " .. Frames.happinessPos .. ")")
        end
    elseif cmd == "level" then
        if Settings_.SetLevelPosition(arg) then
            say("level " .. arg)
        else
            say("level power|name|portrait (now " .. Frames.levelPos .. ")")
        end
    elseif cmd == "text" then
        local unit, kind = arg:match("^(%S+)%s+(%S+)$")
        if unit and Settings_.SetHealthFormat(unit, kind) then
            say(unit .. " health text " .. kind)
        else
            say("text <unit> " .. table.concat(Frames.HEALTH_FORMATS, "|") .. "  (e.g. /glass text target curmaxhp)")
        end
    elseif cmd == "mark" then
        if Settings_.SetMark(arg) then
            say("raid mark " .. arg)
        else
            say("mark name|top|right (now " .. Frames.markPos .. ")")
        end
    elseif tweakByKey[cmd] then
        local t = tweakByKey[cmd]
        local a = tonumber(arg)
        if Settings_.SetTunable(t, a) then
            say(t.key .. " " .. arg)
        else
            say(string.format("%s %s (now %s)", t.key, rangeText(t), tostring(Glass.STYLE[t.style])))
        end
    elseif cmd == "unlock" or cmd == "move" then
        Settings_.Unlock()
    elseif cmd == "mirror" then
        if arg == "on" or arg == "off" then
            Settings_.SetMirror(arg == "on")
            say("mirror " .. arg)
        else
            say("mirror on|off  (unlock mode: the player and target frames move as mirror images)")
        end
    elseif cmd == "snap" then
        local which, state = arg:match("^(%S+)%s+(%S+)$")
        local key = (which == "grid" and "snapGrid") or (which == "align" and "snapAlign") or nil
        if key and (state == "on" or state == "off") and Settings_.SetSnap(key, state == "on") then
            say("snap " .. which .. " " .. state)
        else
            say("snap grid|align on|off  (Alt while dragging places freely)")
        end
    elseif cmd == "lock" then
        Settings_.Lock()
        say("frames locked")
    elseif cmd == "reset" then
        Settings_.ResetPositions()
    elseif cmd == "blizzard" then
        -- Named for what happens to BLIZZARD's frames: "show" brings them back.
        if arg == "show" or arg == "hide" then
            Settings_.SetHideBlizzard(arg == "hide")
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
        for _, t in ipairs(TWEAKS) do say(string.format("/glass %s %s  - %s (saved)", t.key, rangeText(t), t.help)) end
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
            GlassUF.Movers.Load(db)
            if db.hideBlizzard then Blizzard.HideFor(Frames.byUnit) end
            -- Blizzard's own player cast bar stays unless asked (the owner likes it).
            if db.hideBlizzardCast then Blizzard.HideFrame("PlayerCastingBarFrame") end
            -- Our combo pips replace Blizzard's (only built for rogues and druids).
            local t = Frames.byUnit.target
            if db.hideBlizzard and t and t.combo then Blizzard.HideFrame("ComboFrame") end
        end, "frames will appear when combat ends")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin: warn at a real login, never on /reload.
        if arg1 and API.ClientBuild() ~= GlassUF.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " is newer than the one this addon was measured on ("
                .. GlassUF.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        GlassUF.Movers.OnCombat()   -- unlock mode ends: protected frames can't move in combat
    elseif event == "PLAYER_REGEN_ENABLED" then
        if InCombatLockdown() then return end   -- trust the lockdown state, not the event
        runPending()
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
