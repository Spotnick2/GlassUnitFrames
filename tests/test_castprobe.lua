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

-- #159: the crowd-control file, the same module.
assert(loadfile("Tools/CastProbe/CC.lua"))("CastProbe", ns)
WoW.ccSpells[853] = true
fp("cast cc")
check(has("filter valid="), "/fp cast cc: the filter line")
check(has("IsSpellCrowdControl 853=true 118=false"), "the Vanilla CC spells")
check(has("icon target mode=nil container=false"), "GUF's target icon, off")
check(FP.procedures["CastProbe/cc"] ~= nil, "procedure cc defined")

-- Nothing in chat: the console and the saved log only.
for _, line in ipairs(WoW.chat) do
    check(not line:find("CastProbe") and not line:find("====") and not line:find("START"), "no probe line in chat: " .. line)
end

done("test_castprobe")
