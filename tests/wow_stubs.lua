-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump; defining
--   something Forever lacks is how a missing API survives into a build.
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - PROTECTED frames: secure-template frames and their ancestors. Touching one
--   under InCombatLockdown() is recorded in WoW.blocked instead of applied.
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare.
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GLASSUF_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70009.md"

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end
function WoW.IsSecret(v) return secrets[v] ~= nil end

--------------------------------------------------------------------------------
-- Known events (from the dump when present)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
WoW.dumpAvailable = false
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
        WoW.dumpAvailable = next(WoW.KNOWN_EVENTS) ~= nil
    end
    if not WoW.dumpAvailable then
        for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", "UNIT_PET", "UNIT_HEALTH",
            "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
            "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_LEVEL", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED",
            "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
            "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
            "UNIT_SPELLCAST_CHANNEL_STOP" }) do WoW.KNOWN_EVENTS[e] = true end
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.blocked = {}
    WoW.chat = {}
    WoW.timers = {}
    WoW.unitWatch = {}
    WoW.methodsCalled = {}
    WoW.combat = false
    WoW.shift = false
    WoW.secretFields = {}     -- field -> true: that unit field comes back secret for every unit
    WoW.units = {}
    WoW.raid = nil
    WoW.loot = nil
    rawset(_G, "EditModeManagerFrame", nil)
    if UIParent then WoW.CreateBlizzardFrames() end
end

-- Unit fields: exists, health, maxHealth, power, maxPower, powerToken, name,
-- class, player, reaction, dead, connected, visible, tapDenied,
-- casting = { name, channel, remaining }.
function WoW.SetUnit(token, t)
    if t == nil then WoW.units[token] = nil return end
    local u = { exists = true, health = 1000, maxHealth = 1000, power = 500, maxPower = 500,
                powerToken = "MANA", name = token, class = "WARRIOR", player = false, reaction = 5,
                dead = false, connected = true, visible = true, tapDenied = false,
                level = 10, classification = "normal", afk = false,
                leader = false, assistant = false, pvp = false, ffa = false, faction = "Horde" }
    for k, v in pairs(t) do u[k] = v end
    WoW.units[token] = u
end

local function unitField(token, field)
    local u = WoW.units[token]
    if not u then return nil end
    local v = u[field]
    if WoW.secretFields[field] and v ~= nil then return WoW.Secret(token .. "." .. field) end
    return v
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- shared implementations, by method name

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

local function isProtected(w)
    return w._protected == true
end

local function guard(w, what)
    if WoW.combat and isProtected(w) then
        table.insert(WoW.blocked, (w._name or w._type) .. ":" .. what)
        return false
    end
    return true
end

local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end  -- fields read as nil
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    local w = setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                             _attrs = {}, _scripts = {}, _events = {}, _unitEvents = {},
                             _level = parent and parent._level and (parent._level + 1) or 1,
                             _width = 0, _height = 0, _name = name }, widgetMT)
    return w
end

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    if template and template:find("Secure") then
        local p = w
        while p do p._protected = true; p = p._parent end
    end
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    table.insert(WoW.frames, w)
    if name then rawset(_G, name, w) end
    return w
end

-- Visibility / layout (guarded on protected frames).
function Methods.Show(w) if guard(w, "Show") then w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end end end
function Methods.Hide(w) if guard(w, "Hide") then w._shown = false end end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) if guard(w, "SetPoint") then table.insert(w._points, { ... }) end end
function Methods.ClearAllPoints(w) if guard(w, "ClearAllPoints") then w._points = {} end end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if not p then return nil end
    local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4], p[5]
    if type(rel) ~= "table" and type(rel) ~= "string" then
        -- SetPoint(point, x, y) short form is not used by the addon.
    end
    return point, rel, relPoint, x, y
end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) if guard(w, "SetSize") then w._width, w._height = x, y end end
function Methods.SetWidth(w, x) if guard(w, "SetWidth") then w._width = x end end
function Methods.SetHeight(w, y) if guard(w, "SetHeight") then w._height = y end end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.GetEffectiveScale() return 0.64 end

-- Scripts and events.
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.RegisterUnitEvent(w, e, unit)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._unitEvents[e] = unit
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil; w._unitEvents[e] = nil end
function Methods.UnregisterAllEvents(w) w._events = {}; w._unitEvents = {}; w._silenced = true end
function Methods.SetParent(w, p) if guard(w, "SetParent") then w._parent = p end end
function Methods.GetParent(w) return w._parent end
function Methods.GetName(w) return w._name end
function Methods.IsProtected(w) return w._protected == true end

-- Secure attributes and clicks.
function Methods.SetAttribute(w, k, v) if guard(w, "SetAttribute") then w._attrs[k] = v end end
function Methods.GetAttribute(w, k) return w._attrs[k] end
function Methods.RegisterForClicks(w, ...) if guard(w, "RegisterForClicks") then w._clicks = { ... } end end
function Methods.StartMoving(w) if guard(w, "StartMoving") then w._moving = true end end
function Methods.StopMovingOrSizing(w)
    if guard(w, "StopMovingOrSizing") then
        w._moving = false
        w._points = { { "TOPLEFT", "UIParent", "BOTTOMLEFT", 111, 222 } }   -- where the drag "left" it
    end
end

-- Regions.
function Methods.CreateTexture(w) local t = newWidget("Texture", w); return t end
function Methods.CreateMaskTexture(w) local t = newWidget("MaskTexture", w); return t end
function Methods.CreateFontString(w) local t = newWidget("FontString", w); return t end
function Methods.CreateAnimationGroup(w)
    local ag = newWidget("AnimationGroup", w)
    ag._plays = 0
    return ag
end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.Play(ag) ag._plays = (ag._plays or 0) + 1 end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2)
    assert(type(c1) == "table" and type(c2) == "table", "SetGradient takes color objects on this API")
    t._gradient = { orientation, c1, c2 }
end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end

-- FontString: the client formats natively and accepts secrets. Model that:
-- with any secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
function Methods.SetText(fs, text) fs._text = text end
function Methods.GetText(fs) return fs._text end
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end
function Methods.GetFont(fs) if fs._font then return fs._font[1], fs._font[2], fs._font[3] end end

-- StatusBar: takes values (secret or not) without inspecting them.
function Methods.SetMinMaxValues(b, lo, hi) b._min, b._max = lo, hi end
function Methods.GetMinMaxValues(b) return b._min, b._max end
function Methods.SetValue(b, v) b._value = v end
function Methods.GetValue(b) return b._value end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end
function Methods.SetStatusBarColor(b, r, g, bl) b._color = { r, g, bl } end
function Methods.SetTimerDuration(b, d, interp, dir) b._timer = { duration = d, interp = interp, dir = dir } end

-- PlayerModel.
function Methods.SetUnit(m, unit) m._modelUnit = unit; return true end
function Methods.ClearModel(m) m._modelUnit = nil end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
Enum = {
    LuaCurveType = { Linear = 0 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    UITextureSliceMode = { Stretched = 0, Tiled = 1 },
    LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 },
}
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetBuildInfo() return "1.60.1", "70009", "Sep 23 2026", 16001 end
function InCombatLockdown() return WoW.combat end
function IsShiftKeyDown() return WoW.shift end
function RegisterUnitWatch(frame) WoW.unitWatch[frame] = true end
function UnregisterUnitWatch(frame) WoW.unitWatch[frame] = nil; frame._unwatched = true end

-- Post-hook a method, as the client does: the original runs first.
function hooksecurefunc(t, name, fn)
    local orig = t[name]
    rawset(t, name, function(self, ...)
        local r = orig(self, ...)
        fn(self, ...)
        return r
    end)
end

-- Blizzard's own unit frames: secure (protected) buttons under UIParent,
-- watched by the client. EditModeManagerFrame stays absent unless a test
-- opens Edit Mode with WoW.SetEditMode.
-- name -> unit the client watches it for (ComboFrame is not unit-watched).
local BLIZZARD_FRAMES = { { "PlayerFrame", "player" }, { "PetFrame", "pet" }, { "TargetFrame", "target" },
                          { "ComboFrame" }, { "TargetFrameToT", "targettarget" },
                          { "FocusFrame", "focus" }, { "FocusFrameToT", "focustarget" } }
function WoW.CreateBlizzardFrames()
    for _, spec in ipairs(BLIZZARD_FRAMES) do
        local f = CreateFrame("Button", spec[1], UIParent, "SecureUnitButtonTemplate")
        f._blizzard = true
        f.healthbar = CreateFrame("StatusBar", nil, f)
        f.manabar = CreateFrame("StatusBar", nil, f)
        if spec[2] then
            f._attrs.unit = spec[2]
            WoW.unitWatch[f] = true
        end
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    UIParent._protected = nil   -- the client's UIParent is not protected by its children
end
function WoW.SetEditMode(open)
    if open and not rawget(_G, "EditModeManagerFrame") then
        rawset(_G, "EditModeManagerFrame", newWidget("Frame", UIParent, "EditModeManagerFrame"))
    end
    local em = rawget(_G, "EditModeManagerFrame")
    if em then em._shown = open end
end

C_Timer = { After = function(s, fn) table.insert(WoW.timers, fn) end }
function WoW.flushTimers()
    local run = WoW.timers
    WoW.timers = {}
    for _, fn in ipairs(run) do fn() end
end

C_ClassColor = { GetClassColor = function(cls)
    if type(cls) ~= "string" then error("bad class") end
    return { r = 0.53, g = 0.53, b = 0.93 }
end }

C_CurveUtil = { CreateCurve = function()
    local c = { points = {} }
    function c:SetType(t) self.type = t end
    function c:AddPoint(x, y) table.insert(self.points, { x, y }) end
    return c
end }

function UnitExists(u) return WoW.units[u] ~= nil end
function UnitHealth(u) return unitField(u, "health") end
function UnitHealthMax(u) return unitField(u, "maxHealth") end
function UnitPower(u) return unitField(u, "power") end
function UnitPowerMax(u) return unitField(u, "maxPower") end
function UnitPowerType(u) return 0, unitField(u, "powerToken") end
function UnitHealthPercent(u, predicted, curve)
    local h, m = unitField(u, "health"), unitField(u, "maxHealth")
    if h == nil then return nil end
    if secrets[h] or secrets[m] then return WoW.Secret(u .. ".healthPercent") end
    local frac = (m and m > 0) and h / m or 0
    local p1, p2 = curve.points[1], curve.points[2]
    return p1[2] + (p2[2] - p1[2]) * frac
end
function AbbreviateNumbers(n)
    if secrets[n] then return WoW.Secret("abbreviated") end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(n)
end
function GetUnitName(u) return unitField(u, "name") end
function UnitClass(u) return unitField(u, "name"), unitField(u, "class"), 1 end
function UnitIsPlayer(u) return unitField(u, "player") end
function UnitReaction(u) return unitField(u, "reaction") end
function UnitIsConnected(u) return unitField(u, "connected") end
function UnitIsDeadOrGhost(u) return unitField(u, "dead") end
function UnitIsTapDenied(u) return unitField(u, "tapDenied") end
function UnitIsVisible(u) return unitField(u, "visible") end
function UnitLevel(u) return unitField(u, "level") end
function UnitClassification(u) return unitField(u, "classification") end
function UnitIsAFK(u) return unitField(u, "afk") end
function UnitPowerPercent(u, powerType, unmodified, curve)
    local p, m = unitField(u, "power"), unitField(u, "maxPower")
    if p == nil then return nil end
    if secrets[p] or secrets[m] then return WoW.Secret(u .. ".powerPercent") end
    local frac = (m and m > 0) and p / m or 0
    local p1, p2 = curve.points[1], curve.points[2]
    return p1[2] + (p2[2] - p1[2]) * frac
end
-- Indicators. Unit fields: raidTarget (index or nil), leader, assistant, pvp,
-- ffa, faction. WoW.loot = { method, partyID, raidID } (nil = group loot).
function GetRaidTargetIndex(u) return unitField(u, "raidTarget") end
function SetRaidTargetIconTexture(tex, index) tex._raidIndex = index end
function UnitIsGroupLeader(u) return unitField(u, "leader") end
function UnitIsGroupAssistant(u) return unitField(u, "assistant") end
function UnitIsPVP(u) return unitField(u, "pvp") end
function UnitIsPVPFreeForAll(u) return unitField(u, "ffa") end
function UnitFactionGroup(u) return unitField(u, "faction") end
function UnitIsUnit(a, b) return a == b end
C_PartyInfo = { GetLootMethod = function()
    local l = WoW.loot
    if not l then return Enum.LootMethod.Group end
    return l.method, l.partyID, l.raidID
end }

-- Raid roster: WoW.raid = { [unit] = { index = n, subgroup = g } } while in a raid.
function IsInRaid() return WoW.raid ~= nil end
function UnitInRaid(u) return WoW.raid and WoW.raid[u] and WoW.raid[u].index or nil end
function GetRaidRosterInfo(index)
    for u, r in pairs(WoW.raid or {}) do
        if r.index == index then return unitField(u, "name"), 0, r.subgroup end
    end
end

local function durationFor(u, channel)
    local un = WoW.units[u]
    local c = un and un.casting
    if not c or (c.channel == true) ~= channel then return nil end
    return { GetRemainingDuration = function()
        if WoW.secretFields.castRemaining then return WoW.Secret("remaining") end
        return c.remaining or 1.25
    end }
end
function UnitCastingDuration(u) return durationFor(u, false) end
function UnitChannelDuration(u) return durationFor(u, true) end
function UnitCastingInfo(u)
    local c = WoW.units[u] and WoW.units[u].casting
    if not c or c.channel then return nil end
    if WoW.secretFields.castName then return WoW.Secret("castName") end
    return c.name
end
function UnitChannelInfo(u)
    local c = WoW.units[u] and WoW.units[u].casting
    if not (c and c.channel) then return nil end
    if WoW.secretFields.castName then return WoW.Secret("castName") end
    return c.name
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it, the way the client does.
-- Unit events reach a RegisterUnitEvent frame only for its unit. Errors are
-- NOT caught: a handler that throws fails the test.
function WoW.fire(event, ...)
    local unit = ...
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler then
            if w._events[event] then handler(w, event, ...)
            elseif w._unitEvents[event] ~= nil and w._unitEvents[event] == unit then handler(w, event, ...) end
        end
    end
end

-- Every event any frame registered, fired for every modelled unit.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
        for e in pairs(w._unitEvents) do seen[e] = true end
    end
    for e in pairs(seen) do
        for u in pairs(WoW.units) do WoW.fire(e, u) end
        WoW.fire(e, "player")
    end
    return seen
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

-- The client's unit watch: show/hide watched frames by UnitExists.
function WoW.applyUnitWatch()
    for frame in pairs(WoW.unitWatch) do
        local exists = WoW.units[frame._attrs.unit] ~= nil
        if exists and not frame._shown then
            frame._shown = true
            if frame._scripts.OnShow then frame._scripts.OnShow(frame) end
        elseif not exists then
            frame._shown = false
        end
    end
end

WoW.reset()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
local allowNil = { GlassUF = true, GlassUnitFramesDB = true }
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
