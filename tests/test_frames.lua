-- The secure buttons, their wiring, and plain-value painting.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()

eq(#GlassUF.Frames.ORDER, 7, "seven unit frames")
for _, unit in ipairs(GlassUF.Frames.ORDER) do
    local b = button(unit)
    check(b ~= nil, unit .. " frame built")
    eq(b._template, "SecureUnitButtonTemplate", unit .. " template")
    eq(b._name, "GlassUF_" .. unit, unit .. " global name")
    eq(b._attrs.unit, unit, unit .. " unit attribute")
    eq(b._attrs["*type1"], "target", unit .. " left click targets")
    eq(b._attrs["*type2"], "togglemenu", unit .. " right click menu")
    for k in pairs(b._attrs) do
        check(not k:find("typerelease"), unit .. " never sets typerelease (double-acts): " .. k)
    end
    -- Unit buttons: up edge only, as SUF/DinoUF. The unit-button handler acts
    -- on every registered edge, so both edges could toggle the menu twice.
    eq(#(b._clicks or {}), 1, unit .. " registers one click spec")
    eq(b._clicks[1], "AnyUp", unit .. " clicks on the up edge")
    check(WoW.unitWatch[b], unit .. " is under RegisterUnitWatch")
end

-- Plain values reach the bars and text.
local p = button("player")
eq(p.health._max, 1550, "player health max")
eq(p.health._value, 1240, "player health value")
eq(textOf(p.nameText), "Morphisto", "player name")
eq(textOf(p.valueText), AbbreviateNumbers(1240) .. "/" .. AbbreviateNumbers(1550), "player health: cur/max")
eq(textOf(p.powerText), "920/" .. AbbreviateNumbers(1270), "player power right: cur/max")
eq(textOf(p.powerLeftText), "72%", "player power left: percent")
local t0 = button("target")
eq(textOf(t0.valueText), "830/" .. AbbreviateNumbers(1317) .. " | 63%", "target health: cur/max | pct")
eq(textOf(t0.powerLeftText), "10  100%", "target power left: level + power percent")
eq(textOf(button("targettarget").valueText), AbbreviateNumbers(1240), "targettarget: current health")
eq(textOf(button("focus").valueText), "666", "focus: current health")
check(button("pet").powerLeftText == nil and button("pet").powerText == nil, "small frames carry no power text")
eq(p.power._value, 920, "player power value")
eq(p.health._color[3], 0.93, "player coloured by class")
eq(button("target").health._color[1], 0.85, "hostile target is red")
eq(button("pet").power._color[1], 1.00, "pet focus coloured")
eq(textOf(button("pet").valueText), "400/400", "pet: cur/max health")
eq(button("player").model._modelUnit, "player", "3D portrait set to the unit")
eq(button("pet").model and button("pet").model._modelUnit, "pet", "pet has its own 3D portrait")
eq(button("pet")._width, button("player")._width, "pet as wide as the player frame (portrait included)")
eq(GlassUF.Frames.LAYOUT.pet.point[4], GlassUF.Frames.LAYOUT.player.point[4], "pet centred under the player")
-- The player's cast bar is a row inside the frame (SUF's auto-hiding cast
-- bar): idle, health and power fill the body; while casting they shrink and
-- the cast row shows under them. The target keeps its pill under the frame.
do
    local pl = button("player")
    local c = pl.cast
    eq(c.host:GetParent(), pl.body, "player cast row lives inside the body")
    eq(pl.health._height, 34, "idle: full-height health bar")
    WoW.units.player.casting = { name = "Shadow Bolt" }
    WoW.fire("UNIT_SPELLCAST_START", "player"); WoW.tick()
    check(c.host._shown, "cast row shown while casting")
    eq(pl.health._height, 22, "casting: health shrinks")
    eq(pl.power._height, 10, "casting: power shrinks")
    eq(c.bar._points[1][2], pl.power, "cast row sits under the power bar")
    check(pl.healPred ~= nil, "player has heal prediction")
    eq(pl.healPred._height, 22, "heal prediction follows the health bar")
    WoW.units.player.casting = nil
    WoW.fire("UNIT_SPELLCAST_STOP", "player"); WoW.tick()
    check(not c.host._shown, "cast row hidden after the cast")
    eq(pl.health._height, 34, "health back to full height")
    eq(pl.power._height, 12, "power back to full height")
    eq(button("target").cast.host:GetParent(), button("target"), "target keeps its cast pill")
end

-- A unit event repaints on the next rendered frame, once.
WoW.units.player.health = 775
WoW.fire("UNIT_HEALTH", "player")
WoW.fire("UNIT_HEALTH", "player")
eq(p.health._value, 1240, "not painted before the flush")
WoW.tick()
eq(p.health._value, 775, "painted after the flush")
eq(textOf(p.valueText), "775/" .. AbbreviateNumbers(1550), "value text after damage")

-- #10: level + classification on the target's power line; AFK tag; the
-- player's raid group number, following GROUP_ROSTER_UPDATE.
WoW.units.target.level = 12
WoW.units.target.classification = "elite"
WoW.fire("UNIT_CLASSIFICATION_CHANGED", "target"); WoW.tick()
eq(textOf(button("target").powerLeftText), "12 Elite  100%", "target power left: level, classification, power")
WoW.units.target.level = -1
WoW.units.target.classification = "worldboss"
WoW.fire("UNIT_LEVEL", "target"); WoW.tick()
eq(textOf(button("target").powerLeftText), "?? Boss  100%", "boss: ?? level")
WoW.units.target.level, WoW.units.target.classification = 10, "normal"
WoW.units.player.afk = true
WoW.fire("PLAYER_FLAGS_CHANGED", "player"); WoW.tick()
eq(textOf(p.nameText), "(AFK) Morphisto", "AFK tag")
WoW.units.player.afk = false
-- A targeted player going AFK: the client fires PLAYER_FLAGS_CHANGED with
-- their group token (raidN), never "target"; the target's tag must follow.
WoW.units.target.afk = true
WoW.fire("PLAYER_FLAGS_CHANGED", "raid9"); WoW.tick()
check(textOf(button("target").nameText):find("^%(AFK%)"), "target AFK tag follows a group-token event")
WoW.units.target.afk = false
WoW.fire("PLAYER_FLAGS_CHANGED", "raid9"); WoW.tick()
WoW.raid = { player = { index = 5, subgroup = 3 }, target = { index = 9, subgroup = 2 } }
local modelSets = 0
local realSetUnit = p.model.SetUnit
rawset(p.model, "SetUnit", function(self, ...) modelSets = modelSets + 1; return realSetUnit(self, ...) end)
WoW.fire("GROUP_ROSTER_UPDATE"); WoW.tick()
eq(textOf(p.nameText), "Morphisto (3)", "raid group number on the player")
WoW.fire("UNIT_NAME_UPDATE", "target"); WoW.tick()   -- repaint the target's name line too
check(not textOf(button("target").nameText):find("%(%d%)"), "group number only where the layout asks (target is in the raid too)")
eq(modelSets, 0, "a roster change does not reload the 3D portrait")
WoW.raid = nil
WoW.fire("GROUP_ROSTER_UPDATE"); WoW.tick()
eq(textOf(p.nameText), "Morphisto", "no group number out of a raid")

-- No power (max plainly 0): no "0%". A failed health format falls back to the percent.
WoW.units.player.maxPower, WoW.units.player.power = 0, 0
WoW.fire("UNIT_MAXPOWER", "player"); WoW.tick()
eq(textOf(p.powerLeftText), "", "no power: percent blank")
WoW.units.player.maxPower, WoW.units.player.power = 1270, 920
WoW.fire("UNIT_MAXPOWER", "player"); WoW.tick()
local realAbbr = AbbreviateNumbers
AbbreviateNumbers = function() error("client refused") end
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(textOf(p.valueText), "50%", "health text falls back to the percent")
AbbreviateNumbers = realAbbr
GlassUF.paintFailures = {}
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()

-- #14 smooth bars. Enum.StatusBarInterpolation is not in the API dump, so
-- the default stub has none: bars must update instantly without it.
WoW.units.player.health = 1100
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(p.health._value, 1100, "without the enum, bars still update")
eq(p.health._interp, nil, "without the enum, no interpolation is passed")
-- With the enum: an event-driven change eases (range and value alike); a
-- unit swap snaps; the ticker's refresh of a chained unit eases.
Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
WoW.units.player.health = 1000
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(p.health._interp, Enum.StatusBarInterpolation.ExponentialEaseOut, "damage eases the health bar")
eq(p.health._minMaxInterp, Enum.StatusBarInterpolation.ExponentialEaseOut, "the range eases with the value (no dip)")
WoW.units.player.power = 800
WoW.fire("UNIT_POWER_UPDATE", "player"); WoW.tick()
eq(p.power._interp, Enum.StatusBarInterpolation.ExponentialEaseOut, "power eases too")
WoW.SetUnit("target", { name = "Kobold Miner", reaction = 2, health = 40, maxHealth = 90 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(button("target").health._interp, nil, "a new target snaps, not eases from the old target's health")
WoW.units.target.health = 20
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()
eq(button("target").health._interp, Enum.StatusBarInterpolation.ExponentialEaseOut, "then eases again")
WoW.units.targettarget.health = 900
GlassUF.Engine._test.ticker.elapsed = 0
WoW.tick(0.6); WoW.tick()
eq(button("targettarget").health._value, 900, "ticker refreshed targettarget")
eq(button("targettarget").health._interp, Enum.StatusBarInterpolation.ExponentialEaseOut,
   "the ticker's refresh eases (same unit), it does not snap")
-- Identity change with no event (targettarget retargets): the ticker sees a
-- new GUID and snaps instead of easing from the old unit's health.
WoW.SetUnit("targettargettarget", { name = "Someone Else", reaction = 2, health = 10, maxHealth = 100 })
GlassUF.Engine._test.ticker.elapsed = 0
WoW.tick(0.6); WoW.tick()
eq(button("targettargettarget").health._value, 10, "ticker picked up the new unit")
eq(button("targettargettarget").health._interp, nil, "a new unit found by polling snaps")
WoW.units.targettargettarget.health = 20
GlassUF.Engine._test.ticker.elapsed = 0
WoW.tick(0.6); WoW.tick()
eq(button("targettargettarget").health._interp, Enum.StatusBarInterpolation.ExponentialEaseOut,
   "the same unit on the next tick eases")
-- A GUID we cannot compare (secret) snaps: conservative.
WoW.secretFields.guid = true
WoW.units.targettargettarget.health = 30
GlassUF.Engine._test.ticker.elapsed = 0
WoW.tick(0.6); WoW.tick()
eq(button("targettargettarget").health._interp, nil, "an uncomparable GUID snaps")
WoW.secretFields.guid = nil
WoW.SetUnit("targettargettarget", { name = "Defias Pillager", reaction = 2, health = 830, maxHealth = 1317 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
-- A client that rejects the eased call falls back to an instant update.
local realSetValue = p.health.SetValue
rawset(p.health, "SetValue", function(self, v, interp)
    if interp then error("interpolation rejected") end
    return realSetValue(self, v)
end)
WoW.units.player.health = 777
WoW.fire("UNIT_HEALTH", "player"); WoW.tick()
eq(p.health._value, 777, "rejected easing falls back to an instant update")
rawset(p.health, "SetValue", nil)
Enum.StatusBarInterpolation = nil
WoW.units.player.health, WoW.units.player.power = 1240, 920
WoW.fire("UNIT_HEALTH", "player"); WoW.fire("UNIT_POWER_UPDATE", "player"); WoW.tick()

-- Dead and offline read as words.
WoW.units.target.dead = true
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()
eq(textOf(button("target").valueText), "Dead", "dead target")
WoW.units.target.dead = false
WoW.units.target.connected = false
WoW.fire("UNIT_CONNECTION", "target"); WoW.tick()
eq(textOf(button("target").valueText), "Offline", "offline target")
eq(button("target").health._color[1], 0.50, "offline target is grey")

-- Target change repaints target and targettarget and sweeps the sheen.
WoW.SetUnit("target", { name = "Defias Bandit", reaction = 2, health = 77, maxHealth = 100 })
local plays = button("target").sheen._plays or 0
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(textOf(button("target").nameText), "Defias Bandit", "new target painted")
eq(button("target").sheen._plays, plays + 1, "sheen plays on a new target")

-- targettarget has no unit events: the ticker repaints it while shown.
local ttBefore = button("targettarget").health._value
WoW.units.targettarget.health = 155
GlassUF.Engine._test.ticker.elapsed = 0          -- fix the shared ticker's phase
WoW.tick(0.3); WoW.tick()
eq(button("targettarget").health._value, ttBefore, "no repaint before 0.5s")
WoW.tick(0.3); WoW.tick()
eq(button("targettarget").health._value, 155, "ticker repainted targettarget")

-- targettargettarget (#9): name only, repainted on target change and by its ticker.
local ttt = button("targettargettarget")
eq(textOf(ttt.nameText), "Defias Pillager", "targettargettarget name")
check(ttt.valueText == nil and ttt.power == nil, "targettargettarget is name-only: no value text, no power")
eq(ttt.health._value, 830, "targettargettarget health bar still fills")
WoW.SetUnit("targettargettarget", { name = "Hathnos", reaction = 5 })
GlassUF.Engine._test.ticker.elapsed = 0
WoW.fire("UNIT_TARGET", "target"); WoW.tick()
eq(textOf(ttt.nameText), "Hathnos", "UNIT_TARGET on target repaints targettargettarget")
WoW.SetUnit("targettargettarget", { name = "Kobold", reaction = 2 })
GlassUF.Engine._test.ticker.elapsed = 0
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(textOf(ttt.nameText), "Kobold", "PLAYER_TARGET_CHANGED repaints targettargettarget")
WoW.units.targettargettarget.dead = true
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(ttt.health._color[1], 0.50, "a dead name-only unit is greyed")
WoW.units.targettargettarget.dead = false

-- Death and resurrection WITHOUT a target change: health events recolour.
local tgt = button("target")
local hostileR = tgt.health._color[1]
WoW.units.target.dead = true
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()
eq(tgt.health._color[1], 0.50, "death greys the bar on UNIT_HEALTH")
WoW.units.target.dead = false
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()
eq(tgt.health._color[1], hostileR, "resurrection restores the colour on UNIT_HEALTH")
WoW.units.targettargettarget.health = 5
WoW.tick(0.6); WoW.tick()
eq(ttt.health._value, 5, "targettargettarget ticker repaints")

-- Focus (#8): PLAYER_FOCUS_CHANGED repaints focus and focustarget; UNIT_TARGET
-- on focus repaints focustarget; focustarget (no unit events) ticks.
eq(textOf(button("focus").nameText), "Hogger", "focus painted")
eq(button("focus").health._value, 666, "focus health")
eq(button("focus").health._color[1], 0.85, "hostile focus is red")
check(button("focus").power ~= nil and button("focustarget").power == nil, "focus has power, focustarget does not")
WoW.SetUnit("focus", { name = "Mother Fang", reaction = 2, health = 50, maxHealth = 100 })
WoW.SetUnit("focustarget", { name = "Hathnos", reaction = 5, health = 400, maxHealth = 400 })
local sheenBefore = button("target").sheen._plays or 0
button("target").cast.flashing = true
WoW.fire("PLAYER_FOCUS_CHANGED"); WoW.tick()
eq(button("target").sheen._plays or 0, sheenBefore, "a focus change does not replay the target sheen")
check(button("target").cast.flashing, "a focus change does not cut off the target's cast flash")
button("target").cast.flashing = false
eq(textOf(button("focus").nameText), "Mother Fang", "focus repainted on PLAYER_FOCUS_CHANGED")
eq(textOf(button("focustarget").nameText), "Hathnos", "focustarget repainted on PLAYER_FOCUS_CHANGED")
WoW.SetUnit("focustarget", { name = "Morphisto", class = "WARLOCK", player = true })
GlassUF.Engine._test.ticker.elapsed = 0          -- prove the event path, not a ticker coincidence
WoW.fire("UNIT_TARGET", "focus"); WoW.tick()
eq(textOf(button("focustarget").nameText), "Morphisto", "UNIT_TARGET on focus repaints focustarget")
WoW.units.focustarget.health = 10
WoW.tick(0.6); WoW.tick()
eq(button("focustarget").health._value, 10, "focustarget ticker repaints")

-- Pet replaced: UNIT_PET on player repaints the pet frame.
WoW.SetUnit("pet", { name = "Grunthok", reaction = 5 })
WoW.fire("UNIT_PET", "player"); WoW.tick()
eq(textOf(button("pet").nameText), "Grunthok", "pet repainted after UNIT_PET")

-- Every registered event runs for every unit without a Lua error. Casters
-- are mid-cast so START events have a cast to find, as they would in game.
WoW.units.player.casting = { name = "Shadow Bolt" }
WoW.units.target.casting = { name = "Fireball" }
local seen = WoW.fireAllRegistered()
WoW.tick()
check(seen.UNIT_HEALTH and seen.UNIT_SPELLCAST_START and seen.PLAYER_TARGET_CHANGED, "core events registered")
eq(next(GlassUF.eventFailures), nil, "no event registration failures")
eq(next(GlassUF.paintFailures), nil, "no paint failures with plain values")

-- Slash commands run.
SlashCmdList.GLASSUNITFRAMES("")
SlashCmdList.GLASSUNITFRAMES("secrets")
SlashCmdList.GLASSUNITFRAMES("totem")                    -- no TotemFrame in the stub
check(WoW.chat[#WoW.chat]:find("no TotemFrame", 1, true), "totem report without a TotemFrame")
local tf = CreateFrame("Frame", "TotemFrame", PlayerFrame)
tf:SetPoint("TOPLEFT", PlayerFrame, "BOTTOMLEFT", 0, 0)
CreateFrame("Button", nil, tf); CreateFrame("Button", nil, tf)
SlashCmdList.GLASSUNITFRAMES("totem")
local chainLine, infoLine = WoW.chat[#WoW.chat - 1], WoW.chat[#WoW.chat]
check(chainLine:find("PlayerFrame > GlassUF.hiddenParent > UIParent", 1, true),
      "chain names PlayerFrame and GlassUF's own hidden parent: " .. chainLine)
check(infoLine:find("anchored to PlayerFrame", 1, true), "anchor target reported: " .. infoLine)
check(infoLine:find("children=2", 1, true), "child count reported")
check(infoLine:find("explicitly=false", 1, true), "both IsProtected returns reported")
check(infoLine:find("under GlassUF's hidden parent=true", 1, true), "hidden flag from TotemFrame's own ancestry")
rawset(_G, "TotemFrame", nil)
-- /glass frame <Name>: the same report for any global, name kept case-sensitive.
local pab = CreateFrame("Frame", "PetActionBar", UIParent)
pab:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 5, 6)
SlashCmdList.GLASSUNITFRAMES("frame PetActionBar")
check(WoW.chat[#WoW.chat - 1]:find("PetActionBar parent chain: UIParent", 1, true), "frame probe chain: " .. WoW.chat[#WoW.chat - 1])
check(WoW.chat[#WoW.chat]:find("anchored to UIParent (BOTTOMLEFT on BOTTOMLEFT, 5, 6)", 1, true), "frame probe anchor: " .. WoW.chat[#WoW.chat])
SlashCmdList.GLASSUNITFRAMES("frame NoSuchFrame")
check(WoW.chat[#WoW.chat]:find("no NoSuchFrame global", 1, true), "frame probe without the global")
rawset(_G, "PetActionBar", nil)
-- A restricted frame can return secret offsets: the report degrades, never throws.
local rf = CreateFrame("Frame", "RestrictedThing", UIParent)
rawset(rf, "GetPoint", function() return "TOP", UIParent, "TOP", WoW.Secret("x"), WoW.Secret("y") end)
SlashCmdList.GLASSUNITFRAMES("frame RestrictedThing")
check(WoW.chat[#WoW.chat]:find("(unreadable anchor)", 1, true), "secret offsets: unreadable, no error")
rawset(_G, "RestrictedThing", nil)
SlashCmdList.GLASSUNITFRAMES("font friz")
eq(GlassUnitFramesDB.font, "friz", "font saved")
eq(p.nameText._font[1], "Fonts\\FRIZQT__.TTF", "font applied to existing text")
-- Translucent bar fill: texture alpha on every glass bar, text untouched.
eq(p.health:GetStatusBarTexture()._alpha, 0.6, "bar fill at the default opacity (owner-picked)")
SlashCmdList.GLASSUNITFRAMES("fill 0.5")
eq(p.health:GetStatusBarTexture()._alpha, 0.5, "fill retuned live")
eq(p.power:GetStatusBarTexture()._alpha, 0.5, "power bar too")
eq(GlassUnitFramesDB.fill, 0.5, "fill saved")
check(p.nameText._alpha == nil or p.nameText._alpha == 1, "text stays opaque")
p.health:SetStatusBarColor(1, 0, 0)
eq(p.health:GetStatusBarTexture()._alpha, 0.5, "recolouring keeps the fill opacity")
local vc = p.health.track._vertex
eq(p.health.track._file, GlassUF.Glass.MEDIA .. "track_fade", "missing health: the fading ramp")
check(vc and vc[1] == 1 and vc[2] == 0 and vc[4] == 0.75, "tinted with the bar's own colour")
-- Rim brightness: every glass surface, live, saved.
eq(p.glass.rim._alpha, 0.7, "rim softened by default (owner-picked)")
eq(GlassUnitFramesDB.rim, nil, "the default is not written into the saved settings")
SlashCmdList.GLASSUNITFRAMES("rim 0.5")
eq(p.glass.rim._alpha, 0.5, "rim retuned live")
eq(button("pet").glass.rim._alpha, 0.5, "on every frame")
eq(GlassUnitFramesDB.rim, 0.5, "rim saved")
SlashCmdList.GLASSUNITFRAMES("rim 0")
eq(GlassUnitFramesDB.rim, 0.5, "out-of-range rim rejected")
SlashCmdList.GLASSUNITFRAMES("track 0.8")
eq(p.health.track._vertex[4], 0.8, "track retuned live")
eq(p.health.track._vertex[1], 1, "track keeps the bar colour")
eq(GlassUnitFramesDB.track, 0.8, "track saved")
local fg = p.health:GetStatusBarTexture()._gradient
check(fg and fg[1] == "HORIZONTAL" and fg[2].a == 1 and fg[3].a == 1 and fg[3].r == 1,
      "fill even by default (fade off), in the bar's colour")
SlashCmdList.GLASSUNITFRAMES("fade 0.5")
eq(p.health:GetStatusBarTexture()._gradient[3].a, 0.5, "fade retuned live")
eq(GlassUnitFramesDB.fade, 0.5, "fade saved")
-- The track only shows past the fill: its clip starts at the fill's moving
-- edge, so a full bar stays even and the ramp never sits under the fill.
local tc = p.health.trackClip
eq(tc._points[1][2], p.health:GetStatusBarTexture(), "track clip starts at the fill's edge")
eq(tc._points[1][3], "TOPRIGHT", "at the fill's right edge")
eq(tc._points[2][2], p.health, "and ends with the bar")
check(tc._clips == true, "the track is clipped")
eq(p.health.track:GetParent(), tc, "the track lives in the clip")
-- NaN fails every comparison: it must not slip through a range check.
SlashCmdList.GLASSUNITFRAMES("fill nan")
eq(GlassUnitFramesDB.fill, 0.5, "NaN fill rejected")
check(not GlassUF.Glass.SetTrackAlpha(0 / 0), "NaN track rejected")
-- A client visual reset of the fill's alpha is undone on the next recolour.
local fillTex = p.health:GetStatusBarTexture()
fillTex:SetAlpha(1)
p.health:SetStatusBarColor(0, 1, 0)
eq(fillTex._alpha, 0.5, "fill opacity re-applied after a reset")
-- A caller's alpha is honoured by the fill gradient.
p.health:SetStatusBarColor(0, 1, 0, 0.5)
eq(fillTex._gradient[2].a, 0.5, "SetStatusBarColor's alpha kept")
-- The same colour again does no work (painters recolour on every event).
fillTex._gradient = nil
p.health:SetStatusBarColor(0, 1, 0, 0.5)
eq(fillTex._gradient, nil, "unchanged colour: no re-tint")
SlashCmdList.GLASSUNITFRAMES("fill 3")
eq(GlassUnitFramesDB.fill, 0.5, "out-of-range fill rejected")
SlashCmdList.GLASSUNITFRAMES("font comic")
eq(GlassUnitFramesDB.font, "friz", "unknown font rejected")

done("test_frames")
