-- Every unit value secret: nothing may do Lua arithmetic, ordering, concat,
-- tostring or string.format on one. (Truth tests and == cannot be caught by
-- any Lua 5.1 stub; those are covered by review and the in-game probe.)
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
for _, f in ipairs({ "health", "maxHealth", "power", "maxPower", "powerToken", "name", "class",
                     "reaction", "player", "connected", "dead", "tapDenied", "visible",
                     "castRemaining", "castName" }) do
    WoW.secretFields[f] = true
end
WoW.units.player.casting = { name = "Shadow Bolt" }
WoW.units.target.casting = { name = "Frostbolt", channel = true }

loadAddon()                       -- throws if a painter misuses a secret outside attempt()
WoW.fireAllRegistered()
WoW.tick()
WoW.tick(0.1)                     -- cast time text updates
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target")
WoW.fire("UNIT_SPELLCAST_STOP", "target")
WoW.flushTimers()
SlashCmdList.GLASSUNITFRAMES("secrets")

-- attempt() swallows errors to keep the frame alive; any it caught is a bug here.
for step, err in pairs(GlassUF.paintFailures) do check(false, "paint step failed on secrets: " .. step .. ": " .. err) end

local p = button("player")
check(WoW.IsSecret(p.health._value), "secret health handed to the StatusBar untouched")
check(WoW.IsSecret(p.health._max), "secret max handed to the StatusBar untouched")
check(WoW.IsSecret(p.power._value), "secret power handed to the StatusBar untouched")
check(type(textOf(p.valueText)) == "table" and textOf(p.valueText).secretFormat == "%s/%s",
      "value text formatted by the client from secrets")
local tv = textOf(button("target").valueText)
check(type(tv) == "table" and tv.secretFormat == "%s/%s | %.0f%%", "target cur/max | pct formatted from secrets")
check(type(textOf(p.powerLeftText)) == "table", "power percent formatted from a secret")
check(type(textOf(p.nameText)) == "table", "secret name formatted by the client (with AFK/group slots)")
check(type(textOf(p.powerText)) == "table", "power text formatted by the client from a secret")
eq(p.health._color[1], 0.56, "secret identity falls back to the default colour")
eq(p.power._color[3], 1.00, "secret power type falls back to mana colour")

local c = p.cast
check(c.bar._timer and c.bar._timer.duration ~= nil, "cast timer handed a DurationObject")
check(type(textOf(c.time)) == "table", "cast time formatted by the client from a secret")

-- The report ran and classified secrets.
local sawSecretLine = false
for _, line in ipairs(WoW.chat) do
    if line:find("player: hp=S") then sawSecretLine = true end
end
check(sawSecretLine, "/glass secrets classifies secret health as S")

done("test_secrets")
