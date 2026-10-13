-- The hover tooltip (#80): every unit button shows Blizzard's own unit
-- tooltip (UnitFrame_OnEnter / OnLeave), never on a forbidden tooltip, and an
-- error there never reaches the button.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()

-- Without the client's tooltip (the stub has none): hovering does nothing.
local t = button("target")
check(t._scripts.OnEnter ~= nil and t._scripts.OnLeave ~= nil, "OnEnter / OnLeave on the button")
check(pcall(t._scripts.OnEnter, t), "no GameTooltip: hovering is harmless")

-- With it: Blizzard's own functions, handed the button (they read self.unit).
local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
local forbidden = false
rawset(tip, "IsForbidden", function() return forbidden end)
local entered, left = {}, {}
rawset(_G, "UnitFrame_OnEnter", function(self) entered[#entered + 1] = self end)
rawset(_G, "UnitFrame_OnLeave", function(self) left[#left + 1] = self end)
for _, u in ipairs(GlassUF.Frames.ORDER) do
    local b = button(u)
    b._scripts.OnEnter(b)
    b._scripts.OnLeave(b)
end
eq(#entered, #GlassUF.Frames.ORDER, "every frame shows the unit tooltip")
eq(entered[2], t, "handed the button itself")
eq(entered[2].unit, "target", "whose unit Blizzard's code reads")
eq(#left, #GlassUF.Frames.ORDER, "and hides it on leave")

-- A forbidden tooltip is left alone.
forbidden = true
t._scripts.OnEnter(t)
eq(#entered, #GlassUF.Frames.ORDER, "forbidden: not touched")
forbidden = false

-- An error in Blizzard's code is recorded, never thrown at the button.
rawset(_G, "UnitFrame_OnEnter", function() error("boom") end)
check(pcall(t._scripts.OnEnter, t), "an error doesn't escape")
check(GlassUF.paintFailures.tooltip ~= nil, "it's recorded (/glass secrets)")
GlassUF.paintFailures.tooltip = nil

-- Clicks still work: the hooks don't replace the button's own handlers.
eq(t._attrs["*type1"], "target", "left-click still targets")
done("test_tooltip")
