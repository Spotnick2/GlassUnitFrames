-- GlassUnitFrames.lua: bootstrap, saved settings, combat-deferred actions and
-- the /glass command.

local ADDON = ...
GlassUF = GlassUF or {}
local API, Glass, Frames, Blizzard = GlassUF.API, GlassUF.Glass, GlassUF.Frames, GlassUF.Blizzard
local say = API.Print

-- Live material tweaks (Glass.TUNABLES): /glass <key> <value>, saved only
-- once set, so a new default in Glass.STYLE still reaches everyone who never
-- touched it.
-- The material knobs of the instance in use (Glass forwards to it, #102): read
-- when used, never kept from file load.
local function tweaks() return Glass.TUNABLES end
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
    for _, t in ipairs(tweaks()) do
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
-- /glass totem: where Blizzard's TotemFrame lives on this client (#18). A
-- diagnostic only: hosting TotemFrame was removed in #58 (it's a managed
-- frame; moving it out of its container breaks Blizzard's layout code).
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
    "look classic|clean  - the glass: classic, or LibGlass's clean preset (after /reload, saved)",
    "timer on|off  - the combat timer over your portrait (saved)",
    "regen on|off  - mana users: the next 2 s of regen past your mana bar's fill (saved)",
    "ramp whole|edge  - a bar's empty part: its colour fading across the whole bar, or just past the fill (saved)",
    "body clear|smoked  - the glass body: clear, or smoked (darker, after /reload, saved)",
    "level power|name|portrait  - where the target's level goes (saved)",
    "portrait player|target|pet 3d|2d|none  - a frame's portrait (saved; none waits for combat to end)",
    "happiness left|right|under  - hunter pet happiness: left of the pet's portrait, right of the frame, or under the portrait (saved)",
    "text <unit> curhp|curmaxhp|perhp|curmaxhp_perhp  - a frame's health text (saved)",
    "mark name|top|right  - raid mark before the name, on the top edge, or right of the frame (saved)",
    "mirror on|off  - unlock mode: moving the player or target frame mirrors the other (saved)",
    "snap grid|align on|off  - unlock mode: snap to the grid / align to other frames (saved)",
    "unlock | lock  - move frames: drag (the target carries its group, the player its pet), click to nudge x/y",
    "preview  - every frame and bar with sample data, on or off (out of combat; combat ends it)",
    "reset  - move frames back to the default layout (after combat if in combat)",
    "blizzard show|hide  - Blizzard's own frames for the units GlassUF draws (after /reload)",
    "secrets  - which unit values are secret right now, plus any paint failures",
    "totem  - where Blizzard's totem bar lives (diagnostic)",
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

-- The glass look (#102): "clean" saved, classic the default (not saved).
-- Takes effect after /reload: LibGlass builds a look into each surface.
-- The glass body (#101): "smoked" saved, clear the default (not saved).
-- Takes effect after /reload, like the look.
function Settings_.SetGlassBody(body)
    if not GlassUF.BODIES[body] then return false end
    GlassUnitFramesDB.glassBody = body ~= "clear" and body or nil
    return true
end

function Settings_.SetLook(look)
    if not GlassUF.LOOKS[look] then return false end
    GlassUnitFramesDB.look = look ~= "classic" and look or nil
    return true
end

-- Where a bar's empty-part ramp lies (#117): across the whole bar (the
-- default, not saved) or from the fill's moving edge over RAMP_LENGTH of the
-- bar ("edge", saved). Live, on every bar. "edge" needs LibGlass r10's
-- SetTrackLength: with an older copy winning it's refused, but "whole" (what
-- that copy draws anyway) still clears a choice saved under r10.
GlassUF.RAMP_LENGTH = 0.05
GlassUF.RAMPS = { whole = true, edge = true }
function Settings_.SetTrackRamp(mode)
    if not GlassUF.RAMPS[mode] then return false end
    if Glass.SetTrackLength then
        if not Glass.SetTrackLength(mode == "edge" and GlassUF.RAMP_LENGTH or 0) then return false end
    elseif mode == "edge" then
        return false
    end
    GlassUnitFramesDB.trackRamp = mode == "edge" and "edge" or nil
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
    Settings_.SetLook("classic")   -- the glass look too (after /reload, #102)
    Settings_.SetGlassBody("clear")   -- and its body (#101)
    Settings_.SetTrackRamp("whole")   -- and the bars' ramp (#117)
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

-- Preview mode (#109): every frame and bar with sample data. Refused in
-- combat; never saved. Returns whether it is on afterwards.
function Settings_.SetPreview(on)
    local P = GlassUF.Preview
    if on and not P.active then
        local ok, why = P.Start()
        if ok then
            say("preview on: every frame and bar shows sample data. /glass preview again to stop; combat stops it")
        elseif why == "combat" then
            say("can't preview in combat")
        end
    elseif not on and P.active then
        P.Stop()
        say("preview off")
    end
    GlassUF.Movers.SyncPreview()
    return P.active
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
        GlassUF.Castbar.ResetPositions()   -- detached cast bars' spots and sizes (#74)
        GlassUF.Zoom.ResetSpots()          -- the combat zoom spots (the table being edited, #89)
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

-- A frame's portrait (#97): "3d" (default, not saved), "2d" or "none" in
-- db.portrait[unit]. To or from "none" waits for combat to end.
function Settings_.SetPortraitMode(unit, mode)
    local ok, why = Frames.SetPortraitMode(unit, mode)
    if not ok then return false end
    GlassUnitFramesDB.portrait = GlassUnitFramesDB.portrait or {}
    GlassUnitFramesDB.portrait[unit] = mode ~= "3d" and mode or nil
    if next(GlassUnitFramesDB.portrait) == nil then GlassUnitFramesDB.portrait = nil end
    return true, why
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

-- Detach a cast bar from its frame (or attach it back), #74: saved in
-- db.castBars[unit].detached. Allowed in combat (the cast hosts are never
-- protected); while unlocked, its mover appears or goes.
function Settings_.SetCastDetached(unit, on)
    if not GlassUF.Castbar.SetDetached(unit, on) then return false end
    GlassUF.Movers.SyncBars()
    return true
end

-- A cast bar's scale (#74), shown while it's detached; saved in
-- db.castBars[unit].scale. Out of unlock mode too.
function Settings_.SetCastScale(unit, s)
    local ok = GlassUF.Castbar.SetScale(unit, s)
    if ok then GlassUF.Movers.Refresh() end
    return ok
end

-- A cast bar's detached size (#78): w or h may be nil (that one unchanged).
function Settings_.SetCastSize(unit, w, h)
    local ok = GlassUF.Castbar.SetSize(unit, w, h)
    if ok then GlassUF.Movers.Refresh() end
    return ok
end

-- Combat zoom (#89), per bar ("player", "target", "focus", "pet", "swing"):
-- saved in db.zoom[global|role][bar]; while unlocked, its spot's mover follows.
function Settings_.SetZoom(bar, on)
    if not GlassUF.Zoom.SetEnabled(bar, on) then return false end
    GlassUF.Movers.SyncBars()
    return true
end
function Settings_.SetZoomScale(bar, s)
    local ok, v = GlassUF.Zoom.SetScale(bar, s)
    GlassUF.Movers.Refresh()   -- an open nudge panel shows the new scale
    return ok, v
end
-- This character's role for the zoom (nil = global), saved per GUID.
function Settings_.SetZoomRole(role)
    if not GlassUF.Zoom.SetRole(role) then return false end
    GlassUF.Movers.SyncBars()
    GlassUF.Movers.Refresh()   -- the role's spot and scale in an open nudge panel
    return true
end

-- The glass swing timer rows (#87): db.swingTimer = false when off.
function Settings_.SetSwingTimer(on)
    if not GlassUF.Swing.SetEnabled(on) then return false end
    if on then GlassUnitFramesDB.swingTimer = nil else GlassUnitFramesDB.swingTimer = false end
    return true
end

-- The combat timer (#120): db.combatTimer = false when off.
function Settings_.SetCombatTimer(on)
    if not GlassUF.Timer.SetEnabled(on) then return false end
    if on then GlassUnitFramesDB.combatTimer = nil else GlassUnitFramesDB.combatTimer = false end
    return true
end

-- The five-second rule strip (#94): db.fiveSecondRule = false when off,
-- db.fsrCombatOnly = false to show it out of combat too.
function Settings_.SetFiveSecond(on)
    GlassUF.FiveSecond.SetEnabled(on)
    if on then GlassUnitFramesDB.fiveSecondRule = nil else GlassUnitFramesDB.fiveSecondRule = false end
    return true
end
function Settings_.SetFiveSecondCombatOnly(on)
    GlassUF.FiveSecond.SetCombatOnly(on)
    if on then GlassUnitFramesDB.fsrCombatOnly = nil else GlassUnitFramesDB.fsrCombatOnly = false end
    return true
end

-- The regen segment (#118): db.manaRegen = false when off. Mana users only.
function Settings_.SetManaRegen(on)
    if not GlassUF.FiveSecond.SetRegen(on) then return false end
    if on then GlassUnitFramesDB.manaRegen = nil else GlassUnitFramesDB.manaRegen = false end
    return true
end

-- Blizzard's own swing bars: its "Enable Swing Timer" option (the
-- showSwingTimer CVar). Only ever from a click, out of combat.
function Settings_.SetBlizzardSwing(on) return GlassUF.Swing.SetBlizzardShown(on) end

-- A cast bar's spell icon: "left", "right" or "none" (saved only when not its default).
function Settings_.SetCastIcon(unit, side) return GlassUF.Castbar.SetIconSide(unit, side) end

-- The cast bars' colours (db.castColors[key] = { r, g, b, a }); nil r = default.
function Settings_.SetCastColor(key, r, g, b, a) return GlassUF.Castbar.SetColor(key, r, g, b, a) end
function Settings_.ResetCastColors() GlassUF.Castbar.ResetColors() end

-- Cast time precision, 0..3 decimals (db.castPrecision, saved only when not 1).
function Settings_.SetCastPrecision(p) return GlassUF.Castbar.SetPrecision(p) end

-- A detached cast bar in the exact horizontal middle of the screen.
function Settings_.CenterCast(unit)
    local ok = GlassUF.Castbar.CenterX(unit)
    if ok then GlassUF.Movers.Refresh() end
    return ok
end

-- The player cast bar's extras (#72): "latency" (the block), "latencyText"
-- (its ms figure, on a detached bar) and "pushback" (the +0.4 before the
-- time). Saved only when off.
function Settings_.SetCastOption(key, on)
    local Castbar = GlassUF.Castbar
    if not Castbar.SetOption(key, on) then return false end
    local dbKey = Castbar.DB_KEYS[key]
    if on then GlassUnitFramesDB[dbKey] = nil else GlassUnitFramesDB[dbKey] = false end
    return true
end

-- "show" brings back everything GlassUF hides from Blizzard, the cast bar too.
function Settings_.SetHideBlizzard(hide)
    GlassUnitFramesDB.hideBlizzard = hide and true or false
    if not hide then GlassUnitFramesDB.hideBlizzardCast = nil end
end

local function tweakByKey(key)
    for _, t in ipairs(tweaks()) do if t.key == key then return t end end
end

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
    elseif cmd == "portrait" then
        local unit, mode = arg:match("^(%S+)%s+(%S+)$")
        if unit and Settings_.SetPortraitMode(unit, mode) then
            say(unit .. " portrait " .. mode)
        else
            say("portrait player|target|pet 3d|2d|none")
        end
    elseif cmd == "mark" then
        if Settings_.SetMark(arg) then
            say("raid mark " .. arg)
        else
            say("mark name|top|right (now " .. Frames.markPos .. ")")
        end
    elseif cmd == "body" then
        if Settings_.SetGlassBody(arg) then
            say("glass body " .. arg .. ": takes effect after /reload")
        else
            say("body clear|smoked (now " .. GlassUF.body .. ")")
        end
    elseif cmd == "timer" then
        if (arg == "on" or arg == "off") and Settings_.SetCombatTimer(arg == "on") then
            say("combat timer " .. arg)
        else
            say("timer on|off (now " .. (GlassUF.Timer.enabled and "on" or "off") .. ")")
        end
    elseif cmd == "regen" then
        if not GlassUF.FiveSecond.Built() then
            say("regen: for mana users only")
        elseif (arg == "on" or arg == "off") and Settings_.SetManaRegen(arg == "on") then
            say("mana regen segment " .. arg)
        else
            say("regen on|off (now " .. (GlassUF.FiveSecond.regen and "on" or "off") .. ")")
        end
    elseif cmd == "ramp" then
        if Settings_.SetTrackRamp(arg) then
            say("empty bar ramp: " .. arg)
        elseif not Glass.SetTrackLength then
            say("ramp: needs LibGlass r10 (a newer copy of the library)")
        else
            say("ramp whole|edge (now " .. (GlassUnitFramesDB.trackRamp or "whole") .. ")")
        end
    elseif cmd == "look" then
        if Settings_.SetLook(arg) then
            say("look " .. arg .. ": takes effect after /reload")
        else
            say("look classic|clean (now " .. GlassUF.look .. ")")
        end
    elseif tweakByKey(cmd) then
        local t = tweakByKey(cmd)
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
    elseif cmd == "preview" then
        Settings_.SetPreview(not GlassUF.Preview.active)
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
        for _, t in ipairs(tweaks()) do say(string.format("/glass %s %s  - %s (saved)", t.key, rangeText(t), t.help)) end
    end
end

SLASH_GLASSUNITFRAMES1 = "/glass"
SlashCmdList.GLASSUNITFRAMES = slash

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        -- The look first: the knobs, the font and every surface belong to its instance.
        if type(GlassUnitFramesDB) == "table" then
            GlassUF.UseLook(GlassUnitFramesDB.look, GlassUnitFramesDB.glassBody)
        end
        local db = ensureDefaults()
        Glass.SetFont(db.font)
        -- Before the build, so every bar is born with its ramp (#117). Junk is
        -- forgotten; a saved "edge" an older winning LibGlass can't draw is kept.
        if not GlassUF.RAMPS[db.trackRamp] then db.trackRamp = nil end
        if db.trackRamp then Settings_.SetTrackRamp(db.trackRamp) end
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
        GlassUF.Preview.OnCombat()   -- a loading screen ends the preview (#109)
        -- The combat zoom's starting state (a /reload in combat, #89).
        GlassUF.Zoom.OnCombat(InCombatLockdown())
        -- arg1 = isInitialLogin: warn at a real login, never on /reload. Dev
        -- copies only: re-measuring the client is a chore a player can't do.
        if arg1 and API.IsDevBuild() and API.ClientBuild() ~= GlassUF.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " is newer than the one this addon was measured on ("
                .. GlassUF.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The preview first (#109): its unit buttons get their watch back while
        -- the lockdown isn't on yet (measured: false inside this handler).
        GlassUF.Preview.OnCombat()
        GlassUF.Movers.OnCombat()   -- unlock mode ends: protected frames can't move in combat
        GlassUF.Zoom.OnCombat(true)   -- then the bars go to their combat spots (#89)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Home first, so queued work places bars at home (#89). Before the
        -- lockdown guard: the zoom touches no protected frame, and a REGEN_ENABLED
        -- seen with lockdown still reported must not leave the bars zoomed.
        GlassUF.Zoom.OnCombat(false)
        if InCombatLockdown() then return end   -- trust the lockdown state, not the event
        runPending()
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })
