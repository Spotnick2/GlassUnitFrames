-- The regen segment (#118): a faint bar past the mana fill, as wide as the
-- next 2 s of regen. Nothing computed: twice the bar's width, the range
-- (0, max mana), the rate as its value. Inside the five-second window the
-- casting rate applies. A setting, on by default.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local MANA_SPELL = 686
local function costs() WoW.spellCosts[MANA_SPELL] = { { type = 0, cost = 25, minCost = 25 } } end
local regen = { 6.501, 0.001 }
GetManaRegen = function() return regen[1], regen[2] end

-- A warlock (the standard units): mana 920 / 1270, its display power (power / maxPower).
standardUnits()
costs()
loadAddon()
local F, T = GlassUF.FiveSecond, GlassUF.FiveSecond._test
local S = GlassUF.Settings
local st = T.state
local pl = button("player")
local segs = T.segs()
check(segs and segs.power, "a mana user gets the segment on the power bar")
check(segs.druid == nil, "no druid strip for a warlock")
local g = segs.power
local bar, clip = g.bar, g.clip

local function adv(s) WoW.now = WoW.now + s; WoW.runDue() end
local function cast() WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", MANA_SPELL) end
local function mana() WoW.fire("UNIT_POWER_UPDATE", "player", "MANA") end
local function settle() adv(30); T.reset() end

-- Geometry: from the fill's moving edge, top and bottom, twice the bar wide,
-- inside a clip over the bar.
local fill = pl.power:GetStatusBarTexture()
eq(bar._points[1][1], "TOPLEFT", "its top-left")
eq(bar._points[1][2], fill, "on the fill")
eq(bar._points[1][3], "TOPRIGHT", "at its moving edge")
eq(bar._points[2][1], "BOTTOMLEFT", "and its bottom-left")
eq(bar._points[2][3], "BOTTOMRIGHT", "on the fill's bottom edge (follows the row's height)")
eq(bar:GetWidth(), 2 * pl.healthWidth, "twice the bar's width")
eq(clip:GetParent(), pl.power, "its clip is on the power bar")
check(clip._clips, "and clips")

-- Out of combat, below full: the base rate over (0, max mana).
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(clip._shown, "shown below full")
eq(clip._alpha, 1, "visible")
eq(bar._min, 0, "range from 0")
eq(bar._max, 1270, "to max mana")
eq(bar._value, 6.501, "the base rate (2 s on a bar twice as wide)")

-- A spend: the casting rate through the window, the base rate after.
cast()
eq(st.state, "window", "a spend opens the window")
eq(bar._value, 0.001, "inside the window: the casting rate")
adv(5.1)
eq(st.state, "idle", "the window ends")
eq(bar._value, 6.501, "the base rate again")

-- The rate follows the mana sync (a spirit buff); max mana its own event.
regen[1] = 9
mana()
eq(bar._value, 9, "a mana update re-reads the rate")
WoW.units.player.maxPower = 1500
WoW.fire("UNIT_MAXPOWER", "player", "RAGE")
eq(bar._max, 1270, "a rage max change doesn't repaint")
WoW.fire("UNIT_MAXPOWER", "player", "MANA")
eq(bar._max, 1500, "a mana max change does")

-- Full mana: hidden by the client's alpha.
WoW.units.player.power = 1500
mana()
eq(clip._alpha, 0, "full mana: alpha 0")
WoW.units.player.power = 920
mana()
eq(clip._alpha, 1, "below full again")

-- In combat: the rate, the max and the alpha may all be secret; each goes
-- straight to the client.
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
regen = { WoW.Secret("baseRegen"), WoW.Secret("castingRegen") }
WoW.units.player.maxPower = WoW.Secret("maxMana")
mana()
check(WoW.IsSecret(bar._value), "a secret rate reaches the bar")
check(bar._value == regen[1], "the base one")
check(WoW.IsSecret(bar._max), "a secret max too")
cast()
check(bar._value == regen[2], "a spend in combat: the secret casting rate")
check(clip._shown, "still shown")
eq(next(GlassUF.paintFailures), nil, "no failure with secrets")
settle()
regen = { 6.501, 0.001 }
WoW.units.player.maxPower = 1500
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")

-- Death hides it; coming back shows it again.
WoW.units.player.dead = true
WoW.fire("PLAYER_DEAD")
check(not clip._shown, "dead: hidden")
WoW.units.player.dead = false
WoW.fire("PLAYER_UNGHOST")
check(clip._shown, "back alive: shown")
WoW.units.player.dead = true
WoW.fire("PLAYER_DEAD")
WoW.units.player.dead = false
WoW.fire("PLAYER_ALIVE")
check(clip._shown, "PLAYER_ALIVE too")

-- A failing setter: recorded, hidden.
local realSet = bar.SetValue
bar.SetValue = function() error("refused") end
mana()
check(GlassUF.paintFailures.regen ~= nil, "a failure is recorded")
check(not clip._shown, "and the segment hidden")
bar.SetValue = realSet
GlassUF.paintFailures.regen = nil
mana()
check(clip._shown, "shown again once it works")

-- The setting: off hides it and saves; the window is still tracked for the
-- strip; on: not saved.
SlashCmdList.GLASSUNITFRAMES("regen off")
check(not clip._shown, "off: hidden")
eq(GlassUnitFramesDB.manaRegen, false, "saved when off")
mana()
check(not clip._shown, "off: a mana update doesn't show it")
SlashCmdList.GLASSUNITFRAMES("regen on")
eq(GlassUnitFramesDB.manaRegen, nil, "on: not saved")
check(clip._shown, "on: shown")
SlashCmdList.GLASSUNITFRAMES("regen maybe")
check(WoW.chat[#WoW.chat]:find("regen on|off", 1, true), "a wrong word gets the usage")

-- The strip off, the segment on: a spend still switches the rate (the window
-- is tracked for the segment).
S.SetFiveSecond(false)
cast()
eq(bar._value, 0.001, "strip off: the window still applies the casting rate")
check(not T.strips().power.clip._shown, "and the strip stays hidden")
-- The segment off while a window runs: the strip keeps it, with its expiry.
S.SetFiveSecond(true)
settle()
cast()
local gen = st.gen
S.SetManaRegen(false)
eq(st.state, "window", "segment off, strip on: the window is kept")
eq(st.gen, gen, "the same window")
S.SetManaRegen(true)
eq(bar._value, 0.001, "segment on again mid-window: the casting rate")
adv(5.1)
eq(st.state, "idle", "the window ends on its own timer")
eq(bar._value, 6.501, "and the rate goes back")
-- Both off: no events. One on again: tracked.
S.SetFiveSecond(false); S.SetManaRegen(false)
cast()
eq(st.state, "idle", "both off: a spend does nothing")
S.SetManaRegen(true)
cast()
eq(st.state, "window", "the segment on again: spends count")
settle()
S.SetFiveSecond(true)

-- Options: the switch on the main page.
local O = GlassUF.Options
O._test.panel:Show()
local c = O._test.controls
check(c.manaRegen ~= nil, "a regen switch")
c.manaRegen:SetChecked(false); c.manaRegen._scripts.OnClick(c.manaRegen)
eq(GlassUnitFramesDB.manaRegen, false, "the switch turns it off")
c.manaRegen:SetChecked(true); c.manaRegen._scripts.OnClick(c.manaRegen)
eq(GlassUnitFramesDB.manaRegen, nil, "and on")

-- Preview: no override at full mana (the segment is past the end anyway),
-- and its own events still repaint it.
WoW.units.player.power = 1500
check(S.SetPreview(true), "preview")
eq(clip._alpha, 0, "preview at full mana: still alpha 0")
WoW.units.player.power = 920
mana()
eq(clip._alpha, 1, "a mana update in preview repaints it")
WoW.units.player.dead = true
WoW.fire("PLAYER_DEAD")
check(not clip._shown, "a death in preview hides it")
WoW.units.player.dead = false
WoW.fire("PLAYER_ALIVE")
check(clip._shown, "and alive shows it")
-- The strip off during the sample window and during its pause: the sample
-- loop ends, the rate stays the base one.
check(st.state == "window", "the strip's sample window runs")
S.SetFiveSecond(false)
adv(12)
eq(st.state, "idle", "strip off in the sample window: the loop ends")
eq(bar._value, 6.501, "the base rate")
S.SetFiveSecond(true)
adv(5.1)
eq(st.state, "idle", "the sample's pause")
S.SetFiveSecond(false)
adv(12)
eq(st.state, "idle", "strip off in the pause: the loop ends too")
S.SetFiveSecond(true)
S.SetPreview(false)
eq(next(GlassUF.paintFailures), nil, "no failures (warlock)")

-- A druid: in a form, on the druid strip; through a real preview the druid
-- strip shows a fixed 60%, so its segment hides.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class, WoW.units.player.powerToken = "DRUID", "RAGE"
WoW.units.player.power, WoW.units.player.maxPower = 20, 100
WoW.units.player.mana, WoW.units.player.maxMana = 250, 300
costs()
loadAddon()
F, T = GlassUF.FiveSecond, GlassUF.FiveSecond._test
S = GlassUF.Settings
pl = button("player")
local ds = T.segs()
check(ds.druid ~= nil, "a druid gets a segment on the druid strip")
eq(ds.druid.bar._points[1][2], pl.druidMana.bar:GetStatusBarTexture(), "from its fill's edge")
eq(ds.druid.bar:GetWidth(), 2 * pl.druidMana.width, "twice its width")
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
check(ds.druid.clip._shown and not ds.power.clip._shown, "in a form: on the druid strip")
eq(ds.druid.bar._max, 300, "max mana, not the rage bar's")
WoW.units.player.powerToken = "MANA"
WoW.fire("UNIT_DISPLAYPOWER", "player")
check(ds.power.clip._shown and not ds.druid.clip._shown, "caster form: on the power bar")
WoW.units.player.powerToken = "RAGE"
WoW.fire("UNIT_DISPLAYPOWER", "player")
check(S.SetPreview(true), "preview (druid)")
check(not ds.druid.clip._shown, "in a form, in preview: the sampled strip gets no segment")
check(not ds.power.clip._shown, "nor the rage bar")
WoW.units.player.powerToken = "MANA"
WoW.fire("UNIT_DISPLAYPOWER", "player")
check(ds.power.clip._shown, "caster form in preview: the live power bar's segment")
WoW.units.player.powerToken = "RAGE"
WoW.fire("UNIT_DISPLAYPOWER", "player")
check(not ds.druid.clip._shown, "a form again: hidden")
S.SetPreview(false)
check(ds.druid.clip._shown, "preview over: the druid strip's segment is back")
eq(next(GlassUF.paintFailures), nil, "no failures (druid)")

-- A warrior: nothing built, no switch, the slash says so.
WoW.reset(); standardUnits(); GlassUF = nil
WoW.units.player.class, WoW.units.player.powerToken = "WARRIOR", "RAGE"
loadAddon()
check(GlassUF.FiveSecond._test.segs() == nil, "a warrior gets no segment")
GlassUF.Options._test.panel:Show()
check(GlassUF.Options._test.controls.manaRegen == nil, "no switch for a warrior")
SlashCmdList.GLASSUNITFRAMES("regen off")
check(WoW.chat[#WoW.chat]:find("mana users only", 1, true), "the slash says it's for mana users")
eq(GlassUnitFramesDB.manaRegen, nil, "and saves nothing")

GlassUnitFramesDB = nil
done("test_regen")
