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
SlashCmdList.GLASSUNITFRAMES("secrets")
local plainLine
for _, l in ipairs(WoW.chat) do if l:find("  target: ", 1, true) then plainLine = l end end
check(plainLine and plainLine:find("pwAlpha=1.00", 1, true) and plainLine:find("pwBar=1.0", 1, true),
      "plain values are printed, not just 'ok': " .. tostring(plainLine))

-- The level text follows the name channel's events, not every power tick.
WoW.units.target.classification = "rareelite"
WoW.fire("UNIT_CLASSIFICATION_CHANGED", "target"); WoW.tick()
check(t.levelText._text ~= nil and tostring(t.levelText._text):find("Rare", 1, true) ~= nil,
      "classification change repaints the level text: " .. tostring(t.levelText._text))

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

-- Other players always keep their power bar (SUF's behaviour): a warrior at
-- 0 rage shows an empty rage bar. Only NPCs hide.
WoW.reset(); standardUnits(); GlassUF = nil
loadAddon()
t = button("target")
WoW.secretFields.power, WoW.secretFields.maxPower = true, true
WoW.SetUnit("target", { name = "Themeek Tank", player = true, class = "WARRIOR", level = 12,
                        power = 0, maxPower = 100, powerToken = "RAGE" })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(t.power._alpha, 1, "a player target at 0 rage keeps the rage bar")
WoW.SetUnit("target", { name = "Undercity Guardian", player = false, level = 55,
                        power = 0, maxPower = 0, powerToken = "RAGE" })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(WoW.IsSecret(t.power._alpha), "an NPC target still takes the curve's alpha")

-- The empty part of a power bar: the material's ramp, quieted, so a low bar
-- reads low. Health too; /glass track still scales both.
local p = button("player")
eq(p.power.trackClip._alpha, 0.25, "power track at a quarter of the ramp (on its clip frame)")
eq(p.health.trackClip._alpha, 0.25, "health track too")
eq(button("targettarget").health.trackClip._alpha, 0.25, "on every frame")
SlashCmdList.GLASSUNITFRAMES("track 0.4")
eq(p.power.track._vertex[4], 0.4, "the global track still reaches the power bar")
eq(p.power.trackClip._alpha, 0.25, "and keeps its quieting")
check(p.power.track._alpha == nil or p.power.track._alpha == 1, "never the texture's own SetAlpha (no effect in game)")

done("test_power")
