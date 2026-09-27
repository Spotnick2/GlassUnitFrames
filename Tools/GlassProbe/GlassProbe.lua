-- GlassProbe: probe 1 of docs/POC-PLAN.md. One glass unit frame, built from
-- the textures in Media/ (Tools/make_textures.py), with slash commands to flip
-- every layer and setting for A/B screenshots. Throwaway: not secure, fake
-- values only, no events beyond login.
--
-- Every construction step runs through try() so one missing API cannot take
-- the whole frame down; /gprobe report lists what failed and why.

local MEDIA = "Interface\\AddOns\\GlassProbe\\Media\\"
local MASK_WRAP = "CLAMPTOBLACKADDITIVE"

local steps = {}
local layers = {}        -- name -> list of regions/frames
local allTextures = {}   -- for the snap toggle
local P = {}             -- frame references

local function say(msg) print("|cff7fd4ffGlassProbe|r " .. msg) end

local function try(name, fn, ...)
    local ok, err = pcall(fn, ...)
    steps[#steps + 1] = { name = name, ok = ok, err = err }
    if not ok then say("|cffff6060FAILED|r " .. name .. ": " .. tostring(err)) end
    return ok, err
end

local function addLayer(name, region)
    layers[name] = layers[name] or {}
    table.insert(layers[name], region)
end

local function track(tex)
    allTextures[#allTextures + 1] = tex
    return tex
end

local function sliceMode()
    local e = Enum and Enum.UITextureSliceMode
    return (e and e.Stretched) or 0
end

local function slice(tex, m)
    tex:SetTextureSliceMargins(m, m, m, m)
    tex:SetTextureSliceMode(sliceMode())
end

-- A rounded mask on `host`, 9-sliced so the corner radius holds at any size.
local function makeMask(host, file, margin, inset)
    local m = host:CreateMaskTexture()
    m:SetTexture(MEDIA .. file, MASK_WRAP, MASK_WRAP)
    inset = inset or 0
    m:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -inset)
    m:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
    try("slice mask " .. file, slice, m, margin)
    return m
end

-- The glass material on `host`: shadow, tint, grain and wash on host itself,
-- then a `top` child frame (above any content frames) carrying rim and sheen.
local function buildGlass(host, key)
    local g = {}

    try(key .. " shadow", function()
        local t = track(host:CreateTexture(nil, "BACKGROUND", nil, -8))
        t:SetTexture(MEDIA .. "shadow")
        t:SetPoint("TOPLEFT", host, "TOPLEFT", -22, 20)
        t:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 22, -26)
        slice(t, 48)
        addLayer("shadow", t)
    end)

    try(key .. " body mask", function() g.mask = makeMask(host, "body_mask", 16) end)

    try(key .. " tint", function()
        local t = track(host:CreateTexture(nil, "BACKGROUND", nil, -6))
        t:SetAllPoints(host)
        t:SetColorTexture(0.05, 0.07, 0.11, 0.40)
        if g.mask then t:AddMaskTexture(g.mask) end
        g.tint = t
        addLayer("tint", t)
    end)

    try(key .. " grain", function()
        local t = track(host:CreateTexture(nil, "BACKGROUND", nil, -5))
        t:SetAllPoints(host)
        t:SetTexture(MEDIA .. "grain", "REPEAT", "REPEAT")
        t:SetHorizTile(true)
        t:SetVertTile(true)
        if g.mask then t:AddMaskTexture(g.mask) end
        g.grain = t
        addLayer("grain", t)
    end)

    try(key .. " wash (SetGradient)", function()
        local t = track(host:CreateTexture(nil, "BACKGROUND", nil, -4))
        t:SetAllPoints(host)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0.0), CreateColor(1, 1, 1, 0.12))
        if g.mask then t:AddMaskTexture(g.mask) end
        g.wash = t
        addLayer("wash", t)
    end)

    try(key .. " top frame", function()
        local top = CreateFrame("Frame", nil, host)
        top:SetAllPoints(host)
        top:SetFrameLevel(host:GetFrameLevel() + 10)
        g.top = top

        local dark = track(top:CreateTexture(nil, "OVERLAY", nil, 4))
        dark:SetTexture(MEDIA .. "rim_dark")
        dark:SetAllPoints(top)
        slice(dark, 16)
        g.dark = dark
        addLayer("rimdark", dark)

        local rim = track(top:CreateTexture(nil, "OVERLAY", nil, 6))
        rim:SetTexture(MEDIA .. "rim")
        rim:SetAllPoints(top)
        slice(rim, 16)
        g.rim = rim
        addLayer("rim", rim)
    end)

    return g
end

-- A StatusBar with a masked fill, gloss, inner shadow and a thin edge.
local function buildBar(parent, key, height, r, gr, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.8)

    local mask
    try(key .. " mask", function() mask = makeMask(bar, "bar_mask", 8) end)

    try(key .. " background", function()
        local t = track(bar:CreateTexture(nil, "BACKGROUND"))
        t:SetAllPoints(bar)
        t:SetColorTexture(0, 0, 0, 0.35)
        if mask then t:AddMaskTexture(mask) end
        addLayer("barbg", t)
    end)

    try(key .. " fill (masked StatusBar texture)", function()
        bar:SetStatusBarTexture(MEDIA .. "bar_fill")
        bar:SetStatusBarColor(r, gr, b)
        local fill = track(bar:GetStatusBarTexture())
        if mask then fill:AddMaskTexture(mask) end
    end)

    try(key .. " gloss (ADD)", function()
        local t = track(bar:CreateTexture(nil, "OVERLAY", nil, 1))
        t:SetAllPoints(bar)
        t:SetTexture(MEDIA .. "gloss")
        t:SetBlendMode("ADD")
        t:SetAlpha(0.45)
        if mask then t:AddMaskTexture(mask) end
        addLayer("gloss", t)
    end)

    try(key .. " inner shadow (SetGradient)", function()
        local t = track(bar:CreateTexture(nil, "OVERLAY", nil, 2))
        t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
        t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
        t:SetHeight(math.max(3, math.floor(height * 0.45)))
        t:SetColorTexture(1, 1, 1, 1)
        t:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(0, 0, 0, 0))
        if mask then t:AddMaskTexture(mask) end
        addLayer("inner", t)
    end)

    try(key .. " edge", function()
        local t = track(bar:CreateTexture(nil, "OVERLAY", nil, 3))
        t:SetAllPoints(bar)
        t:SetTexture(MEDIA .. "bar_edge")
        slice(t, 8)
        addLayer("baredge", t)
    end)

    return bar
end

local function font(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", nil, 7)
    fs:SetFontObject("GameFontHighlight")
    local file = fs:GetFont()
    fs:SetFont(file, size, "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
    fs:SetJustifyH(justify)
    P.fonts = P.fonts or {}
    table.insert(P.fonts, { fs = fs, size = size })
    addLayer("text", fs)
    return fs
end

-- Client-shipped fonts only (no licensing question). Arial Narrow runs small,
-- so it gets a point more.
local FONTS = {
    friz  = { file = "Fonts\\FRIZQT__.TTF", bump = 0 },
    arial = { file = "Fonts\\ARIALN.TTF",   bump = 1 },
}
local currentFont

local function setFont(key)
    local f = FONTS[key]
    if not (f and P.fonts) then return false end
    for _, e in ipairs(P.fonts) do e.fs:SetFont(f.file, e.size + f.bump, "") end
    currentFont = key
    return true
end

local W, H, PORTRAIT = 360, 66, 66

local function build()
    local root = CreateFrame("Frame", "GlassProbeFrame", UIParent)
    root:SetSize(W, H)
    root:SetPoint("CENTER", UIParent, "CENTER", 40, -140)
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", root.StartMoving)
    root:SetScript("OnDragStop", root.StopMovingOrSizing)
    root:SetClampedToScreen(true)
    root:Hide()   -- hidden until /gprobe show: a tuning tool, not a frame to live with
    P.root = root
    P.glass = buildGlass(root, "frame")

    -- Bars sit between the body (on root) and the rim (on glass.top).
    P.health = buildBar(root, "health", 32, 0.56, 0.34, 0.92)
    P.health:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -8)
    P.health:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -8)
    P.health:SetFrameLevel(root:GetFrameLevel() + 2)

    P.power = buildBar(root, "power", 12, 0.16, 0.56, 1.0)
    P.power:SetPoint("TOPLEFT", P.health, "BOTTOMLEFT", 0, -4)
    P.power:SetPoint("TOPRIGHT", P.health, "BOTTOMRIGHT", 0, -4)
    P.power:SetFrameLevel(root:GetFrameLevel() + 2)
    P.power:SetValue(0.72)

    local top = P.glass.top
    if top then
        try("text", function()
            local name = font(top, 15, "LEFT")
            name:SetPoint("LEFT", P.health, "LEFT", 10, 0)
            name:SetText("Morphisto")
            P.valueText = font(top, 15, "RIGHT")
            P.valueText:SetPoint("RIGHT", P.health, "RIGHT", -10, 0)
            local pw = font(top, 11, "RIGHT")
            pw:SetPoint("RIGHT", P.power, "RIGHT", -8, 0)
            pw:SetText("920")
        end)

        -- The sheen lives on `top` with its own body mask, so the translating
        -- texture is clipped by a mask that stays put.
        try("sheen", function()
            local mask = makeMask(top, "body_mask", 16)
            local s = track(top:CreateTexture(nil, "OVERLAY", nil, 5))
            s:SetTexture(MEDIA .. "sheen")
            s:SetSize(180, H + 20)
            s:SetPoint("RIGHT", top, "LEFT", 0, 0)
            s:SetBlendMode("ADD")
            s:SetAlpha(0)
            s:AddMaskTexture(mask)
            local ag = s:CreateAnimationGroup()
            local move = ag:CreateAnimation("Translation")
            move:SetOffset(W + 180, 0)
            move:SetDuration(0.9)
            move:SetSmoothing("IN_OUT")
            local fadeIn = ag:CreateAnimation("Alpha")
            fadeIn:SetFromAlpha(0)
            fadeIn:SetToAlpha(1)
            P.sheenPeak = fadeIn
            fadeIn:SetDuration(0.25)
            local fadeOut = ag:CreateAnimation("Alpha")
            fadeOut:SetFromAlpha(1)
            P.sheenFade = fadeOut
            fadeOut:SetToAlpha(0)
            fadeOut:SetStartDelay(0.65)
            fadeOut:SetDuration(0.25)
            P.sheen, P.sheenAnim = s, ag
            addLayer("sheen", s)
        end)
    end

    -- Portrait tile, to the left of the frame, as a child so /gprobe scale moves both.
    local tile = CreateFrame("Frame", nil, root)
    tile:SetSize(PORTRAIT, PORTRAIT)
    tile:SetPoint("RIGHT", root, "LEFT", -6, 0)
    P.tile = tile
    P.tileGlass = buildGlass(tile, "portrait")
    addLayer("portrait", tile)

    try("portrait 3d model", function()
        local m = CreateFrame("PlayerModel", nil, tile)
        m:SetPoint("TOPLEFT", tile, "TOPLEFT", 4, -4)
        m:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -4, 4)
        m:SetFrameLevel(tile:GetFrameLevel() + 2)
        m:SetKeepModelOnHide(true)
        P.model = m
    end)

    try("portrait 2d masked", function()
        local holder = CreateFrame("Frame", nil, tile)
        holder:SetAllPoints(tile)
        holder:SetFrameLevel(tile:GetFrameLevel() + 2)
        local mask = makeMask(holder, "body_mask", 16, 3)
        local t = track(holder:CreateTexture(nil, "ARTWORK"))
        t:SetPoint("TOPLEFT", holder, "TOPLEFT", 3, -3)
        t:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -3, 3)
        t:AddMaskTexture(mask)
        P.portrait2dTex = t
        P.portrait2d = holder
        holder:Hide()
    end)
end

-- Material variants, switchable live with /gprobe style <n>.
-- 1: the first cut ("chrome bezel"); 2: thin clear rim; 3: thick clear bevel.
local STYLES = {
    { rim = "rim",  dark = "rim_dark",  sheen = "sheen",  tint = { 0.05, 0.07, 0.11, 0.40 }, grain = 1.0, wash = 0.12, sheenAlpha = 1.0 },
    { rim = "rim2", dark = "rim_dark2", sheen = "sheen2", tint = { 0.10, 0.12, 0.16, 0.26 }, grain = 0.5, wash = 0.16, sheenAlpha = 0.8 },
    { rim = "rim3", dark = "rim_dark3", sheen = "sheen2", tint = { 0.08, 0.10, 0.14, 0.30 }, grain = 0.6, wash = 0.14, sheenAlpha = 0.8 },
    -- 4: style 3 polished: brighter rim with corner glints, cooler and lighter tint, Arial Narrow.
    { rim = "rim4", dark = "rim_dark4", sheen = "sheen2", tint = { 0.13, 0.16, 0.22, 0.24 }, grain = 0.45, wash = 0.18, sheenAlpha = 0.8, font = "arial" },
}
local currentStyle

local function applyStyle(n)
    local st = STYLES[n]
    if not st then return false end
    for _, g in ipairs({ P.glass, P.tileGlass }) do
        if g then
            if g.rim then g.rim:SetTexture(MEDIA .. st.rim); slice(g.rim, 16) end
            if g.dark then g.dark:SetTexture(MEDIA .. st.dark); slice(g.dark, 16) end
            if g.tint then g.tint:SetColorTexture(st.tint[1], st.tint[2], st.tint[3], st.tint[4]) end
            if g.grain then g.grain:SetAlpha(st.grain) end
            if g.wash then
                g.wash:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, st.wash))
            end
        end
    end
    if P.sheen then P.sheen:SetTexture(MEDIA .. st.sheen); P.sheenMax = st.sheenAlpha end
    if P.sheenPeak then P.sheenPeak:SetToAlpha(st.sheenAlpha) end
    if P.sheenFade then P.sheenFade:SetFromAlpha(st.sheenAlpha) end
    setFont(st.font or "friz")
    currentStyle = n
    return true
end

-- SUF's refresh sequence (modules/portrait.lua): clear, set unit, zoom, reset
-- position, show. Run on events, not just once at login.
local function refreshPortrait()
    if P.model then
        P.model:ClearModel()
        P.model:SetUnit("player")
        P.model:SetPortraitZoom(1)
        P.model:SetPosition(0, 0, 0)
    end
    -- disableMasking = true: a square portrait, not the client's circle on black corners.
    if P.portrait2dTex then SetPortraitTexture(P.portrait2dTex, "player", true) end
end

local function setFill(v, quiet)
    P.health:SetValue(v)
    if P.valueText then
        P.valueText:SetText(string.format("%.2fk | %d%%", 1.55 * v, math.floor(v * 100 + 0.5)))
    end
    if not quiet and P.sheenAnim then P.sheenAnim:Stop(); P.sheenAnim:Play() end
end

-- Show the probe. The portrait was refreshed while hidden, so refresh it now
-- (a PlayerModel set up while hidden can come up blank), and play the sheen.
local function showProbe()
    P.root:Show()
    try("portrait refresh on show", refreshPortrait)
    if P.sheenAnim then P.sheenAnim:Stop(); P.sheenAnim:Play() end
end

-- Commands whose result you can only judge by looking: they show the probe.
local VISUAL = { fill = true, sheen = true, sheenloop = true, layer = true, rimadd = true, snap = true,
                 scale = true, tint = true, portrait = true, style = true, font = true, newfile = true }

local presets = { empty = 0, tiny = 0.03, half = 0.5, full = 1 }
local sheenLoop

local function toggleLayer(name)
    local list = layers[name]
    if not list then
        local names = {}
        for k in pairs(layers) do names[#names + 1] = k end
        table.sort(names)
        say("layers: " .. table.concat(names, ", "))
        return
    end
    local show = not list[1]:IsShown()
    for _, r in ipairs(list) do r:SetShown(show) end
    say(name .. (show and " on" or " off"))
end

local function report()
    local ok, bad = 0, 0
    for _, s in ipairs(steps) do
        if s.ok then ok = ok + 1 else bad = bad + 1 end
    end
    say(string.format("%d steps ok, %d failed", ok, bad))
    for _, s in ipairs(steps) do
        if not s.ok then say("  FAILED " .. s.name .. ": " .. tostring(s.err)) end
    end
    local build = select(2, GetBuildInfo())
    local pw, ph = 0, 0
    if GetPhysicalScreenSize then pw, ph = GetPhysicalScreenSize() end
    say(string.format("build %s, screen %dx%d, UIParent scale %.3f, frame effective scale %.3f",
        tostring(build), pw, ph, UIParent:GetEffectiveScale(), P.root:GetEffectiveScale()))
    local modelFile = P.model and select(2, pcall(P.model.GetModelFileID, P.model))
    local texFile = P.portrait2dTex and select(2, pcall(P.portrait2dTex.GetTextureFileID, P.portrait2dTex))
    say("font " .. tostring(currentFont) .. ": " .. tostring(P.fonts and P.fonts[1].fs:GetFont()))
    say(string.format("style %s, 3d model file %s (shown %s), 2d portrait file %s (shown %s)",
        tostring(currentStyle), tostring(modelFile), tostring(P.model and P.model:IsShown()),
        tostring(texFile), tostring(P.portrait2d and P.portrait2d:IsShown())))
end

local HELP = {
    "show | hide  - the probe starts hidden",
    "fill empty|tiny|half|full|<0-1>  - set health (plays the sheen)",
    "sheen  - play the sheen once;  sheenloop - repeat it every 2.5s",
    "layer <name>  - toggle a layer (no name lists them)",
    "rimadd  - toggle rim blend ADD/BLEND",
    "snap on|off  - pixel snapping on every texture",
    "scale <n>  - frame scale;  tint <0-1> - body tint alpha",
    "style 1|2|3|4  - material: 1 first cut, 2 thin rim, 3 thick bevel, 4 polished bevel",
    "font arial|friz  - override the style's font",
    "portrait 3d|2d  - model or masked 2D portrait (no arg: refresh)",
    "newfile  - show Media\\late.tga (new-file-after-/reload check)",
    "report  - failed steps, build, screen and scale",
    "reset  - recentre",
}

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if not P.root and cmd ~= "" and cmd ~= "help" then
        say("the probe did not build; see the errors printed at login")
        return
    end
    if VISUAL[cmd] and not P.root:IsShown() then
        showProbe()
        say("showing the probe (/gprobe hide)")
    end
    if cmd == "fill" then
        local v = presets[arg] or tonumber(arg)
        if v then setFill(math.max(0, math.min(1, v))) else say("fill empty|tiny|half|full|<0-1>") end
    elseif cmd == "sheen" then
        if P.sheenAnim then P.sheenAnim:Stop(); P.sheenAnim:Play() end
    elseif cmd == "sheenloop" then
        if sheenLoop then
            sheenLoop:Cancel(); sheenLoop = nil; say("sheen loop off")
        elseif P.sheenAnim then
            sheenLoop = C_Timer.NewTicker(2.5, function() P.sheenAnim:Stop(); P.sheenAnim:Play() end)
            say("sheen loop on")
        end
    elseif cmd == "layer" then
        toggleLayer(arg)
    elseif cmd == "rimadd" then
        for _, g in ipairs({ P.glass, P.tileGlass }) do
            if g.rim then g.rim:SetBlendMode(g.rim:GetBlendMode() == "ADD" and "BLEND" or "ADD") end
        end
        say("rim blend " .. (P.glass.rim and P.glass.rim:GetBlendMode() or "?"))
    elseif cmd == "snap" then
        local on = arg ~= "off"
        for _, t in ipairs(allTextures) do
            t:SetSnapToPixelGrid(on)
            t:SetTexelSnappingBias(on and 1 or 0)
        end
        say("pixel snapping " .. (on and "on" or "off"))
    elseif cmd == "scale" then
        local v = tonumber(arg)
        if v and v > 0.2 and v < 4 then P.root:SetScale(v); say("scale " .. v) end
    elseif cmd == "tint" then
        local v = tonumber(arg)
        for _, g in ipairs({ P.glass, P.tileGlass }) do
            if v and g.tint then g.tint:SetColorTexture(0.05, 0.07, 0.11, v) end
        end
    elseif cmd == "portrait" then
        if arg == "2d" or arg == "3d" then
            local use2d = arg == "2d"
            if P.model then P.model:SetShown(not use2d) end
            if P.portrait2d then P.portrait2d:SetShown(use2d) end
        end
        try("portrait refresh", refreshPortrait)
        say("portrait " .. (arg ~= "" and arg or "refreshed"))
    elseif cmd == "style" then
        if try("style " .. arg, applyStyle, tonumber(arg)) and currentStyle == tonumber(arg) then
            say("style " .. arg)
        else
            say("style 1|2|3|4  (1 first cut, 2 thin rim, 3 thick bevel, 4 polished bevel)")
        end
    elseif cmd == "font" then
        if try("font " .. arg, setFont, arg) and currentFont == arg then
            say("font " .. arg .. " (" .. tostring(P.fonts and P.fonts[1].fs:GetFont()) .. ")")
        else
            say("font arial|friz")
        end
    elseif cmd == "newfile" then
        if not P.late then
            P.late = P.root:CreateTexture(nil, "OVERLAY")
            P.late:SetSize(24, 24)
            P.late:SetPoint("BOTTOMLEFT", P.root, "TOPLEFT", 0, 6)
        end
        local ok = P.late:SetTexture(MEDIA .. "late")
        P.late:SetVertexColor(1, 0.2, 0.8)
        say("late.tga SetTexture returned " .. tostring(ok) .. " - a pink square above the frame means it loaded")
    elseif cmd == "show" then
        showProbe()
    elseif cmd == "hide" then
        if sheenLoop then sheenLoop:Cancel(); sheenLoop = nil; say("sheen loop off") end
        P.root:Hide()
    elseif cmd == "report" then
        report()
    elseif cmd == "reset" then
        P.root:SetScale(1)
        P.root:ClearAllPoints()
        P.root:SetPoint("CENTER", UIParent, "CENTER", 40, -140)
    else
        for _, line in ipairs(HELP) do say("/gprobe " .. line) end
    end
end

SLASH_GLASSPROBE1 = "/gprobe"
SlashCmdList.GLASSPROBE = slash

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then
        refreshPortrait()
        return
    end
    try("build", build)
    if P.root then
        try("style 4", applyStyle, 4)
        try("initial fill", setFill, 0.8, true)
    end
    try("portrait events", function()
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
        self:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player")
    end)
    C_Timer.After(1, function() try("portrait delayed refresh", refreshPortrait) end)
    local bad = 0
    for _, s in ipairs(steps) do if not s.ok then bad = bad + 1 end end
    if P.root then
        say(string.format("%d steps, %d failed. Hidden: /gprobe show  (all commands: /gprobe help)", #steps, bad))
    else
        say(string.format("%d steps, %d failed: the probe did not build. /gprobe help", #steps, bad))
    end
end)
