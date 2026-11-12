-- test_dots.lua: the DoT tracker (#175, docs/DOT-KILL-PLAN.md section 6).
-- Casts, outcomes and inferred ticks driven through the real events, with a
-- secret UNIT_COMBAT amount throughout (a proxy that throws on any use).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Client APIs this test drives (each in the dump): hostility by reaction, and
-- spell power that a test can make secret, as in combat (run #108).
local sp, spSecret = 0, false
UnitCanAttack = function(_, u) local un = WoW.units[u]; return un ~= nil and un.reaction <= 4 end
GetSpellBonusDamage = function() if spSecret then return WoW.Secret("spellPower") end return sp end

standardUnits()
WoW.units.player.level = 60
loadAddon()
local Dots = GlassUF.Dots
local T = Dots._test
local MOB = "GUID-Defias Pillager"
local CORRUPTION, SWP, REND, RIP, SERPENT, FIREBALL = 172, 589, 772, 1079, 1978, 133

local n = 0
local function send(spellID, name)
    n = n + 1
    local guid = "Cast-3-" .. n
    WoW.fire("UNIT_SPELLCAST_SENT", "player", name or "Defias Pillager", guid, spellID)
    return guid
end
local function land(guid, spellID) WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, spellID) end
local function cast(spellID, name) local g = send(spellID, name); land(g, spellID); return g end
local function wait(dt)            -- time passes a rendered frame at a time
    local steps = math.floor(dt / 0.05 + 0.5)
    for _ = 1, steps do WoW.now = WoW.now + 0.05; WoW.tick(0.05) end
end
local function hit(unit, school, action)
    WoW.fire("UNIT_COMBAT", unit or "target", action or "WOUND", "", WoW.Secret("amount"), school or 32)
end
local function est(unit) return Dots.Estimate(unit or "target") end
local function app(key, family) local a = T.state().apps[key or MOB]; return a and a[family or CORRUPTION] end
local function reset()
    T.forget()
    sp, spSecret = 0, false
    WoW.secretFields = {}
    standardUnits()
    WoW.units.player.level = 60
    WoW.units.mouseover = nil
    WoW.fire("PLAYER_REGEN_ENABLED")
    wait(1)
end

-- Corruption rank 1: 4 ticks of 10 every 3 s. Shown once its outcome window
-- passes; committed only once a tick of it is seen.
reset()
local t0 = WoW.now
cast(CORRUPTION)
eq((est()), 0, "pending until the outcome window passes")
wait(0.5)
local shown, committed, cum = est()
eq(shown, 40, "confirmed: 4 ticks of 10")
eq(committed, 0, "not committed before a tick is seen")
eq(table.concat(cum, ","), "10,20,30,40", "the running totals, next tick first")
wait(t0 + 2.5 - WoW.now)
eq((est()), 40, "still 40 just before the first tick's window")
WoW.now = t0 + 2.56
eq((est()), 30, "at its window's start the first tick no longer counts: it may land any moment")
eq(select(2, est()), 0, "nothing committed yet")
hit()
shown, committed = est()
eq(shown, 30, "an early tick changes nothing more")
eq(committed, 30, "and commits the application")
check(app().slots[1].filled, "the first slot is filled")

-- A tick that lands unseen stops counting at its window's start (the plan's
-- retarget case: committed 20 at 6.1 s, not 30).
reset()
t0 = WoW.now
cast(CORRUPTION)
wait(3.0)
hit()
eq(select(2, est()), 30, "committed after the first tick")
wait(1.9)
local mob = WoW.units.target
WoW.SetUnit("target", { name = "Kobold", reaction = 2, guid = "GUID-Kobold" })
WoW.fire("PLAYER_TARGET_CHANGED")
wait(t0 + 6.1 - WoW.now)
WoW.units.target = mob
WoW.fire("PLAYER_TARGET_CHANGED")
shown, committed = est()
eq(committed, 20, "the second tick, due unseen, no longer counts")
eq(shown, 20, "nor in the marker")
check(app() ~= nil, "a GUID key survives the target change")

-- A late match after the damage cutoff commits but gives nothing back, and
-- the rhythm moves at most SHIFT_MAX in total.
reset()
t0 = WoW.now
cast(CORRUPTION)
wait(3.4)
eq((est()), 30, "slot 1's damage is gone at its window's start")
hit()
shown, committed = est()
eq(shown, 30, "a late tick gives no damage back")
eq(committed, 30, "but commits")
eq(app().shift, 0.25, "the rhythm shift is capped")
check(math.abs(app().slots[2].t - (t0 + 6.25)) < 1e-6, "later slots move by the capped shift")

-- Two consecutive observed misses drop it (resisted unseen, dispelled).
reset()
cast(CORRUPTION)
wait(3.6)
check(app() ~= nil, "one observed miss keeps it")
eq(app().misses, 1, "one miss counted")
wait(3.0)
eq((est()), 0, "two observed misses drop it")
check(app() == nil, "the application is gone")

-- Slots the mob wasn't watched through never count as misses.
reset()
cast(CORRUPTION)
wait(0.5)
WoW.SetUnit("target", nil)
WoW.fire("PLAYER_TARGET_CHANGED")
wait(7)
check(app() ~= nil, "unwatched slots don't drop it")
eq(app().misses, 0, "no miss counted")
standardUnits()
WoW.fire("PLAYER_TARGET_CHANGED")
eq((est()), 20, "back in view: the two slots left (9 s and 12 s)")

-- Outcomes: a resist drops a spell; a dodge doesn't (spells can't be dodged)
-- but drops a bleed; a failed refresh keeps the old application.
reset()
cast(CORRUPTION)
WoW.now = WoW.now + 0.1
hit("target", 32, "RESIST")
wait(0.5)
eq((est()), 0, "a resisted cast is never shown")
reset()
cast(CORRUPTION)
WoW.now = WoW.now + 0.1
hit("target", 1, "DODGE")
wait(0.5)
eq((est()), 40, "a dodge isn't a spell's outcome")
reset()
cast(REND)
WoW.now = WoW.now + 0.1
hit("target", 1, "DODGE")
wait(0.5)
eq((est()), 0, "a dodged bleed is dropped")
reset()
hit("target", 32, "RESIST")
WoW.now = WoW.now + 0.1
cast(CORRUPTION)
wait(0.5)
eq((est()), 0, "a resist just before the cast event counts too")
-- The lookback keeps the newest avoid of each rule (plan 12.1): a dodge after
-- our resist doesn't hide it.
reset()
hit("target", 32, "RESIST")
WoW.now = WoW.now + 0.1
hit("target", 1, "DODGE")
WoW.now = WoW.now + 0.1
cast(CORRUPTION)
wait(0.5)
eq((est()), 0, "a dodge after a resist doesn't hide it from the lookback")
reset()
hit("target", 1, "DODGE")
WoW.now = WoW.now + 0.1
cast(REND)
wait(0.5)
eq((est()), 0, "a dodge just before a bleed's cast event drops it")
reset()
hit("target", 1, "DODGE")
WoW.now = WoW.now + 0.1
cast(CORRUPTION)
wait(0.5)
eq((est()), 40, "a dodge just before a spell's cast event doesn't")
reset()
hit("target", 32, "RESIST")
WoW.now = WoW.now + 0.3
cast(CORRUPTION)
wait(0.5)
eq((est()), 40, "an avoid older than the lookback isn't the cast's")

reset()
t0 = WoW.now
cast(CORRUPTION)
wait(3.0)
hit()
cast(CORRUPTION)
WoW.now = WoW.now + 0.1
hit("target", 32, "RESIST")
wait(0.5)
local a = app()
eq(a.castAt, t0, "a failed refresh keeps the old application")
eq((est()), 30, "still ticking")
cast(CORRUPTION)
wait(0.5)
check(app().castAt > t0, "a confirmed refresh replaces it")
eq((est()), 40, "with a fresh rhythm")
check(not app().committed, "and isn't committed until it ticks")

-- Ranks share a family: a higher rank replaces the lower one.
reset()
cast(CORRUPTION)
wait(0.5)
local r2 = 6222   -- Corruption rank 2
check(GlassUF.DotSpells.cast[r2] ~= nil, "Corruption rank 2 is generated")
cast(r2)
wait(0.5)
local n2 = 0
for _ in pairs(T.state().apps[MOB]) do n2 = n2 + 1 end
eq(n2, 1, "one Corruption on the mob")

-- Attribution: exactly one watched mob must answer to the name.
reset()
cast(FIREBALL)
wait(0.5)
eq((est()), 0, "an unsupported spell isn't tracked")
cast(CORRUPTION, "Somebody Else")
wait(0.5)
eq((est()), 0, "a name no watched mob has isn't tracked")
WoW.SetUnit("focus", { name = "Defias Pillager", reaction = 2, guid = "GUID-Defias Twin" })
cast(CORRUPTION)
wait(0.5)
eq((est()), 0, "two different mobs with the name: not tracked")
WoW.SetUnit("focus", { name = "Defias Pillager", reaction = 2, guid = MOB })
cast(CORRUPTION)
wait(0.5)
eq((est()), 40, "target and focus on the same mob: tracked once")
eq((est("focus")), 40, "the focus shows the same mob's DoTs")
T.forget()
cast(CORRUPTION)
cast(SWP)
wait(3.0)
hit("target")
local one = app(MOB, CORRUPTION).committed or app(MOB, SWP).committed
hit("focus")
local both = app(MOB, CORRUPTION).committed and app(MOB, SWP).committed
check(one and not both, "the focus copy of the same hit is the same hit: it fills no second slot")
reset()
WoW.SetUnit("focus", { name = "Hogger", reaction = 2, guid = "GUID-Hogger" })
cast(CORRUPTION, "Hogger")
wait(0.5)
eq((est("focus")), 40, "a cast at the focus by name lands on the focus")
eq((est()), 0, "not on the target")
reset()
WoW.SetUnit("target", { name = "Defias Pillager", reaction = 5 })
cast(CORRUPTION)
wait(0.5)
eq((est()), 0, "a friendly unit isn't tracked")

-- Same school, same moment: two events fill two slots; one fills one.
reset()
cast(CORRUPTION)
cast(SWP)
wait(3.0)
hit()
hit()
check(app(MOB, CORRUPTION).committed and app(MOB, SWP).committed, "two events fill two applications")
reset()
cast(CORRUPTION)
cast(SWP)
wait(3.0)
hit()
local c1, c2 = app(MOB, CORRUPTION).committed, app(MOB, SWP).committed
check((c1 and not c2) or (c2 and not c1), "one event fills one slot")
reset()
cast(CORRUPTION)
wait(3.0)
hit("target", 4)
check(not app().committed, "a hit in another school is no tick of it")

-- A projectile's first tick may come late.
reset()
cast(SERPENT)
wait(4.8)
hit("target", 8)
check(app(MOB, SERPENT).committed, "Serpent Sting's late first tick matches")

-- Per-token keys when GUIDs are secret: a cast sent at one mob never lands
-- on the next, and a token change drops the old mob's applications.
reset()
WoW.secretFields.guid = true
local g = send(CORRUPTION)
WoW.fire("PLAYER_TARGET_CHANGED")
land(g, CORRUPTION)
eq(#T.state().pending, 0, "a SENT from before the token change is stale: nothing pending")
wait(0.5)
eq((est()), 0, "nor shown")
cast(CORRUPTION)
wait(0.5)
eq((est()), 40, "tracked on the token key")
check(next(T.state().apps) and next(T.state().apps):find("^target#"), "keyed by token and generation")
WoW.fire("PLAYER_TARGET_CHANGED")
eq((est()), 0, "a token change drops it")
g = send(CORRUPTION)
land(g, CORRUPTION)
WoW.fire("PLAYER_TARGET_CHANGED")
wait(0.5)
eq((est()), 0, "a pending application from before the change is dropped")

-- Spell power: a plain SENT read wins; a secret one takes the fight's
-- snapshot; with none it's 0; a cast's value stays what it was.
reset()
sp = 100
cast(CORRUPTION)
wait(0.5)
eq((est()), 120, "SENT read: 4 ticks of 10 + 0.2 * 100")
reset()
sp = 100
WoW.fire("PLAYER_REGEN_DISABLED")
spSecret = true
cast(CORRUPTION)
wait(0.5)
eq((est()), 120, "secret at SENT: the fight's snapshot")
WoW.fire("PLAYER_REGEN_ENABLED")
eq((est()), 120, "an application keeps its value after the fight's snapshot goes")
T.forget()
cast(CORRUPTION)
wait(0.5)
eq((est()), 40, "no snapshot (outside a fight, or a load mid-fight): 0")
reset()
spSecret = true
WoW.fire("PLAYER_REGEN_DISABLED")
cast(CORRUPTION)
wait(0.5)
eq((est()), 40, "a secret snapshot is no snapshot")
reset()
sp = 50
local opener = send(CORRUPTION)
land(opener, CORRUPTION)
sp = 100
WoW.fire("PLAYER_REGEN_DISABLED")   -- the measured order: SENT, SUCCEEDED, then the fight starts
spSecret = true
wait(0.5)
eq((est()), 80, "the opener keeps its own SENT read")
cast(SWP)
wait(0.5)
check(app(MOB, SWP).slots[1].est > 5, "a later secret SENT takes the snapshot")

-- Combo points: read at SENT if plain, else 1 point.
reset()
WoW.units.player.combo = 5
cast(RIP)
wait(0.5)
eq(app(MOB, RIP).slots[1].est, 31, "Rip at 5 points")
reset()
WoW.units.player.combo = 5
WoW.secretFields.combo = true
cast(RIP)
wait(0.5)
eq(app(MOB, RIP).slots[1].est, 9, "secret combo points: 1 point")

-- Ends: death, UNIT_DIED, a loading screen, the option off.
reset()
cast(CORRUPTION)
wait(0.5)
WoW.units.target.dead = true
wait(0.5)
eq((est()), 0, "a dead target's DoTs are dropped")
reset()
cast(CORRUPTION)
wait(0.5)
WoW.fire("UNIT_DIED", MOB)
check(app() == nil, "UNIT_DIED drops its mob")
reset()
cast(CORRUPTION)
wait(0.5)
WoW.fire("PLAYER_ENTERING_WORLD")
eq((est()), 0, "a loading screen forgets everything")
reset()
Dots.SetEnabled(false)
cast(CORRUPTION)
wait(0.5)
eq((est()), 0, "off: nothing tracked")
Dots.SetEnabled(true)

-- The mouseover guard (plan 12.3): a same-name, attackable mob under the cursor
-- that isn't the bound unit may be where the cast went, so it isn't tracked.
local function twin(t)       -- another mob with the target's name
    local u = { name = "Defias Pillager", reaction = 2, guid = "GUID-Defias Twin" }
    for k, v in pairs(t or {}) do u[k] = v end
    WoW.SetUnit("mouseover", u)
end
local function landed(name)  -- cast now, past its outcome window: the estimate
    cast(CORRUPTION, name)
    wait(0.5)
    return (est(name == "Hogger" and "focus" or "target"))
end
local function with(name, fn, body)  -- a client function replaced for one case
    local real = _G[name]
    _G[name] = function(...) return fn(real, ...) end
    local ok, err = pcall(body)
    _G[name] = real
    if not ok then error(err, 0) end
end
reset()
WoW.units.mouseover = WoW.units.target
eq(landed(), 40, "the cursor on the target (or its frame): tracked")
reset()
WoW.SetUnit("mouseover", { name = "Kobold", reaction = 2, guid = "GUID-Kobold" })
eq(landed(), 40, "the cursor on a mob with another name: tracked")
reset()
twin({ reaction = 5 })
eq(landed(), 40, "the cursor on a same-name mob we can't attack: tracked")
reset()
twin()
eq(landed(), 0, "the cursor on a same-name hostile mob: not tracked")
check(next(T.state().sent) == nil and next(T.state().pending) == nil, "no SENT record, nothing pending")
wait(3.05 - 0.5)
hit()
eq(select(2, est()), 0, "and a Shadow hit at its first tick commits nothing")
reset()
WoW.SetUnit("mouseover", { name = "Hogger", reaction = 2, guid = "GUID-Hogger Twin" })
eq(landed("Hogger"), 0, "a cast bound to the focus, same-name twin under the cursor: not tracked")
reset()
WoW.units.mouseover = WoW.units.focus
eq(landed("Hogger"), 40, "the cursor on the focus: tracked")
reset()
WoW.SetUnit("focus", { name = "Defias Pillager", reaction = 2, guid = "GUID-Defias Twin" })
WoW.units.mouseover = WoW.units.target
eq(landed(), 0, "two watched mobs with the name stay ambiguous, mouseover or not")

-- Reads that can't clear the mouseover leave the cast untracked.
local function secretFor(token, real, u, ...)
    if u == "mouseover" or select(1, ...) == "mouseover" then return WoW.Secret(token) end
    return real(u, ...)
end
reset()
twin()
with("UnitExists", function(real, u) if u == "mouseover" then error("refused") end return real(u) end,
    function() eq(landed(), 0, "UnitExists(mouseover) throwing: not tracked") end)
reset()
with("UnitExists", function(real, u) return secretFor("exists", real, u) end,
    function() eq(landed(), 0, "a secret UnitExists(mouseover): not tracked") end)
reset()
twin()
with("UnitIsUnit", function(real, a, b) return secretFor("isUnit", real, a, b) end,
    function() eq(landed(), 0, "a secret UnitIsUnit on a same-name mouseover: not tracked") end)
reset()
WoW.units.mouseover = WoW.units.target
with("UnitIsUnit", function(real, a, b) return secretFor("isUnit", real, a, b) end,
    function() eq(landed(), 0, "the target under the cursor, identity unreadable: not tracked (errs low)") end)
reset()
twin()
with("UnitCanAttack", function(real, p, u) if u == "mouseover" then return WoW.Secret("canAttack") end
        return real(p, u) end,
    function() eq(landed(), 0, "a secret UnitCanAttack on a same-name mouseover: not tracked") end)
reset()
twin({ name = "Kobold" })
with("GetUnitName", function(real, u, ...) return secretFor("fullName", real, u, ...) end,
    function() eq(landed(), 0, "the full name unreadable: another first name can't rule it out") end)
reset()
twin({ name = "Kobold" })
with("UnitName", function(real, u) if u == "mouseover" then return "Kobold", WoW.Secret("surname") end
        return real(u) end,
    function() eq(landed(), 0, "a secret surname: the first-and-surname form might match") end)
reset()
twin({ name = "Kobold" })
with("UnitName", function(real, u) if u == "mouseover" then error("refused") end return real(u) end,
    function() eq(landed(), 0, "UnitName(mouseover) throwing: not tracked") end)
reset()
twin({ name = "Defias" })
with("GetUnitName", function(real, u, ...) if u == "mouseover" then return "Defias Pillager" end
        return real(u, ...) end,
    function() eq(landed(), 0, "a display-name match alone is the same name") end)

-- What the guard leaves alone.
reset()
local first = cast(CORRUPTION)
wait(0.5)
local castAt = app().castAt
twin()
cast(CORRUPTION)
wait(0.5)
eq(app().castAt, castAt, "a refresh the guard refuses keeps the old application")
reset()
twin()
local g = send(CORRUPTION)
WoW.units.mouseover = nil
land(g, CORRUPTION)
wait(0.5)
eq((est()), 0, "refused at SENT stays refused when the cursor leaves before SUCCEEDED")
reset()
WoW.units.mouseover = WoW.units.target
g = send(CORRUPTION)
twin()
land(g, CORRUPTION)
wait(0.5)
eq((est()), 40, "the SENT reading decides: a cursor moved after it changes nothing")
reset()
g = send(CORRUPTION)
check(T.state().sent[g] ~= nil, "a SENT never followed by its SUCCEEDED is kept a while")
WoW.now = WoW.now + Dots.SENT_TTL + 1
twin()
send(CORRUPTION)
check(T.state().sent[g] == nil, "an expired SENT is still swept when the new cast is refused")

-- It idles when nothing is tracked.
reset()
wait(1)
check(not T.runner:IsShown(), "the pass idles with nothing tracked")
cast(CORRUPTION)
check(T.runner:IsShown(), "and runs while something is")

eq(next(GlassUF.paintFailures), nil, "no paint failures")
done("test_dots")
