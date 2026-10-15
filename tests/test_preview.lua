-- Preview mode (#109): every frame and bar with sample data, out of combat.
-- The frames with no unit show samples; the player's frame stays live but for
-- its cast bar and druid mana strip; real events never repaint a sample, and
-- stopping brings back exactly the real state.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ABSENT = { "target", "pet", "targettarget", "targettargettarget", "focus", "focustarget" }
local MANA_SPELL = 686

local function setup()
    standardUnits()
    for _, u in ipairs(ABSENT) do WoW.units[u] = nil end
    WoW.spellCosts[MANA_SPELL] = { { type = 0, cost = 25, minCost = 25 } }
    loadAddon()
    WoW.applyUnitWatch()
end
setup()

local P, S = GlassUF.Preview, GlassUF.Settings
local Castbar, Swing, F = GlassUF.Castbar, GlassUF.Swing, GlassUF.FiveSecond
local loops = P._test.loops
-- Small steps, so chained timers fire on time (a step of 1/8 s adds exactly).
local function adv(s)
    while s > 1e-9 do
        local d = math.min(s, 0.125)
        WoW.now = WoW.now + d
        WoW.runDue()
        s = s - d
    end
end
local function tick() WoW.tick(0.06) end
local function bar(u) return Castbar.bars[u] end
local function anyBlocked() return next(WoW.blocked) ~= nil end

for _, u in ipairs(ABSENT) do check(not button(u)._shown, u .. ": hidden with no unit") end

-- Refused in combat.
WoW.combat = true
local ok, why = P.Start()
check(not ok and why == "combat" and not P.active, "refused in combat")
WoW.combat = false

-- A real swing out of combat shows its row; Blizzard turns its range check
-- off, and the re-enable is queued for the next frame.
local rows = Swing._test.rows()
WoW.fire("PLAYER_SWING", 3.3, 0)
check(rows[1].visible, "a real swing's row")
Swing._test.onRangeCheck(0, false)
check(Swing._test.pending[0], "a re-enable queued")
local checksBefore = #WoW.rangeChecks

-- Start: every other frame leaves its unit watch and shows sample data.
eq(S.SetPreview(true), true, "Settings.SetPreview(true): on")
WoW.runDue()
eq(#WoW.rangeChecks, checksBefore, "the queued re-enable runs during the preview: no call")
for _, u in ipairs(ABSENT) do
    local b = button(u)
    check(b._shown and WoW.unitWatch[b] == nil and b._unwatched, u .. ": unwatched and shown")
end
check(not anyBlocked(), "nothing blocked")
local t = button("target")
eq(textOf(t.nameText), "Sample Target", "the target's sample name")
eq(t.health._value, 8400, "sample health")
eq(t.health._max, 12000, "of a sample max")
eq(textOf(t.valueText), "8.4K/12.0K | 70%", "in the frame's health format")
eq(textOf(t.levelText), "60 Elite", "the level on the power line")
eq(t.indicators.raidTarget._raidIndex, 8, "a skull, so the mark's spot shows")
check(t.indicators.raidTarget._shown, "shown")
eq(t.model._modelUnit, "player", "3D portrait: the player's model")
eq(t.lossBar._value, 9600, "the health-loss segment")
eq(textOf(button("targettargettarget").nameText), "Sample ToTT", "name-only frames too")
eq(textOf(button("pet").nameText), "Sample Pet", "the pet")
check(button("pet").indicators.happiness._shown, "the pet's happiness icon")

-- A flush (the OnShow repaints) keeps the samples.
tick()
eq(textOf(t.nameText), "Sample Target", "a flush refreshes the sample, never the unit")

-- Real events never repaint a sample; the player's frame stays live.
WoW.SetUnit("target", { name = "Defias Pillager", reaction = 2, health = 830, maxHealth = 1317 })
WoW.fire("PLAYER_TARGET_CHANGED")
check(bar("target").icon._shown, "a target change doesn't reset the target's sample cast")
WoW.fire("UNIT_HEALTH", "target")
tick()
eq(textOf(t.nameText), "Sample Target", "a real target doesn't replace the sample")
eq(t.health._value, 8400, "nor its health")
WoW.tick(0.6)
eq(textOf(button("targettarget").nameText), "Sample ToT", "the chained-token ticker doesn't either")
WoW.units.player.health = 1000
WoW.fire("UNIT_HEALTH", "player")
tick()
eq(button("player").health._value, 1000, "the player's own health still repaints")

-- Cast bars: every one shows a sample with a duration we own.
for _, u in ipairs({ "player", "target", "focus", "pet" }) do
    local c = bar(u)
    check(c.host._shown, u .. ": a sample cast shows")
    eq(c.bar._timer.duration, loops[u].dur, u .. ": on the preview's own duration")
    check(not WoW.IsSecret(c.bar._timer.duration._dur), u .. ": plain")
end
local pc = bar("player")
eq(textOf(pc.spell), "Frostbolt -> Sample Target", "the player's: spell -> target")
eq(pc.delay, 0.4, "with a pushback")
check(pc.icon._shown and pc.icon._file:find("FrostBolt"), "its icon")
check(button("player").castShown, "the docked row reflows the body")
eq(textOf(bar("target").spell), "Shadow Bolt", "the target's")

-- A real cast never repaints the sample.
WoW.units.player.casting = { name = "Shadow Bolt", remaining = 2 }
WoW.fire("UNIT_SPELLCAST_START", "player", "Cast-3-9", 686)
eq(textOf(pc.spell), "Frostbolt -> Sample Target", "a real START leaves the sample")
WoW.units.player.casting = nil

-- The player's cycle: a cast and its green flash, a channel, a craft that's interrupted.
adv(3.0)
check(pc.flashing, "the cast ends in a flash")
eq(pc.bar._color[1], Castbar.colors.complete[1], "green")
adv(1.5)
eq(textOf(pc.spell), "Arcane Missiles", "then a channel")
check(pc.channel, "a channel")
adv(3.0)
check(not pc.host._shown, "a channel ends with no flash")
adv(1.5)
eq(textOf(pc.spell), "Linen Bandage (2/5)", "then a craft with its count")
adv(3.0)
eq(textOf(pc.spell), "Interrupted", "interrupted")
eq(pc.bar._color[1], Castbar.colors.failed[1], "red")
adv(1.5)
eq(textOf(pc.spell), "Frostbolt -> Sample Target", "and round again")

-- Swing: all three rows loop, with no range-check call and no real swing.
for i, row in ipairs(rows) do check(row.bar._shown and row.live, "swing row " .. i .. " shows and runs") end
eq(#WoW.rangeChecks, checksBefore, "no EnableRangeCheck call")
local mhEnd = rows[1].endTime
WoW.fire("PLAYER_SWING", 3.3, 0)
eq(rows[1].endTime, mhEnd, "a real swing is ignored")
adv(2.7); tick()
check(rows[1].live and rows[1].endTime > mhEnd, "the main hand swings again")
Swing._test.onRangeCheck(0, false)
eq(Swing._test.pending[0], nil, "a Blizzard range-off during the preview queues nothing")
WoW.runDue()
eq(#WoW.rangeChecks, checksBefore, "and calls nothing")

-- The five-second strip: out of combat with "combat only" on, at full mana too.
local strip = F._test.strips().power
WoW.units.player.power = WoW.units.player.maxPower
check(F.combatOnly and strip.clip._shown, "shown out of combat with combat only on")
eq(strip.clip._alpha, 1, "at alpha 1 (full mana would hide the real one)")
local fsrStart = F._test.dur()._start
adv(fsrStart + 5.1 - WoW.now)
check(not strip.clip._shown, "after 5 s: hidden")
adv(1.0)
check(strip.clip._shown and F._test.dur()._start > fsrStart, "1 s later: again")
eq(strip.clip._alpha, 1, "at full mana: still alpha 1")
local sampleStart = F._test.dur()._start
adv(0.5)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", MANA_SPELL)
eq(F._test.dur()._start, sampleStart, "a real spend doesn't restart the sample window")

-- The swing timer and the five-second rule turned off and on during the
-- preview: off hides their samples, on brings them back looping.
S.SetSwingTimer(false)
for i, row in ipairs(rows) do check(not row.bar._shown, "swing off: row " .. i .. " gone") end
S.SetSwingTimer(true)
for i, row in ipairs(rows) do check(row.bar._shown and row.live, "swing on again: row " .. i .. " runs") end
S.SetFiveSecond(false)
check(not strip.clip._shown, "five-second rule off: hidden")
S.SetFiveSecond(true)
check(strip.clip._shown and F._test.state.state == "window", "on again: the sample window")
adv(6.1)
check(strip.clip._shown, "and it loops")
-- Off before the preview starts, on during it: the same.
S.SetPreview(false)
S.SetSwingTimer(false); S.SetFiveSecond(false)
S.SetPreview(true)
check(not rows[1].bar._shown and not strip.clip._shown, "off at the start: no sample")
S.SetSwingTimer(true); S.SetFiveSecond(true)
check(rows[1].bar._shown and rows[1].live and strip.clip._shown, "turned on during the preview: both samples run")
while not loops.player.showing do adv(0.125) end

-- Settings changed during the preview: the sample follows, its step kept.
while not loops.player.showing do adv(0.125) end
local stepDur = loops.player.dur
S.SetCastIcon("player", "none")
check(not pc.icon._shown, "icon none: hidden")
S.SetCastIcon("player", "left")
check(pc.icon._shown, "icon left: back on the sample")
eq(pc.bar._timer.duration, stepDur, "same duration: the step isn't restarted")
S.SetCastDetached("player", true)
check(pc.host._shown and not button("player").castShown, "detached: the sample shows on its pill")
S.SetCastDetached("player", false)
check(pc.host._shown and button("player").castShown, "docked again")
S.SetPortraitMode("target", "2d")
tick()
check(t.portrait2D._shown and not t.model._shown, "portrait 2d: the sample's 2D portrait")
S.SetPortraitMode("target", "none")
check(not t.tile._shown, "portrait none: no tile")
t.model._modelUnit = nil
S.SetPortraitMode("target", "3d")
tick()
eq(t.model._modelUnit, "player", "portrait 3d again: the sample model, not an empty tile")

-- Stop: the unit watch back, absent units hidden, real values everywhere.
eq(S.SetPreview(false), false, "Settings.SetPreview(false): off")
for _, u in ipairs(ABSENT) do
    local b = button(u)
    check(WoW.unitWatch[b], u .. ": watched again")
    if u ~= "target" then check(not b._shown, u .. ": hidden (no unit)") end
end
check(t._shown, "the target (a real one now) stays")
tick()
eq(textOf(t.nameText), "Defias Pillager", "real data over the sample")
eq(t.health._value, 830, "real health")
for _, u in ipairs({ "player", "target", "focus", "pet" }) do
    check(not bar(u).host._shown, u .. ": no real cast, no bar")
end
for i, row in ipairs(rows) do check(not row.bar._shown and not row.visible, "swing row " .. i .. " gone") end
check(not strip.clip._shown and F._test.state.state == "idle", "the strip idle and hidden")
local stray = false
for _ = 1, 80 do
    adv(0.125)
    for _, u in ipairs({ "player", "target", "focus", "pet" }) do stray = stray or bar(u).host._shown end
end
check(not stray, "no sample step or flash outlives the preview")
check(not anyBlocked(), "nothing blocked")

-- Stop with a real cast running: the real bar, no sample target or pushback.
S.SetPreview(true)
WoW.units.player.casting = { name = "Shadow Bolt", remaining = 2 }
S.SetPreview(false)
tick()
check(pc.host._shown, "the real cast shows again")
eq(textOf(pc.spell), "Shadow Bolt", "its own name, no sample target")
eq(pc.delay, nil, "no sample pushback")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-9", 686)
adv(1)

-- Stop during a sample flash: its hide never lands on a real cast after it.
S.SetPreview(true)
adv(3.0)
check(pc.flashing, "mid-flash")
S.SetPreview(false)
WoW.units.player.casting = { name = "Shadow Bolt", remaining = 2 }
WoW.fire("UNIT_SPELLCAST_START", "player", "Cast-3-10", 686)
adv(0.6)
check(pc.host._shown, "the flash's hide doesn't hide the real cast")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-10", 686)
adv(1)

-- A batch held between crafts when the preview starts: the sample has its own duration.
pc.craft = { spellID = 1, total = 5, left = 3, holding = true, merged = true, dur = C_DurationUtil.CreateDuration() }
S.SetPreview(true)
eq(pc.craft, nil, "the batch is forgotten")
eq(pc.bar._timer.duration, loops.player.dur, "the sample's own duration, not the batch's")
S.SetPreview(false)

-- A real health loss queued before the preview never lands on the sample.
tick()   -- the Stop's snapped repaint first: the next one eases, so its loss waits
WoW.units.target.health = 500
WoW.fire("UNIT_HEALTH", "target")
tick()
S.SetPreview(true)
adv(0.5)
eq(t.lossBar._value, 9600, "the pending loss applied nothing")
S.SetPreview(false)
tick()

-- Combat ends it, before Movers locks: measured, the lockdown isn't on yet
-- inside PLAYER_REGEN_DISABLED, so the watch comes back at once.
S.Unlock()
S.SetPreview(true)
local dialog = GlassUF.Movers._test.dialog()
check(dialog.preview:GetChecked(), "the unlock dialog's switch follows")
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.combat = true
check(not P.active, "combat: preview off")
check(not GlassUF.Movers.unlocked, "and unlock mode ended")
check(WoW.unitWatch[button("focus")] and not button("focus")._shown, "the watch is back, the empty frame hidden")
check(not anyBlocked(), "nothing blocked")
-- A spend in that fight shows the real strip (FiveSecond saw the combat start).
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-2", MANA_SPELL)
WoW.units.player.power = 400
WoW.fire("UNIT_POWER_UPDATE", "player", "MANA")
check(strip.clip._shown, "a real spend in combat shows")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
adv(10)

-- FiveSecond hearing the combat start first (while the preview still owns
-- it), then the dispatcher ending the preview: combat is still known.
S.SetPreview(true)
F._test.onEvent(nil, "PLAYER_REGEN_DISABLED")
P.OnCombat()
WoW.combat = true
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-3", MANA_SPELL)
check(strip.clip._shown, "the other order: a real spend in combat shows too")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
adv(10)

-- Lockdown already on at Stop (unmeasured): only the protected part waits.
S.SetPreview(true)
WoW.combat = true
P.Stop()
check(not P.active, "stopped")
check(WoW.unitWatch[button("focus")] == nil, "the watch waits for combat to end")
check(not anyBlocked(), "nothing protected was touched in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(WoW.unitWatch[button("focus")] and not button("focus")._shown, "then it's back")

-- A loading screen ends it.
S.SetPreview(true)
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(not P.active, "a loading screen ends it")

-- The slash command and the options buttons.
SlashCmdList.GLASSUNITFRAMES("preview")
check(P.active, "/glass preview: on")
check(dialog.preview:GetChecked(), "the dialog follows /glass preview")
SlashCmdList.GLASSUNITFRAMES("preview")
check(not P.active, "/glass preview again: off")
check(not dialog.preview:GetChecked(), "and back")
dialog.preview:SetChecked(true); dialog.preview._scripts.OnClick(dialog.preview)
check(P.active, "the dialog's switch turns it on")
dialog.preview:SetChecked(false); dialog.preview._scripts.OnClick(dialog.preview)
check(not P.active, "and off")
S.Lock()
local O = GlassUF.Options
O._test.panel:Show()
local ctl = O._test.controls
ctl.preview._scripts.OnClick(ctl.preview)
check(P.active, "the options page's Preview button")
S.SetPreview(false)

eq(next(GlassUF.paintFailures), nil, "no paint failures")

-- A druid: the mana strip sample and three combo pips on the target.
WoW.reset(); GlassUF = nil
standardUnits()
for _, u in ipairs(ABSENT) do WoW.units[u] = nil end
WoW.units.player.class, WoW.units.player.powerToken = "DRUID", "MANA"
loadAddon(); WoW.applyUnitWatch()
local dm = button("player").druidMana
check(not dm.host._shown, "caster form: no druid strip")
GlassUF.Settings.SetPreview(true)
check(dm.host._shown and dm.bar._value == 60, "preview: the druid strip at 60%")
check(button("target").combo.holder._shown, "druid: the combo pips show")
eq(button("target").combo.pips[3]._alpha, 1, "three lit")
eq(button("target").combo.pips[4]._alpha, 0, "of five")
GlassUF.Settings.SetPreview(false)
tick()
check(not dm.host._shown, "after: caster form hides it again")
eq(next(GlassUF.paintFailures), nil, "no paint failures (druid)")

GlassUnitFramesDB = nil
done("test_preview")
