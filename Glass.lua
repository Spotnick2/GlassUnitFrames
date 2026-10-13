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
local current = lib:New()   -- classic, the default
GlassUF.LOOKS = { classic = true, clean = true }
GlassUF.look = "classic"
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
-- look. `body` is "smoked" or anything else (clear).
function GlassUF.UseLook(look, body)
    local opts = {}
    if look == "clean" then opts.preset = "clean" end
    if body == "smoked" then opts.bodyAlpha = GlassUF.SMOKED end
    if next(opts) == nil then return end
    current = lib:New(opts)
    GlassUF.look = opts.preset or "classic"
    GlassUF.body = opts.bodyAlpha and "smoked" or "clear"
end
