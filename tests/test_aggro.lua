-- #28: a neutral NPC fighting you reads red, like Blizzard's nameplate.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local HOSTILE, NEUTRAL = { 0.85, 0.22, 0.22 }, { 0.92, 0.76, 0.22 }
local function colourOf(b) return b.health._color end
local function same(c, want) return c and c[1] == want[1] and c[2] == want[2] and c[3] == want[3] end

standardUnits()
loadAddon()
local t = button("target")

-- A neutral NPC at peace: yellow.
WoW.SetUnit("target", { name = "Kodo", reaction = 4, selType = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(same(colourOf(t), NEUTRAL), "neutral NPC at peace is yellow")

-- It attacks you: the selection type turns hostile (what the nameplate shows).
WoW.units.target.selType = 0
WoW.fire("UNIT_FLAGS", "target"); WoW.tick()
check(same(colourOf(t), HOSTILE), "neutral NPC fighting you turns red (selection type)")

-- Fallback: selection type unchanged, but you're on its threat list.
WoW.units.target.selType, WoW.units.target.threat = 2, 3
WoW.fire("UNIT_THREAT_LIST_UPDATE", "target"); WoW.tick()
check(same(colourOf(t), HOSTILE), "on its threat list: red")

-- Fight over.
WoW.units.target.threat = nil
WoW.fire("UNIT_FLAGS", "target"); WoW.tick()
check(same(colourOf(t), NEUTRAL), "fight over: yellow again")

-- Secret answers mean "don't know": stays yellow, and nothing fails.
WoW.secretFields.selType, WoW.secretFields.threat = true, true
WoW.units.target.selType, WoW.units.target.threat = 0, 3
WoW.fire("UNIT_FLAGS", "target"); WoW.tick()
check(same(colourOf(t), NEUTRAL), "secret selection/threat: stays yellow, no guess")
eq(next(GlassUF.paintFailures), nil, "no failures on the secret path")
WoW.secretFields.selType, WoW.secretFields.threat = nil, nil

-- The option: off keeps neutral NPCs yellow, saved only when off.
WoW.fire("UNIT_FLAGS", "target"); WoW.tick()
check(same(colourOf(t), HOSTILE), "back to red with plain values")
GlassUF.Settings.SetAggroRed(false); WoW.tick()
check(same(colourOf(t), NEUTRAL), "option off: yellow even while fighting (repainted live)")
eq(GlassUnitFramesDB.aggroRed, false, "off is saved")
GlassUF.Settings.SetAggroRed(true); WoW.tick()
check(same(colourOf(t), HOSTILE), "option on again: red")
eq(GlassUnitFramesDB.aggroRed, nil, "on is the default: nothing saved")

-- A hostile mob is red regardless; the option only affects neutral NPCs.
WoW.SetUnit("target", { name = "Defias", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(same(colourOf(t), HOSTILE), "hostile stays red")

-- Saved "off" applies at build.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = { font = "arial", hideBlizzard = true, aggroRed = false, pos = {} } })
eq(GlassUF.Frames.aggroRed, false, "saved off applied at build")
GlassUnitFramesDB = nil

done("test_aggro")
