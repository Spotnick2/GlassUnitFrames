-- Frames.lua: the secure unit buttons, their glass, and the channel painters.
--
-- Secret-value rule for every painter: values from the client go straight
-- back to the client (StatusBar:SetMinMaxValues/SetValue, SetText,
-- SetFormattedText, AbbreviateNumbers, UnitHealthPercent). Lua never does
-- arithmetic, comparison, concatenation, tostring or a truth test on them.
-- Plain facts we branch on (connected, dead, class, reaction) go through
-- plain(), which drops anything secret.

GlassUF = GlassUF or {}
local API, Glass, Engine = GlassUF.API, GlassUF.Glass, GlassUF.Engine
local Frames = {}
GlassUF.Frames = Frames
Frames.byUnit = {}

local GAP = 3    -- between portrait tile and body

-- Default positions are sized for WoW's UIParent, which is 768 units tall at
-- the default UI scale (half-height 384): every frame, the target's cast lane
-- and two aura rows included, stays above y = -280, clear of the action bars.
-- `point` is where each frame sits by default, in screen (UIParent CENTER)
-- offsets for readability. Frames with `anchorTo` are placed RELATIVE to that
-- frame (the offset between the two default points), so moving the target
-- carries its cluster and moving the player carries the pet (#34); DinoUF
-- anchors its unit frames to each other the same way on Forever.
Frames.LAYOUT = {
    player       = { w = 300, h = 62, point = { "CENTER", "UIParent", "CENTER", -300, -110 },
                     portrait = "left", power = true, cast = true, size = "large", groupNumber = true, healPrediction = true,
                     -- SUF-style: the cast bar is a row INSIDE the frame, shown only while
                     -- casting; health and power shrink to make room (the pet frame sits
                     -- right under the player, so nothing may hang below it).
                     castInside = true, healthLoss = true, druidMana = true,
                     indicators = { raidTarget = true, leader = true, masterLoot = true, pvp = true, resting = true },
                     text = { healthRight = "curmaxhp", powerLeft = "perpp", powerRight = "curmaxpp" } },
    target       = { w = 300, h = 62, point = { "CENTER", "UIParent", "CENTER", 300, -110 },
                     portrait = "right", power = true, cast = true, sheen = true, size = "large", auras = true,
                     healPrediction = true, healthLoss = true, combo = true,
                     indicators = { raidTarget = true, leader = true, pvp = true },
                     text = { healthRight = "curmaxhp_perhp", powerLevel = true, powerLeft = "perpp", powerRight = "curmaxpp" } },
    -- Same total width as the player frame and centred on it (portrait 32 + gap 3
    -- + body 330 = 365), 5 px under it (player bottom -141, pet top -146), as the
    -- owner's SUF had it.
    pet          = { w = 330, h = 32, point = { "CENTER", "UIParent", "CENTER", -300, -162 },
                     portrait = "left", power = true, size = "small", text = { healthRight = "curmaxhp" },
                     indicators = { raidTarget = true, happiness = true }, anchorTo = "player" },
    -- The target cluster, SUF-style: targettarget and targettargettarget side by
    -- side ABOVE the target body (x 117.5..417.5, top at -79), 12 px up so the
    -- target's raid mark and leader crown (centred on its top edge, up to
    -- -69) stay clear of the row; auras right
    -- under it, the cast bar under the auras, focus above the ToT row.
    targettarget = { w = 180, h = 26, point = { "CENTER", "UIParent", "CENTER", 207.5, -54 },
                     size = "small", ticker = true, text = { healthRight = "curhp" },
                     indicators = { raidTarget = true }, anchorTo = "target" },
    -- Right of targettarget on the same row; name only, as the owner's SUF profile had it.
    targettargettarget = { w = 115, h = 26, point = { "CENTER", "UIParent", "CENTER", 360, -54 },
                     size = "small", ticker = true, nameOnly = true, indicators = { raidTarget = true },
                     anchorTo = "target" },
    -- Above the ToT row, following the target; focustarget to its right, following focus.
    focus        = { w = 210, h = 32, point = { "CENTER", "UIParent", "CENTER", 345, -15 },
                     power = true, size = "small", text = { healthRight = "curhp" },
                     indicators = { raidTarget = true, leader = true }, healPrediction = true, anchorTo = "target" },
    focustarget  = { w = 180, h = 26, point = { "CENTER", "UIParent", "CENTER", 546, -15 },
                     size = "small", ticker = true, text = { healthRight = "curhp" },
                     indicators = { raidTarget = true }, anchorTo = "focus" },
}
Frames.ORDER = { "player", "target", "pet", "targettarget", "targettargettarget", "focus", "focustarget" }

-- Our own colour tables: PowerBarColor / FACTION_BAR_COLORS are FrameXML
-- tables the API dump cannot confirm.
local POWER_COLORS = {
    MANA = { 0.16, 0.56, 1.00 }, RAGE = { 0.90, 0.22, 0.22 },
    ENERGY = { 1.00, 0.85, 0.25 }, FOCUS = { 1.00, 0.55, 0.25 },
}
local HOSTILE, NEUTRAL, FRIENDLY = { 0.85, 0.22, 0.22 }, { 0.92, 0.76, 0.22 }, { 0.26, 0.74, 0.32 }
local GREY, DEFAULT = { 0.50, 0.50, 0.52 }, { 0.56, 0.34, 0.92 }
local CAST, CHANNEL, FAILED = { 0.95, 0.74, 0.22 }, { 0.40, 0.80, 1.00 }, { 0.85, 0.22, 0.22 }

-- First result of fn(...) if it is plain; nil on error or when secret.
local function plain(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or API.IsSecret(v) then return nil end
    return v
end

-- The player's class and current power token (plain from the start): class
-- resources (#29) are built and shown by them.
local function playerClass()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class or nil
end

local function playerPowerToken()
    local ok, _, token = pcall(UnitPowerType, "player")
    if not ok or API.IsSecret(token) then return nil end
    return token
end

-- Run a paint step; remember the first failure per step for /glass secrets.
local function attempt(key, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then API.Fail(key, err) end
    return ok
end

-- A neutral NPC fighting you or your group reads red, as Blizzard's nameplate
-- does (#28). Its reaction stays neutral, and UnitSelectionType stays 2 in
-- combat (measured), so: are you on its threat list (any status, so a healer
-- sees their group's fight too), or is it in combat and targeting you. Both
-- through plain(): a secret answer means "don't know", and the NPC stays
-- yellow rather than guessing. An option (on by default).
Frames.aggroRed = true
local function neutralFighting(u)
    if plain(UnitThreatSituation, "player", u) ~= nil then return true end
    -- Targeting you and in combat: attacking you (the first in-game try on a
    -- neutral bat stayed yellow while it was clearly targeting the player).
    return plain(UnitIsUnit, u .. "target", "player") == true and plain(UnitAffectingCombat, u) == true
end

local function unitColor(u)
    if plain(UnitIsConnected, u) == false then return GREY end
    if plain(UnitIsDeadOrGhost, u) == true then return GREY end   -- dead reads as dead even on name-only frames
    if plain(UnitIsPlayer, u) == true then
        local ok, _, classFile = pcall(UnitClass, u)
        if ok then
            local r, g, b = API.ClassColor(classFile)
            if r then return { r, g, b } end
        end
    end
    if plain(UnitIsTapDenied, u) == true then return GREY end
    local reaction = plain(UnitReaction, u, "player")
    if type(reaction) == "number" then
        if reaction <= 3 then return HOSTILE end
        if reaction == 4 then
            if Frames.aggroRed and neutralFighting(u) then return HOSTILE end
            return NEUTRAL
        end
        return FRIENDLY
    end
    return DEFAULT
end

--------------------------------------------------------------------------------
-- Text formats, named after the SUF tags the owner's profile used. Not a tag
-- language: a fixed set, each handing client values (often secret) straight to
-- SetFormattedText / AbbreviateNumbers. LAYOUT[unit].text picks them per slot.
--------------------------------------------------------------------------------

local CLASSIFICATION = { worldboss = "Boss", rareelite = "Rare Elite", elite = "Elite", rare = "Rare" }

-- "12 Elite", "?? Boss", "12" or "" from plain level and classification.
local function levelClass(u)
    local out = ""
    local lvl = plain(UnitLevel, u)
    if type(lvl) == "number" then out = (lvl > 0) and tostring(lvl) or "??" end
    local c = CLASSIFICATION[plain(UnitClassification, u) or ""]
    if c then out = (out ~= "" and (out .. " ") or "") .. c end
    return out
end

-- Power percent, blank when the unit has no power (max plainly 0). For other
-- units max power is secret, so they may still read "0%".
local function powerPct(u)
    if plain(UnitPowerMax, u) == 0 then return nil end
    return API.PowerPercent(u)
end

-- Health formats get (u, hp, maxHp); power formats get (u, pow, maxPow): the
-- painters fetch each value once.
local TEXT = {
    perhp          = function(fs, u) fs:SetFormattedText("%.0f%%", API.HealthPercent(u)) end,
    curhp          = function(fs, u, hp) fs:SetFormattedText("%s", AbbreviateNumbers(hp)) end,
    curmaxhp       = function(fs, u, hp, maxHp)
        fs:SetFormattedText("%s/%s", AbbreviateNumbers(hp), AbbreviateNumbers(maxHp))
    end,
    curmaxhp_perhp = function(fs, u, hp, maxHp)
        fs:SetFormattedText("%s/%s | %.0f%%", AbbreviateNumbers(hp), AbbreviateNumbers(maxHp), API.HealthPercent(u))
    end,
    perpp          = function(fs, u) fs:SetFormattedText("%.0f%%", powerPct(u)) end,
    curpp          = function(fs, u, pow) fs:SetFormattedText("%s", AbbreviateNumbers(pow)) end,
    curmaxpp       = function(fs, u, pow, maxPow)
        fs:SetFormattedText("%s/%s", AbbreviateNumbers(pow), AbbreviateNumbers(maxPow))
    end,
}
Frames.TEXT = TEXT

-- If a format fails (a secret the client would not take, a missing API), fall
-- back to the percent rather than blanking the text.
local FALLBACK = { curhp = "perhp", curmaxhp = "perhp", curmaxhp_perhp = "perhp" }
local KEYS = {}   -- attempt() keys, built once per format

local function paintText(fs, kind, ...)
    if not (fs and kind) then return end
    KEYS[kind] = KEYS[kind] or ("text " .. kind)
    if attempt(KEYS[kind], TEXT[kind], fs, ...) then return end
    local fb = FALLBACK[kind]
    if fb and attempt(KEYS[kind] .. " fallback", TEXT[fb], fs, ...) then return end
    fs:SetText("")
end

-- "(AFK) Name (3)": AFK tag, and the player's raid group number (SUF's
-- [(()afk() )][name][( ()group())]). Name may be secret: formatted by the client.
local function paintName(f, u)
    local afk = (plain(UnitIsAFK, u) == true) and "(AFK) " or ""
    local grp = ""
    if f.layout.groupNumber and plain(IsInRaid) == true then
        local idx = plain(UnitInRaid, u)
        if type(idx) == "number" then
            local ok, _, _, subgroup = pcall(GetRaidRosterInfo, idx)
            if ok and not API.IsSecret(subgroup) and type(subgroup) == "number" then
                grp = " (" .. subgroup .. ")"
            end
        end
    end
    local lvl = ""
    if f.levelText and Frames.levelPos == "name" then
        lvl = levelClass(u)
        if lvl ~= "" then lvl = lvl .. " " end
    end
    f.nameText:SetFormattedText("%s%s%s%s", afk, lvl, GetUnitName(u, false), grp)
end

--------------------------------------------------------------------------------
-- Painters
--------------------------------------------------------------------------------

-- Health just lost (Blizzard's player frame does this): a bar with the
-- health bar's geometry takes the SAME values, only later, inside a clip
-- frame that starts at the health fill's moving edge, so only the part
-- beyond the current health shows. No Lua maths on the secret values.
--   * The RANGE follows at once, so a max-health change (a buff, a level)
--     never shows a false loss; only the value lags.
--   * Throttled, not debounced: the latest value is kept on the frame and one
--     timer applies it LOSS_HOLD later, so under steady damage the red part
--     still catches up every LOSS_HOLD instead of growing for the whole fight.
--   * Snaps with the health bar (new unit), and for dead/offline units.
local LOSS_HOLD = 0.4
local function paintLoss(f, maxHp, hp, snap)
    local interp = (not snap) and Glass.Smooth() or nil
    if not attempt("health loss range", function()
        if interp then f.lossBar:SetMinMaxValues(0, maxHp, interp) else f.lossBar:SetMinMaxValues(0, maxHp) end
    end) then return end
    if snap then
        f.lossPending = nil
        attempt("health loss", function() f.lossBar:SetValue(hp) end)
        return
    end
    f.lossPending = { hp = hp }
    if f.lossTimer then return end
    f.lossTimer = true
    C_Timer.After(LOSS_HOLD, function()
        f.lossTimer = nil
        local p = f.lossPending
        f.lossPending = nil
        -- Only the value: the range is already current (set on every paint).
        if p then
            attempt("health loss", function()
                local i = Glass.Smooth()
                if i then f.lossBar:SetValue(p.hp, i) else f.lossBar:SetValue(p.hp) end
            end)
        end
    end)
end

-- The health bar's colour depends on death and connection as well as class
-- and reaction, so both the name and the health painters apply it: a unit
-- revived (UNIT_HEALTH) must lose its dead grey without waiting for a name event.
local function paintColor(f, u)
    local c = unitColor(u)
    f.health:SetStatusBarColor(c[1], c[2], c[3])
end

Engine.SetPainter("color", function(f)
    if UnitExists(f.unit) then paintColor(f, f.unit) end
end)

Engine.SetPainter("name", function(f)
    local u = f.unit
    if not UnitExists(u) then return end
    if not attempt("name text", paintName, f, u) then f.nameText:SetText("") end
    if f.levelText then
        local lc = levelClass(u)
        f.levelText:SetText(Frames.levelPos == "power" and lc or "")
        if f.levelOnTile then f.levelOnTile:SetText(Frames.levelPos == "portrait" and lc or "") end
    end
    paintColor(f, u)
end)

Engine.SetPainter("health", function(f)
    local u = f.unit
    if not UnitExists(u) then f.lossPending = nil return end   -- a pending loss must not land on the next unit
    local hp, maxHp = UnitHealth(u), UnitHealthMax(u)
    attempt("health bar", Glass.SetBar, f.health, maxHp, hp, f.snap)
    if f.lossBar then
        local gone = plain(UnitIsConnected, u) == false or plain(UnitIsDeadOrGhost, u) == true
        paintLoss(f, maxHp, hp, f.snap or gone)
    end
    paintColor(f, u)

    if not f.valueText then return end   -- name-only frames
    if plain(UnitIsConnected, u) == false then f.valueText:SetText("Offline") return end
    if plain(UnitIsDeadOrGhost, u) == true then f.valueText:SetText("Dead") return end

    paintText(f.valueText, Frames.healthFormat[f.unit] or (f.layout.text and f.layout.text.healthRight), u, hp, maxHp)
end)

-- An NPC with no power left (no mana at all: max 0, or drained) shows no
-- power bar or power numbers, instead of "0%" and "0/0" over an empty bar
-- (#27). The level text stays. Other players always show theirs (SUF never
-- hid a target's power bar). For the player and pet, max power is plain, so
-- only a max of 0 hides it (running out of mana must not hide your own bar);
-- for NPCs max is secret, so the client's colour curve decides.
local function paintPowerAlpha(f, u, maxPow)
    local a = 1   -- unknown: show, as before
    if plain(UnitIsPlayer, u) == true and u ~= "player" then
        -- Other players always show their power bar, as SUF does: a warrior
        -- at 0 rage keeps an empty rage bar (it says what they use). Only
        -- NPCs hide an empty one.
        a = 1
    elseif API.IsSecret(maxPow) then
        -- The alpha may be secret too: never truth-test or compare it (that
        -- throws on this client, and the stub cannot catch it). Only its
        -- type decides what to do with it.
        local ok, v = pcall(API.PowerAlpha, u)
        if ok and (API.IsSecret(v) or type(v) == "number") then a = v end
    elseif type(maxPow) == "number" then
        a = (maxPow > 0) and 1 or 0
    end
    for _, region in ipairs(f.powerRegions) do
        if not attempt("power alpha", region.SetAlpha, region, a) then region:SetAlpha(1) end
    end
end

Engine.SetPainter("power", function(f)
    local u = f.unit
    if not (f.power and UnitExists(u)) then return end
    local pow, maxPow = UnitPower(u), UnitPowerMax(u)
    attempt("power bar", Glass.SetBar, f.power, maxPow, pow, f.snap)
    local ok, _, token = pcall(UnitPowerType, u)
    if not ok or API.IsSecret(token) then token = nil end
    local c = (token and POWER_COLORS[token]) or POWER_COLORS.MANA
    f.power:SetStatusBarColor(c[1], c[2], c[3])
    local t = f.layout.text or {}
    paintText(f.powerLeftText, t.powerLeft, u, pow, maxPow)
    paintText(f.powerText, t.powerRight, u, pow, maxPow)
    paintPowerAlpha(f, u, maxPow)
end)

-- SUF's sequence (modules/portrait.lua): clear, set unit, zoom, reset position.
Engine.SetPainter("portrait", function(f)
    local m, u = f.model, f.unit
    if not (m and UnitExists(u)) then return end
    if plain(UnitIsVisible, u) == false then m:ClearModel() return end
    attempt("portrait", function()
        m:ClearModel()
        m:SetUnit(u)
        m:SetPortraitZoom(1)
        m:SetPosition(0, 0, 0)
    end)
end)

-- Indicators: SUF's default set as the owner's profile kept it (modules/
-- indicators.lua). Every fact read through plain(): a secret never branches.
-- Master looter is shown on the player frame only: IsMasterLooter() answers
-- that directly (Enum.LootMethod is not in the API dump).
local function playerIsMasterLooter()
    return plain(IsMasterLooter) == true
end

-- Raid mark placement (#30): "name" (default, the owner's pick: a slot in
-- front of the name, inside the health bar), "top" (centred on the frame's
-- top edge) or "right" (outside the frame, past the portrait). Whether a mark
-- shows is plain (see the painter), so the name can move for it.
Frames.MARK_POSITIONS = { name = true, top = true, right = true }
Frames.markPos = "name"

local function placeMark(b)
    local icon = b.indicators and b.indicators.raidTarget
    if not icon then return end
    icon:ClearAllPoints()
    local pos = Frames.markPos
    if pos == "top" then
        icon:SetPoint("CENTER", b.body, "TOP", 0, 0)
    elseif pos == "right" then
        -- Past the pet's happiness icon when that is on the right too.
        local happy = b.indicators.happiness
        if happy and Frames.happinessPos == "right" then
            icon:SetPoint("LEFT", happy, "RIGHT", 4, 0)
        else
            icon:SetPoint("LEFT", b, "RIGHT", 4, 0)
        end
    else
        icon:SetPoint("LEFT", b.health, "LEFT", b.namePad or 5, 0)
    end
end

-- The name's left edge: the bar's padding, or just past a shown mark.
local function anchorName(b, marked)
    local fs, pad = b.nameText, b.namePad or 5
    local icon = b.indicators and b.indicators.raidTarget
    fs:ClearAllPoints()
    if marked and icon and Frames.markPos == "name" then
        fs:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    else
        fs:SetPoint("LEFT", b.health, "LEFT", pad, 0)
    end
    if b.valueText then
        fs:SetPoint("RIGHT", b.valueText, "LEFT", -6, 0)
    else
        fs:SetPoint("RIGHT", b.health, "RIGHT", -pad, 0)
    end
end

-- Health text per frame (#46): one of the fixed formats, overriding the
-- layout's default. Frames without a value text (name-only) have none.
Frames.HEALTH_FORMATS = { "curhp", "curmaxhp", "perhp", "curmaxhp_perhp" }
local HEALTH_FORMAT_OK = {}
for _, k in ipairs(Frames.HEALTH_FORMATS) do HEALTH_FORMAT_OK[k] = true end
Frames.healthFormat = {}

function Frames.HealthFormatOf(unit)
    local L = Frames.LAYOUT[unit]
    return Frames.healthFormat[unit] or (L and L.text and L.text.healthRight)
end

function Frames.SetHealthFormat(unit, kind)
    local b = Frames.byUnit[unit]
    if not (HEALTH_FORMAT_OK[kind] and b and b.valueText) then return false end
    Frames.healthFormat[unit] = kind
    Engine.RepaintChannel("health", function(f) return f.unit == unit end)
    return true
end

-- Where the level goes (#46), on frames that show one (the target): "power"
-- (the power line, default), "name" (before the name) or "portrait".
Frames.LEVEL_POSITIONS = { power = true, name = true, portrait = true }
Frames.levelPos = "power"

local function placeLevel(b)
    if not b.levelText then return end
    b.powerLeftText:ClearAllPoints()
    if Frames.levelPos == "power" then
        b.powerLeftText:SetPoint("LEFT", b.levelText, "RIGHT", 6, 0)
    else
        b.powerLeftText:SetPoint("LEFT", b.power, "LEFT", 7, 0)
    end
    b.powerLeftText:SetPoint("RIGHT", b.powerText, "LEFT", -6, 0)
end

function Frames.SetLevelPosition(pos)
    if not Frames.LEVEL_POSITIONS[pos] then return false end
    Frames.levelPos = pos
    for _, b in pairs(Frames.byUnit) do placeLevel(b) end
    Engine.RepaintChannel("name")
    return true
end

function Frames.SetAggroRed(on)
    Frames.aggroRed = on and true or false
    Engine.RepaintChannel("color")
end

-- Pet happiness placement: "left" (default, the owner's pick: left of the
-- pet's portrait, which sits at the frame's left edge), "right" (right of
-- the frame, where Blizzard's PetFrame shows it) or "under" (under the portrait).
Frames.HAPPINESS_POSITIONS = { left = true, right = true, under = true }
Frames.happinessPos = "left"

local function placeHappiness(b)
    local icon = b.indicators and b.indicators.happiness
    if not icon then return end
    icon:ClearAllPoints()
    local pos, anchor = Frames.happinessPos, b.tile or b
    if pos == "right" then
        icon:SetPoint("LEFT", b, "RIGHT", 4, 0)
    elseif pos == "under" then
        icon:SetPoint("TOP", anchor, "BOTTOM", 0, -3)
    else
        icon:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    end
end

function Frames.SetHappinessPosition(pos)
    if not Frames.HAPPINESS_POSITIONS[pos] then return false end
    Frames.happinessPos = pos
    for _, b in pairs(Frames.byUnit) do
        placeHappiness(b)
        placeMark(b)   -- a right-hand mark steps past a right-hand happiness icon
    end
    return true
end

-- Switch the placement live (out of combat or in: nothing here is secure).
function Frames.SetMarkPosition(pos)
    if not Frames.MARK_POSITIONS[pos] then return false end
    Frames.markPos = pos
    for _, b in pairs(Frames.byUnit) do
        placeMark(b)
        local icon = b.indicators and b.indicators.raidTarget
        if b.nameText then anchorName(b, icon and icon:IsShown() or false) end
    end
    return true
end

-- Hunter pet happiness: 1 unhappy, 2 content, 3 happy (the cells of
-- UI-PetHappiness, as Blizzard's PetFrame and SUF use them). The legacy
-- GetPetHappiness global is gone on Forever (DinoUF), but C_PetInfo has it.
-- Only for a hunter's pet (HasPetUI's second return), never a warlock's
-- demon. Plain values only; anything else hides the icon.
local HAPPINESS_CELLS = { { 0.375, 0.5625 }, { 0.1875, 0.375 }, { 0, 0.1875 } }
local function isHunterPet()
    local hasUI = rawget(_G, "HasPetUI")
    if hasUI then
        local ok, _, hunter = pcall(hasUI)
        return ok and not API.IsSecret(hunter) and hunter == true
    end
    -- No HasPetUI: fail closed on anything but a hunter's own pet.
    local ok, _, class = pcall(UnitClass, "player")
    return ok and class == "HUNTER"
end

local function petHappiness()
    if not isHunterPet() then return nil end
    local ci = rawget(_G, "C_PetInfo")
    local h = ci and plain(ci.GetPetHappiness)
    if type(h) == "number" then return h end
    return nil
end

-- Rogues always; druids only in cat form (energy). Alphas straight from the
-- client's curves; a failure leaves the pips empty, never stuck full.
Engine.SetPainter("combo", function(f)
    local c = f.combo
    if not c then return end
    local class = playerClass()
    local active = UnitExists(f.unit) and (class == "ROGUE" or (class == "DRUID" and playerPowerToken() == "ENERGY"))
    c.holder:SetShown(active and true or false)
    if not active then return end
    for i, pip in ipairs(c.pips) do
        local ok, a = pcall(API.ComboAlpha, i)
        if ok and (API.IsSecret(a) or type(a) == "number") then
            if not attempt("combo pip", pip.SetAlpha, pip, a) then pip:SetAlpha(0) end
        else
            pip:SetAlpha(0)
        end
    end
end)

-- Shown while the druid's current power isn't mana. Values straight to the
-- bar; neither the current nor the max mana is read in Lua.
Engine.SetPainter("druidmana", function(f)
    local d = f.druidMana
    if not d then return end
    local token = playerPowerToken()
    local active = token ~= nil and token ~= "MANA"
    d.host:SetShown(active)
    if not active then return end
    attempt("druid mana", Glass.SetBar, d.bar, UnitPowerMax("player", 0), UnitPower("player", 0), f.snap)
end)

Engine.SetPainter("happiness", function(f)
    local icon = f.indicators and f.indicators.happiness
    if not icon then return end
    local cell = UnitExists(f.unit) and HAPPINESS_CELLS[petHappiness()]
    if cell then
        icon:SetTexCoord(cell[1], cell[2], 0, 0.359375)
        icon:Show()
    else
        icon:Hide()
    end
end)

Engine.SetPainter("indicators", function(f)
    local ind, u = f.indicators, f.unit
    if not (ind and UnitExists(u)) then return end
    if ind.raidTarget then
        -- The mark index is SECRET for other units on Forever (measured: mark=S
        -- on a marked target). SetRaidTargetIconTexture does the texcoord maths
        -- in Lua, which a secret would break; SetSpriteSheetCell lets the
        -- client pick the cell from the index itself. The marker texture is a
        -- 4x4 sheet with marks 1-8 in reading order, as Blizzard's maths assumes.
        local okIdx, idx = pcall(GetRaidTargetIndex, u)
        local icon = ind.raidTarget
        if okIdx and (API.IsSecret(idx) or type(idx) == "number") then
            if pcall(icon.SetSpriteSheetCell, icon, idx, 4, 4) then icon:Show() else icon:Hide() end
        else
            icon:Hide()   -- plain nil: no mark
        end
        -- The name makes room for the mark only while one shows ("name" mode).
        if f.nameText then anchorName(f, icon:IsShown()) end
    end
    if ind.leader then
        if plain(UnitIsGroupLeader, u) == true then
            ind.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            ind.leader:Show()
        elseif plain(UnitIsGroupAssistant, u) == true then
            ind.leader:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
            ind.leader:Show()
        else
            ind.leader:Hide()
        end
    end
    if ind.masterLoot then
        local show = playerIsMasterLooter()
        -- Sit right of the leader icon when it shows, else take the corner itself.
        ind.masterLoot:ClearAllPoints()
        if ind.leader and ind.leader:IsShown() then
            ind.masterLoot:SetPoint("LEFT", ind.leader, "RIGHT", 2, 0)
        else
            ind.masterLoot:SetPoint("CENTER", f.indCorner.anchor, "TOPLEFT", f.indCorner.x, 0)
        end
        ind.masterLoot:SetShown(show)
    end
    if ind.resting then
        ind.resting:SetShown(plain(IsResting) == true)
    end
    if ind.pvp then
        local faction = plain(UnitFactionGroup, u)
        if plain(UnitIsPVPFreeForAll, u) == true then
            ind.pvp:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
            ind.pvp:Show()
        elseif (faction == "Alliance" or faction == "Horde") and plain(UnitIsPVP, u) == true then
            ind.pvp:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
            ind.pvp:Show()
        else
            ind.pvp:Hide()
        end
    end
end)

-- Incoming heals: values straight to the bar, snapped (an eased cancelled
-- heal would leave a residue). Cleared for offline/dead units, and whenever
-- the read fails, so a previous unit's heal never lingers.
local function clearHeal(f) f.healPred:SetMinMaxValues(0, 1); f.healPred:SetValue(0) end

local function paintHeal(f, u)
    local incoming, maxHealth = API.IncomingHeals(u, f.healCalc)
    Glass.SetBar(f.healPred, maxHealth, incoming, true)
end

Engine.SetPainter("heal", function(f)
    local u = f.unit
    if not (f.healCalc and UnitExists(u)) then return end
    if plain(UnitIsConnected, u) == false or plain(UnitIsDeadOrGhost, u) == true then
        clearHeal(f)
        return
    end
    if not attempt("heal prediction", paintHeal, f, u) then clearHeal(f) end
end)

local CAST_STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
local CAST_FAIL = { UNIT_SPELLCAST_FAILED = "Failed", UNIT_SPELLCAST_INTERRUPTED = "Interrupted" }

-- What the unit is casting right now: DurationObject + channel flag, or nil.
local function currentCast(u)
    if not UnitExists(u) then return nil end
    local ok, d, channel = pcall(API.CastDuration, u)
    if ok and d then return d, channel end
    return nil
end

local function showCast(f, c, d, channel)
    c.token = c.token + 1
    c.flashing = false
    if not attempt("cast timer", c.bar.SetTimerDuration, c.bar, d, nil, API.TimerDirection(channel)) then
        c.duration = nil
        c.host:Hide()
        return
    end
    -- Colour AFTER attaching the timer: attaching can reset the bar's visual
    -- state (DinoUF re-applies it afterwards too, modules/cast.lua).
    local col = channel and CHANNEL or CAST
    c.bar:SetStatusBarColor(col[1], col[2], col[3])
    c.duration = d
    local info = channel and UnitChannelInfo or UnitCastingInfo
    if not attempt("cast name", function() c.spell:SetText((info(f.unit))) end) then c.spell:SetText("") end
    c.host:Show()
end

local function flash(c, text)
    c.token = c.token + 1
    local token = c.token
    c.flashing = true
    c.duration = nil
    c.bar:SetMinMaxValues(0, 1)
    c.bar:SetValue(1)
    c.bar:SetStatusBarColor(FAILED[1], FAILED[2], FAILED[3])
    c.spell:SetText(text)
    c.time:SetText("")
    c.host:Show()
    C_Timer.After(0.5, function()
        if c.token == token then
            c.flashing = false
            c.host:Hide()
        end
    end)
end

-- Every event re-reads what the unit is casting NOW rather than trusting the
-- event alone: FAILED also fires for a rejected attempt while another cast
-- carries on, and a STOP can land after the next cast began.
-- event nil = full repaint.
Engine.SetPainter("cast", function(f, event)
    local c = f.cast
    if not c then return end
    local d, channel = currentCast(f.unit)

    if d then
        showCast(f, c, d, channel)
        return
    end

    if CAST_FAIL[event] then
        flash(c, CAST_FAIL[event])
        return
    end

    if event ~= nil and not CAST_STOP[event] then
        API.Fail("cast duration", "no DurationObject on " .. event)
    end
    -- Nothing casting: hide, unless an interrupt/fail flash is still up.
    if not c.flashing then
        c.duration = nil
        c.host:Hide()
    end
end)

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- Positions (#34). Every frame sits CENTER-on-CENTER: on its leader (anchorTo)
-- or on UIParent. Saved as { "CENTER", relName, "CENTER", x, y } where relName
-- is "UIParent" or a unit name. Older saves (any point, on UIParent) are still
-- honoured until the frame is moved again. Positions change only through
-- Frames.SetPosition, out of combat: nothing starts the client's own drag on a
-- protected frame (a drag combat interrupts can't be stopped; porting guide).

-- The default offset from the leader's default point (or the screen centre).
local function defaultOffset(unit)
    local L = Frames.LAYOUT[unit]
    local lead = L.anchorTo and Frames.LAYOUT[L.anchorTo]
    if lead then return L.point[4] - lead.point[4], L.point[5] - lead.point[5] end
    return L.point[4], L.point[5]
end

-- Offsets beyond this are nonsense (the UI is ~1400 x 768 units) and ±inf
-- would poison the SavedVariables file.
local MAX_OFFSET = 4096
local function sane(v)
    return type(v) == "number" and not API.IsSecret(v) and v == v and v > -MAX_OFFSET and v < MAX_OFFSET
end

local VALID_POINT = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
                      TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- A saved entry we can apply, or nil: one malformed save must not abort the
-- build of every frame after it.
local function validSaved(unit)
    local p = Frames.db.pos[unit]
    if type(p) ~= "table" then return nil end
    if not (VALID_POINT[p[1]] and VALID_POINT[p[3]]) then return nil end
    if not (sane(p[4]) and sane(p[5])) then return nil end
    local rel = p[2]
    if rel ~= "UIParent" and not (Frames.byUnit[rel] and rel == Frames.LAYOUT[unit].anchorTo) then return nil end
    return p
end

local function relFrame(name)
    if name == "UIParent" then return UIParent end
    return Frames.byUnit[name]
end

local function applyPosition(b)
    local p = validSaved(b.unit)
    b:ClearAllPoints()
    if p then
        b:SetPoint(p[1], relFrame(p[2]), p[3], p[4], p[5])
        return
    end
    local lead = b.layout.anchorTo and Frames.byUnit[b.layout.anchorTo]
    local x, y = defaultOffset(b.unit)
    if lead then
        b:SetPoint("CENTER", lead, "CENTER", x, y)
    else
        local L = b.layout.point
        b:SetPoint(L[1], UIParent, L[3], L[4], L[5])
    end
end

-- What a frame's position is relative to: its leader's unit, or "UIParent";
-- and that frame. SetPosition always places it there.
function Frames.AnchorOf(unit)
    local b = Frames.byUnit[unit]
    local rel = (b and b.layout.anchorTo) or "UIParent"
    return rel, relFrame(rel)
end

-- A save in the current form: CENTER on what the frame is anchored to now.
local function canonical(unit, p)
    return p and p[1] == "CENTER" and p[3] == "CENTER" and p[2] == Frames.AnchorOf(unit)
end

-- Where a frame is: CENTER offsets from its anchor (see AnchorOf), and that
-- anchor's name. An older save (another point, or a follower saved on the
-- screen) is measured from the live rects; nil when they aren't laid out, so
-- a nudge never invents a position.
function Frames.PositionOf(unit)
    local b = Frames.byUnit[unit]
    if not b then return nil end
    local rel, rf = Frames.AnchorOf(unit)
    local p = validSaved(unit)
    if canonical(unit, p) then return p[4], p[5], rel end
    if not p then
        local x, y = defaultOffset(unit)
        return x, y, rel
    end
    local bx, by = b:GetCenter()
    local rx, ry
    if rf then rx, ry = rf:GetCenter() end
    if type(bx) == "number" and type(by) == "number" and type(rx) == "number" and type(ry) == "number" then
        return bx - rx, by - ry, rel
    end
    return nil
end

-- Record a position without touching the frame (safe in combat): the one
-- owner of the saved format.
function Frames.SavePosition(unit, x, y)
    if not (Frames.byUnit[unit] and sane(x) and sane(y)) then return false end
    Frames.db.pos[unit] = { "CENTER", (Frames.AnchorOf(unit)), "CENTER", x, y }
    return true
end

-- Place one frame at CENTER offsets from its leader (or the screen centre),
-- rounded to 0.5 units; saved unless `live` (the unlock-mode drag in flight).
-- Refused in combat: these are protected frames.
-- Returns true and the (rounded) offsets it applied.
function Frames.SetPosition(unit, x, y, live)
    local b = Frames.byUnit[unit]
    if not b or InCombatLockdown() then return false end
    if not (sane(x) and sane(y)) then return false end
    x, y = math.floor(x * 2 + 0.5) / 2, math.floor(y * 2 + 0.5) / 2
    local _, rf = Frames.AnchorOf(unit)
    b:ClearAllPoints()
    b:SetPoint("CENTER", rf, "CENTER", x, y)
    if not live then Frames.SavePosition(unit, x, y) end
    return true, x, y
end

-- Rewrite older saves in the current form, measured from the live rects (out
-- of combat, when the frames are laid out; unlock mode runs it first).
function Frames.NormalizeSaves()
    if InCombatLockdown() then return end
    for _, unit in ipairs(Frames.ORDER) do
        local p = validSaved(unit)
        if p and not canonical(unit, p) then
            local x, y = Frames.PositionOf(unit)
            if x then Frames.SetPosition(unit, x, y) end
        end
    end
end

-- One frame back to its default (and, for a leader, its followers with it).
function Frames.ResetPosition(unit)
    local b = Frames.byUnit[unit]
    if not b or InCombatLockdown() then return false end
    Frames.db.pos[unit] = nil
    applyPosition(b)
    return true
end

function Frames.ResetPositions()
    Frames.db.pos = {}
    -- Leaders first (ORDER), so followers anchor to their final spot.
    for _, unit in ipairs(Frames.ORDER) do
        local b = Frames.byUnit[unit]
        if b then applyPosition(b) end
    end
end

-- An inside cast row: CAST_ROW px plus CAST_GAP above it and between
-- health and power. The idle heights come from build() (b.rows.idle); the
-- casting ones are derived from them, so a different frame height still
-- fills its body. No secure frame is touched, so this works in combat.
local CAST_ROW, CAST_GAP = 14, 2

local function castingRows(idle)
    local inner = idle.health + idle.gap + idle.power
    local power = math.max(8, idle.power - 2)
    return { health = inner - CAST_ROW - 2 * CAST_GAP - power, gap = CAST_GAP, power = power }
end

local function layoutRows(b, casting)
    local r = casting and b.rows.casting or b.rows.idle
    b.health:SetHeight(r.health)
    if b.healPred then b.healPred:SetHeight(r.health) end
    b.power:ClearAllPoints()
    b.power:SetPoint("TOPLEFT", b.health, "BOTTOMLEFT", 0, -r.gap)
    b.power:SetPoint("TOPRIGHT", b.health, "BOTTOMRIGHT", 0, -r.gap)
    b.power:SetHeight(r.power)
end

-- The cast bar either rides in its own glass pill under the body (target), or
-- is a row inside the body that appears only while casting (player, SUF's
-- auto-hiding cast bar): health and power shrink while it shows.
local function castHost(b, body, L)
    -- Needs a power bar to sit under; a frame without one keeps the pill.
    if L.castInside and b.power then
        local host = CreateFrame("Frame", nil, body)
        host:SetAllPoints(body)
        host:SetFrameLevel(Glass.ContentLevel(body))
        local bar = Glass.Bar(host, CAST_ROW)
        bar:SetPoint("TOPLEFT", b.power, "BOTTOMLEFT", 0, -CAST_GAP)
        bar:SetPoint("TOPRIGHT", b.power, "BOTTOMRIGHT", 0, -CAST_GAP)
        bar:SetFrameLevel(Glass.ContentLevel(body))
        -- Text above the bar's glass overlay (Glass.OVERLAY_LEVEL); hides with the host.
        local txt = CreateFrame("Frame", nil, host)
        txt:SetAllPoints(bar)
        txt:SetFrameLevel(bar:GetFrameLevel() + Glass.OVERLAY_LEVEL + 1)
        host:SetScript("OnShow", function() layoutRows(b, true) end)
        host:SetScript("OnHide", function() layoutRows(b, false) end)
        return host, bar, txt, 10
    end
    local host = CreateFrame("Frame", nil, b)
    host:SetSize(L.w, 20)
    -- Under the aura rows when the frame has them (target), else right under the body.
    host:SetPoint("TOP", body, "BOTTOM", 0, L.auras and (GlassUF.Auras.Bottom() - 6) or -6)
    host:SetFrameLevel(b:GetFrameLevel() + 1)
    local g = Glass.Apply(host, "small")
    local inset = Glass.Inset("small")
    local bar = Glass.Bar(host, 20 - 2 * inset)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, -inset)
    bar:SetFrameLevel(Glass.ContentLevel(host))
    return host, bar, g.top, 11
end

local function buildCast(b, body, L)
    local host, bar, textLayer, fontSize = castHost(b, body, L)
    local spell = Glass.Font(textLayer, fontSize, "LEFT")
    spell:SetPoint("LEFT", bar, "LEFT", 6, 0)
    local time = Glass.Font(textLayer, fontSize, "RIGHT")
    time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    spell:SetPoint("RIGHT", time, "LEFT", -6, 0)
    host:Hide()

    local c = { host = host, bar = bar, spell = spell, time = time, token = 0 }
    host.acc = 0
    host:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        local d = c.duration
        if not d then return end
        attempt("cast time", function() c.time:SetFormattedText("%.1fs", d:GetRemainingDuration()) end)
    end)
    return c
end

-- Resting "zzz": Blizzard's own animated PlayerFrame flipbook when the client
-- has the atlas (a 6x7 sheet, 42 frames in 1.5 s, as Blizzard's PlayerFrame.xml
-- plays it; SetAtlas, not SetTexture, or the sheet's padding slices into the
-- frames), else the classic static state icon SUF uses. Sits on the portrait
-- tile's top-left corner; the animation only runs while it is shown.
local REST_ATLAS = "UI-HUD-UnitFrame-Player-Rest-Flipbook"
local function hasAtlas(name)
    local ct = rawget(_G, "C_Texture")
    local fn = ct and ct.GetAtlasExists
    if not fn then return false end
    local ok, yes = pcall(fn, name)
    return ok and yes == true
end

local function buildResting(top, large)
    local holder = CreateFrame("Frame", nil, top)
    holder:SetFrameLevel(top:GetFrameLevel() + 1)
    local s = large and 22 or 16
    holder:SetSize(s, s)
    -- Tucked into the corner so it reads as attached to the portrait (the
    -- flipbook's Zs rise up and right from the bottom-left of its cell).
    holder:SetPoint("CENTER", top, "TOPLEFT", s * 0.5, -s * 0.6)
    local tex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    if hasAtlas(REST_ATLAS) then
        tex:SetAtlas(REST_ATLAS)
        tex:SetSize(s, s * 21 / 16)   -- one flipbook cell is 16x21
        tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
        local anim = holder:CreateAnimationGroup()
        anim:SetLooping("REPEAT")
        local flip = anim:CreateAnimation("FlipBook")
        flip:SetTarget(tex)
        flip:SetDuration(1.5)
        flip:SetFlipBookRows(7)
        flip:SetFlipBookColumns(6)
        flip:SetFlipBookFrames(42)
        flip:SetFlipBookFrameWidth(0)
        flip:SetFlipBookFrameHeight(0)
        holder:SetScript("OnShow", function() anim:Play() end)
        holder:SetScript("OnHide", function() anim:Stop() end)
        holder.animated = true
    else
        tex:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        tex:SetTexCoord(0, 0.5, 0, 0.421875)
        tex:SetAllPoints(holder)
    end
    holder:Hide()
    return holder
end

-- Indicator icons on the glass top layer (above the rim). Raid target sits on
-- the top edge, leader and loot on the top-left corner, PvP on the portrait.
local function buildIndicators(b, body, g, L, tileGlass)
    local want = L.indicators
    if not want then return end
    local large = L.size == "large"
    local ind = {}
    local function icon(size)
        local t = g.top:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSize(size, size)
        t:Hide()
        return t
    end
    if want.raidTarget then
        ind.raidTarget = icon(large and 20 or 14)
        ind.raidTarget:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        b.indicators = ind   -- placeMark reads it
        placeMark(b)
    end
    local cornerX = large and 14 or 9   -- the top-left corner slot
    b.indCorner = { anchor = body, x = cornerX }
    if want.leader then
        ind.leader = icon(large and 14 or 11)
        ind.leader:SetPoint("CENTER", body, "TOPLEFT", cornerX, 0)
    end
    if want.masterLoot then
        ind.masterLoot = icon(large and 12 or 10)
        ind.masterLoot:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter")
        ind.masterLoot:SetPoint("CENTER", body, "TOPLEFT", cornerX, 0)
    end
    -- PvP badge on the portrait tile's own top layer, inset so it stays on the
    -- tile, in the corner away from the body (mirrored for a right-side portrait).
    if want.pvp and tileGlass then
        local s = large and 24 or 18
        local left = L.portrait == "left"
        ind.pvp = tileGlass.top:CreateTexture(nil, "OVERLAY", nil, 7)
        ind.pvp:SetSize(s, s)
        ind.pvp:SetPoint("CENTER", tileGlass.top, left and "BOTTOMLEFT" or "BOTTOMRIGHT",
            left and s / 2 or -s / 2, s / 2)
        ind.pvp:Hide()
    end
    if want.resting and tileGlass then ind.resting = buildResting(tileGlass.top, large) end
    -- Hunter pet happiness: its own square, nearly as tall as the frame,
    -- placed by placeHappiness (left of the portrait by default). No glass
    -- tile: the texture has its own border, and sliced masks break on tiles
    -- this small (GLASS-MATERIAL §6).
    if want.happiness then
        local s = L.h - 6
        ind.happiness = g.top:CreateTexture(nil, "OVERLAY", nil, 7)
        ind.happiness:SetSize(s, s)
        ind.happiness:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
        ind.happiness:Hide()
    end
    b.indicators = ind
end

-- A translucent bar over the health fill, with the FULL health-bar geometry,
-- in a clip frame at health level + `level` (over the glass track at +1,
-- under the glass overlay at +4).
-- `fromEdge` clips it to the part past the health fill's moving edge. No Lua
-- geometry from secrets: the client moves the fill edge, the clip follows.
local function overlayBar(b, color, level, fromEdge)
    local clip = CreateFrame("Frame", nil, b.health)
    if fromEdge then
        clip:SetPoint("TOPLEFT", b.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        clip:SetPoint("BOTTOMRIGHT", b.health, "BOTTOMRIGHT", 0, 0)
    else
        clip:SetAllPoints(b.health)
    end
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(b.health:GetFrameLevel() + level)
    local bar = CreateFrame("StatusBar", nil, clip)
    bar:SetFrameLevel(clip:GetFrameLevel())   -- a child would default to +1, tying the overlay
    bar:SetStatusBarTexture(Glass.MEDIA .. "bar_fill")
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar:SetAlpha(color[4])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    -- The rounded mask covers the health bar's bounds, so only the far end
    -- is rounded, never the seam against the fill.
    bar:GetStatusBarTexture():AddMaskTexture(Glass.Mask(bar, "bar_mask", 8, 0, b.health))
    return bar
end

-- Incoming heals (#13): the FULL health-bar width, anchored to the health
-- fill's moving edge and clipped at the bar's boundary, so a heal of X% of
-- max always reads as X% (a bar squeezed into the remaining gap would
-- understate it). Level +3: above the health-loss bar.
local HEAL_COLOR = { 0.35, 0.95, 0.55, 0.45 }
local function buildHealPrediction(b)
    local calc = API.NewHealCalculator()
    if not calc then return end
    local pred = overlayBar(b, HEAL_COLOR, 3, false)
    pred:SetSize(b.healthWidth, b.health:GetHeight())
    pred:SetPoint("TOPLEFT", b.health:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    b.healCalc, b.healPred = calc, pred
end

-- Health loss (#40): the health bar's own geometry, clipped from the fill
-- edge. A light red, so it still reads next to a hostile (red) health fill.
-- Combo points: five glossy pips on the target body's top edge, right half,
-- over dim slots (0 points reads as five empty slots). No sliced masks: they
-- break on tiles this small.
local COMBO_COLOR = { 1.00, 0.82, 0.20 }
local function buildCombo(b, body, g)
    local holder = CreateFrame("Frame", nil, g.top)
    holder:SetSize(5 * 12 + 4 * 3, 8)
    holder:SetPoint("CENTER", body, "TOP", 90, 0)
    holder:SetFrameLevel(g.top:GetFrameLevel() + 1)
    local pips = {}
    for i = 1, 5 do
        local slot = holder:CreateTexture(nil, "ARTWORK")
        slot:SetSize(12, 8)
        slot:SetPoint("LEFT", holder, "LEFT", (i - 1) * 15, 0)
        slot:SetColorTexture(0, 0, 0, 0.55)
        local pip = holder:CreateTexture(nil, "OVERLAY")
        pip:SetAllPoints(slot)
        pip:SetTexture(Glass.MEDIA .. "bar_fill")
        pip:SetVertexColor(COMBO_COLOR[1], COMBO_COLOR[2], COMBO_COLOR[3], 1)
        pip:SetAlpha(0)
        pips[i] = pip
    end
    holder:Hide()
    b.combo = { holder = holder, pips = pips }
    b.channels.combo = true
end

-- Druid mana while in a form (bear rage, cat energy): a thin glass strip just
-- under the player frame (druids have no pet; the strip follows the body).
local function buildDruidMana(b, body, L)
    local host = CreateFrame("Frame", nil, b)
    host:SetSize(L.w, 12)
    host:SetPoint("TOP", body, "BOTTOM", 0, -3)
    host:SetFrameLevel(b:GetFrameLevel() + 1)
    Glass.Apply(host, "small")
    local inset = Glass.Inset("small")
    local bar = Glass.Bar(host, 12 - 2 * inset)
    bar:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, -inset)
    bar:SetFrameLevel(Glass.ContentLevel(host))
    bar:SetStatusBarColor(POWER_COLORS.MANA[1], POWER_COLORS.MANA[2], POWER_COLORS.MANA[3])
    host:Hide()
    b.druidMana = { host = host, bar = bar }
    b.channels.druidmana = true
end

local LOSS_COLOR = { 1.00, 0.55, 0.50, 0.90 }
local function buildHealthLoss(b)
    local loss = overlayBar(b, LOSS_COLOR, 2, true)
    loss:SetAllPoints(b.health)
    b.lossBar = loss
end

local function build(unit)
    local L = Frames.LAYOUT[unit]
    local size = L.size
    local tileW = L.portrait and (L.h + GAP) or 0

    local b = CreateFrame("Button", "GlassUF_" .. unit, UIParent, "SecureUnitButtonTemplate")
    b.unit, b.layout = unit, L
    local hasPower = L.power and not L.nameOnly   -- nameOnly: just the name over a health bar
    b.channels = { name = true, color = true, health = true, power = hasPower or nil,
                   happiness = (L.indicators and L.indicators.happiness) or nil,
                   indicators = L.indicators and true or nil,
                   heal = L.healPrediction or nil,
                   portrait = L.portrait and true or nil, cast = L.cast or nil }
    b:SetSize(L.w + tileW, L.h)
    b:SetAttribute("unit", unit)
    b:SetAttribute("*type1", "target")
    b:SetAttribute("*type2", "togglemenu")
    b:RegisterForClicks(API.UnitButtonClicks())
    b:SetClampedToScreen(true)
    applyPosition(b)   -- leaders are built first (ORDER), so a follower's leader exists

    -- The glass hosts are plain children without mouse, so a click anywhere
    -- on the unit (portrait included) reaches the secure button.
    local body = CreateFrame("Frame", nil, b)
    body:SetSize(L.w, L.h)
    body:SetPoint(L.portrait == "left" and "RIGHT" or "LEFT", b, L.portrait == "left" and "RIGHT" or "LEFT")
    body:SetFrameLevel(b:GetFrameLevel() + 1)
    local g = Glass.Apply(body, size)
    b.glass, b.body = g, body

    local inset = Glass.Inset(size)
    local large = size == "large"
    local gap = large and 4 or 2
    local healthH = hasPower and (large and 34 or 17) or (L.h - 2 * inset)
    b.health = Glass.Bar(body, healthH)
    b.healthWidth = L.w - 2 * inset   -- the health bar's width (anchored inset on both sides)
    b.health:SetPoint("TOPLEFT", body, "TOPLEFT", inset, -inset)
    b.health:SetPoint("TOPRIGHT", body, "TOPRIGHT", -inset, -inset)
    b.health:SetFrameLevel(Glass.ContentLevel(body))
    if hasPower then
        b.power = Glass.Bar(body, L.h - 2 * inset - healthH - gap)
        b.power:SetPoint("TOPLEFT", b.health, "BOTTOMLEFT", 0, -gap)
        b.power:SetPoint("TOPRIGHT", b.health, "BOTTOMRIGHT", 0, -gap)
        b.power:SetFrameLevel(Glass.ContentLevel(body))
        local idle = { health = healthH, gap = gap, power = L.h - 2 * inset - healthH - gap }
        b.rows = { idle = idle, casting = castingRows(idle) }
    end

    local textSize = large and 15 or 11
    local pad = large and 9 or 5
    b.nameText = Glass.Font(g.top, textSize, "LEFT")
    b.namePad = pad
    if not L.nameOnly then
        b.valueText = Glass.Font(g.top, textSize, "RIGHT")
        b.valueText:SetPoint("RIGHT", b.health, "RIGHT", -pad, 0)
    end
    anchorName(b, false)
    if hasPower and large then
        b.powerText = Glass.Font(g.top, 11, "RIGHT")
        b.powerText:SetPoint("RIGHT", b.power, "RIGHT", -7, 0)
        -- Level (and classification) in its own string, so it stays when the
        -- power numbers beside it fade out on a unit with no power.
        if L.text and L.text.powerLevel then
            b.levelText = Glass.Font(g.top, 11, "LEFT")
            b.levelText:SetPoint("LEFT", b.power, "LEFT", 7, 0)
        end
        if L.text and L.text.powerLeft then
            b.powerLeftText = Glass.Font(g.top, 11, "LEFT")
            if b.levelText then
                b.powerLeftText:SetPoint("LEFT", b.levelText, "RIGHT", 6, 0)
            else
                b.powerLeftText:SetPoint("LEFT", b.power, "LEFT", 7, 0)
            end
            b.powerLeftText:SetPoint("RIGHT", b.powerText, "LEFT", -6, 0)
        end
    end
    -- What fades on a unit with no power (#27); the level text never does.
    if hasPower then b.powerRegions = { b.power, b.powerText, b.powerLeftText } end

    local tileGlass
    if L.portrait then
        local tile = CreateFrame("Frame", nil, b)
        tile:SetSize(L.h, L.h)
        tile:SetPoint(L.portrait == "left" and "LEFT" or "RIGHT", b, L.portrait == "left" and "LEFT" or "RIGHT")
        tile:SetFrameLevel(b:GetFrameLevel() + 1)
        tileGlass = Glass.Apply(tile, size)
        local m = CreateFrame("PlayerModel", nil, tile)
        local mi = Glass.Inset(size) - 1
        m:SetPoint("TOPLEFT", tile, "TOPLEFT", mi, -mi)
        m:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -mi, mi)
        m:SetFrameLevel(Glass.ContentLevel(tile))
        m:SetKeepModelOnHide(true)
        b.tile = tile
        if b.levelText then
            -- The level can sit on the portrait: on the tile's own top layer,
            -- so its rim never covers it.
            b.levelOnTile = Glass.Font(tileGlass.top, 11, "CENTER")
            b.levelOnTile:SetPoint("BOTTOM", tile, "BOTTOM", 0, Glass.Inset(size) + 1)
        end
        b.model = m
    end

    if L.cast then b.cast = buildCast(b, body, L) end
    -- Optional features build under pcall: a client that refuses one (as an
    -- aura-container anchor once did in game) must not abort the frame's
    -- build before RegisterUnitWatch / Engine.Register below, nor the frames
    -- built after it.
    attempt("build indicators", buildIndicators, b, body, g, L, tileGlass)
    if L.healthLoss then attempt("build health loss", buildHealthLoss, b) end
    local class = playerClass()
    if L.combo and (class == "ROGUE" or class == "DRUID") then attempt("build combo", buildCombo, b, body, g) end
    if L.druidMana and class == "DRUID" then attempt("build druid mana", buildDruidMana, b, body, L) end
    if L.healPrediction then attempt("build heal prediction", buildHealPrediction, b) end
    if L.auras then attempt("build auras", GlassUF.Auras.Attach, b, body) end
    if L.sheen then b.sheen = Glass.Sheen(g, body, L.w, L.h) end

    placeLevel(b)
    placeHappiness(b)   -- after the portrait tile exists
    placeMark(b)        -- a right-hand mark may step past the happiness icon
    RegisterUnitWatch(b)
    Engine.Register(b, { ticker = L.ticker })
    Frames.byUnit[unit] = b
    return b
end

-- A fresh target sweeps the sheen across its frame. Only the target: a focus
-- change must not replay it or cut off the target's cast flash.
Engine.OnTokenChanged = function(base)
    if base ~= "target" then return end
    local t = Frames.byUnit.target
    if t and t.auraContainers then GlassUF.Auras.Refresh(t) end
    if t and t.cast then t.cast.flashing = false end   -- the old target's flash is not the new one's
    if t and t.sheen and UnitExists("target") then
        t.sheen:Stop()
        t.sheen:Play()
    end
end

-- Called once at ADDON_LOADED, before any lockdown can apply.
function Frames.Build(db)
    Frames.db = db
    if Frames.MARK_POSITIONS[db.mark] then Frames.markPos = db.mark end
    if db.aggroRed == false then Frames.aggroRed = false end
    if Frames.LEVEL_POSITIONS[db.level] then Frames.levelPos = db.level end
    if Frames.HAPPINESS_POSITIONS[db.happiness] then Frames.happinessPos = db.happiness end
    if type(db.healthText) == "table" then
        for unit, kind in pairs(db.healthText) do
            if HEALTH_FORMAT_OK[kind] then Frames.healthFormat[unit] = kind end
        end
    end
    for _, unit in ipairs(Frames.ORDER) do build(unit) end
end
