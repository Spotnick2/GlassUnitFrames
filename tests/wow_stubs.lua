-- wow_stubs.lua: GlassUnitFrames' WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The mechanics come from WowTestKit (tests/kit.lua loads the commit
-- tests/kit.pin names; its README is the reference): strict globals, secrets,
-- event names checked against the pinned build, widgets that record every
-- method called, protected frames, print (with the stray-"|" check done()
-- fails on), timers, fire / tick. This file adds GUF's own client APIs (units,
-- casts, heal prediction, the aura container, Blizzard's unit frames, ...),
-- the methods the core doesn't have, and replaces a WoW.Methods entry where a
-- test relies on it.

-- WowTestKit #8: a test that loads this file again for a fresh client
-- (test_cc) keeps its counts: the kit, with its assertions, is loaded once; a
-- reload rebuilds only the stub core.
if rawget(_G, "Kit") and Kit.counts then
    local strays = WoW.strays
    setmetatable(_G, nil)
    dofile(Kit.ROOT .. "/core/stubs.lua")
    for _, line in ipairs(strays) do table.insert(WoW.strays, line) end
else
    dofile("tests/kit.lua")
end
local Methods = WoW.Methods
local newWidget = WoW.newWidget
local secrets = WoW.secrets

function WoW.IsSecret(v) return issecretvalue(v) end

--------------------------------------------------------------------------------
-- Protected frames
--------------------------------------------------------------------------------

-- A secure template protects the frame and every ancestor, as the client does
-- (a frame that parents secure buttons is protected). UIParent is not
-- (WoW.CreateBlizzardFrames clears it).
WoW.templates.SecureUnitButtonTemplate = function(w)
    local p = w
    while p do p._protected = true; p = p._parent end
end

-- WowTestKit #12: a protected frame in combat also refuses resizing,
-- reparenting and SetAttribute (and, below, SetScale, RegisterForClicks,
-- StartMoving and StopMovingOrSizing); each refusal is recorded in
-- WoW.blocked, which the tests assert stays empty. The old stub's guards,
-- kept so those assertions still cover every change the client refuses.
for _, m in ipairs({ "SetSize", "SetWidth", "SetHeight", "SetParent", "SetAttribute" }) do
    local impl = Methods[m]
    Methods[m] = function(w, ...)
        if WoW.refused(w, m) then return end
        if impl then return impl(w, ...) end
    end
end

--------------------------------------------------------------------------------
-- Unit events
--------------------------------------------------------------------------------

-- WowTestKit #17: RegisterUnitEvent. A unit event reaches the frame only for
-- the unit it registered (w._unitEvents[event] = unit); WoW.fire's first
-- payload argument is the unit.
local function knownEvent(e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 3) end
end
function Methods.RegisterUnitEvent(w, e, unit)
    knownEvent(e)
    w._unitEvents = w._unitEvents or {}
    w._unitEvents[e] = unit
    return true
end
local coreUnregisterEvent, coreUnregisterAllEvents = Methods.UnregisterEvent, Methods.UnregisterAllEvents
function Methods.UnregisterEvent(w, e)
    coreUnregisterEvent(w, e)
    if w._unitEvents then w._unitEvents[e] = nil end
end
-- w._silenced: test_blizzard checks Blizzard's frames were silenced.
function Methods.UnregisterAllEvents(w)
    coreUnregisterAllEvents(w)
    w._unitEvents = {}
    w._silenced = true
end

--------------------------------------------------------------------------------
-- Widget methods the core doesn't have, or GUF's on top of the core's
--------------------------------------------------------------------------------

function Methods.GetNumPoints(w) return #w._points end
function Methods.SetScale(w, sc) if not WoW.refused(w, "SetScale") then w._scale = sc end end
function Methods.GetScale(w) return w._scale or 1 end
-- The UI's base scale (WoW.uiScale, 0.64 by default) times every SetScale on
-- the widget and its parents, as the client computes it.
function Methods.GetEffectiveScale(w)
    local s = WoW.uiScale or 0.64
    local p = w
    while p do
        s = s * (p._scale or 1)
        p = p._parent
    end
    return s
end
function Methods.IsProtected(w) return w._protected == true, w._explicit == true end
function Methods.SetClipsChildren(w, v) w._clips = v end
function Methods.RegisterForClicks(w, ...) if not WoW.refused(w, "RegisterForClicks") then w._clicks = { ... } end end
function Methods.StartMoving(w) if not WoW.refused(w, "StartMoving") then w._moving = true end end

-- No real geometry in the stub: a test sets w._center = { x, y } where it matters.
-- With no _center: a frame placed CENTER on UIParent's CENTER resolves as the
-- client would, in the frame's own (scaled) units; UIParent's centre is
-- WoW.uiCenter, in its units.
-- Opt-in anchor layout (WoW.layout = true): a frame's rect resolved from its
-- first point (or SetAllPoints), its size and its scale, as the client lays it
-- out. Worked in screen pixels (units x effective scale), handed back in the
-- frame's own units. UIParent needs _center, _width and _height.
local ANCHOR = { CENTER = { 0, 0 }, TOP = { 0, 1 }, BOTTOM = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 },
                 TOPLEFT = { -1, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { -1, -1 }, BOTTOMRIGHT = { 1, -1 } }
local function screenRect(w, depth)
    if depth > 20 then return nil end
    local e = w:GetEffectiveScale()
    if w._center then return w._center[1] * e, w._center[2] * e, (w._width or 0) * e / 2, (w._height or 0) * e / 2 end
    local p = w._points[1]
    if not p or w == UIParent then return nil end
    local rel = p[2] == "UIParent" and UIParent or p[2]
    if type(rel) ~= "table" then return nil end
    local rx, ry, rhw, rhh = screenRect(rel, depth + 1)
    if not rx then return nil end
    if p[1] == "ALL" then return rx, ry, rhw, rhh end
    local a, b = ANCHOR[p[1]], ANCHOR[p[3]]
    local hw, hh = (w._width or 0) * e / 2, (w._height or 0) * e / 2
    return rx + b[1] * rhw + (p[4] or 0) * e - a[1] * hw, ry + b[2] * rhh + (p[5] or 0) * e - a[2] * hh, hw, hh
end
local function laidOut(w)
    if not WoW.layout or w._center then return nil end
    local x, y = screenRect(w, 0)
    if not x then return nil end
    local e = w:GetEffectiveScale()
    return x / e, y / e
end

function Methods.GetCenter(w)
    if w._center then return w._center[1], w._center[2] end
    local lx, ly = laidOut(w)
    if lx then return lx, ly end
    local pt = w._points[1]
    if pt and pt[1] == "CENTER" and pt[2] == UIParent and pt[3] == "CENTER" and w ~= UIParent then
        local ux, uy = UIParent:GetCenter()
        if not ux then return nil end
        local k = UIParent:GetEffectiveScale() / w:GetEffectiveScale()
        return ux * k + (pt[4] or 0), uy * k + (pt[5] or 0)
    end
end
-- Edges from a test-set centre and the frame's size (no real layout here).
local function edge(w, axis, sign)
    local cx, cy = laidOut(w)
    if cx then
        if axis == "x" then return cx + sign * (w._width or 0) / 2 end
        return cy + sign * (w._height or 0) / 2
    end
    if not (w._center and w._width and w._height) then return nil end
    if axis == "x" then return w._center[1] + sign * w._width / 2 end
    return w._center[2] + sign * w._height / 2
end
function Methods.GetRect(w)
    local l, b = edge(w, "x", -1), edge(w, "y", -1)
    if not (l and b) then return nil end
    return l, b, w._width or 0, w._height or 0
end
function Methods.GetLeft(w) return edge(w, "x", -1) end
function Methods.GetRight(w) return edge(w, "x", 1) end
function Methods.GetBottom(w) return edge(w, "y", -1) end
function Methods.GetTop(w) return edge(w, "y", 1) end
function Methods.StopMovingOrSizing(w)
    if not WoW.refused(w, "StopMovingOrSizing") then
        w._moving = false
        w._points = { { "TOPLEFT", "UIParent", "BOTTOMLEFT", 111, 222 } }   -- where the drag "left" it
    end
end

-- Regions. WoW.fontStrings lists every font string, so a test can find a page's texts.
local coreCreateFontString = Methods.CreateFontString
function Methods.CreateFontString(w, ...)
    local t = coreCreateFontString(w, ...)
    table.insert(WoW.fontStrings, t)
    return t
end
-- An animation group counts its plays (ag._plays), on top of the core's state:
-- the sheen tests count replays.
local corePlay = Methods.Play
function Methods.Play(ag) corePlay(ag); ag._plays = (ag._plays or 0) + 1 end
function Methods.SetTexCoord(t, ...) t._texCoord = { ... } end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end

-- A rough wrap: about 7 units a character, 14 a line, at the string's width.
function Methods.GetStringHeight(fs)
    local w, text = fs._width, fs._text
    if type(text) ~= "string" or text == "" then return 0 end
    if not w or w <= 0 then return 14 end
    return math.ceil(#text * 7 / w) * 14
end
function Methods.LockHighlight(b) b._highlightLocked = true end
function Methods.UnlockHighlight(b) b._highlightLocked = false end
function Methods.SetScrollChild(sf, child) sf._scrollChild = child end
function Methods.GetScrollChild(sf) return sf._scrollChild end
function Methods.SetFocus(e) e._focus = true end
function Methods.ClearFocus(e) e._focus = false end
function Methods.HasFocus(e) return e._focus == true end
-- Button state textures: Set<State>Texture creates the texture, Get<State>Texture returns it.
for _, state in ipairs({ "Normal", "Pushed", "Highlight", "Checked", "Disabled" }) do
    Methods["Set" .. state .. "Texture"] = function(b, file)
        local t = newWidget("Texture", b)
        t._file = file
        b["_" .. state] = t
    end
    Methods["Get" .. state .. "Texture"] = function(b) return b["_" .. state] end
end

-- StatusBar: takes values (secret or not) without inspecting them, and keeps
-- the interpolation each call was given (the tests check snaps and eases).
function Methods.SetMinMaxValues(b, lo, hi, interp) b._min, b._max, b._minMaxInterp = lo, hi, interp end
function Methods.GetMinMaxValues(b) return b._min, b._max end
local coreSetValue = Methods.SetValue
function Methods.SetValue(b, v, interp)
    coreSetValue(b, v)
    b._interp = interp
end
function Methods.SetReverseFill(b, on) b._reverse = on end
function Methods.GetReverseFill(b) return b._reverse end
-- WowTestKit #19: the client sets the fill's vertex colour, which replaces
-- the gradient that held the fill's opacity (measured in game, LibGlass#64);
-- test_frames' "recolouring keeps the fill opacity" relies on it.
function Methods.SetStatusBarColor(b, r, g, bl, a)
    b._color = { r, g, bl }
    if b._fill then b._fill._gradient, b._fill._vertex = nil, { r, g, bl, a } end
end
function Methods.SetTimerDuration(b, d, interp, dir) b._timer = { duration = d, interp = interp, dir = dir } end

--------------------------------------------------------------------------------
-- Units
--------------------------------------------------------------------------------

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

-- PlayerModel (and the aura container: both take a unit).
local function seq(w, what) w._seq = w._seq or {}; table.insert(w._seq, what) end
function Methods.SetUnit(m, unit) m._modelUnit = unit; seq(m, "SetUnit"); return true end
-- A model file for the unit set, unless the unit says it has none
-- (WoW.units[u].noModel: the Earthborer case, #82).
function Methods.GetModelFileID(m)
    local un = m._modelUnit and WoW.units[m._modelUnit]
    if not un or un.noModel then return nil end
    return 123456
end

-- Blizzard's managed aura container (Blizzard_AuraContainer; not in the API
-- dump, shipped by DinoUF on Forever). It records its groups; the client
-- would create buttons and call initializeFrame on each.
function Methods.AddAuraGroup(c, name, filter, spec)
    c._groups = c._groups or {}
    c._groups[name] = { filter = filter, spec = spec }
    seq(c, "AddAuraGroup")
end
function Methods.UpdateAllAuras(c) c._refreshes = (c._refreshes or 0) + 1; seq(c, "UpdateAllAuras") end
function Methods.SetIcon(b, t) b._icon = t end
function Methods.SetDurationCooldown(b, cd) b._cooldown = cd end
function Methods.SetDurationText(b, fs) b._durationText = fs end
function Methods.SetApplicationCount(b, fs) b._countText = fs end
function Methods.ClearModel(m) m._modelUnit = nil end
-- dump: SetPortraitTexture(textureObject, unitToken, disableMasking)
function SetPortraitTexture(tex, unit) tex._portraitUnit = unit end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

SlashCmdList = {}
Enum = {
    LuaCurveType = { Linear = 0 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
    UITextureSliceMode = { Stretched = 0, Tiled = 1 },
}
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetBuildInfo() return "1.60.1", "70450", "Oct 15 2026", 16001 end
-- For LibTaxiTime-1.0 (#153; dump 70532): server time follows the frame
-- time; WoW.onTaxi says the player is on a taxi.
function GetServerTime() return 1800000000 + math.floor(WoW.now) end
function IsPlayerInWorld() return true end
function UnitOnTaxi(unit) return unit == "player" and WoW.onTaxi == true end
function GetNetStats() return unpack(WoW.netStats) end
-- Plain out of combat (6.501, 0.001 on a level-10 druid), secret in combat: measured, #94.
function GetManaRegen() return 6.501, 0.001 end
function IsShiftKeyDown() return WoW.shift end
function IsAltKeyDown() return WoW.alt == true end
-- The client refuses both under lockdown: recorded in WoW.blocked, not applied.
function RegisterUnitWatch(frame)
    if WoW.combat then table.insert(WoW.blocked, (frame._name or frame._type) .. ":RegisterUnitWatch") return end
    WoW.unitWatch[frame] = true
end
function UnregisterUnitWatch(frame)
    if WoW.combat then table.insert(WoW.blocked, (frame._name or frame._type) .. ":UnregisterUnitWatch") return end
    WoW.unitWatch[frame] = nil; frame._unwatched = true
end

-- Blizzard's own unit frames: secure (protected) buttons under UIParent,
-- watched by the client. EditModeManagerFrame stays absent unless a test
-- opens Edit Mode with WoW.SetEditMode.
-- name -> unit the client watches it for (ComboFrame is not unit-watched),
-- then the Blizzard parent when it isn't UIParent (the forever branch of
-- wow-ui-source: PetFrame sits in PlayerFrame's managed container).
local BLIZZARD_FRAMES = { { "PlayerFrame", "player" }, { "PetFrame", "pet", "PlayerFrame" },
                          { "TargetFrame", "target" }, { "ComboFrame" },
                          { "TargetFrameToT", "targettarget", "TargetFrame" },
                          { "FocusFrame", "focus" }, { "FocusFrameToT", "focustarget", "FocusFrame" },
                          { "PlayerCastingBarFrame" } }
function WoW.CreateBlizzardFrames()
    for _, spec in ipairs(BLIZZARD_FRAMES) do
        local parent = spec[3] and _G[spec[3]] or UIParent
        local f = CreateFrame("Button", spec[1], parent, "SecureUnitButtonTemplate")
        f._blizzard = true
        -- ManagedFrameTemplate's key (PlayerBottomManagedFrameTemplate / BottomManagedFrameTemplate).
        if spec[1] == "PetFrame" or spec[1] == "PlayerCastingBarFrame" then f.isManagedFrame = true end
        f.healthbar = CreateFrame("StatusBar", nil, f)
        f.manabar = CreateFrame("StatusBar", nil, f)
        if spec[2] then
            f._attrs = { unit = spec[2] }
            WoW.unitWatch[f] = true
        end
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    -- Blizzard's mirror timers (Blizzard_MirrorTimer): an Edit Mode system, not a unit frame.
    local mc = CreateFrame("Frame", "MirrorTimerContainer", UIParent)
    mc._blizzard = true
    for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE" }) do
        mc:RegisterEvent(ev)
    end
    UIParent._protected = nil   -- the client's UIParent is not protected by its children
end

-- The mirror timers (dump 70532): GetMirrorTimerInfo(index) -> name, startValue,
-- maxValue, scale, paused, label, spellID ("UNKNOWN" when idle);
-- GetMirrorTimerProgress(name) -> optional progress (ms). WoW.mirror[name] =
-- { index, value, max, scale, paused, label }; WoW.secretFields.mirror makes
-- the values secret.
function GetMirrorTimerInfo(i)
    for name, t in pairs(WoW.mirror) do
        if t.index == i then
            local s = WoW.secretFields.mirror
            return name, s and WoW.Secret("value") or t.value, s and WoW.Secret("max") or t.max, t.scale or -1,
                t.paused or 0, t.label or name, 0
        end
    end
    return "UNKNOWN", 0, 0, 0, 0, "", 0
end
function GetMirrorTimerProgress(name)
    local t = WoW.mirror[name]
    if not t then return nil end
    if WoW.secretFields.mirror then return WoW.Secret("progress") end
    return t.value
end
function WoW.SetEditMode(open)
    if open and not rawget(_G, "EditModeManagerFrame") then
        rawset(_G, "EditModeManagerFrame", newWidget("Frame", UIParent, "EditModeManagerFrame"))
    end
    local em = rawget(_G, "EditModeManagerFrame")
    if em then em._shown = open end
end


--------------------------------------------------------------------------------
-- Timers: the core's C_Timer.After records ({ s, fn, at }), run by its
-- WoW.flushTimers / WoW.advance, plus GUF's two helpers on top
--------------------------------------------------------------------------------

-- WoW.runDue(): one pass over the timers due by WoW.now (at <= now), in the
-- order they were scheduled, keeping the rest; one scheduled inside waits for
-- the next pass. The timing tests move WoW.now by hand and call it.
function WoW.runDue()
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if (t.at or 0) <= WoW.now then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do if not t.cancelled then t.fn() end end
end

-- WoW.tickTickers(): one tick of every live ticker (the core's C_Timer.NewTicker
-- records, those with `every`), each left in place. The core records a ticker
-- once, like a timer: WoW.flushTimers / WoW.advance run it and drop it
-- (WowTestKit #18: on the client it repeats); no test relies on a repeat yet.
function WoW.tickTickers()
    for _, t in ipairs(WoW.timers) do
        if t.every and not t.cancelled then t.fn() end
    end
end

-- C_DurationUtil.CreateDuration() -> LuaDurationObject (dump 70338): the
-- methods the addon uses. A test reads _start / _dur.
C_DurationUtil = { CreateDuration = function()
    local d = {}
    function d:SetTimeFromStart(startTime, duration) self._start, self._dur = startTime, duration end
    function d:GetRemainingDuration() return math.max(0, (self._start or 0) + (self._dur or 0) - WoW.now) end
    function d:GetTotalDuration() return self._dur or 0 end
    function d:HasSecretValues() return false end
    return d
end }

-- C_Spell.GetSpellPowerCost(spellID) -> powerCosts (dump 70338; measured
-- plain, entries { type, cost, minCost, costPerSec }). WoW.spellCosts drives it.
C_Spell = { GetSpellPowerCost = function(id)
    local c = WoW.spellCosts[id]
    if c == "error" then error("GetSpellPowerCost failed") end
    return c
end }
-- C_Spell.GetSpellCooldown(spell) -> SpellCooldownInfo { startTime, duration,
-- isEnabled, isActive, modRate, isOnGCD (NeverSecret) } and
-- GetSpellCooldownDuration(spell, ignoreGCD) -> LuaDurationObject (dump 70532).
-- WoW.cooldowns[id] = { isActive, isOnGCD, start, duration } drives them.
function C_Spell.GetSpellCooldown(id)
    local cd = WoW.cooldowns[id]
    if cd == "error" then error("GetSpellCooldown failed") end
    if not cd then return { startTime = 0, duration = 0, isEnabled = true, isActive = false, modRate = 1 } end
    return { startTime = cd.start or 0, duration = cd.duration or 0, isEnabled = true,
             isActive = cd.isActive == true, modRate = 1, isOnGCD = cd.isOnGCD }
end
function C_Spell.GetSpellCooldownDuration(id, ignoreGCD)
    local cd = WoW.cooldowns[id]
    if type(cd) ~= "table" then return nil end
    local d = C_DurationUtil.CreateDuration()
    d:SetTimeFromStart(cd.start or WoW.now, cd.duration or 0)
    if cd.secret then
        function d:GetRemainingDuration() return WoW.Secret("cooldownRemaining") end
        function d:HasSecretValues() return true end
    end
    return d
end
-- C_Spell.IsSpellInRange(spell, optional unit) -> optional inRange (dump
-- 70532). WoW.inRange[unit] drives it (nil = unknown; "secret"; "error").
function C_Spell.IsSpellInRange(id, unit)
    WoW.rangeAsked[#WoW.rangeAsked + 1] = { id, unit }
    local r = WoW.inRange[unit]
    if r == "error" then error("IsSpellInRange failed") end
    if r == "secret" then return WoW.Secret("inRange") end
    return r
end

-- GetPlayerInfoByGUID(guid) -> localizedClass, englishClass, localizedRace,
-- englishRace, sex, name, realmName, level (dump 70532). WoW.players[guid].
function GetPlayerInfoByGUID(guid)
    local p = WoW.players[guid]
    if not p then return nil end
    return "Mage", "MAGE", "Human", "Human", 2, p.name, p.realm or "", p.level
end
-- C_Spell.IsSpellCrowdControl(spell) -> isCrowdControl (dump 70532): the
-- Vanilla CC ids in WoW.ccSpells.
function C_Spell.IsSpellCrowdControl(id) return WoW.ccSpells[id] == true end

-- The swing timer API (dump 70338): EnableRangeCheck(swingType, enable),
-- IsTargetWithinSwingRange(swingType) -> optional isInRange.
C_SwingTimer = {
    EnableRangeCheck = function(t, on) table.insert(WoW.rangeChecks, { t, on }) end,
    IsTargetWithinSwingRange = function(t) return WoW.swingInRange[t] end,
}

-- The profession batch (dump 70338): GetRemainingRecasts() -> remaining,
-- IsRecipeRepeating() -> bool; WoW.recasts / WoW.repeating drive them.
C_TradeSkillUI = {
    GetRemainingRecasts = function() return WoW.recasts end,
    IsRecipeRepeating = function() return WoW.repeating == true end,
}

-- CVars (dump 70338): GetCVarBool(name) -> optional bool; SetCVar(name, value)
-- -> success, firing CVAR_UPDATE(name, value) as the client does.
C_CVar = {
    GetCVarBool = function(name)
        local v = WoW.cvars[name]
        if v == nil then return nil end
        return v == "1"
    end,
    SetCVar = function(name, value)
        if WoW.cvarRefused then return false end
        WoW.cvars[name] = value
        WoW.fire("CVAR_UPDATE", name, value)
        return true
    end,
}
C_ClassColor = { GetClassColor = function(cls)
    if type(cls) ~= "string" then error("bad class") end
    return { r = 0.53, g = 0.53, b = 0.93 }
end }

C_CurveUtil = { CreateCurve = function()
    local c = { points = {} }
    function c:SetType(t) self.type = t end
    function c:AddPoint(x, y) table.insert(self.points, { x, y }) end
    return c
end, CreateColorCurve = function()
    local c = { points = {}, color = true }
    function c:SetType(t) self.type = t end
    function c:AddPoint(x, col) table.insert(self.points, { x, col }) end
    return c
end }
-- A colour-curve result: a colour object; its components secret when the input was.
local function curveColor(col, secret)
    return { GetRGBA = function()
        if secret then return WoW.Secret("r"), WoW.Secret("g"), WoW.Secret("b"), WoW.Secret("a") end
        return col.r, col.g, col.b, col.a
    end }
end
-- Step evaluation: the last point at or below x. NOTE: a 0/0 unit is modelled
-- as fraction 0 here; what the real client returns for max 0 is UNMEASURED
-- (#27's in-game check), so tests built on it only prove our side.
local function evalColor(curve, x)
    local col = curve.points[1][2]
    for _, pt in ipairs(curve.points) do if x >= pt[1] then col = pt[2] end end
    return col
end

function UnitExists(u) return WoW.units[u] ~= nil end
function UnitGUID(u)
    local un = WoW.units[u]
    if not un then return nil end
    if WoW.secretFields.guid then return WoW.Secret(u .. ".guid") end
    return un.guid or ("GUID-" .. tostring(un.name))
end
function UnitHealth(u) return unitField(u, "health") end
function UnitHealthMax(u) return unitField(u, "maxHealth") end
-- Power by type: 0 = mana (fields mana / maxMana, else the display power),
-- 4 = combo points (field combo, max 5); none = the display power.
local function powerFields(u, t)
    if t == 4 then return "combo", nil end
    if t == 0 and WoW.units[u] and WoW.units[u].mana ~= nil then return "mana", "maxMana" end
    return "power", "maxPower"
end
function UnitPower(u, t) return unitField(u, (powerFields(u, t))) end
function UnitPowerMax(u, t)
    local _, mf = powerFields(u, t)
    if mf == nil then return WoW.units[u] and 5 or nil end
    return unitField(u, mf)
end
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
-- Forever's UnitName: the first name, with the surname where the realm
-- should be (CLAUDE.md); dump: UnitName(unit) -> unitName, unitServer.
function UnitName(u)
    local n = unitField(u, "name")
    if type(n) ~= "string" then return n end
    local first, rest = n:match("^(%S+)%s+(.+)$")
    if first then return first, rest end
    return n, nil
end
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
    local pf, mf = powerFields(u, powerType)
    local p, m = unitField(u, pf), nil
    if pf == "combo" then m = 5 else m = unitField(u, mf) end
    if powerType == 4 and p == nil and WoW.units[u] then p = 0 end
    if p == nil then return nil end
    if curve.color then
        if secrets[p] or secrets[m] then
            -- The stub still knows the real numbers behind the fields it made secret.
            local rp, rm = WoW.units[u][pf] or 0, mf and WoW.units[u][mf] or 5
            return curveColor(evalColor(curve, (rm and rm > 0 and not secrets[rp]) and rp / rm or 0), true)
        end
        return curveColor(evalColor(curve, (m and m > 0) and p / m or 0), false)
    end
    if secrets[p] or secrets[m] then return WoW.Secret(u .. ".powerPercent") end
    local frac = (m and m > 0) and p / m or 0
    local p1, p2 = curve.points[1], curve.points[2]
    return p1[2] + (p2[2] - p1[2]) * frac
end
-- Indicators. Unit fields: raidTarget (index or nil), leader, assistant, pvp,
-- ffa, faction. WoW.masterLooter: the player is master looter.
function GetRaidTargetIndex(u) return unitField(u, "raidTarget") end
function SetRaidTargetIconTexture(tex, index) tex._raidIndex = index end
function Methods.SetSpriteSheetCell(t, cell, rows, cols) t._raidIndex, t._sheet = cell, { rows, cols } end
function UnitIsGroupLeader(u) return unitField(u, "leader") end
function UnitIsGroupAssistant(u) return unitField(u, "assistant") end
function UnitIsPVP(u) return unitField(u, "pvp") end
function UnitIsPVPFreeForAll(u) return unitField(u, "ffa") end
function UnitFactionGroup(u) return unitField(u, "faction") end
function IsMasterLooter() return WoW.masterLooter == true end
function IsResting() return WoW.resting == true end
-- #28. Unit fields: threat (the player's UnitThreatSituation on that mob,
-- nil = not on its list), ownThreat (UnitThreatSituation(unit)), combat.
function UnitThreatSituation(u, mob)
    if mob == nil then return unitField(u, "ownThreat") end
    if u ~= "player" then return nil end   -- the `threat` field models the player's threat only
    return unitField(mob, "threat")
end
function UnitAffectingCombat(u) return unitField(u, "combat") end
-- Hunter pet happiness. WoW.petHappiness (1-3 or nil), WoW.hunterPet.
C_PetInfo = { GetPetHappiness = function()
    if WoW.secretFields.happiness and WoW.petHappiness then return WoW.Secret("happiness") end
    return WoW.petHappiness, 0, 0
end }
function HasPetUI() return WoW.units.pet ~= nil, WoW.hunterPet == true end
function UnitIsUnit(a, b)
    local ua, ub = WoW.units[a], WoW.units[b]
    return ua ~= nil and ua == ub
end
-- Retail's Settings framework (names from the dump's _G walk; signatures as
-- Priestly uses them on Forever). WoW.settings records what the addon did.
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local c = { frame = frame, name = name }
        function c:GetID() return 4242 end
        WoW.settings.canvas = c
        return c
    end,
    RegisterAddOnCategory = function(c) WoW.settings.addon = c end,
    -- A sub-page (GlassRaidFrames ships these on Forever): recorded in order.
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        local c = { parent = parent, frame = frame, name = name }
        WoW.settings.subs = WoW.settings.subs or {}
        table.insert(WoW.settings.subs, c)
        return c
    end,
    OpenToCategory = function(id) WoW.settings.opened = id end,
}
C_Texture = { GetAtlasExists = function(name) return WoW.atlases[name] == true end }

-- Retail's EventRegistry (CallbackRegistryMixin): with an owner, a callback
-- gets it first, then the event's arguments.
EventRegistry = {
    RegisterCallback = function(self, event, fn, owner)
        WoW.callbacks[event] = WoW.callbacks[event] or {}
        table.insert(WoW.callbacks[event], { fn, owner })
    end,
    TriggerEvent = function(self, event, ...)
        for _, cb in ipairs(WoW.callbacks[event] or {}) do cb[1](cb[2], ...) end
    end,
}
C_AddOns = {
    IsAddOnLoaded = function(name) return WoW.loadedAddOns[name] == true, WoW.loadedAddOns[name] == true end,
    LoadAddOn = function(name) WoW.loadedAddOns[name] = true; return true end,
    -- WoW.addonVersion is the TOC's Version field (nil = unreadable).
    GetAddOnMetadata = function(name, field)
        if name == "GlassUnitFrames" and field == "Version" then return WoW.addonVersion end
        return nil
    end,
}

-- Raid roster: WoW.raid = { [unit] = { index = n, subgroup = g } } while in a raid.
function IsInRaid() return WoW.raid ~= nil end
function UnitInRaid(u) return WoW.raid and WoW.raid[u] and WoW.raid[u].index or nil end
function GetRaidRosterInfo(index)
    for u, r in pairs(WoW.raid or {}) do
        if r.index == index then return unitField(u, "name"), 0, r.subgroup end
    end
end

-- casting also takes, for the player's own cast (#72): total (s), startMs,
-- endMs, guid, spellID, delayMs. WoW.secretFields.castTimes makes those
-- secret, and the duration report HasSecretValues.
local function durationFor(u, channel)
    local un = WoW.units[u]
    local c = un and un.casting
    if not c or (c.channel == true) ~= channel then return nil end
    return {
        GetRemainingDuration = function()
            if WoW.secretFields.castRemaining then return WoW.Secret("remaining") end
            return c.remaining or 1.25
        end,
        GetTotalDuration = function()
            if WoW.secretFields.castTimes then return WoW.Secret("total") end
            return c.total or 2
        end,
        HasSecretValues = function() return WoW.secretFields.castTimes == true end,
    }
end
function UnitCastingDuration(u) return durationFor(u, false) end

function UnitChannelDuration(u) return durationFor(u, true) end

-- Heal prediction: unit field `incoming` (all healers).
function CreateUnitHealPredictionCalculator()
    local c = { clamp = nil }
    function c:SetIncomingHealClampMode(m) self.clamp = m end
    function c:SetIncomingHealOverflowPercent(p) self.overflow = p end
    function c:GetIncomingHeals()
        return self._incoming, 0, self._incoming, false
    end
    function c:GetMaximumHealth() return self._max end
    return c
end
function UnitGetDetailedHealPrediction(u, healer, calc)
    calc._incoming = unitField(u, "incoming") or 0
    calc._max = unitField(u, "maxHealth")
end
local function castTime(c, field)
    if c[field] ~= nil and WoW.secretFields.castTimes then return WoW.Secret(field) end
    return c[field]
end
-- name, displayName, texture, startMs, endMs, isTradeskill, castID,
-- notInterruptible, spellID, castBarID, delayTimeMs (the dump's order).
function UnitCastingInfo(u)
    local c = WoW.units[u] and WoW.units[u].casting
    if not c or c.channel then return nil end
    if WoW.secretFields.castName then return WoW.Secret("castName") end
    local trade = c.trade or false
    if WoW.secretFields.tradeskill then trade = WoW.Secret("isTradeskill") end
    return c.name, c.name, 136243, castTime(c, "startMs"), castTime(c, "endMs"), trade, c.guid,
        false, c.spellID, nil, castTime(c, "delayMs")
end
-- name, displayName, texture, startMs, endMs, isTradeskill, notInterruptible,
-- spellID, isEmpowered, numEmpowerStages, castBarID.
function UnitChannelInfo(u)
    local c = WoW.units[u] and WoW.units[u].casting
    if not (c and c.channel) then return nil end
    if WoW.secretFields.castName then return WoW.Secret("castName") end
    return c.name, c.name, 136243, castTime(c, "startMs"), castTime(c, "endMs"), false, false,
        c.spellID, false, 0, nil
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- WowTestKit #17: fire an event at every frame registered for it, the way
-- the client does; a unit event reaches a RegisterUnitEvent frame only for
-- its unit. Errors are NOT caught: a handler that throws fails the test.
function WoW.fire(event, ...)
    local unit = ...
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler then
            if w._events[event] then handler(w, event, ...)
            elseif w._unitEvents and w._unitEvents[event] ~= nil and w._unitEvents[event] == unit then
                handler(w, event, ...)
            end
        end
    end
end

-- WowTestKit #17: every event any frame registered, unit events included,
-- fired for every modelled unit and the player.
function WoW.fireAllRegistered()
    local seen = {}
    for _, w in ipairs(WoW.frames) do
        for e in pairs(w._events) do seen[e] = true end
        for e in pairs(w._unitEvents or {}) do seen[e] = true end
    end
    for e in pairs(seen) do
        for u in pairs(WoW.units) do WoW.fire(e, u) end
        WoW.fire(e, "player")
    end
    return seen
end

-- The client's unit watch: show/hide watched frames by UnitExists.
function WoW.applyUnitWatch()
    for frame in pairs(WoW.unitWatch) do
        local exists = WoW.units[frame._attrs and frame._attrs.unit] ~= nil
        if exists and not frame._shown then
            frame._shown = true
            if frame._scripts.OnShow then frame._scripts.OnShow(frame) end
        elseif not exists then
            frame._shown = false
        end
    end
end

--------------------------------------------------------------------------------
-- State the tests set, cleared with the core's (WoW.reset)
--------------------------------------------------------------------------------

local function resetState()
    WoW.fontStrings = {}
    WoW.addonVersion = "dev"
    WoW.onTaxi = nil
    WoW.now = 1000            -- GetTime(): the frame time, advanced by tests
    WoW.netStats = { 3.4, 0.15, 29, 33 }   -- GetNetStats(): in, out, home ms, world ms (measured)
    WoW.unitWatch = {}
    WoW.shift = false
    WoW.alt = false
    WoW.secretFields = {}     -- field -> true: that unit field comes back secret for every unit
    WoW.units = {}
    WoW.raid = nil
    WoW.masterLooter = false
    WoW.resting = false
    WoW.settings = {}
    WoW.atlases = { ["UI-HUD-UnitFrame-Player-Rest-Flipbook"] = true }
    WoW.loadedAddOns = {}
    WoW.rangeChecks = {}      -- C_SwingTimer.EnableRangeCheck calls, in order: { type, enable }
    WoW.swingInRange = {}     -- swing type -> IsTargetWithinSwingRange's answer (nil = unknown)
    WoW.cvars = { showSwingTimer = "1" }
    WoW.spellCosts = {}       -- spellID -> GetSpellPowerCost's table ("error": it throws)
    WoW.cooldowns = {}        -- spellID -> { isActive, isOnGCD, start, duration, secret } ("error": it throws)
    WoW.inRange = {}          -- unit -> IsSpellInRange's answer (nil, true, false, "secret", "error")
    WoW.rangeAsked = {}       -- IsSpellInRange calls: { spellID, unit }
    WoW.players = {}          -- guid -> { name, realm, level } for GetPlayerInfoByGUID
    WoW.mirror = {}           -- mirror timers: name -> { index, value, max, scale, paused, label }
    WoW.ccSpells = {}         -- spellID -> true: C_Spell.IsSpellCrowdControl
    WoW.uiScale = 0.64        -- UIParent's effective scale
    WoW.recasts = 0           -- C_TradeSkillUI.GetRemainingRecasts()
    WoW.repeating = false
    WoW.layout = false        -- true: frames' rects resolved from their anchors (GetCenter)
    WoW.callbacks = {}        -- EventRegistry: event -> { { fn, owner } }
    rawset(_G, "EditModeManagerFrame", nil)
    WoW.CreateBlizzardFrames()
end
table.insert(WoW.onReset, resetState)
resetState()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
Kit.strict({ GlassUF = true, GlassUnitFramesDB = true, LibStub = true })
