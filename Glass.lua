-- Glass.lua: the "liquid glass" material (style 4 of the probe).
--
-- Self-contained on purpose so other addons can copy it: it needs only the
-- textures from Tools/make_textures.py and a media path. It knows nothing
-- about units, events or secure frames. Full write-up, parameters and the
-- reasoning behind each layer: docs/GLASS-MATERIAL.md.
--
-- Layer stack on a host frame, bottom to top:
--   shadow -> tint -> grain -> wash      (on the host, masked to a rounded rect)
--   ...caller's content frames...        (host level + 2)
--   dark rim -> sheen -> rim -> text     (on g.top, host level + 10)
--   optional edge: top line + glow, bottom line (on g.top; off by default)

local ADDON = ...
GlassUF = GlassUF or {}
local Glass = {}
GlassUF.Glass = Glass

Glass.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local MASK_WRAP = "CLAMPTOBLACKADDITIVE"

-- Texture sets. Slice margins are in texture pixels and must match the
-- generator; "small" is for anything under ~40px tall. `inset` is where
-- content (bars) starts inside the bevel.
Glass.SIZES = {
    large = { mask = "body_mask", maskMargin = 16, rim = "rim5", dark = "rim_dark5", rimMargin = 16,
              shadow = "shadow", shadowMargin = 48, shadowPad = { -22, 20, 22, -26 }, inset = 6 },
    small = { mask = "body_mask_small", maskMargin = 8, rim = "rim5_small", dark = "rim_dark5_small", rimMargin = 8,
              shadow = "shadow_small", shadowMargin = 24, shadowPad = { -12, 10, 12, -14 }, inset = 3 },
}

-- The settled look: probe style 4 (docs/FOREVER-PROBE.md, third run) with the
-- thinner, dimmer rim5 from the outside review.
Glass.STYLE = {
    tint = { 0.13, 0.16, 0.22, 0.24 },   -- cool, light: glass, not smoked plastic
    grain = 0.45,                        -- faint frost; cannot track the scene behind
    wash = 0.18,                         -- top-down white gradient inside the body
    gloss = 0.45,                        -- ADD highlight on bars
    innerShadow = 0.35,                  -- bottom shade on bars
    rimAlpha = 0.7,                      -- outer rim, softened (owner-picked; 1.0 read as bulky)
    fillAlpha = 0.60,                    -- bar fill opacity: the scene shows through, text stays opaque
    fillEnd = 1.0,                       -- optional left-to-right fade of the fill (1 = none, as the mockup)
    trackTop = 0.75,                     -- the missing part: the bar's colour fading to clear across the bar
    frost = 0.10,                        -- plus a white frost, 0 at the bottom to this at the top
    sheenAlpha = 0.8,
    edge = 0,                            -- the optional directional edge's top line (0 = off; GlassChat ships 0.45)
}

-- The directional edge, as fractions of its top line (GlassChat's owner-tuned
-- values: top 0.45, glow 0.12, bottom 0.35), and the glow's depth.
Glass.EDGE = { glow = 0.12 / 0.45, bottom = 0.35 / 0.45, glowh = 4 }

-- Client-shipped fonts only. Arial Narrow runs small, so it gets a point more.
Glass.FONTS = {
    arial = { file = "Fonts\\ARIALN.TTF",   bump = 1 },
    friz  = { file = "Fonts\\FRIZQT__.TTF", bump = 0 },
}
Glass.fontKey = "arial"
local fontStrings = {}

local function slice(tex, m)
    tex:SetTextureSliceMargins(m, m, m, m)
    local modes = Enum and Enum.UITextureSliceMode
    tex:SetTextureSliceMode((modes and modes.Stretched) or 0)
end

-- A 9-sliced rounded mask owned by `host`, covering `anchor` (default: host)
-- inset by `inset` px. A mask masks textures of its own frame: give a child
-- its own mask anchored to the shape it must follow.
function Glass.Mask(host, file, margin, inset, anchor)
    local m = host:CreateMaskTexture()
    m:SetTexture(Glass.MEDIA .. file, MASK_WRAP, MASK_WRAP)
    inset = inset or 0
    anchor = anchor or host
    m:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    m:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
    slice(m, margin)
    return m
end

-- Apply the material to `host`. Returns a table of the regions it made:
-- g.top is the frame to parent text and anything that must sit above the rim.
local rims = {}
local edges = {}   -- every edge built, for Glass.SetEdgeAlpha (hosts that set their own are skipped)

-- Paint an edge: the top line's alpha, the glow's peak, the bottom line's, the
-- glow's depth. Hidden at 0, so an unused edge costs nothing to draw.
local function paintEdge(e, top, glow, bottom, glowh)
    e.top:SetColorTexture(1, 1, 1, top)
    e.glow:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, glow))
    e.glow:SetHeight(math.max(1, glowh))
    e.bottom:SetColorTexture(0, 0, 0, bottom)
    e.top:SetShown(top > 0)
    e.glow:SetShown(glow > 0)
    e.bottom:SetShown(bottom > 0)
end

-- A fine bright line along the top with a short sheen fading under it, and a
-- dark line along the bottom: a thinner, lit-from-above edge than the rim
-- alone (GlassChat, after an outside critique). Straight lines, kept off the
-- rounded corners by the mask's slice margin.
local function makeEdge(g, host, S)
    local inset = S.maskMargin - 2
    local e = {}
    e.top = g.top:CreateTexture(nil, "OVERLAY", nil, 7)
    e.top:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -1)
    e.top:SetPoint("TOPRIGHT", host, "TOPRIGHT", -inset, -1)
    e.top:SetHeight(1)
    e.glow = g.top:CreateTexture(nil, "OVERLAY", nil, 5)
    e.glow:SetColorTexture(1, 1, 1, 1)
    e.glow:SetPoint("TOPLEFT", e.top, "BOTTOMLEFT", 0, 0)
    e.glow:SetPoint("TOPRIGHT", e.top, "BOTTOMRIGHT", 0, 0)
    e.bottom = g.top:CreateTexture(nil, "OVERLAY", nil, 7)
    e.bottom:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", inset, 1)
    e.bottom:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, 1)
    e.bottom:SetHeight(1)
    local a = Glass.STYLE.edge
    paintEdge(e, a, a * Glass.EDGE.glow, a * Glass.EDGE.bottom, Glass.EDGE.glowh)
    table.insert(edges, e)
    return e
end

function Glass.Apply(host, size)
    local S = Glass.SIZES[size or "large"]
    local st = Glass.STYLE
    local g = { size = size or "large" }

    local sh = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    sh:SetTexture(Glass.MEDIA .. S.shadow)
    sh:SetPoint("TOPLEFT", host, "TOPLEFT", S.shadowPad[1], S.shadowPad[2])
    sh:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", S.shadowPad[3], S.shadowPad[4])
    slice(sh, S.shadowMargin)
    g.shadow = sh

    g.mask = Glass.Mask(host, S.mask, S.maskMargin)

    local tint = host:CreateTexture(nil, "BACKGROUND", nil, -6)
    tint:SetAllPoints(host)
    tint:SetColorTexture(st.tint[1], st.tint[2], st.tint[3], st.tint[4])
    tint:AddMaskTexture(g.mask)
    g.tint = tint

    local grain = host:CreateTexture(nil, "BACKGROUND", nil, -5)
    grain:SetAllPoints(host)
    grain:SetTexture(Glass.MEDIA .. "grain", "REPEAT", "REPEAT")
    grain:SetHorizTile(true)
    grain:SetVertTile(true)
    grain:SetAlpha(st.grain)
    grain:AddMaskTexture(g.mask)
    g.grain = grain

    local wash = host:CreateTexture(nil, "BACKGROUND", nil, -4)
    wash:SetAllPoints(host)
    wash:SetColorTexture(1, 1, 1, 1)
    wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, st.wash))
    wash:AddMaskTexture(g.mask)
    g.wash = wash

    local top = CreateFrame("Frame", nil, host)
    top:SetAllPoints(host)
    top:SetFrameLevel(host:GetFrameLevel() + 10)
    g.top = top

    local dark = top:CreateTexture(nil, "OVERLAY", nil, 4)
    dark:SetTexture(Glass.MEDIA .. S.dark)
    dark:SetAllPoints(top)
    slice(dark, S.rimMargin)
    g.dark = dark

    local rim = top:CreateTexture(nil, "OVERLAY", nil, 6)
    rim:SetTexture(Glass.MEDIA .. S.rim)
    rim:SetAllPoints(top)
    slice(rim, S.rimMargin)
    rim:SetAlpha(st.rimAlpha)
    table.insert(rims, rim)
    g.rim = rim

    g.edge = makeEdge(g, host, S)

    return g
end

-- A content frame level for things drawn between the body and the rim.
function Glass.ContentLevel(host)
    return host:GetFrameLevel() + 2
end

-- Content inset (px) inside the bevel for this material size.
function Glass.Inset(size)
    return Glass.SIZES[size or "large"].inset
end

-- A glass StatusBar: masked rounded fill, ADD gloss, inner shadow, thin edge.
-- Colour it with bar:SetStatusBarColor(r, g, b). Values may be secret:
-- SetMinMaxValues/SetValue take them without Lua touching them.
-- Levels above the bar: the track's clip frame at +1 (Glass.TRACK_LEVEL);
-- callers' overlays over the fill at +2 and +3 (GlassUnitFrames: health loss,
-- heal prediction); the gloss, shade and edge on bar.overlay at +4, so all of
-- them sit UNDER the glass layers, like the fill itself.
Glass.TRACK_LEVEL = 1
Glass.OVERLAY_LEVEL = 4
local bars = {}

-- Range check that also rejects NaN (it fails every comparison).
local function inRange(a, lo, hi)
    return type(a) == "number" and a >= lo and a <= hi
end

-- Re-applied after every colour change: the fill (optionally) fades from its
-- colour to STYLE.fillEnd at its moving edge (the gradient spans the fill
-- quad) and keeps STYLE.fillAlpha; the track takes the bar's colour at
-- STYLE.trackTop over its horizontal ramp. No arithmetic on the colour
-- beyond the caller's own (plain) alpha.
local function tintTrack(bar)
    local c, st = bar.trackColor, Glass.STYLE
    if not c then return end
    local fill = bar:GetStatusBarTexture()
    fill:SetAlpha(st.fillAlpha)   -- a client visual reset (SetTimerDuration) must not leave it opaque
    pcall(fill.SetGradient, fill, "HORIZONTAL",
        CreateColor(c[1], c[2], c[3], c[4]), CreateColor(c[1], c[2], c[3], c[4] * st.fillEnd))
    pcall(bar.track.SetVertexColor, bar.track, c[1], c[2], c[3], st.trackTop)
end

-- Live-tune how far the fill fades towards its edge (1 = no fade).
function Glass.SetFillEnd(a)
    if not inRange(a, 0, 1) then return false end
    Glass.STYLE.fillEnd = a
    for _, bar in ipairs(bars) do tintTrack(bar) end
    return true
end

-- Live-tune how strongly the missing part shows the bar's colour (top alpha).
function Glass.SetTrackAlpha(a)
    if not inRange(a, 0, 1) then return false end
    Glass.STYLE.trackTop = a
    for _, bar in ipairs(bars) do tintTrack(bar) end
    return true
end

function Glass.Bar(parent, height)
    local st = Glass.STYLE
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    local mask = Glass.Mask(bar, "bar_mask", 8)
    bar.glassMask = mask

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.15)
    bg:AddMaskTexture(mask)

    local frost = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
    frost:SetAllPoints(bar)
    frost:SetColorTexture(1, 1, 1, 1)
    frost:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, st.frost))
    frost:AddMaskTexture(mask)

    bar:SetStatusBarTexture(Glass.MEDIA .. "bar_fill")
    bar:GetStatusBarTexture():AddMaskTexture(mask)
    -- Translucent fill: the texture's own alpha, so SetStatusBarColor (which
    -- sets vertex colour) never resets it. Text lives on the host's g.top,
    -- not on the bar, so it stays fully opaque.
    bar:GetStatusBarTexture():SetAlpha(st.fillAlpha)
    table.insert(bars, bar)

    -- (After the fill exists: the clip anchors to its moving edge.)
    -- The missing health/power, as in the mockup: the bar's own colour, full
    -- over the first 30% of the bar, easing to clear glass by 85%. The ramp
    -- spans the whole bar but lives in a clip frame that starts at the fill's
    -- moving edge, so it only shows past the fill: a full bar stays even, and
    -- the ramp never doubles up under the translucent fill.
    local trackClip = CreateFrame("Frame", nil, bar)
    trackClip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    trackClip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    trackClip:SetClipsChildren(true)
    trackClip:SetFrameLevel(bar:GetFrameLevel() + Glass.TRACK_LEVEL)
    local track = trackClip:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    track:SetTexture(Glass.MEDIA .. "track_fade")
    track:SetVertexColor(1, 1, 1, 0)
    track:AddMaskTexture(Glass.Mask(trackClip, "bar_mask", 8, 0, bar))
    bar.track, bar.trackClip = track, trackClip
    -- Only re-tint on an actual change: painters recolour on every health and
    -- power event. A 4th (alpha) argument is honoured.
    hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b, a)
        a = a or 1
        local c = self.trackColor
        if c and c[1] == r and c[2] == g and c[3] == b and c[4] == a then return end
        self.trackColor = { r, g, b, a }
        tintTrack(self)
    end)


    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints(bar)
    over:SetFrameLevel(bar:GetFrameLevel() + Glass.OVERLAY_LEVEL)
    bar.overlay = over
    local omask = Glass.Mask(over, "bar_mask", 8)

    local gloss = over:CreateTexture(nil, "OVERLAY", nil, 1)
    gloss:SetAllPoints(bar)
    gloss:SetTexture(Glass.MEDIA .. "gloss")
    gloss:SetBlendMode("ADD")
    gloss:SetAlpha(st.gloss)
    gloss:AddMaskTexture(omask)

    local inner = over:CreateTexture(nil, "OVERLAY", nil, 2)
    inner:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
    inner:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    inner:SetHeight(math.max(3, math.floor(height * 0.45)))
    -- Keep the shade at 45% when the bar is resized later (the player's
    -- bars shrink while its inside cast row shows).
    hooksecurefunc(bar, "SetHeight", function(_, h)
        if type(h) == "number" then inner:SetHeight(math.max(3, math.floor(h * 0.45))) end
    end)
    inner:SetColorTexture(1, 1, 1, 1)
    inner:SetGradient("VERTICAL", CreateColor(0, 0, 0, st.innerShadow), CreateColor(0, 0, 0, 0))
    inner:AddMaskTexture(omask)

    local edge = over:CreateTexture(nil, "OVERLAY", nil, 3)
    edge:SetAllPoints(bar)
    edge:SetTexture(Glass.MEDIA .. "bar_edge")
    slice(edge, 8)

    -- Keep the overlay and the track's clip at their offsets when the caller moves the bar.
    hooksecurefunc(bar, "SetFrameLevel", function(self, level)
        over:SetFrameLevel(level + Glass.OVERLAY_LEVEL)
        trackClip:SetFrameLevel(level + Glass.TRACK_LEVEL)
    end)
    return bar
end

-- The client eases a StatusBar to its new value itself (secret values
-- included: Lua never sees the in-between). Enum names are not in the API
-- dump, so fall back to an instant change when they are missing.
function Glass.Smooth()
    local e = Enum and Enum.StatusBarInterpolation
    return e and e.ExponentialEaseOut or nil
end

-- Set a bar's range and value, eased unless `snap`. Both calls take the same
-- interpolation, so a max change doesn't jump the fill and then slide. If the
-- client rejects the eased call, fall back to an instant one rather than
-- leaving the bar frozen.
function Glass.SetBar(bar, maxValue, value, snap)
    local interp = (not snap) and Glass.Smooth() or nil
    if interp and pcall(function()
        bar:SetMinMaxValues(0, maxValue, interp)
        bar:SetValue(value, interp)
    end) then return end
    bar:SetMinMaxValues(0, maxValue)
    bar:SetValue(value)
end

-- A diagonal highlight that sweeps across the body once per Play(). Clipped
-- by its own mask on g.top, which stays put while the texture translates.
-- Returns the AnimationGroup; call :Stop() then :Play() to sweep.
function Glass.Sheen(g, host, width, height)
    local S = Glass.SIZES[g.size]
    local mask = Glass.Mask(g.top, S.mask, S.maskMargin)
    local s = g.top:CreateTexture(nil, "OVERLAY", nil, 5)
    s:SetTexture(Glass.MEDIA .. "sheen2")
    s:SetSize(math.floor(width * 0.5), height + 20)
    s:SetPoint("RIGHT", g.top, "LEFT", 0, 0)
    s:SetBlendMode("ADD")
    s:SetAlpha(0)
    s:AddMaskTexture(mask)

    local ag = s:CreateAnimationGroup()
    local move = ag:CreateAnimation("Translation")
    move:SetOffset(width + math.floor(width * 0.5), 0)
    move:SetDuration(0.9)
    move:SetSmoothing("IN_OUT")
    local fadeIn = ag:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(Glass.STYLE.sheenAlpha)
    fadeIn:SetDuration(0.25)
    local fadeOut = ag:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(Glass.STYLE.sheenAlpha)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(0.65)
    fadeOut:SetDuration(0.25)
    return ag
end

-- A FontString in the current glass font, tracked so Glass.SetFont can
-- restyle every one of them later.
function Glass.Font(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", nil, 7)
    local f = Glass.FONTS[Glass.fontKey] or Glass.FONTS.arial
    fs:SetFont(f.file, size + f.bump, "")
    -- Opaque, slightly longer shadow: at a 0.64 UI scale a 1-unit offset is
    -- under a pixel, and pale bars (a friendly target's green) washed it out.
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1.5, -1.5)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    table.insert(fontStrings, { fs = fs, size = size })
    return fs
end

-- Live-tune the bright rim's opacity on every glass surface built so far.
function Glass.SetRimAlpha(a)
    if not inRange(a, 0.2, 1) then return false end
    Glass.STYLE.rimAlpha = a
    for _, rim in ipairs(rims) do rim:SetAlpha(a) end
    return true
end

-- Live-tune the bar fill opacity on every glass bar built so far.
function Glass.SetFillAlpha(a)
    if not inRange(a, 0.2, 1) then return false end
    Glass.STYLE.fillAlpha = a
    for _, bar in ipairs(bars) do bar:GetStatusBarTexture():SetAlpha(a) end
    return true
end

-- Live-tune the directional edge on every glass surface built so far (its top
-- line; the glow and bottom line keep their ratios). 0 hides it.
function Glass.SetEdgeAlpha(a)
    if not inRange(a, 0, 1) then return false end
    Glass.STYLE.edge = a
    for _, e in ipairs(edges) do
        if not e.custom then paintEdge(e, a, a * Glass.EDGE.glow, a * Glass.EDGE.bottom, Glass.EDGE.glowh) end
    end
    return true
end

-- One host's own edge values (GlassChat's /gchat tune); Glass.SetEdgeAlpha
-- leaves it alone from then on.
function Glass.SetEdge(g, top, glow, bottom, glowh)
    g.edge.custom = true
    paintEdge(g.edge, top, glow, bottom, glowh or Glass.EDGE.glowh)
end

function Glass.SetFont(key)
    local f = Glass.FONTS[key]
    if not f then return false end
    Glass.fontKey = key
    for _, e in ipairs(fontStrings) do e.fs:SetFont(f.file, e.size + f.bump, "") end
    return true
end

-- The live-tunable material knobs, in one place for anything that exposes
-- them (GlassUnitFrames: /glass <key>, the options panel). `default` is the
-- shipped STYLE value, captured before any saved setting is applied.
Glass.TUNABLES = {
    { key = "fill",  style = "fillAlpha", set = Glass.SetFillAlpha,  min = 0.2, max = 1,
      label = "Bar fill opacity",     help = "bar fill opacity; text stays opaque" },
    { key = "rim",   style = "rimAlpha",  set = Glass.SetRimAlpha,   min = 0.2, max = 1,
      label = "Glass outline",        help = "brightness of the glass outline" },
    { key = "track", style = "trackTop",  set = Glass.SetTrackAlpha, min = 0,   max = 1,
      label = "Empty bar colour",     help = "how strongly a bar's empty part shows its colour" },
    { key = "fade",  style = "fillEnd",   set = Glass.SetFillEnd,    min = 0,   max = 1,
      label = "Fill fade (1 = none)", help = "how far a bar's fill fades towards its edge, 1 = none" },
    { key = "edge",  style = "edge",      set = Glass.SetEdgeAlpha,  min = 0,   max = 1,
      label = "Edge highlight",       help = "a fine bright top line and dark bottom line, 0 = off" },
}
for _, t in ipairs(Glass.TUNABLES) do t.default = Glass.STYLE[t.style] end
