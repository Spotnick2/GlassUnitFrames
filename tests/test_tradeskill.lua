-- The batch craft count (#91): "Name (3/5)" on the player's bar, from the
-- client's own batch state (GetRemainingRecasts at each START: 4, 3, 2, 1, 0
-- for a batch of 5, measured). The event order replays the trace on #91:
-- SUCCEEDED, STOP, then ~0.1 s later SENT + START of the next craft;
-- UPDATE_TRADESKILL_CAST_STOPPED(false) after a batch's last craft or a cancel.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local Castbar, S = GlassUF.Castbar, GlassUF.Settings
local pc = button("player").cast
-- The older cast tests turn these off; here the target text matters.
local n = 0
local function guid(spell) n = n + 1; return "Cast-3-1-1-1-" .. (spell or 3275) .. "-" .. n end

-- One craft's START with `left` crafts after it (WoW.recasts), as the trace has it.
local function craftStart(left, spell, name)
    local g = guid(spell)
    WoW.recasts, WoW.repeating = left, left > 0
    WoW.units.player.casting = { name = name or "Heavy Linen Bandage", guid = g, spellID = spell or 3275, total = 3,
                                 remaining = 2, trade = true, startMs = WoW.now * 1000,
                                 endMs = (WoW.now + 3) * 1000, delayMs = 0 }
    WoW.fire("UNIT_SPELLCAST_SENT", "player", "", g, spell or 3275)
    WoW.fire("UNIT_SPELLCAST_START", "player", g, spell or 3275, "CastBar-1")
    return g
end
local function craftEnd(g, spell)
    WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, spell or 3275, "CastBar-1")
    WoW.units.player.casting = nil
    WoW.fire("UNIT_SPELLCAST_STOP", "player", g, spell or 3275, "CastBar-1")
end
local function stopped() WoW.recasts, WoW.repeating = 0, false; WoW.fire("UPDATE_TRADESKILL_CAST_STOPPED", false) end
local function spell() return textOf(pc.spell) end

-- A batch of 5: 1/5 ... 5/5.
for i = 1, 5 do
    local g = craftStart(5 - i)
    eq(spell(), string.format("Heavy Linen Bandage (%d/5)", i), "craft " .. i .. " of 5")
    craftEnd(g)
    if i < 5 then
        check(not pc.flashing, "no complete flash between crafts (" .. i .. ")")
    else
        check(pc.flashing, "the batch's last craft flashes complete")
    end
    WoW.flushTimers()
end
stopped()
check(pc.craft == nil, "the batch is over")

-- A single craft: no count.
local g = craftStart(0)
eq(spell(), "Heavy Linen Bandage", "a single craft shows no count")
craftEnd(g)
check(pc.flashing, "and flashes complete")
WoW.flushTimers()

-- A cancel after 2 (moving), then the same recipe x3 at once: a new batch.
g = craftStart(4); craftEnd(g); WoW.flushTimers()
g = craftStart(3); craftEnd(g); WoW.flushTimers()
g = craftStart(2)
eq(spell(), "Heavy Linen Bandage (3/5)", "the third of five")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", g, 3275, nil, "CastBar-1")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", g, 3275, "CastBar-1")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", g, 3275, nil, nil)
stopped()
check(pc.craft == nil, "a cancel ends the batch")
WoW.flushTimers()
g = craftStart(2)
eq(spell(), "Heavy Linen Bandage (1/3)", "the same recipe right after: a new batch of 3")
craftEnd(g); WoW.flushTimers()
g = craftStart(1)
eq(spell(), "Heavy Linen Bandage (2/3)", "2/3")
-- A late STOP / INTERRUPTED of the previous craft leaves this one's count alone.
local old = "Cast-3-1-1-1-3275-old"
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", old, 3275, nil, nil)
WoW.fire("UNIT_SPELLCAST_STOP", "player", old, 3275, "CastBar-1")
check(pc.craft ~= nil and pc.craft.left == 1, "an older craft's late events keep the batch")
-- A rejected, unrelated FAILED keeps it too.
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0-133-0000000001", 133, nil)
check(pc.craft ~= nil, "an unrelated failure keeps the batch")
-- A mid-cast repaint keeps the index.
WoW.fire("PLAYER_ENTERING_WORLD"); WoW.tick()
eq(spell(), "Heavy Linen Bandage (2/3)", "a repaint keeps 2/3")
-- The option: off shows the plain name, on brings the count back.
S.SetCastOption("craftCount", false); WoW.tick()
eq(spell(), "Heavy Linen Bandage", "craft count off: the plain name")
eq(GlassUnitFramesDB.castCraftCount, false, "saved when off")
S.SetCastOption("craftCount", true); WoW.tick()
eq(spell(), "Heavy Linen Bandage (2/3)", "back on")
craftEnd(g); WoW.flushTimers()
local prev = g
g = craftStart(0)
eq(spell(), "Heavy Linen Bandage (3/3)", "3/3")
WoW.fire("UNIT_SPELLCAST_STOP", "player", prev, 3275, "CastBar-1")   -- late, of 2/3
check(pc.craft ~= nil and pc.craft.left == 0, "a late STOP of the previous craft doesn't end the last one")
craftEnd(g); stopped(); WoW.flushTimers()

-- The same recipe again with no boundary event between (the count didn't go
-- down by one): a new batch, not a continuation.
g = craftStart(2)
craftEnd(g); WoW.flushTimers()
g = craftStart(4)
eq(spell(), "Heavy Linen Bandage (1/5)", "a count that went up: a new batch")
craftEnd(g); stopped(); WoW.flushTimers()

-- A different recipe starts its own batch; a non-craft cast clears.
g = craftStart(1)
craftEnd(g); WoW.flushTimers()
g = craftStart(1, 3276, "Silk Bandage")
eq(spell(), "Silk Bandage (1/2)", "a different recipe: its own batch")
craftEnd(g); WoW.flushTimers()
local gs = guid(2061)
WoW.units.player.casting = { name = "Greater Heal", guid = gs, spellID = 2061, total = 2.5, remaining = 2,
                             startMs = WoW.now * 1000, endMs = (WoW.now + 2.5) * 1000, delayMs = 0 }
WoW.recasts = 0
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Karuzo", gs, 2061)
WoW.fire("UNIT_SPELLCAST_START", "player", gs, 2061, "CastBar-1")
check(pc.craft == nil, "a normal cast clears the batch")
eq(spell(), "Greater Heal -> Karuzo", "and shows its own text")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", gs, 2061, "CastBar-1")
WoW.flushTimers()
-- A channel clears too.
g = craftStart(3)
local gc = guid(5143)
WoW.units.player.casting = { name = "Arcane Missiles", guid = gc, spellID = 5143, channel = true, remaining = 2 }
WoW.fire("UNIT_SPELLCAST_CHANNEL_START", "player", gc, 5143)
check(pc.craft == nil, "a channel clears the batch")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", gc, 5143)
WoW.flushTimers()

-- A craft never shows a target, even with the count off.
S.SetCastOption("craftCount", false)
g = guid()
WoW.recasts = 2
WoW.units.player.casting = { name = "Heavy Linen Bandage", guid = g, spellID = 3275, total = 3, remaining = 2,
                             trade = true, startMs = WoW.now * 1000, endMs = (WoW.now + 3) * 1000, delayMs = 0 }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Karuzo", g, 3275)
WoW.fire("UNIT_SPELLCAST_START", "player", g, 3275, "CastBar-1")
eq(spell(), "Heavy Linen Bandage", "no '-> target' on a craft")
S.SetCastOption("craftCount", true)
craftEnd(g); stopped(); WoW.flushTimers()

-- Unreadable: a secret isTradeskill or recasts, a malformed count: no count, a stale one cleared.
g = craftStart(3)
eq(spell(), "Heavy Linen Bandage (1/4)", "a batch")
craftEnd(g); WoW.flushTimers()
WoW.secretFields.tradeskill = true
g = craftStart(2)
eq(spell(), "Heavy Linen Bandage", "a secret isTradeskill: no count")
check(pc.craft == nil, "and the stale batch is gone")
craftEnd(g); WoW.flushTimers()
WoW.secretFields.tradeskill = nil
for _, bad in ipairs({ WoW.Secret("recasts"), -1, 1.5, 0 / 0, "2" }) do
    g = craftStart(1)
    WoW.recasts = bad
    WoW.fire("PLAYER_ENTERING_WORLD"); WoW.tick()
    craftEnd(g); WoW.flushTimers()
    g = guid()
    WoW.units.player.casting = { name = "Heavy Linen Bandage", guid = g, spellID = 3275, total = 3, remaining = 2,
                                 trade = true, startMs = WoW.now * 1000, endMs = (WoW.now + 3) * 1000, delayMs = 0 }
    WoW.fire("UNIT_SPELLCAST_START", "player", g, 3275, "CastBar-1")
    eq(spell(), "Heavy Linen Bandage", "an unreadable count (" .. tostring(type(bad)) .. "): no count")
    check(pc.craft == nil, "nothing tracked")
    craftEnd(g); WoW.flushTimers()
end
WoW.recasts = 0

-- UPDATE_TRADESKILL_CAST_STOPPED: only false ends a batch (scrapping is left
-- alone); it reaches only the player's bar and never paints a failure.
g = craftStart(3)
WoW.fire("UPDATE_TRADESKILL_CAST_STOPPED", true)
check(pc.craft ~= nil, "isScrapping true: left alone")
WoW.fire("UPDATE_TRADESKILL_CAST_STOPPED", WoW.Secret("scrap"))
check(pc.craft ~= nil, "a secret payload: left alone")
WoW.fire("UPDATE_TRADESKILL_CAST_STOPPED", false)
check(pc.craft == nil, "false: the batch ends")
craftEnd(g); WoW.flushTimers()
-- A target change on another frame never touches it; the target's bar has no count.
g = craftStart(2)
WoW.SetUnit("target", { name = "Kobold", reaction = 2 })
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
check(pc.craft ~= nil, "the target changing keeps the player's batch")
craftEnd(g); stopped(); WoW.flushTimers()

-- The merged batch bar (#93): one duration for the batch, held in the gaps.
local function advance(sec) WoW.now = WoW.now + sec; WoW.runDue(); WoW.tick(0.06) end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end
WoW.flushTimers()
local t0 = WoW.now
g = craftStart(4)
local k = pc.craft
check(pc.merged, "a batch of 5 merges (on by default)")
eq(pc.bar._timer.duration, k.dur, "the bar runs on the batch duration")
eq(pc.duration, k.dur, "and so does the time text")
eq(k.dur._start, t0, "from the batch's start")
check(near(k.dur._dur, 3 + 4 * (3 + 0.1)), "to this craft's end + 4 x (3 s + 0.1 s)")
check(not pc.lag._shown, "no latency block on a batch")
advance(1)
check(textOf(pc.time):find("15.4"), "the time text shows the batch total")
advance(2)
craftEnd(g)
check(pc.host._shown and not pc.flashing, "between crafts: the bar stays, no flash")
eq(pc.duration, k.dur, "with the batch duration")
-- Unrelated and older events during the gap leave the hold alone.
WoW.fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0-133-0000000009", 133, nil)
WoW.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-1-1-1-3275-older", 3275, "CastBar-1")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-3-1-1-1-3275-older", 3275, nil, nil)
WoW.tick()
check(k.holding and pc.host._shown, "an unrelated FAILED and an older craft's events keep the hold")
-- A duplicate STOP doesn't re-arm.
local gen = k.holdGen
WoW.fire("UNIT_SPELLCAST_STOP", "player", g, 3275, "CastBar-1")
eq(k.holdGen, gen, "a duplicate STOP doesn't re-arm the guard")
advance(0.12)
g = craftStart(3)
eq(k.gapN, 1, "one gap sample")
check(near(k.gapSum, 0.12), "the measured gap")
check(near(k.dur._dur, (WoW.now + 3) + 3 * (3 + 0.12) - t0), "re-anchored to this craft's real end")
eq(k.dur._start, t0, "the start never moves")
-- The first hold's guard comes due mid-craft: stale, it does nothing.
advance(1.6)
check(pc.merged and pc.host._shown, "a stale guard never touches a later craft")
-- A pushed-back craft moves the end, not the start; no pushback text.
local before = k.dur._dur
WoW.units.player.casting.endMs = WoW.units.player.casting.endMs + 500
WoW.units.player.casting.delayMs = 500
WoW.fire("UNIT_SPELLCAST_DELAYED", "player", g, 3275, "CastBar-1")
check(near(k.dur._dur, before + 0.5), "DELAYED: the batch end moves by the pushback")
eq(k.dur._start, t0, "its start doesn't")
eq(k.gapN, 1, "and no gap sample")
advance(0.1)
check(not textOf(pc.time):find("+", 1, true), "no pushback text on a batch")
advance(1.9)
craftEnd(g)
check(k.holding, "held")
-- No next craft within 1.5 s: the guard drops the merge and hides the bar.
advance(1.6); WoW.tick()
check(not k.merged and not k.holding, "the guard ends the merge")
check(not pc.host._shown, "and the bar hides (no stuck bar)")
-- A craft after that is per craft (sticky for the batch).
g = craftStart(2)
check(not pc.merged, "the rest of this batch is per craft")
check(pc.bar._timer.duration ~= k.dur, "its own duration")
craftEnd(g); stopped(); WoW.flushTimers()

-- The cancel: a red flash, the merge gone.
g = craftStart(4); advance(1)
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", g, 3275, nil, "CastBar-1")
WoW.units.player.casting = nil
WoW.fire("UNIT_SPELLCAST_STOP", "player", g, 3275, "CastBar-1")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "player", g, 3275, nil, nil)
check(pc.flashing and textOf(pc.spell) == "Interrupted", "a cancel flashes red")
check(pc.craft == nil, "and ends the batch")
stopped(); WoW.tick()
check(pc.flashing, "the stopped event keeps the red flash")
WoW.flushTimers()

-- The world event during a hold hides the held bar.
g = craftStart(3); advance(3); craftEnd(g)
check(pc.host._shown, "held")
stopped(); WoW.tick()
check(not pc.host._shown, "UPDATE_TRADESKILL_CAST_STOPPED hides a held bar")
WoW.flushTimers()
-- The batch's last craft: the green flash survives the stopped event.
g = craftStart(1); advance(3); craftEnd(g); advance(0.1)
g = craftStart(0); advance(3); craftEnd(g)
check(pc.flashing, "the last craft flashes complete")
stopped(); WoW.tick()
check(pc.flashing and pc.host._shown, "the stopped event keeps it")
WoW.flushTimers()

-- The option off mid-craft and in a gap; on again from the next batch.
g = craftStart(3)
check(pc.merged, "merged")
S.SetCastOption("craftMerge", false); WoW.tick()
eq(GlassUnitFramesDB.castCraftMerge, false, "saved when off")
check(not pc.merged, "off mid-craft: per craft at once")
S.SetCastOption("craftMerge", true); WoW.tick()
check(not pc.merged, "on again: not for this batch")
advance(3); craftEnd(g); advance(0.1)
g = craftStart(2)
check(not pc.merged, "still this batch: per craft")
craftEnd(g); stopped(); WoW.flushTimers()
g = craftStart(2)
check(pc.merged, "the next batch merges")
advance(3); craftEnd(g)
check(pc.host._shown, "held")
S.SetCastOption("craftMerge", false); WoW.tick()
check(not pc.host._shown, "off in a gap: the held bar hides")
stopped(); WoW.flushTimers()
g = craftStart(2)
check(not pc.merged and pc.craft ~= nil, "a new batch with the option off: counted, not merged")
S.SetCastOption("craftMerge", true); WoW.tick()
check(not pc.merged, "turned on during that batch: still not merged (from the next batch)")
craftEnd(g); stopped(); WoW.flushTimers()

-- Unreadable timing on a later craft ends the merge for the batch.
g = craftStart(3); advance(3); craftEnd(g); advance(0.1)
WoW.secretFields.castTimes = true
g = craftStart(2)
check(not pc.merged, "secret timing: per craft")
WoW.secretFields.castTimes = nil
advance(3); craftEnd(g); advance(0.1)
g = craftStart(1)
check(not pc.merged, "and stays per craft for the batch")
craftEnd(g); stopped(); WoW.flushTimers()

-- The other text options with a merged batch.
S.SetCastOption("totalTime", false); S.SetCastOption("craftCount", false)
g = craftStart(2); advance(0.5)
check(pc.merged, "merged")
eq(textOf(pc.spell), "Heavy Linen Bandage", "count off: the plain name")
check(not textOf(pc.time):find("/", 1, true), "total off: remaining only")
S.SetCastOption("complete", false)
advance(2.5); craftEnd(g); advance(0.1); g = craftStart(1); advance(3); craftEnd(g); advance(0.1)
g = craftStart(0); advance(3); craftEnd(g)
check(not pc.flashing, "complete off: no flash at the end")
S.SetCastOption("totalTime", true); S.SetCastOption("craftCount", true); S.SetCastOption("complete", true)
stopped(); WoW.flushTimers()

eq(next(GlassUF.paintFailures), nil, "no paint failures (no generic-duration failure from the new event)")
GlassUnitFramesDB = nil
done("test_tradeskill")
