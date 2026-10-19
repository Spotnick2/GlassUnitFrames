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

--------------------------------------------------------------------------------
-- The real layout (#132's last checks, GRF#69): Glass Raid Frames' own
-- centred layout, a reload (GRF loads first, by name, and announces again
-- once UIParent has its real size: the late-announcement path a GUF-first
-- load would take), GRF absent, and a reload in combat.
--------------------------------------------------------------------------------

-- Was this load a /reload mid-fight? The lockdown is OFF while addons load
-- even then (run #278, 70450), so it can't say. A fight that ends after the
-- load can; UnitAffectingCombat at load is logged to measure it as a signal.
local lockdownAtLoad = InCombatLockdown()
local okC, inFight = pcall(UnitAffectingCombat, "player")
local fightAtLoad = okC and inFight == true
local foughtAfterLoad = false               -- PLAYER_REGEN_ENABLED came since
local blocked = {}                          -- protected calls refused this session

-- Where GUF's frames are against GRF's state: the player's right edge 24 left
-- of the union, the target's left edge 24 right of it (within a unit).
local function verify()
    local G, R = GUF(), rawget(_G, "GlassRaidFrames")
    if not (G and G.Link) then return false, "no GlassUnitFrames link" end
    if not (R and type(R.LayoutState) == "function") then return false, "no GlassRaidFrames.LayoutState" end
    local ok, s = pcall(R.LayoutState)
    if not ok or type(s) ~= "table" then return false, "no GRF state yet" end
    if s.mode ~= "hud" then return false, "GRF's mode is " .. tostring(s.mode) .. ", not hud" end
    if not G.Link.Placing() then return false, "GUF isn't placing" end
    local by = G.Frames.byUnit
    local pr = by.player and by.player:GetRight()
    local tl = by.target and by.target:GetLeft()
    local want = s.l - 24
    if type(pr) ~= "number" or math.abs(pr - want) > 1 then
        return false, string.format("player right %s, want %.1f", tostring(pr), want)
    end
    local d = string.format("player right %.1f (want %.1f)", pr, want)
    if type(tl) == "number" then
        local wantT = s.l + s.w + 24
        if math.abs(tl - wantT) > 1 then return false, string.format("target left %.1f, want %.1f", tl, wantT) end
        d = d .. string.format(", target left %.1f (want %.1f)", tl, wantT)
    end
    return true, d
end

local function noTrouble()
    local G = GUF()
    local failures = 0
    for _ in pairs(G and G.paintFailures or {}) do failures = failures + 1 end
    return #blocked == 0 and failures == 0, string.format("%d blocked, %d paint failures", #blocked, failures)
end

Probe:Steps("real", {
    rev = 2,
    title = "Group layout: Glass Raid Frames' real layout",
    { text = "Make Glass Raid Frames show its centred layout: the healer role, or its HUD switch on for your role, with a party or its solo grid shown. This step goes on by itself once GlassUnitFrames places your frames beside it.",
      wait = function() return verify() end, timeout = 600, screenshot = "real hud" },
    { text = "Are your frame and the target's beside the grid, at their usual height, with the cast bars above the grid?", ask = true },
    { text = "Reload. Glass Raid Frames loads first and announces again once the screen has its real size: the path GlassUnitFrames takes when it loads first.", reload = true },
    { text = "Waiting for the frames to be placed again.", wait = function() return verify() end, timeout = 90,
      check = function() return verify() end, screenshot = "after reload" },
    { text = "Did they appear in place as the loading screen lifted, with no glide?", ask = true },
    { text = "Turn Glass Raid Frames off in the AddOns list (Game Menu > AddOns), then reload.", reload = true },
    { text = "Checking your frames without Glass Raid Frames.", auto = true,
      run = function()
          local L = GUF().Link
          return rawget(_G, "GlassRaidFrames") == nil and not L.Placing(), "GRF loaded: " .. tostring(rawget(_G, "GlassRaidFrames") ~= nil) .. "; link " .. L.Status()
      end,
      check = function()
          local L = GUF().Link
          local ok, d = noTrouble()
          return rawget(_G, "GlassRaidFrames") == nil and not L.Placing() and ok, d
      end,
      screenshot = "no GRF" },
    { text = "Are your frames where you had them before the group layout, with no error?", ask = true },
    { text = "Turn Glass Raid Frames back on in the AddOns list, then reload.", reload = true },
    { text = "Waiting for the frames to be placed beside its layout again.", wait = function() return verify() end, timeout = 90 },
    { text = "Start a fight (attack a mob), and while you're in combat type /reload.", reload = true },
    { text = "Finish the fight. This step goes on by itself once you're out of combat and the frames are placed.",
      wait = function()
          if InCombatLockdown() then return false, "in combat" end
          return verify()
      end, timeout = 600,
      check = function()
          local ok, d = verify()
          local fine, t = noTrouble()
          return ok and fine and foughtAfterLoad, string.format("%s; %s; the fight went on after the load: %s "
              .. "(lockdown at load %s, in a fight at load %s)", d, t, tostring(foughtAfterLoad),
              tostring(lockdownAtLoad), tostring(fightAtLoad))
      end,
      screenshot = "after combat reload" },
    { text = "Did your frames come back (when the fight ended at the latest) beside the grid, with no error on screen?", ask = true },
    { text = "Reloading saves the answers.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_REGEN_ENABLED" })
boot:SetScript("OnEvent", function(_, event, name, fn)
    if event == "PLAYER_REGEN_ENABLED" then foughtAfterLoad = true; return end
    if event ~= "ADDON_LOADED" then
        blocked[#blocked + 1] = event
        say(string.format("%s: %s %s", event, tostring(name), tostring(fn)))
        return
    end
    if name ~= ADDON then return end
    Probe:Ready()
    if type(rawget(_G, "LayoutProbeDB")) ~= "table" then LayoutProbeDB = {} end
    if type(LayoutProbeDB.log) ~= "table" then LayoutProbeDB.log = {} end
    Probe:UseLog(LayoutProbeDB.log, LOG_MAX)
    say(string.format("loaded (lockdown %s, in a fight %s). /fp steps layout glide | real (or /fp layout hud|wide|off|state)",
        tostring(lockdownAtLoad), tostring(fightAtLoad)))
end)

NS._test = { Probe = Probe, state = state, announce = announce, describe = describe, fakePet = fakePet, fakeStance = fakeStance,
             verify = verify, noTrouble = noTrouble, blocked = blocked }
