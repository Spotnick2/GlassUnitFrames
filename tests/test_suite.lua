-- Following Glass UI (#129, Glass UI's docs/SUITE.md, API 1): when Glass UI's
-- Theme says "pearl", the instance is LibGlass's Pearl preset and the local
-- look (look, body, knobs, ramp) is suspended but kept. Anything else, or a
-- failed build, is the local look exactly as before, saved keys untouched.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ADDON = "GlassUnitFrames"
local MAJOR = "LibGlass-1.0"

-- A saved appearance far from every default: the clean look, a smoked body,
-- the ramp at the fill's edge and two non-default knobs.
local function savedLook()
    return { look = "clean", glassBody = "smoked", trackRamp = "edge", rim = 0.55, fill = 0.4, font = "friz" }
end
local LOOK_KEYS = { "look", "glassBody", "trackRamp", "rim", "fill", "track", "fade", "edge" }
local function untouched(db, want, what)
    for _, k in ipairs(LOOK_KEYS) do eq(db[k], want[k], what .. ": saved " .. k .. " untouched") end
end

-- Glass UI's Suite, recording what it was asked and told.
local calls
local function glassUI(theme, suiteFields)
    calls = { theme = {}, reports = {} }
    local S = { API = 1,
                Theme = function(addon) calls.theme[#calls.theme + 1] = addon return theme(addon) end,
                Report = function(addon, state) calls.reports[#calls.reports + 1] = { addon = addon, state = state } end }
    for k, v in pairs(suiteFields or {}) do S[k] = v end
    rawset(_G, "GlassUI", { Suite = S })
end
local function pearl() return { name = "pearl", preset = "pearl" } end
local function notFollowing() return nil, "not-following" end

-- The pinned LibGlass (r11) builds the real Pearl. For the failures, a copy
-- of any MINOR: a New that builds Pearl as the clean preset, throws, or (below
-- r11) refuses it the way r6-r10 do. `asked` counts the pearl requests. Undone by
-- restoreLib, so each case starts from the checkout's own copy.
local realNew, realMinor, realReady
local asked = 0
local function fakeLib(minor, throws)
    return function()
        local lib = LibStub(MAJOR)
        realNew, realMinor, realReady = realNew or lib.New, realMinor or LibStub.minors[MAJOR], realReady or lib.ready
        LibStub.minors[MAJOR], lib.ready = minor, minor   -- New refuses a copy whose ready isn't its MINOR
        lib.New = function(self, opts)
            if opts and opts.preset == "pearl" then
                asked = asked + 1
                if minor < 11 then error('LibGlass-1.0: unknown preset pearl (use "clean" or omit it)', 2) end
                if throws then error("LibGlass-1.0: boom") end
                local inst = realNew(self, { preset = "clean" })
                inst.preset = "pearl"
                return inst
            end
            return realNew(self, opts)
        end
    end
end
local function restoreLib()
    if realNew then
        local lib = LibStub(MAJOR)
        lib.New, LibStub.minors[MAJOR], lib.ready = realNew, realMinor, realReady
    end
end

local function load(db, opts)
    WoW.reset()
    standardUnits()
    opts = opts or {}
    opts.db = db
    loadAddon(opts)
end

local function localLook(db, what)
    check(GlassUF.following == nil, what .. ": not following")
    eq(GlassUF.look, "clean", what .. ": the saved look is built")
    eq(GlassUF.body, "smoked", what .. ": and its body")
    eq(GlassUF.Glass.STYLE.rimAlpha, 0.55, what .. ": the saved knob is applied")
    eq(GlassUF.Glass.STYLE.trackLength, GlassUF.RAMP_LENGTH, what .. ": and the saved ramp")
    eq(GlassUF.Glass.fontKey, "friz", what .. ": and the font")
    untouched(db, savedLook(), what)
end

local function lastReport()
    return calls.reports[#calls.reports] and calls.reports[#calls.reports].state
end

--------------------------------------------------------------------------------
-- Glass UI absent, or not speaking API 1: the local look, nothing asked.
--------------------------------------------------------------------------------
rawset(_G, "GlassUI", nil)
local db = savedLook()
load(db)
localLook(db, "no Glass UI")
check(GlassUF.SuiteStatus() == nil, "no Glass UI: nothing to say")

local shapes = {
    ["GlassUI not a table"] = function() rawset(_G, "GlassUI", "yes") end,
    ["no Suite (the released Glass UI)"] = function() rawset(_G, "GlassUI", {}) end,
    ["Suite not a table"] = function() rawset(_G, "GlassUI", { Suite = true }) end,
    ["API 2"] = function() glassUI(pearl, { API = 2 }) end,
    ["API \"1\""] = function() glassUI(pearl, { API = "1" }) end,
    ["no Theme function"] = function() glassUI(pearl, { Theme = "pearl" }) end,
    ["no Report function"] = function() glassUI(pearl, { Report = false }) end,
}
for what, install in pairs(shapes) do
    calls = nil
    install()
    db = savedLook()
    load(db, { beforeLoaded = fakeLib(11) })
    localLook(db, what)
    check(calls == nil or #calls.theme == 0, what .. ": Theme never asked")
    check(calls == nil or #calls.reports == 0, what .. ": nothing reported")
    restoreLib()
end

--------------------------------------------------------------------------------
-- Glass UI speaks the API but doesn't say Pearl: the local look, reported.
--------------------------------------------------------------------------------
local junk = setmetatable({}, { __index = function() error("junk") end })
local answers = {
    ["not-following"] = notFollowing,
    ["not-ready"] = function() return nil, "not-ready" end,
    ["Theme throws"] = function() error("Glass UI broke") end,
    ["a string"] = function() return "pearl" end,
    ["another preset"] = function() return { name = "x", preset = "clean" } end,
    ["a throwing table"] = function() return junk end,
}
for what, theme in pairs(answers) do
    glassUI(theme)
    db = savedLook()
    load(db, { beforeLoaded = fakeLib(11) })
    localLook(db, what)
    eq(calls.theme[1], ADDON, what .. ": asked once, by our name")
    eq(#calls.theme, 1, what .. ": once a session")
    eq(#calls.reports, 1, what .. ": reported")
    local r = lastReport()
    eq(calls.reports[1].addon, ADDON, what .. ": as us")
    eq(r.api, 1, what .. ": api 1")
    eq(r.built, nil, what .. ": built the local look")
    eq(r.reason, nil, what .. ": no reason (never told Pearl)")
    eq(r.minor, 11, what .. ": LibGlass's MINOR")
    eq(type(r.options), "function", what .. ": an options opener")
    restoreLib()
end

--------------------------------------------------------------------------------
-- Told Pearl, but the build can't happen: the local look, the reason reported.
--------------------------------------------------------------------------------
-- An r10 copy winning (no pearl): New is never asked.
glassUI(pearl)
db = savedLook()
asked = 0
load(db, { beforeLoaded = fakeLib(10) })
localLook(db, "LibGlass too old")
eq(asked, 0, "too old: New never asked for pearl")
eq(GlassUF.suiteFailure, "library-too-old", "too old: recorded")
eq(lastReport().built, nil, "too old: reported the local look")
eq(lastReport().reason, "library-too-old", "too old: and why")
eq(lastReport().minor, 10, "too old: with the old MINOR")
eq(GlassUF.SuiteStatus(), "own look: library-too-old", "too old: said")
WoW.chat = {}
SlashCmdList.GLASSUNITFRAMES("look")
check(WoW.chat[#WoW.chat]:find("own look: library-too-old", 1, true) ~= nil, "/glass look says it: " .. WoW.chat[#WoW.chat])
restoreLib()
-- A newer copy arriving after the build changes nothing this session.
fakeLib(11)()
check(GlassUF.following == nil, "newer copy later: still the local look")
eq(asked, 0, "newer copy later: Pearl never asked for")
eq(GlassUF.look, "clean", "newer copy later: the instance is kept")
eq(#calls.reports, 1, "newer copy later: no second report")
check(GlassUF.Settings.SetLook("classic"), "too old: the local look is still ours to set")
eq(db.look, "classic", "and it saves")
restoreLib()

-- r11, but New throws: build-failed.
glassUI(pearl)
db = savedLook()
load(db, { beforeLoaded = fakeLib(11, true) })
localLook(db, "build failed")
eq(GlassUF.suiteFailure, "build-failed", "build failed: recorded")
eq(lastReport().reason, "build-failed", "build failed: reported")
eq(lastReport().minor, 11, "build failed: with r11's MINOR")
restoreLib()

--------------------------------------------------------------------------------
-- Following: Pearl is built, the local look is suspended and kept.
--------------------------------------------------------------------------------
local _, checkoutMinor = LibStub:GetLibrary(MAJOR, true)
check(checkoutMinor >= 11, "the LibGlass checkout has Pearl (r11, the pin): MINOR " .. tostring(checkoutMinor))
glassUI(pearl)
db = savedLook()
load(db)
local Glass = GlassUF.Glass
eq(GlassUF.following, "pearl", "following: Pearl built")
eq(Glass.preset, "pearl", "following: the instance in use is LibGlass's Pearl")
check(Glass.STYLE.rimAlpha ~= 0.55, "following: the saved knob is not applied")
eq(Glass.STYLE.trackLength, 0, "following: nor the saved ramp")
eq(Glass.fontKey, "friz", "following: the font still applies")
untouched(db, savedLook(), "following")
local r = lastReport()
eq(r.built, "pearl", "following: reported Pearl")
eq(r.reason, nil, "following: no reason")
eq(r.minor, checkoutMinor, "following: LibGlass's MINOR")
check(pcall(r.options), "following: the options opener runs")
eq(GlassUF.SuiteStatus(), "Look: following Glass UI (Pearl), set in Glass UI", "following: said")

-- Every write path refuses and writes nothing.
local S = GlassUF.Settings
check(not S.SetLook("classic"), "following: SetLook refused")
check(not S.SetGlassBody("clear"), "following: SetGlassBody refused")
check(not S.SetTrackRamp("whole"), "following: SetTrackRamp refused")
for _, t in ipairs(Glass.TUNABLES) do
    local before = Glass.STYLE[t.style]
    check(not S.SetTunable(t, t.min), "following: SetTunable refused: " .. t.key)
    eq(Glass.STYLE[t.style], before, "following: knob unchanged: " .. t.key)
end
check(not S.ResetLook(), "following: Reset look refused")
eq(Glass.fontKey, "friz", "following: Reset look left the font alone too")
for _, cmd in ipairs({ "look classic", "body clear", "ramp whole", "rim 0.3", "fill 0.9", "track 0.1", "fade 0.5", "edge 0.5" }) do
    WoW.chat = {}
    SlashCmdList.GLASSUNITFRAMES(cmd)
    eq(WoW.chat[#WoW.chat], "|cff7fd4ffGlassUF|r Look: following Glass UI (Pearl), set in Glass UI", "/glass " .. cmd .. ": set in Glass UI")
end
untouched(db, savedLook(), "following, after every write path")
check(S.SetFont("arial"), "following: the font is still ours")
db.font = "friz"

-- The options page says so, with the look controls off.
local O = GlassUF.Options
local panel, controls = O._test.panel, O._test.controls
panel:Show()
eq(controls.suiteNote and controls.suiteNote._text, "Look: following Glass UI (Pearl), set in Glass UI", "options: the note")
for _, name in ipairs({ "look", "glassBody", "trackRamp" }) do
    for _, rb in ipairs(controls[name]) do check(not rb:IsEnabled(), "options: " .. name .. " radio off") end
end
for _, t in ipairs(Glass.TUNABLES) do check(not controls["slider_" .. t.key]:IsEnabled(), "options: slider off: " .. t.key) end
check(not controls.resetLook:IsEnabled(), "options: Reset look off")
untouched(db, savedLook(), "following, after the options page")

-- Then not following: the local look and its keys come back after the reload.
glassUI(notFollowing)
load(db)
localLook(db, "following, then not")
check(GlassUF.Glass.preset ~= "pearl", "following, then not: not Pearl")
O = GlassUF.Options
O._test.panel:Show()
check(O._test.controls.suiteNote == nil, "not following: no note")
check(O._test.controls.look[1]:IsEnabled(), "not following: the look radios work")
rawset(_G, "GlassUI", nil)

-- The TOC asks the client to load Glass UI first when it's enabled.
local deps
for line in io.lines("GlassUnitFrames.toc") do deps = deps or line:match("^## OptionalDeps:%s*(.-)%s*$") end
eq(deps, "GlassUI", "## OptionalDeps: GlassUI")

-- "Set in Glass UI" (GlassUI bcbd20f): a button under the suspended look,
-- only while following and only when the Suite has Open; called under pcall.
local function panelFor(theme, fields)
    glassUI(theme, fields)
    load(savedLook())
    local O = GlassUF.Options._test
    O.panel:Show()
    return O.controls
end
local opened = {}
local c = panelFor(pearl, { Open = function(...) opened[#opened + 1] = select("#", ...) return true end })
check(c.openSuite ~= nil, "following with Open: the button")
eq(c.openSuite._text or c.openSuite.Text and c.openSuite.Text._text, "Set in Glass UI", "its label")
c.openSuite._scripts.OnClick(c.openSuite)
eq(#opened, 1, "a click opens Glass UI")
eq(opened[1], 0, "with no arguments")
check(GlassUF.OpenSuite(), "Open's answer is passed back")
c = panelFor(pearl, { Open = function() error("Glass UI broke") end })
check(pcall(c.openSuite._scripts.OnClick, c.openSuite), "an Open that throws never reaches the button")
check(not GlassUF.OpenSuite(), "and counts as not opened")
c = panelFor(pearl)
check(c.openSuite == nil, "no Open (an older Glass UI): no button")
c = panelFor(notFollowing, { Open = function() return true end })
check(c.openSuite == nil, "not following: no button")
rawset(_G, "GlassUI", nil)

done("test_suite")
