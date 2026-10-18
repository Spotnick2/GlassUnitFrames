-- Click-casting (#125): every unit button is registered in Clique's
-- ClickCastFrames table, so a click-caster (GlassRaidFrames, Clique) binds it.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- No click-caster loaded: the table is created, one entry per built button.
standardUnits()
loadAddon()
local registry = rawget(_G, "ClickCastFrames")
check(type(registry) == "table", "ClickCastFrames created when absent")
for _, u in ipairs(GlassUF.Frames.ORDER) do
    eq(registry[button(u)], true, "registered: " .. u)
    eq(registry[button(u)], registry[rawget(_G, "GlassUF_" .. u)], "the named button: " .. u)
end
eq(button("target"):GetAttribute("*type1"), "target", "plain left click still targets")
eq(button("target"):GetAttribute("*type2"), "togglemenu", "plain right click still opens the menu")

-- A click-caster loaded first keeps its entries behind the public table and
-- sees assignments only through __newindex: every button must go through it.
WoW.reset()
standardUnits()
local seen, existing = {}, {}
local watching = setmetatable({}, { __newindex = function(_, k, v) seen[k] = v end,
                                    __index = existing })
existing.someoneElse = true
rawset(_G, "ClickCastFrames", watching)
loadAddon()
eq(rawget(_G, "ClickCastFrames"), watching, "an existing table is kept, never replaced")
for _, u in ipairs(GlassUF.Frames.ORDER) do
    eq(seen[button(u)], true, "through __newindex: " .. u)
    eq(rawget(watching, button(u)), nil, "never rawset: " .. u)
end
eq(watching.someoneElse, true, "other entries untouched")

done("test_clickcast")
