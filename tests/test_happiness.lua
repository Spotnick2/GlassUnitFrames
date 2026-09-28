-- Hunter pet happiness on the pet's portrait.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local pet = button("pet")
local icon = pet.indicators.happiness
check(icon ~= nil, "the pet frame has a happiness icon")
eq(icon._file, [[Interface\PetPaperDollFrame\UI-PetHappiness]], "Blizzard's happiness texture, path intact")
check(button("player").indicators.happiness == nil, "only the pet frame")
check(not icon._shown, "hidden without a hunter pet")
eq(GlassUF.Frames.happinessPos, "left", "default: left of the pet's portrait")
eq(icon._points[1][2], pet.tile, "anchored to the portrait")
eq(icon._points[1][3], "LEFT", "on its left")

-- A hunter's pet: the cell follows its mood.
WoW.hunterPet, WoW.petHappiness = true, 3
WoW.fire("UNIT_HAPPINESS", "pet"); WoW.tick()
check(icon._shown, "happy hunter pet: shown")
eq(icon._texCoord and icon._texCoord[1], 0, "happy: the green cell")
WoW.petHappiness = 1
WoW.fire("UNIT_HAPPINESS", "pet"); WoW.tick()
eq(icon._texCoord and icon._texCoord[1], 0.375, "unhappy: the red cell")

-- A warlock's demon: never.
WoW.hunterPet = false
WoW.fire("UNIT_HAPPINESS", "pet"); WoW.tick()
check(not icon._shown, "not a hunter pet: hidden")

-- Secret happiness: hidden, no failure.
WoW.hunterPet, WoW.secretFields.happiness = true, true
WoW.fire("UNIT_HAPPINESS", "pet"); WoW.tick()
check(not icon._shown, "secret happiness: hidden")
eq(next(GlassUF.paintFailures), nil, "no failures")
WoW.secretFields.happiness = nil

-- /glass secrets reports it.
WoW.petHappiness = 2
SlashCmdList.GLASSUNITFRAMES("secrets")
local found
for _, l in ipairs(WoW.chat) do if l:find("petHappiness=2", 1, true) then found = true end end
check(found, "/glass secrets prints the pet's happiness")

-- Placement options: right of the frame (Blizzard's spot), under the portrait.
check(GlassUF.Settings.SetHappinessPosition("right"), "right accepted")
eq(icon._points[1][2], pet, "right: anchored to the whole frame")
eq(icon._points[1][3], "RIGHT", "past its right edge")
eq(GlassUnitFramesDB.happiness, "right", "saved")
SlashCmdList.GLASSUNITFRAMES("happiness under")
eq(icon._points[1][2], pet.tile, "under: anchored to the portrait")
eq(icon._points[1][3], "BOTTOM", "below it")
check(not GlassUF.Settings.SetHappinessPosition("above"), "unknown placement rejected")
local saved = GlassUnitFramesDB
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
eq(button("pet").indicators.happiness._points[1][3], "BOTTOM", "saved placement applied at build")
GlassUnitFramesDB = nil

done("test_happiness")
