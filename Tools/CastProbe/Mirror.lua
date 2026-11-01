-- CastProbe, the mirror timers' gate (#151): are GetMirrorTimerInfo's and
-- GetMirrorTimerProgress's values plain, in and out of combat, and does GUF's
-- glass pill replace Blizzard's? A second file of the same module (one name,
-- one module): /fp steps cast mirror.

local Probe = ForeverProbe:Module("CastProbe", { api = 1, cmd = "cast" })

local function show(v) return Probe.Show(v, true) end
local isSecretFn = rawget(_G, "issecretvalue")
local function secret(v) return isSecretFn ~= nil and isSecretFn(v) == true end

-- Every live timer, every value classified (Show renders a secret as <secret>).
local function mirrorLine()
    local parts = { "mirror combat=" .. show(InCombatLockdown()) }
    for i = 1, 3 do
        local ok, name, value, maxValue, scale, paused, label, spellID = pcall(GetMirrorTimerInfo, i)
        if not ok then
            parts[#parts + 1] = i .. ":ERR"
        else
            local prog = "?"
            if type(name) == "string" and not secret(name) and name ~= "UNKNOWN" then
                local okP, p = pcall(GetMirrorTimerProgress, name)
                prog = okP and show(p) or "ERR"
            end
            parts[#parts + 1] = string.format("%d:{name=%s value=%s max=%s scale=%s paused=%s label=%s spell=%s progress=%s}",
                i, show(name), show(value), show(maxValue), show(scale), show(paused), show(label), show(spellID), prog)
        end
    end
    local GUF = rawget(_G, "GlassUF")
    local bar = GUF and GUF.Castbar and GUF.Castbar.bars.mirror
    local mc = rawget(_G, "MirrorTimerContainer")
    parts[#parts + 1] = "gufPill=" .. show(bar and bar.host:IsShown()) .. " blizzard=" .. show(mc and mc:IsShown())
    return table.concat(parts, " ")
end

local function read()
    local line = mirrorLine()
    Probe:Say(line)
    return line
end

Probe:Command("mirror", read, "the live mirror timers, every value classified")

Probe:Steps("mirror", {
    title = "Mirror timers (#151)",
    rev = 1,
    { text = "Swim down and stay under water until the breath bar appears.", event = "MIRROR_TIMER_START" },
    { text = "Still under water: press Run.", button = "Read timers", run = read },
    { text = "Is the glass Breath bar at the top of the screen, counting down, with Blizzard's gone?",
      ask = true, screenshot = "breath" },
    { text = "Pull a mob that follows you into the water (or get hit while under): press Run in combat.",
      button = "Read timers", run = read,
      check = function() return InCombatLockdown(), "read in combat" end },
    { text = "Come up for air and wait until the bar has gone.", event = "MIRROR_TIMER_STOP" },
    { text = "Did the glass bar go away when the client's did?", ask = true },
    { text = "Hunters: Feign Death, then press Run while it lasts. Others: Skip.", button = "Read timers", run = read },
    { text = "Type /reload (or press Reload now) to save the results.", reload = true },
})
