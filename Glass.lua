-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Its contract, write-up and textures are
-- there: material changes are LibGlass PRs, not edits here.
--
-- An instance, not the library itself: STYLE, the live setters and the font
-- registry are this addon's own, so /glass rim never touches another glass
-- addon's surfaces. Every call site keeps the dot-call shape (Glass.Apply,
-- Glass.Bar, Glass.MEDIA, ...).

--
-- The look (#102): LibGlass r6's presets are construction settings, and the
-- saved choice is only readable at ADDON_LOADED, after every file has taken its
-- `local Glass = GlassUF.Glass`. So GlassUF.Glass forwards to the instance in
-- use, picked once by GlassUF.UseLook before anything is built; switching
-- needs /reload. The instance's functions are closures bound to it, so a
-- forwarded Glass.Apply(...) is that instance's own.

GlassUF = GlassUF or {}
local lib = LibStub("LibGlass-1.0")
local current = lib:New()   -- until ADDON_LOADED's UseLook
-- The looks are LibGlass presets. Pearl is the default (owner, #129: not
-- saved, so a profile that never chose one moves to it); a saved Clean or
-- Classic keeps it. Pearl needs LibGlass r11: with an older copy winning, the
-- look falls back to Clean and GlassUF.lookFallback says why.
GlassUF.LOOKS = { pearl = true, clean = true, classic = true }
GlassUF.DEFAULT_LOOK = "pearl"
GlassUF.PEARL_MINOR = 11     -- LibGlass r11 brought preset = "pearl"
GlassUF.look = "classic"
GlassUF.lookFallback = nil
-- The glass body (#101): clear is LibGlass's own default (tint alpha 0.24,
-- its notes' "clear"); smoked takes the middle of the 0.50-0.80 its notes
-- explored for smoked reading surfaces.
GlassUF.BODIES = { clear = true, smoked = true }
GlassUF.SMOKED = 0.65
GlassUF.body = "clear"
GlassUF.Glass = setmetatable({}, {
    __index = function(_, k) return current[k] end,
    __newindex = function(_, k, v) current[k] = v end,
})

-- Before the build only (ADDON_LOADED): surfaces built earlier keep their
-- look. `look` is a LOOKS name (anything else: the default); `body` is
-- "smoked" or anything else (clear).
function GlassUF.UseLook(look, body)
    if not GlassUF.LOOKS[look] then look = GlassUF.DEFAULT_LOOK end
    local opts = {}
    if body == "smoked" then opts.bodyAlpha = GlassUF.SMOKED end
    if look == "pearl" then
        local _, minor = LibStub:GetLibrary("LibGlass-1.0", true)
        local ok, inst
        if type(minor) == "number" and minor >= GlassUF.PEARL_MINOR then
            opts.preset = "pearl"
            ok, inst = pcall(lib.New, lib, opts)
        end
        if ok then
            current = inst
        else
            GlassUF.lookFallback = "Pearl needs LibGlass r11 or newer: Clean in use"
            look = "clean"
        end
    end
    if look ~= "pearl" then
        -- r6-r10 refuse "classic": an omitted preset is classic on every copy.
        opts.preset = look ~= "classic" and look or nil
        current = lib:New(opts)
    end
    GlassUF.look = look
    GlassUF.body = opts.bodyAlpha and "smoked" or "clear"
end

-- The suite theme (#129, Glass UI's docs/SUITE.md, API 1). When the player
-- turns Follow on in Glass UI, its Theme answer says "pearl" and this
-- addon builds LibGlass's Pearl preset instead of its own look; its look,
-- body, tunables and ramp are then suspended (refused, never written) but
-- stay saved. Decided once, at ADDON_LOADED, before anything is built.
GlassUF.following = nil      -- "pearl" while this session built the suite theme
GlassUF.suiteFailure = nil   -- why Pearl was asked for and not built

-- Glass UI's Suite table, or nil: anything but API 1 exactly counts as absent
-- (the released Glass UI has no Suite at all).
local function suite()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil end
    local S = rawget(G, "Suite")
    if type(S) ~= "table" or rawget(S, "API") ~= 1 then return nil end
    if type(rawget(S, "Theme")) ~= "function" or type(rawget(S, "Report")) ~= "function" then return nil end
    return S
end

-- The answer's preset, read under pcall: a junk answer can't throw at us.
local function presetOf(answer)
    if type(answer) ~= "table" then return nil end
    local ok, preset = pcall(function() return answer.preset end)
    return ok and preset == "pearl" and preset or nil
end

-- Ask Glass UI and, when told Pearl, build it. Returns the Suite table (nil
-- when Glass UI doesn't speak the API) and LibGlass's MINOR at the attempt.
-- Afterwards GlassUF.following or GlassUF.suiteFailure says what happened.
function GlassUF.UseSuite(addon)
    local S = suite()
    if not S then return nil end
    local ok, answer = pcall(S.Theme, addon)
    local preset = ok and presetOf(answer) or nil
    local _, minor = LibStub:GetLibrary("LibGlass-1.0", true)
    if not preset then return S, minor end
    if type(minor) ~= "number" or minor < GlassUF.PEARL_MINOR then
        GlassUF.suiteFailure = "library-too-old"
        return S, minor
    end
    local built, inst = pcall(lib.New, lib, { preset = preset })
    if not built then
        GlassUF.suiteFailure = "build-failed"
        return S, minor
    end
    current = inst
    GlassUF.following = preset
    return S, minor
end

-- Glass UI's settings page, when its Suite has Open (an addition to API 1,
-- GlassUI bcbd20f): for the "Set in Glass UI" button under the suspended look.
function GlassUF.CanOpenSuite()
    local S = suite()
    return S ~= nil and type(rawget(S, "Open")) == "function"
end
function GlassUF.OpenSuite()
    if not GlassUF.CanOpenSuite() then return false end
    local ok, opened = pcall(rawget(suite(), "Open"))
    return ok and opened == true
end

-- What the player reads while the suite theme owns the look, or after it failed.
function GlassUF.SuiteStatus()
    if GlassUF.following then return "Look: following Glass UI (Pearl), set in Glass UI" end
    if GlassUF.suiteFailure then return "own look: " .. GlassUF.suiteFailure end
    return GlassUF.lookFallback
end
