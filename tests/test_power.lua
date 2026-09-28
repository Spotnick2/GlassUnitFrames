-- #27: no power display on units without power. For other units max power
-- is secret, so the client's colour curve decides the opacity.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local t = button("target")

-- A guard with no power, max secret: "0%" and "0/0" fade, the level stays.
WoW.secretFields.power, WoW.secretFields.maxPower = true, true
WoW.SetUnit("target", { name = "Stormwind City Guard", level = 55, power = 0, maxPower = 0, powerToken = "RAGE" })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(WoW.IsSecret(t.power._alpha), "secret max: the client's (secret) alpha goes straight to the bar")
check(WoW.IsSecret(t.powerText._alpha) and WoW.IsSecret(t.powerLeftText._alpha), "and to the power numbers")
check(t.levelText._alpha == nil or t.levelText._alpha == 1, "the level text is never faded")
eq(next(GlassUF.paintFailures), nil, "no failures on the secret path")
SlashCmdList.GLASSUNITFRAMES("secrets")
local line
for _, l in ipairs(WoW.chat) do if l:find("  target: ", 1, true) then line = l end end
check(line and line:find("pwAlpha=S", 1, true) and line:find("pwBar=S", 1, true),
      "/glass secrets reports the curve's opacity and the bar's: " .. tostring(line))

-- Plain values (a client that doesn't hide them): the curve's own answer.
WoW.secretFields.power, WoW.secretFields.maxPower = nil, nil
WoW.fire("UNIT_POWER_UPDATE", "target"); WoW.tick()
eq(t.power._alpha, 0, "plain 0/0: faded")
WoW.units.target.maxPower, WoW.units.target.power = 100, 40
WoW.fire("UNIT_MAXPOWER", "target"); WoW.tick()
eq(t.power._alpha, 1, "a unit with power: shown")

-- A client that refuses a secret alpha: shown as before, never stuck hidden.
WoW.secretFields.power, WoW.secretFields.maxPower = true, true
for _, region in ipairs({ t.power, t.powerText, t.powerLeftText }) do
    rawset(region, "SetAlpha", function(self, a)
        if WoW.IsSecret(a) then error("secret alpha refused") end
        self._alpha = a
    end)
end
WoW.fire("UNIT_POWER_UPDATE", "target"); WoW.tick()
eq(t.power._alpha, 1, "refused secret alpha: bar shown")
check(GlassUF.paintFailures["power alpha"] ~= nil, "the refusal is recorded for /glass secrets")

done("test_power")
