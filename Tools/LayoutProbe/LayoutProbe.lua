-- LayoutProbe: M5 of the group layout plan (#132, GlassUI's
-- docs/GROUP-LAYOUT.md): does GlassUnitFrames' glide, when the group layout
-- moves its player and target, read like the combat zoom's? Glass Raid Frames
-- doesn't announce its new layout yet (GRF#69), so this probe announces a
-- fake one, through the real event (GlassRaidFrames.LayoutChanged on
-- EventRegistry), and outlines where its grid would be.
--
-- Throwaway, never shipped (.pkgmeta ignores Tools). A ForeverProbe module:
-- its lines go to the /fp console and its own saved log, never to chat.

local ADDON, NS = ...
local LOG_MAX = 2000
local EVENT = "GlassRaidFrames.LayoutChanged"

local Probe = ForeverProbe:Module("LayoutProbe", { api = 1, cmd = "layout" })
local function say(msg) Probe:Say(msg) end

local function GUF() return rawget(_G, "GlassUF") end

-- A party-sized union centred on the screen: the plan's baseline at 152/1080
-- of UIParent's height, the grid's bottom 68 above it, 60 high; `widen` makes
-- it wider (a raid's columns): the frames move apart, at their own height
-- (the link is horizontal only, GlassUI#32).
local W, H = 500, 60
local function state(widen, mode)
    local base = UIParent:GetHeight() * 152 / 1080
    local w = W + (widen or 0)
    local l = UIParent:GetWidth() / 2 - w / 2
    local b = base + 68
    return { role = "healer", l = l, b = b, w = w, h = H, top = b + H, base = base, mode = mode or "hud" }
end

local outline
local function showOutline(s)
    if not outline then
        outline = CreateFrame("Frame", nil, UIParent)
        outline:SetFrameStrata("BACKGROUND")
        local t = outline:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints(outline)
        t:SetColorTexture(1, 0.82, 0, 0.18)
    end
    outline:ClearAllPoints()
    if not s or s.mode ~= "hud" then outline:Hide(); return end
    outline:SetSize(s.w, s.h)
    outline:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.l, s.b)
    outline:Show()
end

-- What GlassUnitFrames did with it: the link's status, the player's centre,
-- and how many visuals glide.
local function describe()
    local G = GUF()
    local L = G and G.Link
    if not L then return "GlassUnitFrames has no group layout link (an older copy?)" end
    local n = 0
    for _ in pairs(L._test and L._test.glides or {}) do n = n + 1 end
    local pl = G.Frames.byUnit.player
    local x, y
    if pl then x, y = pl:GetCenter() end
    return string.format("link %s; player centre %s, %s; %d visuals gliding", L.Status(),
        x and string.format("%.1f", x) or "?", y and string.format("%.1f", y) or "?", n)
end

local function announce(s)
    if InCombatLockdown() then return false, "in combat: GRF never announces in combat; try again after" end
    local reg = rawget(_G, "EventRegistry")
    if not (reg and reg.TriggerEvent) then return false, "no EventRegistry" end
    reg:TriggerEvent(EVENT, s.role, s.l, s.b, s.w, s.h, s.top, s.base, s.mode)
    showOutline(s)
    local d = describe()
    say(string.format("%s at l %.0f b %.0f top %.0f base %.0f: %s", s.mode, s.l, s.b, s.top, s.base, d))
    return true, d
end

Probe:Command("hud", function() announce(state(0)) end, "announce a fake centred layout (healer)")
Probe:Command("wide", function() announce(state(240)) end, "the same, 240 wider (watch the glide)")
Probe:Command("off", function() announce(state(0, "legacy")) end, "GRF's layout off: GlassUnitFrames lets go")
-- GlassUnitFrames' own announcement (the plan's section 5b), faked for
-- GlassActionBars' stance and pet bars: the real frames' rects, made-up moves.
-- "pet <dx>" moves both (the pet rides the player), "stance <dx>" the player
-- only (a pet saved on the screen); "off" sends GlassUnitFrames' real state.
local OUT = "GlassUnitFrames.LayoutChanged"
local function fake(arg, petRides)
    local G = GUF()
    if not (G and G.LayoutState) then say("GlassUnitFrames has no LayoutState (an older copy?)"); return end
    if InCombatLockdown() then say("in combat: GlassUnitFrames never announces in combat"); return end
    local s = G.LayoutState()
    if not s then say("GlassUnitFrames hasn't built yet"); return end
    local dx = tonumber(arg)
    local linked, petDx = s.linked, nil
    if arg ~= "off" then
        if not dx then say("pet|stance <dx>|off  (e.g. /fp layout pet -150)"); return end
        linked, petDx = dx ~= 0, petRides and dx or 0
    else
        dx, petDx = s.dx, s.petDx
    end
    local p, q = s.player or {}, s.pet or {}
    EventRegistry:TriggerEvent(OUT, linked, p.l, p.b, p.w, p.h, q.l, q.b, q.w, q.h, dx, petDx)
    say(string.format("%s %s, dx %g, petDx %g%s", OUT, linked and "linked" or "not linked", dx, petDx,
        arg == "off" and " (GlassUnitFrames' real state)" or " (fake)"))
end
local function fakePet(arg) fake(arg, true) end
local function fakeStance(arg) fake(arg, false) end

Probe:Command("state", function() say(describe()) end, "what GlassUnitFrames is doing")
Probe:Command("pet", fakePet, "pet <dx>|off: fake GlassUnitFrames moving player and pet by dx (GlassActionBars' bars)")
Probe:Command("stance", fakeStance, "stance <dx>|off: fake it moving the player only (the pet saved on the screen)")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

local function gliding()
    local L = GUF() and GUF().Link
    return L and L._test and next(L._test.glides) ~= nil
end

Probe:Steps("glide", {
    rev = 4,
    title = "M5: the group layout's glide",
    -- Two runs had no target: only the player's frame was seen gliding.
    { text = "Out of combat, select a target (any NPC), and on a hunter have your pet out. This step goes on by itself once something is targeted.",
      wait = function()
          if UnitExists("target") then return true, "a target selected" end
          return false, "no target yet"
      end, timeout = 300 },
    { text = "A fake centred layout: the yellow box is where its grid would be. Stopping early? /fp layout off (or /reload) gives your frames their own positions back.", auto = true,
      run = function() return announce(state(0)) end,
      check = function() local L = GUF().Link; return L.Placing() and UnitExists("target"), describe() end,
      screenshot = "placed" },
    { text = "Press Run: the grid gets 240 wider. Watch your frame, your target's, the pet, the target of target and the cast bars move apart, at their own height.", button = "Run",
      run = function()
          local ok, d = announce(state(240))
          return ok and gliding(), d
      end },
    { text = "Press Run again: narrower. Run it a few times, and once while it's still moving.", button = "Run",
      run = function()
          local ok, d = announce(state(0))
          return ok and gliding(), d
      end },
    { text = "Does it glide like the combat zoom (smooth, about a third of a second, slowing at the end)?", ask = true },
    { text = "Did anything jump or lag behind: the raid mark, the combat timer, pet happiness, the target's auras, the portrait?", ask = true },
    { text = "Is anything covered now (the chat, a bar, another frame)?", ask = true, screenshot = "placed, wide" },
    { text = "Press Run: the layout goes away and the frames glide back to your own positions.", button = "Run",
      run = function() return announce(state(0, "legacy")) end,
      check = function() return not GUF().Link.Placing(), describe() end,
      screenshot = "home" },
    { text = "Are they exactly where they were before the probe?", ask = true },
    { text = "Reloading saves the answers.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    if type(rawget(_G, "LayoutProbeDB")) ~= "table" then LayoutProbeDB = {} end
    if type(LayoutProbeDB.log) ~= "table" then LayoutProbeDB.log = {} end
    Probe:UseLog(LayoutProbeDB.log, LOG_MAX)
    say("loaded. /fp steps layout glide (or /fp layout hud|wide|off|state)")
end)

NS._test = { Probe = Probe, state = state, announce = announce, describe = describe, fakePet = fakePet, fakeStance = fakeStance }
