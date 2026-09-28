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

-- PET_UI_UPDATE (Blizzard's PetFrame refreshes here) repaints it too: after a
-- login or call, HasPetUI may only report the hunter pet by then.
WoW.petHappiness = 2
WoW.fire("PET_UI_UPDATE"); WoW.tick()
eq(icon._texCoord and icon._texCoord[1], 0.1875, "PET_UI_UPDATE refreshes the icon (content)")
check(button("player").channels.happiness == nil, "only the pet frame carries the happiness channel")

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
-- Both on the right: the raid mark steps past the happiness icon.
GlassUF.Settings.SetMark("right")
GlassUF.Settings.SetHappinessPosition("right")
eq(pet.indicators.raidTarget._points[1][2], icon, "right-hand mark sits past the right-hand happiness icon")
GlassUF.Settings.SetHappinessPosition("left")
eq(pet.indicators.raidTarget._points[1][2], pet, "happiness moved away: the mark takes the frame's edge again")
GlassUF.Settings.SetMark("name")
GlassUF.Settings.SetHappinessPosition("under")
local saved = GlassUnitFramesDB
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon({ db = saved })
eq(button("pet").indicators.happiness._points[1][3], "BOTTOM", "saved placement applied at build")
GlassUnitFramesDB = nil

-- Without HasPetUI, only a hunter's pet shows it (fail closed).
local realHasPetUI = HasPetUI
rawset(_G, "HasPetUI", nil)
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon()
WoW.hunterPet, WoW.petHappiness = true, 3
WoW.fire("UNIT_HAPPINESS", "pet"); WoW.tick()
check(not button("pet").indicators.happiness._shown, "no HasPetUI and a warlock player: hidden")
WoW.units.player.class = "HUNTER"
WoW.fire("UNIT_HAPPINESS", "pet"); WoW.tick()
check(button("pet").indicators.happiness._shown, "no HasPetUI and a hunter player: shown")
rawset(_G, "HasPetUI", realHasPetUI)

done("test_happiness")
