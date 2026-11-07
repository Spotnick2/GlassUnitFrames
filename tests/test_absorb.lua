-- Absorb shields left on the health bar (#171).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- UnitGetTotalAbsorbs (in the dump: unit -> number), stubbed here for this
-- test only: the unit field `absorbs`, secret with WoW.secretFields.absorbs.
local function stubAbsorbs()
    UnitGetTotalAbsorbs = function(u)
        local unit = WoW.units[u]
        local v = unit and unit.absorbs
        if v == nil then return 0 end
        if WoW.secretFields.absorbs then return WoW.Secret(u .. ".absorbs") end
        return v
    end
end
stubAbsorbs()
standardUnits()
loadAddon()
local p, t = button("player"), button("target")

check(p.absorbBar and t.absorbBar and button("focus").absorbBar, "player, target and focus show absorbs")
check(button("pet").absorbBar == nil and button("targettarget").absorbBar == nil, "small chained frames do not")
check(p.channels.absorb and button("pet").channels.absorb == nil, "only those frames carry the absorb channel")

-- Geometry: the full health-bar width, past the fill, starting where the
-- incoming heals end, clipped at the bar.
local bar = p.absorbBar
eq(bar._width, p.healthWidth, "spans the full health bar width")
eq(bar._points[1][1], "TOPLEFT", "its left end")
eq(bar._points[1][2], p.healPred:GetStatusBarTexture(), "on the heal prediction's fill edge")
eq(bar._points[1][3], "TOPRIGHT", "at that fill's right edge")
check(not bar._reverse, "fills rightward, past the fill")
check(bar._parent._clips == true, "clipped at the health bar's boundary")
eq(bar._parent._points[1][1], "ALL", "the clip is the whole health bar")
local hl = p.health:GetFrameLevel()
eq(bar._parent._level, hl + 3, "over the track, level with the heal prediction")
eq(p.health.overlay._level, hl + 4, "the glass overlay stays above it")

-- Values go straight through, snapped.
Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
WoW.units.player.absorbs = 87
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); WoW.tick()
eq(bar._value, 87, "the shield reaches the bar")
eq(bar._max, 1550, "scaled to maximum health")
eq(bar._interp, nil, "snaps")
WoW.units.player.absorbs = 40
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); WoW.tick()
eq(bar._value, 40, "a hit on the shield shrinks it")
WoW.units.player.absorbs = 0
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); WoW.tick()
eq(bar._value, 0, "a broken shield clears")
Enum.StatusBarInterpolation = nil

-- A target change repaints the target's shield.
WoW.SetUnit("target", { name = "Shielded Friend", reaction = 5, health = 500, maxHealth = 600, absorbs = 120 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(t.absorbBar._value, 120, "the new target's shield")
eq(t.absorbBar._max, 600, "over its own maximum health")

-- Dead or offline: cleared.
WoW.units.target.dead = true
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()
eq(t.absorbBar._value, 0, "a dead unit's shield is cleared")
WoW.units.target.dead = nil
WoW.fire("UNIT_HEALTH", "target"); WoW.tick()
eq(t.absorbBar._value, 120, "back once alive")

-- A failed read clears instead of leaving the old shield.
local real = UnitGetTotalAbsorbs
UnitGetTotalAbsorbs = function() error("restricted unit") end
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "target"); WoW.tick()
eq(t.absorbBar._value, 0, "a throwing read clears")
UnitGetTotalAbsorbs = function() return nil end
WoW.units.target.absorbs = 120
GlassUF.paintFailures = {}
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "target"); WoW.tick()
eq(t.absorbBar._value, 0, "a nil read clears")
eq(next(GlassUF.paintFailures), nil, "a nil read is not a failure")
UnitGetTotalAbsorbs = real

-- Secret values (measured: always, in and out of combat) pass through untouched.
WoW.secretFields.absorbs, WoW.secretFields.maxHealth = true, true
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "target"); WoW.tick()
check(WoW.IsSecret(t.absorbBar._value) and WoW.IsSecret(t.absorbBar._max), "secret absorbs handed to the bar untouched")
eq(next(GlassUF.paintFailures), nil, "no paint failures")
WoW.secretFields.absorbs, WoW.secretFields.maxHealth = nil, nil

-- The option: off clears every bar and is saved; on repaints and saves nothing.
WoW.units.player.absorbs = 87
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); WoW.tick()
eq(bar._value, 87, "shown while on")
check(GlassUF.Settings.SetAbsorbs(false), "turned off")
WoW.tick()
eq(bar._value, 0, "off clears the bar")
eq(GlassUnitFramesDB.absorbBar, false, "off is saved")
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "player"); WoW.tick()
eq(bar._value, 0, "and stays clear on the next change")
GlassUF.Settings.SetAbsorbs(true); WoW.tick()
eq(bar._value, 87, "on repaints the shield")
eq(GlassUnitFramesDB.absorbBar, nil, "on is the default: nothing saved")

-- The slash command.
SlashCmdList.GLASSUNITFRAMES("absorb off"); WoW.tick()
eq(GlassUF.Frames.absorbs, false, "/glass absorb off")
SlashCmdList.GLASSUNITFRAMES("absorb on"); WoW.tick()
eq(GlassUF.Frames.absorbs, true, "/glass absorb on")

-- The preview's sample shows a shield on the target (only while on).
GlassUF.Frames.PaintSample(t)
eq(t.absorbBar._value, GlassUF.Frames.SAMPLES.target.maxHp * 0.2, "the sample's shield")
GlassUF.Frames.absorbs = false
GlassUF.Frames.PaintSample(t)
eq(t.absorbBar._value, 0, "no sample shield while off")
GlassUF.Frames.absorbs = true

-- The player's docked cast row shrinks health: the absorb bar follows.
local before = p.health._height
p.castShown = true
GlassUF.Frames.ReflowRows(p)
check(p.health._height < before, "the docked cast row shrinks health")
eq(bar._height, p.health._height, "the bar's height follows the health row")
p.castShown = nil
GlassUF.Frames.ReflowRows(p)
eq(bar._height, before, "and grows back with it")

-- A saved off applies at build.
WoW.reset()
standardUnits()
GlassUF = nil
stubAbsorbs()
loadAddon({ db = { font = "arial", hideBlizzard = true, absorbBar = false, pos = {} } })
eq(GlassUF.Frames.absorbs, false, "saved off applied at build")

-- No heal prediction calculator: the shield starts at the health fill's edge.
WoW.reset()
standardUnits()
GlassUF = nil
stubAbsorbs()
local realCreate = CreateUnitHealPredictionCalculator
CreateUnitHealPredictionCalculator = nil
loadAddon()
local pb = button("player")
check(pb.healPred == nil and pb.absorbBar ~= nil, "no prediction bar, but an absorb bar")
eq(pb.absorbBar._points[1][2], pb.health:GetStatusBarTexture(), "anchored to the health fill's edge")
CreateUnitHealPredictionCalculator = realCreate

-- No absorb API: no bar, nothing breaks.
WoW.reset()
standardUnits()
GlassUF = nil
UnitGetTotalAbsorbs = nil
loadAddon()
check(button("player").absorbBar == nil and button("player").health ~= nil, "no API: no absorb bar, frame fine")
check(button("player").channels.absorb == nil, "and no absorb channel")
eq(next(GlassUF.paintFailures), nil, "no paint failures")

done("test_absorb")
