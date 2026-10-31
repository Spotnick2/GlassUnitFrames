-- GlassUnitFrames: preview mode (#109). Every frame and bar shows sample data,
-- so a look, a colour or a placement can be checked without setting up the
-- target, the fight or the cast that shows it.
--
-- DBM's simulated test bars are the idea: preview objects are flagged and the
-- real code skips them, and leaving undoes only what the preview changed.
-- Unlike DBM's demo, combat ends it (the unit buttons are secure) and it runs
-- until turned off rather than for a fixed time.
--
-- - The frames: every unit button but the player's leaves its unit watch and
--   shows sample data (Frames.PaintSample). The player's frame stays live; its
--   cast bar and druid mana strip are samples.
-- - One gate: Engine skips a painter the preview owns (Engine.Owned). A
--   repaint with no event (a setting changed, a frame shown) refreshes the
--   sample instead.
-- - The cast bars loop sample casts on durations we own (plain); the swing
--   rows and the five-second strip loop their own samples (SetPreview).
-- - Out of combat only, never saved. Combat or a loading screen ends it.

GlassUF = GlassUF or {}
local API, Frames, Engine = GlassUF.API, GlassUF.Frames, GlassUF.Engine
local Castbar = GlassUF.Castbar

local Preview = {}
GlassUF.Preview = Preview
Preview.active = false

-- Each cast bar's loop: a sample per step (Castbar.ShowSample), then its end
-- (a green flash; red for `failed`; nothing for a channel).
local ICON = "Interface\\Icons\\"
Preview.CYCLES = {
    player = {
        { name = "Frostbolt", icon = ICON .. "Spell_Frost_FrostBolt02", len = 3.0, delay = 0.4, target = "Sample Target" },
        { name = "Arcane Missiles", icon = ICON .. "Spell_Nature_StarFall", len = 3.0, channel = true },
        { name = "Linen Bandage", icon = ICON .. "INV_Misc_Bandage_15", len = 3.0, count = { 2, 5 }, failed = true },
    },
    target = { { name = "Shadow Bolt", icon = ICON .. "Spell_Shadow_ShadowBolt", len = 2.5 } },
    focus = { { name = "Heal", icon = ICON .. "Spell_Holy_Heal", len = 2.0 } },
    pet = { { name = "Fire Bolt", icon = ICON .. "Spell_Fire_FireBolt", len = 1.5 } },
}
local FLASH, PAUSE = 0.5, 1.0   -- the end flash, then a pause before the next step

local loops = {}   -- unit -> { gen, dur, step, showing }

-- One step of a bar's loop; a newer generation (Stop, a restart) cancels it.
local function runStep(unit, c, i)
    local cycle, lp = Preview.CYCLES[unit], loops[unit]
    local s, gen = cycle[i], lp.gen
    if not Frames.attempt("preview cast", lp.dur.SetTimeFromStart, lp.dur, GetTime(), s.len) then return end
    lp.step, lp.showing = s, true
    Castbar.ShowSample(c, s, lp.dur)
    C_Timer.After(s.len, function()
        if not Preview.active or lp.gen ~= gen then return end
        lp.showing = false
        Castbar.SampleEnd(c, s.failed, s.channel)
        C_Timer.After(FLASH + PAUSE, function()
            if Preview.active and lp.gen == gen then runStep(unit, c, i % #cycle + 1) end
        end)
    end)
end

-- The step on screen again (a setting changed): same duration, no restart.
-- Nothing while its end flash or the pause runs.
local function refreshCast(c)
    local lp = c and loops[c.unit]
    if lp and lp.showing then Castbar.ShowSample(c, lp.step, lp.dur) end
end

-- A repaint the preview owns: refresh the sample it would have overwritten.
local function refresh(f, channel)
    if channel == "cast" then refreshCast(f.cast)
    elseif channel == "druidmana" then Frames.PaintDruidManaSample(f)
    elseif channel == "portrait" then Frames.SamplePortrait(f)
    elseif f.unit ~= "player" then Frames.PaintSample(f) end
end

-- The player's frame stays live but for these.
local PLAYER_OWNED = { cast = true, druidmana = true }

-- Engine's gate: true = the preview owns this (frame, channel); skip the painter.
function Preview.Owns(f, channel, event)
    if not Preview.active then return false end
    if f.unit == "player" and not PLAYER_OWNED[channel] then return false end
    if event == nil then refresh(f, channel) end
    return true
end
Engine.Owned = Preview.Owns

-- Castbar.Place ran (a size, scale, side or mode change): the sample follows.
function Preview.Placed(c)
    if c.unit ~= "swing" then refreshCast(c) end
end

-- Out of combat only.
function Preview.Start()
    if Preview.active then return true end
    if InCombatLockdown() then return false, "combat" end
    if not next(Frames.byUnit) then return false, "not built" end
    Preview.active = true   -- the gate first: showing a frame repaints it
    for unit, b in pairs(Frames.byUnit) do
        if unit ~= "player" then
            UnregisterUnitWatch(b)
            b:Show()
            Frames.PaintSample(b, true)
        end
    end
    for unit, c in pairs(Castbar.bars) do
        if Preview.CYCLES[unit] then
            Castbar.ResetForPreview(c)
            local lp = loops[unit] or { gen = 0, dur = C_DurationUtil.CreateDuration() }
            loops[unit] = lp
            lp.gen = lp.gen + 1
            runStep(unit, c, 1)
        end
    end
    local p = Frames.byUnit.player
    if p then Frames.PaintDruidManaSample(p) end
    GlassUF.Swing.SetPreview(true)
    GlassUF.Mirror.SetPreview(true)
    GlassUF.Timer.SetPreview(true)
    GlassUF.FiveSecond.SetPreview(true)
    return true
end

-- The unit watch back; a frame whose unit is plainly gone hides first, so it
-- never waits on the watch's next check.
local function restoreWatch()
    for unit, b in pairs(Frames.byUnit) do
        if unit ~= "player" then
            local ok, exists = pcall(UnitExists, unit)
            if ok and not API.IsSecret(exists) and not exists then b:Hide() end
            RegisterUnitWatch(b)
        end
    end
end

function Preview.Stop()
    if not Preview.active then return true end
    Preview.active = false
    for _, lp in pairs(loops) do
        lp.gen = lp.gen + 1
        lp.showing = false
    end
    -- Inside PLAYER_REGEN_DISABLED the lockdown isn't on yet (measured), so this
    -- normally runs now; if it is on, only the protected part waits.
    if InCombatLockdown() then GlassUF.WhenOutOfCombat("preview", restoreWatch, false)
    else restoreWatch() end
    for unit, c in pairs(Castbar.bars) do
        if Preview.CYCLES[unit] then Castbar.ResetForPreview(c) end
    end
    GlassUF.Swing.SetPreview(false)
    GlassUF.Mirror.SetPreview(false)
    GlassUF.Timer.SetPreview(false)
    GlassUF.FiveSecond.SetPreview(false)
    -- Real data over every sample; a cast in progress shows again.
    for unit in pairs(Frames.byUnit) do Engine.RepaintUnit(unit) end
    return true
end

function Preview.Toggle()
    if Preview.active then return Preview.Stop() end
    return Preview.Start()
end

-- Combat, or a loading screen: the preview ends.
function Preview.OnCombat()
    if Preview.active then Preview.Stop() end
end

Preview._test = { loops = loops, restoreWatch = restoreWatch }
