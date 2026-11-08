-- CastProbe (#112): a ForeverProbe module. Its commands run on the stubbed
-- client without throwing, its lines go to the host's console and its own
-- saved log (never chat), a secret payload is logged as S, and clearing
-- empties the bound log in place.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

standardUnits()
loadAddon()
local FP = loadForeverProbe()

-- The probe, as the client loads it: its file with (name, ns), then its saved
-- table (absent on a first run), then its ADDON_LOADED.
local ns = {}
assert(loadfile("Tools/CastProbe/CastProbe.lua"))("CastProbe", ns)
check(rawget(_G, "CastProbeDB") == nil, "no saved table made at file scope")
WoW.fire("ADDON_LOADED", "CastProbe")
local T = ns._test
check(T and T.Probe, "the module registered")
check(type(CastProbeDB) == "table" and type(CastProbeDB.log) == "table", "its saved log, made at ADDON_LOADED")

local log = CastProbeDB.log
local function has(pattern)
    for _, line in ipairs(log) do if line:find(pattern) then return true end end
    return false
end
check(has("==== session start ===="), "the session start is logged")
-- Every event registers; the stub has no crafting functions to hook.
for _, e in ipairs(T.failed) do check(e:find("^hook C_TradeSkillUI"), "registered: " .. e) end

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end

-- The trace: SENT then START of the same cast measure send->start.
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Sample Target", "Cast-3-1", 686)
WoW.now = WoW.now + 0.139
WoW.fire("UNIT_SPELLCAST_START", "player", "Cast-3-1", 686)
check(has("START player Cast%-3%-1 686 sent%->start=139ms"), "SENT -> START measured")
check(has("^.*%+0%.139 START"), "with the gap since the previous trace line")

-- A secret in the payload is logged as S, without an error line.
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", WoW.Secret("spellID"))
check(has("SUCCEEDED player Cast%-3%-1 S"), "a secret spellID is S")
check(not has("handler ERR"), "no handler error")

-- The commands.
fp("cast status")
check(has("status build="), "/fp cast status")
fp("cast mark pull 1")
check(has("==== pull 1 ===="), "/fp cast mark <text>")
fp("cast cd")
check(has("SPELL_UPDATE_COOLDOWN logging on"), "/fp cast cd")
fp("cast hier")
check(has("hier start") or has("GlassUF_player not found"), "/fp cast hier runs")

-- Clearing empties the bound table in place; the next line lands in both logs.
fp("cast clear")
check(CastProbeDB.log == log, "the same table (never replaced)")
fp("cast mark after")
check(has("==== after ===="), "a line after clearing lands in the saved log")
local inHost = false
for _, entry in ipairs(FP.lines) do
    if entry.m == "CastProbe" and entry.text:find("==== after ====") then inHost = true end
end
check(inHost, "and in the host's console")

-- #149: the cooldown update after a SENT reads the GCD spell and the spell sent.
WoW.cooldowns[2061] = { isActive = true, isOnGCD = true, start = WoW.now, duration = 1.5 }
WoW.fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-3-2", 2061)
WoW.fire("SPELL_UPDATE_COOLDOWN")
check(has("^.*GCD payload=.* gcdSpell id=61304 .*isActive=false.* sent id=2061 .*isOnGCD=true"), "the GCD line")
check(has("dur{secretVals=false total=1%.500"), "the cooldown's duration object")
eq(T.seen.gcdOn, 1, "counted as on the GCD")
WoW.fire("SPELL_UPDATE_COOLDOWN")
eq(T.seen.gcd, 1, "one line per SENT, not per update")
-- #150: a target's interrupt, with the name GUF would show.
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-3-3", 133, "GUID-Morphisto", "CastBar-1")
check(has("TARGET INTERRUPTED target Cast%-3%-3 133 GUID%-Morphisto .* gufName=Morphisto isPlayer=true"),
    "the target's interrupt and GUF's name for it")
WoW.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-3-4", 133, WoW.Secret("by"), "CastBar-1")
check(has("TARGET INTERRUPTED target Cast%-3%-4 133 S"), "a secret interruptedBy is S")
check(not has("TARGET ERR"), "no error on the target's events")
-- #152: the range line.
WoW.inRange.target = false
check(T.rangeLine():find("inRange=false"), "the range line reads IsSpellInRange")
-- The procedures exist.
for _, name in ipairs({ "gcd", "kick", "range" }) do
    check(FP.procedures["CastProbe/" .. name] ~= nil, "procedure " .. name .. " defined")
end
-- #151: the mirror timers' file, the same module.
assert(loadfile("Tools/CastProbe/Mirror.lua"))("CastProbe", ns)
WoW.mirror.BREATH = { index = 1, value = 30000, max = 60000, label = "Breath" }
fp("cast mirror")
check(has("mirror combat=false 1:{name=BREATH value=30000 max=60000 .* progress=30000}"), "/fp cast mirror")
WoW.secretFields.mirror = true
fp("cast mirror")
check(has("1:{name=BREATH value=<secret> max=<secret>"), "secret values shown as <secret>")
WoW.secretFields.mirror = nil
check(FP.procedures["CastProbe/mirror"] ~= nil, "procedure mirror defined")
-- #159: the crowd-control file, the same module.
assert(loadfile("Tools/CastProbe/CC.lua"))("CastProbe", ns)
WoW.ccSpells[853] = true
fp("cast cc")
check(has("filter valid="), "/fp cast cc: the filter line")
check(has("IsSpellCrowdControl 853=true 118=false"), "the Vanilla CC spells")
check(has("icon target mode=nil container=false"), "GUF's target icon, off")
check(FP.procedures["CastProbe/cc"] ~= nil, "procedure cc defined")

-- #171: the absorb file, the same module. The stub has no absorb API, so
-- every read says absent rather than throwing; the events count by unit.
assert(loadfile("Tools/CastProbe/Absorb.lua"))("CastProbe", ns)
fp("cast absorb")
check(has("absorb player exists=true combat=false total=absent healAbsorbs=absent"), "/fp cast absorb: the totals")
check(has("calc{damage=absent total=absent"), "the calculator's damage absorbs")
check(has("aura=absent events=0/0"), "the aura cross-check and the event counts")
fp("cast absorb target")
check(has("absorb target exists="), "/fp cast absorb <unit>")
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check(has("UNIT_ABSORB_AMOUNT_CHANGED %-> absorb player .* events=1/0"), "a change on you is logged with a read")
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", "nameplate3")
WoW.fire("UNIT_ABSORB_AMOUNT_CHANGED", WoW.Secret("unit"))
eq(T.absorbSeen.other, 2, "other units (and a secret token) only counted")
check(not has("UNIT_ABSORB_AMOUNT_CHANGED %-> absorb nameplate3"), "and not logged")
check(FP.procedures["CastProbe/absorb"] ~= nil, "procedure absorb defined")

-- #175: the DoT estimate's inputs, the same module. The stub has no spell
-- power, instance or meter API: each read says absent rather than throwing.
assert(loadfile("Tools/CastProbe/Dots.lua"))("CastProbe", ns)
fp("cast dots")
check(has("dots combat=false spellPower%(2%.%.7%)=absent/absent"), "/fp cast dots: spell power absent")
check(has("instance=ERR"), "no GetInstanceInfo in the stub: ERR, not a throw")
-- A tracked cast: GUF's own estimate from a plain spell power (the stub has no
-- combo points: unknown).
rawset(_G, "GetSpellBonusDamage", function(i) return i == 6 and 100 or 0 end)
WoW.fire("UNIT_SPELLCAST_SENT", "player", "Sample Target", "Cast-3-9", 172)
check(has("SENT 172 %-> Sample Target combo="), "SENT of a tracked spell logs the combo read")
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-9", 172)
check(has("DOT Corruption cast=172 aura=172 every 3s travel=false spellPower=100 combo=unknown ticks=30,30,30,30"),
    "the estimate with 100 spell power")
-- A secret spell power at the cast is 0, never an older read.
rawset(_G, "GetSpellBonusDamage", function() return WoW.Secret("spellPower") end)
WoW.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-10", 172)
check(has("spellPower=none combo=unknown ticks=10,10,10,10"), "secret spell power: 0; no SENT: combo unknown")
check(not has("DOT .* cast=133"), "untracked spells aren't logged")
-- Hits on target and focus (a secret amount is shown, never read); others ignored.
WoW.fire("UNIT_COMBAT", "target", "WOUND", "", WoW.Secret("amount"), 32)
check(has("HIT target action=WOUND flag= amount=<secret> school=32 .* after Corruption"), "a hit with a secret amount, shown as <secret>")
WoW.fire("UNIT_COMBAT", "nameplate2", "WOUND", "", 5, 32)
check(not has("HIT nameplate2"), "other tokens ignored")
WoW.fire("UNIT_COMBAT", WoW.Secret("unit"), "WOUND", "", 5, 32)
check(not has("handler ERR"), "a secret token doesn't throw")
-- After combat: the meter is read (absent here) and the wait step can end.
WoW.fire("PLAYER_REGEN_ENABLED")
check(has("dots fight end: 1 hits"), "the fight's hit count")
WoW.flushTimers()
check(has("meter %+0%.5s absent"), "the meter read after combat")
check(T.dotsState.meterDone, "the meter wait completes")
fp("cast dots stripe")
check(has("stripe 1 file Interface.RaidFrame.Absorb%-Overlay texture="), "/fp cast dots stripe: the file sample")
check(has("stripe 2 atlas RaidFrame%-Absorb%-Overlay .* info="), "the atlas samples, with their atlas info")
check(has("stripe 4 file Interface.RaidFrame.Shield%-Overlay"), "the shield file")
fp("cast dots stripe")
check(FP.procedures["CastProbe/dots"] ~= nil, "procedure dots defined")

-- Nothing in chat: the console and the saved log only.
for _, line in ipairs(WoW.chat) do
    check(not line:find("CastProbe") and not line:find("====") and not line:find("START"), "no probe line in chat: " .. line)
end

done("test_castprobe")
