-- CastProbe, the crowd-control icon's gate (#159): does the client's
-- CROWD_CONTROL aura filter mean anything on Forever's Vanilla rules, does
-- the aura container take it on a hostile target and on focus, in combat and
-- for other players' CC? A third file of the same module: /fp steps cast cc.
-- If the filter matches nothing, #159 closes (no out-of-combat-only version).

local Probe = ForeverProbe:Module("CastProbe", { api = 1, cmd = "cast" })

local function show(v) return Probe.Show(v, true) end

-- Vanilla crowd control, by class, for C_Spell.IsSpellCrowdControl (the flag
-- the filter is likely built on). Rank 1 ids; a nil answer is "not known".
local CC_SPELLS = {
    { 853, "Hammer of Justice" }, { 118, "Polymorph" }, { 122, "Frost Nova" }, { 5782, "Fear" },
    { 6358, "Seduction" }, { 8122, "Psychic Scream" }, { 15487, "Silence" }, { 1776, "Gouge" },
    { 2094, "Blind" }, { 408, "Kidney Shot" }, { 1833, "Cheap Shot" }, { 6770, "Sap" },
    { 5211, "Bash" }, { 339, "Entangling Roots" }, { 2637, "Hibernate" }, { 19503, "Scatter Shot" },
    { 3355, "Freezing Trap Effect" }, { 5246, "Intimidating Shout" }, { 7922, "Charge Stun" },
    { 1715, "Hamstring (a snare: expect false)" },
}

local function filterLine()
    local util = rawget(_G, "AuraUtil")
    local valid = util and util.IsValidFilterString
    local ok, v, why = false, nil, nil
    if type(valid) == "function" then ok, v, why = pcall(valid, "HARMFUL|CROWD_CONTROL") end
    local known = util and type(util.AuraFilters) == "table" and util.AuraFilters.CrowdControl
    return "filter valid=" .. (ok and show(v) or "ERR") .. " why=" .. show(why) .. " AuraFilters.CrowdControl=" .. show(known)
end

local function spellsLine()
    local parts = {}
    for _, s in ipairs(CC_SPELLS) do
        local ok, cc = pcall(C_Spell.IsSpellCrowdControl, s[1])
        parts[#parts + 1] = s[1] .. "=" .. (ok and show(cc) or "ERR")
    end
    return "IsSpellCrowdControl " .. table.concat(parts, " ")
end

-- What GUF's icon is doing: its container, mode, and whether a button shows.
local function iconLine(unit)
    local GUF = rawget(_G, "GlassUF")
    local b = GUF and GUF.Frames and GUF.Frames.byUnit[unit]
    local c = b and b.ccContainer
    local shown = 0
    if c and c.GetChildren then
        for _, child in ipairs({ c:GetChildren() }) do
            local ok, s = pcall(child.IsShown, child)
            if ok and s then shown = shown + 1 end
        end
    end
    return string.format("icon %s mode=%s container=%s shown=%s buttonsShown=%d combat=%s exists=%s", unit,
        show(GUF and GUF.Auras and GUF.Auras.ccMode[unit]), show(c ~= nil), show(c and c:IsShown()), shown,
        show(InCombatLockdown()), show(UnitExists(unit)))
end

local function say(line) Probe:Say(line) return line end
local function setMode(unit, mode)
    local GUF = rawget(_G, "GlassUF")
    if not (GUF and GUF.Settings and GUF.Settings.SetCCIcon) then return say("GlassUnitFrames not loaded") end
    return say("SetCCIcon " .. unit .. " " .. mode .. " -> " .. show(GUF.Settings.SetCCIcon(unit, mode)))
end

Probe:Command("cc", function()
    say(filterLine())
    say(spellsLine())
    say(iconLine("target"))
    say(iconLine("focus"))
end, "the CROWD_CONTROL filter, IsSpellCrowdControl on Vanilla CC, and GUF's icons")

Probe:Steps("cc", {
    title = "The crowd-control icon (#159)",
    rev = 1,
    { text = "Does the client know the filter, and which Vanilla spells it flags as CC? Nothing to do: Next.",
      auto = true, run = function() return say(filterLine()), say(spellsLine()) end },
    { text = "Out of combat: press Run to turn the icon on over your target's portrait (it's restored at the end).",
      button = "Turn it on", run = function() return setMode("target", "portrait") end },
    { text = "Target a mob and crowd-control it (stun, fear, root, polymorph, silence), or have a partner do it. Then press Run while it lasts.",
      button = "Read the icon", run = function() return say(iconLine("target")) end },
    { text = "Did a CC icon with its timer cover the portrait, and the portrait come back when it ended?",
      ask = true, screenshot = "cc on target" },
    { text = "In combat, with a CC on your target cast by ANOTHER player if you can: press Run.",
      button = "Read the icon", run = function() return say(iconLine("target")) end,
      check = function() return InCombatLockdown(), "read in combat" end },
    { text = "Did the icon show in combat (for another player's CC)?", ask = true },
    { text = "Two CCs on one target (a root and a stun, say): which one did the icon show? Type it in the Note, then Next." },
    { text = "Out of combat: press Run to turn it on for your focus, then focus a mob and CC it.",
      button = "Turn it on", run = function() return setMode("focus", "portrait") end },
    { text = "Did the icon show left of the focus frame, with its timer?", ask = true, screenshot = "cc on focus" },
    { text = "Out of combat: press Run to turn both icons off again (they're off by default).",
      button = "Turn them off", run = function() return setMode("target", "off"), setMode("focus", "off") end },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})
