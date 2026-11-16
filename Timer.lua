-- GlassUnitFrames: the combat timer (#120). A small glass pill over the
-- player's portrait with the fight's time (00:07, 1:00:05 past an hour). It
-- opens when combat starts (a circle growing into the pill, fading in) and
-- closes the same way when it ends, frozen on the fight's final time. With
-- the portrait set to "none", it sits over the frame's left edge instead.
-- Not movable: a detached timer is GlassPanel's business.
--
-- What shows comes from independent inputs, each set by its own event or
-- setter, and one resolver: off -> closed; preview -> the preview's clock;
-- combat -> its clock; else closed. Combat is recorded whatever else shows,
-- so the order of the combat handlers (Preview.OnCombat, this file's frame)
-- never loses a start. The time is our own stamp against GetTime(): plain,
-- no client secret.
--
-- Timer.enabled is public: ForeverCombatAssistant hides its own timer while
-- it's true.
--
-- The alert (#186), so a fight's start is noticed: Blizzard's gold proc glow
-- (SpellActivationOverlay's IconAlert, as Apotheca's ready check shows it)
-- bursts around the pill, holds, then fades (on by default; a preview plays
-- it too), and a sound kit plays (off by default; never in a preview). The
-- glow is drawn by the clock's own OnUpdate, ants included: AnimateTexCoords
-- is absent on Forever (measured in Apotheca).

GlassUF = GlassUF or {}
local API, Glass = GlassUF.API, GlassUF.Glass

local Timer = {}
GlassUF.Timer = Timer

local W, H = 52, 18       -- narrower than the 62 px tile: clear of the leader crown at the body's corner
local GAP = 4             -- over the tile
local GAP_NO_TILE = 10    -- over the body's top-left corner: clear of the crown (7 above the edge)
local TEXT_SIZE = 13
local TICK = 0.2          -- the clock's writes (only when the whole second changed)
local ANIM = 0.25         -- opening and closing, seconds
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

local ALERT = "Interface\SpellActivationOverlay\IconAlert"
local ANTS = "Interface\SpellActivationOverlay\IconAlertAnts"
local GLOW_IN, GLOW_HOLD, GLOW_OUT = 0.3, 3, 0.4   -- the burst, the hold, the fade (seconds)
local OVERLAY = 1.4       -- the glow's box, times the pill on each axis (an action button's proportions)
local ANT_FRAMES, ANT_STEP, ANT_SIZE = 22, 0.01, 48 / 256   -- the ants' flipbook: 5 a row on a 256 px sheet
Timer.SOUND_KIT = 8959    -- SOUNDKIT.RAID_WARNING

Timer.enabled = true      -- db.combatTimer == false turns it off
Timer.glow = true         -- db.timerGlow == false turns it off
Timer.sound = false       -- db.timerSound == true turns it on
local c                   -- host, glass, text, ticker
local live                -- GetTime() at combat start, or nil out of combat
local previewAt           -- GetTime() at the preview's start, or nil
local shownSecond         -- the whole second on screen
local open = 0            -- 0 closed .. 1 open: the pill's width and alpha
local anim                -- { from, to, t0 } while opening or closing
local glowAt              -- GetTime() at the glow's start, or nil
local antFrame            -- the ants' flipbook frame on screen

function Timer.Format(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

-- The clock that shows now, as its start stamp; nil = closed.
local function since()
    if not Timer.enabled then return nil end
    return previewAt or live
end

local function write(seconds)
    local whole = math.floor(seconds)
    if whole == shownSecond then return end
    shownSecond = whole
    c.text:SetText(Timer.Format(whole))
end

-- The pill at `f` open: from a circle (H wide) to W, transparent to opaque.
local function draw(f)
    open = f
    c.host:SetWidth(H + (W - H) * f)
    c.host:SetAlpha(f)
end

local function easeOut(t) return 1 - (1 - t) ^ 3 end

-- Step the animation; true while it runs.
local function stepAnim()
    if not anim then return false end
    local t = math.min(1, (GetTime() - anim.t0) / ANIM)
    draw(anim.from + (anim.to - anim.from) * easeOut(t))
    if t < 1 then return true end
    anim = nil
    if open == 0 then
        c.host:Hide()
        Timer.StopGlow()   -- it faded with the pill
    end
    return false
end

local function animateTo(to)
    if open == to and not anim then return end
    if anim and anim.to == to then return end
    anim = { from = open, to = to, t0 = GetTime() }
    c.host:Show()
end

--------------------------------------------------------------------------------
-- The glow (#186)
--------------------------------------------------------------------------------

-- A glow texture `k` times the glow's box, the box OVERLAY times the pill as
-- it is now (it follows the opening).
local function size(tex, k)
    tex:SetSize((H + (W - H) * open) * OVERLAY * k, H * OVERLAY * k)
end

local function stepGlow()
    if not glowAt then return end
    local t = GetTime() - glowAt
    if t >= GLOW_IN + GLOW_HOLD + GLOW_OUT then
        Timer.StopGlow()
        return
    end
    local g = c.glow
    local e = easeOut(math.min(1, t / GLOW_IN))
    local fade = 1
    if t > GLOW_IN + GLOW_HOLD then fade = 1 - (t - GLOW_IN - GLOW_HOLD) / GLOW_OUT end
    -- The burst: the ring closes in from twice its size, white turning gold,
    -- while an inner glow grows out of the pill and goes.
    size(g.outer, 2 - e)
    g.outer:SetAlpha(fade)
    size(g.flash, 2 - e)
    g.flash:SetAlpha(1 - e)
    size(g.inner, 0.5 + 0.5 * e)
    g.inner:SetAlpha(math.max(0, math.min(1, 1 - (t - GLOW_IN) / 0.2)))
    -- The ants march once the burst is over.
    size(g.ants, 0.85)
    g.ants:SetAlpha(math.max(0, math.min(1, (t - GLOW_IN) / 0.2)) * fade)
    local f = math.floor(t / ANT_STEP) % ANT_FRAMES
    if f ~= antFrame then
        antFrame = f
        local col, row = f % 5, math.floor(f / 5)
        g.ants:SetTexCoord(col * ANT_SIZE, (col + 1) * ANT_SIZE, row * ANT_SIZE, (row + 1) * ANT_SIZE)
    end
end

-- From the burst, while the option is on. The clock's OnUpdate draws it.
local function startGlow()
    if not c or not Timer.glow or not since() then return end
    glowAt = GetTime()
    antFrame = nil
    c.glow.frame:Show()
    stepGlow()
    c.ticker:Show()
end

function Timer.StopGlow()
    glowAt = nil
    if c then c.glow.frame:Hide() end
end

local function resolve()
    if not c then return end
    local s = since()
    if s then
        shownSecond = nil
        write(GetTime() - s)
        animateTo(1)
    else
        animateTo(0)   -- frozen on the last time while it closes
    end
    c.ticker:SetShown(s ~= nil or anim ~= nil)
end

local function onEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        live = GetTime()
        resolve()
        startGlow()
        if Timer.sound and not API.PlaySoundKit(Timer.SOUND_KIT) then
            API.Fail("timer sound", "sound kit " .. Timer.SOUND_KIT .. " could not be played")
        end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        live = nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A /reload mid-fight counts from now (the best known); a loading
        -- screen inside a fight already timed keeps its start.
        if InCombatLockdown() then live = live or GetTime() else live = nil end
    end
    resolve()
end

-- Over the portrait tile while it shows, else over the frame's left edge.
-- Also called when the player's portrait mode is applied.
function Timer.Place()
    if not c then return end
    local b, host = c.b, c.host
    host:ClearAllPoints()
    if b.tile and b.portraitMode ~= "none" then
        host:SetPoint("BOTTOM", b.tile, "TOP", 0, GAP)
    else
        -- The body, not the button: it rides the group layout's glide (#132).
        host:SetPoint("BOTTOMLEFT", b.body, "TOPLEFT", 0, GAP_NO_TILE)
    end
end

--------------------------------------------------------------------------------
-- Building and settings
--------------------------------------------------------------------------------

-- Called by Frames.Build for the player's frame. Built even when off, so
-- turning it on later works.
function Timer.Build(b, db)
    if not b then return end
    Timer.enabled = db.combatTimer ~= false
    Timer.glow = db.timerGlow ~= false
    Timer.sound = db.timerSound == true
    local level = b:GetFrameLevel() + 1
    local host = CreateFrame("Frame", nil, b)   -- a plain child: hidden with the button, never protected
    host:SetFrameLevel(level)
    host:SetSize(H, H)
    local glass = Glass.Apply(host, "small")
    local text = Glass.Font(glass.top, TEXT_SIZE, "CENTER")
    text:SetPoint("CENTER", host, "CENTER", 0, 0)
    text:SetTextColor(1, 1, 1, 0.95)
    -- The clock and the animation: shown only while one runs; inside the host,
    -- so it rests while the player frame is hidden (the stamp keeps the time).
    local ticker = CreateFrame("Frame", nil, host)
    ticker:Hide()
    ticker.acc = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
        local animating = stepAnim()
        stepGlow()
        self.acc = self.acc + elapsed
        if self.acc >= TICK then
            self.acc = 0
            local s = since()
            if s then write(GetTime() - s) end
        end
        if not animating and not since() then self:Hide() end
    end)
    -- The glow: over the rim (the glass's top layer is the host's + 10), its
    -- textures centred on the pill and sized as it opens.
    local gf = CreateFrame("Frame", nil, host)
    gf:SetFrameLevel(level + 11)
    gf:SetAllPoints(host)
    gf:Hide()
    local function tex(file, layer, l, r, t, bt)
        local x = gf:CreateTexture(nil, layer)
        x:SetTexture(file)
        x:SetTexCoord(l, r, t, bt)
        x:SetPoint("CENTER", host, "CENTER", 0, 0)
        x:SetAlpha(0)
        return x
    end
    local glow = {
        frame = gf,
        outer = tex(ALERT, "ARTWORK", 0.00781, 0.50781, 0.27734, 0.52734),
        inner = tex(ALERT, "ARTWORK", 0.00781, 0.50781, 0.27734, 0.52734),
        flash = tex(ALERT, "ARTWORK", 0.00781, 0.50781, 0.53516, 0.78516),   -- the white ring
        ants = tex(ANTS, "OVERLAY", 0, ANT_SIZE, 0, ANT_SIZE),
    }
    c = { b = b, host = host, glass = glass, text = text, ticker = ticker, glow = glow }
    host:SetAlpha(0)
    host:Hide()
    Timer.Place()

    local ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", onEvent)
    c.events = ev
    if Timer.enabled then
        API.RegisterEvents(ev, EVENTS)
        -- A build deferred until now may come after the fight's start.
        live = InCombatLockdown() and GetTime() or nil
    end
    resolve()
    return c
end

-- On or off (saved only when off). A request for the state it's in changes
-- nothing, so a repeated "on" mid-fight keeps counting. Off -> on re-reads
-- combat: the start was missed while off, so it counts from now.
function Timer.SetEnabled(on)
    on = on and true or false
    if not c then
        Timer.enabled = on
        return false
    end
    if on == Timer.enabled then return true end
    Timer.enabled = on
    if on then
        API.RegisterEvents(c.events, EVENTS)
        live = InCombatLockdown() and GetTime() or nil
    else
        c.events:UnregisterAllEvents()
        live = nil
    end
    resolve()
    return true
end

-- The glow and the sound at a fight's start (#186).
function Timer.SetGlow(on)
    Timer.glow = on and true or false
    if not Timer.glow then Timer.StopGlow() end
    return true
end

function Timer.SetSound(on)
    Timer.sound = on and true or false
    return true
end

-- Plays the sound once (`/glass timer sound test`); false when refused.
function Timer.TestSound()
    return API.PlaySoundKit(Timer.SOUND_KIT)
end

-- Preview mode (#109): counts up from 00:00 like a fight, with the glow.
function Timer.SetPreview(on)
    previewAt = on and GetTime() or nil
    resolve()
    if on then startGlow() end
end

Timer._test = { bar = function() return c end, live = function() return live end, onEvent = onEvent,
                open = function() return open end, glowing = function() return glowAt ~= nil end }
