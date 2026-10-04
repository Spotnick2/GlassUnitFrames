-- The material's optional directional edge (#60): off by default and hidden,
-- live-tuned for every surface with /glass edge (saved only once set), and a
-- host can set its own values, which the global tune then leaves alone.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GUF = loadAddon()
local Glass = GUF.Glass
local host = CreateFrame("Frame", nil, UIParent)
host:SetSize(200, 40)
local g = Glass.Apply(host, "large")
check(g.edge and g.edge.top and g.edge.glow and g.edge.bottom, "every glass surface has an edge")
check(not g.edge.top:IsShown() and not g.edge.bottom:IsShown(), "off by default: hidden, so nothing changes for anyone")
eq(Glass.STYLE.edge, 0, "the shipped edge is 0")

SlashCmdList.GLASSUNITFRAMES("edge 0.45")
check(g.edge.top:IsShown(), "/glass edge shows it")
eq(g.edge.top._color[4], 0.45, "the top line at the value")
check(math.abs(g.edge.bottom._color[4] - 0.35) < 1e-6, "the bottom line in proportion (0.35)")
eq(GlassUnitFramesDB.edge, 0.45, "saved once set")

-- A host with its own values keeps them.
local host2 = CreateFrame("Frame", nil, UIParent)
local g2 = Glass.Apply(host2, "small")
Glass.SetEdge(g2, 0.6, 0.2, 0.5, 6)
SlashCmdList.GLASSUNITFRAMES("edge 0.1")
eq(g2.edge.top._color[4], 0.6, "a host's own edge isn't overridden by the global tune")
eq(g.edge.top._color[4], 0.1, "while the others follow it")

SlashCmdList.GLASSUNITFRAMES("edge 0")
check(not g.edge.top:IsShown(), "0 hides it again")
SlashCmdList.GLASSUNITFRAMES("edge 2")
eq(Glass.STYLE.edge, 0, "out of range is refused")

done("test_edge")
