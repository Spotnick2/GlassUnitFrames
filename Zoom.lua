-- GlassUnitFrames: combat zoom (#89). During combat a bar (player, target,
-- focus, pet cast bar, or the swing rows) is placed like a detached bar at its
-- zoom spot (x, y, scale), and goes home when combat ends: a 0.3 s ease-out
-- glide of its centre and scale when it is visible, else a snap. Per bar: on
-- by default for the player and target (#141), else off; global, with
-- per-role overrides from a manual per-character role.
--
-- Placement stays with Castbar.Place / the swing rows' place: they ask
-- Zoom.Target(unit) and lay the bar out detached at the spot (an EFFECTIVE
-- detach: the saved one is untouched). Any Place cancels that bar's glide and
-- snaps; a mode change retargets from the point on screen.

GlassUF = GlassUF or {}
local API, Glass = GlassUF.API, GlassUF.Glass

local Zoom = {}
GlassUF.Zoom = Zoom

Zoom.BARS = { "player", "target", "focus", "pet", "swing" }
Zoom.ROLES = { "healer", "tank", "dps" }
local ROLE_OK = { healer = true, tank = true, dps = true }
-- The player's and target's zoom is on by default, at 1.5, at the owner's tested
-- spots: the target's bar just above the player's, the pair clear of the target's
-- ToT row (top at y -203; #141).
Zoom.DEFAULTS = { player = { x = 0, y = -182, on = true, scale = 1.5 },
                  target = { x = 0, y = -152, on = true, scale = 1.5 }, focus = { x = 0, y = -60 },
                  pet = { x = 0, y = -150 }, swing = { x = 0, y = -142 } }
Zoom.SCALE = 1.25
Zoom.LIMITS = { x = { -4096, 4096 }, y = { -4096, 4096 }, scale = { 0.5, 2.5 } }
local DURATION = 0.3

Zoom.combat = false
Zoom.flying = false   -- a flight shows on the player's bar (Flight.lua, #148)
Zoom.role = nil     -- this character's role ("healer", "tank", "dps") or nil: global
local db, guid
local glides = {}   -- unit -> { fx, fy, fs (from), tx, ty, ts (to), t, cx, cy, cs (on screen now) }

local function finite(v)
    return type(v) == "number" and not API.IsSecret(v) and v == v and v > -math.huge and v < math.huge
end
local function inLimits(v, k)
    local lim = Zoom.LIMITS[k]
    return finite(v) and v >= lim[1] and v <= lim[2]
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- The table being used and edited: this character's role, else global.
function Zoom.EditedKey() return Zoom.role or "global" end

local function rawEntry(key, bar)
    local z = db and db.zoom
    local t = type(z) == "table" and z[key]
    local e = type(t) == "table" and t[bar]
    return type(e) == "table" and e or nil
end

-- A bar's settings from one table (nil = the next one down): a whole entry,
-- each field validated, a bad one back to its default.
local function resolve(e, bar)
    local d = Zoom.DEFAULTS[bar] or { x = 0, y = 0 }
    e = e or {}
    local on = d.on == true
    if type(e.on) == "boolean" then on = e.on end
    return { on = on,
             x = inLimits(e.x, "x") and e.x or d.x,
             y = inLimits(e.y, "y") and e.y or d.y,
             scale = inLimits(e.scale, "scale") and e.scale or d.scale or Zoom.SCALE }
end

-- What a bar uses: the role's entry when it has one, else the global one.
function Zoom.Entry(bar)
    local e = (Zoom.role and rawEntry(Zoom.role, bar)) or rawEntry("global", bar)
    return resolve(e, bar)
end

-- The entry to write into. A role's first edit starts from what the bar
-- resolves to globally, so changing the healer's spot never turns its zoom off.
local function editEntry(bar)
    local key = Zoom.EditedKey()
    if type(db.zoom) ~= "table" then db.zoom = {} end
    if type(db.zoom[key]) ~= "table" then db.zoom[key] = {} end
    local t = db.zoom[key]
    if type(t[bar]) ~= "table" then
        if key ~= "global" then
            local g = resolve(rawEntry("global", bar), bar)
            t[bar] = { on = g.on, x = g.x, y = g.y, scale = g.scale }
        else
            t[bar] = {}
        end
    end
    return t[bar]
end

-- Empty global entries and tables go, so the saved table stays sparse. A
-- role's entry never goes: it is used whole, so even an empty one means
-- "this role's own settings", not "fall back to global" (Codex, #90).
local function prune(key, bar)
    if key ~= "global" then return end
    local z = db.zoom
    if type(z) ~= "table" then return end
    local t = z[key]
    if type(t) == "table" and type(t[bar]) == "table" and next(t[bar]) == nil then t[bar] = nil end
    if type(t) == "table" and next(t) == nil then z[key] = nil end
    if next(z) == nil then db.zoom = nil end
end

function Zoom.Enabled(bar) return Zoom.Entry(bar).on end

-- A bar's zoom spot when its zoom is on: x, y, scale, else nil.
function Zoom.Spot(unit)
    if not (db and Zoom.DEFAULTS[unit]) then return nil end
    local e = Zoom.Entry(unit)
    if not e.on then return nil end
    return e.x, e.y, e.scale
end

-- Where a bar goes right now: x, y, scale while in combat (or, for the
-- player's bar, on a flight, #148) with its zoom on, else nil.
function Zoom.Target(unit)
    local on = Zoom.combat or (unit == "player" and Zoom.flying)
    if not (on and db and Zoom.DEFAULTS[unit]) then return nil end
    local e = Zoom.Entry(unit)
    if not e.on then return nil end
    return e.x, e.y, e.scale
end

--------------------------------------------------------------------------------
-- The glide
--------------------------------------------------------------------------------

local controller = CreateFrame("Frame", nil, UIParent)
controller:Hide()

-- A host's centre in UIParent units, offset from UIParent's centre, and its
-- scale; nil when unreadable (no rect, a secret, a non-finite number).
local function rectOf(host)
    local ok, hx, hy = pcall(host.GetCenter, host)
    local ux, uy = UIParent:GetCenter()
    local he, ue, s = host:GetEffectiveScale(), UIParent:GetEffectiveScale(), host:GetScale()
    if not (ok and finite(hx) and finite(hy) and finite(ux) and finite(uy)
            and finite(he) and finite(ue) and finite(s) and he > 0 and ue > 0 and s > 0) then
        return nil
    end
    return hx * he / ue - ux, hy * he / ue - uy, s
end

local function put(host, x, y, s) GlassUF.Castbar.PlaceAt(host, x, y, s) end

-- Any Place stops that bar's glide (an option, a resize, a reset): it snaps.
function Zoom.Cancel(unit)
    glides[unit] = nil
    if not next(glides) then controller:Hide() end
end

local function ease(k) return 1 - (1 - k) * (1 - k) * (1 - k) end   -- ease-out cubic

controller:SetScript("OnUpdate", function(self, elapsed)
    local Castbar = GlassUF.Castbar
    for unit, g in pairs(glides) do
        local c = Castbar.bars[unit]
        g.t = g.t + elapsed
        local k = math.min(1, g.t / DURATION)
        local e = ease(k)
        g.cx, g.cy, g.cs = g.fx + (g.tx - g.fx) * e, g.fy + (g.ty - g.fy) * e, g.fs + (g.ts - g.fs) * e
        if c then put(c.host, g.cx, g.cy, g.cs) end
        if k >= 1 or not c then
            glides[unit] = nil
            if c then Castbar.Place(c) end   -- the exact final anchors
        end
    end
    if not next(glides) then self:Hide() end
end)

-- Does this bar snap rather than glide? A docked row inside the player body
-- (the cast row, the swing rows): their home is the body, not a pill.
local function docksInside(c)
    if c.unit == "swing" then return not GlassUF.Castbar.IsDetached("swing") end
    return c.inside and not GlassUF.Castbar.IsDetached(c.unit)
end

-- Re-place one bar for the current mode, gliding when it can.
local function move(c)
    local Castbar = GlassUF.Castbar
    local g = glides[c.unit]
    local fx, fy, fs
    if g then
        fx, fy, fs = g.cx, g.cy, g.cs   -- retarget from the point on screen
    elseif c.host:IsVisible() then
        fx, fy, fs = rectOf(c.host)
    end
    Castbar.Place(c)   -- the final layout (also cancels the old glide)
    if not fx or docksInside(c) or not c.host:IsVisible() then return end
    local tx, ty, ts = rectOf(c.host)
    if not tx then return end
    put(c.host, fx, fy, fs)
    glides[c.unit] = { fx = fx, fy = fy, fs = fs, tx = tx, ty = ty, ts = ts, t = 0, cx = fx, cy = fy, cs = fs }
    controller:Show()
end

-- The group layout's link (#132) moves the player and target bars through
-- the same glide: one controller writes each host.
Zoom.Move = move

-- A flight started or ended on the player's bar (#148): it zooms like combat.
-- The target's bar moves too: under the group layout both share one lift
-- (Codex, #154).
function Zoom.SetFlying(on)
    on = on and true or false
    if Zoom.flying == on then return end
    Zoom.flying = on
    if Zoom.combat or not Zoom.Entry("player").on then return end
    local Castbar = GlassUF.Castbar
    for _, unit in ipairs({ "player", "target" }) do
        local c = Castbar.bars[unit]
        if c then move(c) end
    end
end

-- Combat started or ended (GUF's combat dispatcher, after Movers.OnCombat).
function Zoom.OnCombat(on)
    on = on and true or false
    if Zoom.combat == on then return end
    Zoom.combat = on
    local Castbar = GlassUF.Castbar
    for _, bar in ipairs(Zoom.BARS) do
        local c = Castbar.bars[bar]
        if c and Zoom.Entry(bar).on then move(c) end
    end
end

-- Re-place a bar now for the current mode (a setting changed): a snap.
local function refresh(bar)
    local c = GlassUF.Castbar.bars[bar]
    -- The player's and target's share the group layout's lift: both (Codex, #143).
    if c then GlassUF.Castbar.PlaceStack(c) end
    if Zoom.ShowProxies and Zoom.proxiesShown then Zoom.ShowProxies(true) end
end

--------------------------------------------------------------------------------
-- Setters (GlassUF.Settings calls these)
--------------------------------------------------------------------------------

function Zoom.SetEnabled(bar, on)
    if not (db and Zoom.DEFAULTS[bar]) then return false end
    -- Global: the bar's default is not saved. A role stores both explicitly.
    on = on and true or false
    if Zoom.EditedKey() == "global" and on == (Zoom.DEFAULTS[bar].on == true) then on = nil end
    editEntry(bar).on = on
    prune(Zoom.EditedKey(), bar)
    refresh(bar)
    return true
end

function Zoom.SetScale(bar, s)
    if not (db and Zoom.DEFAULTS[bar]) or not finite(s) then return false end
    local lim = Zoom.LIMITS.scale
    s = math.max(lim[1], math.min(lim[2], math.floor(s * 20 + 0.5) / 20))
    editEntry(bar).scale = s
    refresh(bar)
    return true, s
end

-- The spot, rounded to 0.5 units.
function Zoom.SetSpot(bar, x, y)
    if not (db and Zoom.DEFAULTS[bar] and inLimits(x, "x") and inLimits(y, "y")) then return false end
    x, y = math.floor(x * 2 + 0.5) / 2, math.floor(y * 2 + 0.5) / 2
    local e = editEntry(bar)
    e.x, e.y = x, y
    refresh(bar)
    return true, x, y
end

-- Back to the default spot and scale (in the table being edited); on stays.
function Zoom.ResetSpot(bar)
    if not (db and Zoom.DEFAULTS[bar]) then return false end
    local t = type(db.zoom) == "table" and db.zoom[Zoom.EditedKey()]
    local e = type(t) == "table" and t[bar]
    if type(e) == "table" then e.x, e.y, e.scale = nil, nil, nil end
    prune(Zoom.EditedKey(), bar)
    refresh(bar)
    return true
end

function Zoom.ResetSpots()
    for _, bar in ipairs(Zoom.BARS) do Zoom.ResetSpot(bar) end
end

-- This character's role (nil = global), saved per GUID.
function Zoom.SetRole(role)
    if role ~= nil and not ROLE_OK[role] then return false end
    if not (db and guid) then return false end
    if type(db.zoomRole) ~= "table" then db.zoomRole = {} end
    db.zoomRole[guid] = role
    if next(db.zoomRole) == nil then db.zoomRole = nil end
    Zoom.role = role
    for _, bar in ipairs(Zoom.BARS) do refresh(bar) end
    return true
end

--------------------------------------------------------------------------------
-- The zoom spots in unlock mode: an outline per enabled bar (a proxy frame the
-- mover sits on), at the spot, its detached size times the zoom scale.
--------------------------------------------------------------------------------

local proxies = {}

local function proxy(bar)
    local p = proxies[bar]
    if p then return p end
    p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("MEDIUM")
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = p:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0, 0.8)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT", p, side .. "LEFT")
            t:SetPoint(side .. "RIGHT", p, side .. "RIGHT")
            t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side, p, "TOP" .. side)
            t:SetPoint("BOTTOM" .. side, p, "BOTTOM" .. side)
            t:SetWidth(1)
        end
    end
    p:Hide()
    proxies[bar] = p
    return p
end

local function placeProxy(bar)
    local p = proxy(bar)
    local e = Zoom.Entry(bar)
    local _, _, w, h = GlassUF.Castbar.HomeGeometry(bar)
    -- The group layout's lift, as it will be in combat (#142).
    local dy = GlassUF.Link.CAST[bar] and GlassUF.Castbar.Lift(true) or 0
    if bar == "swing" then   -- the unlocked pill: every row, as Swing's sample shows it
        h = 3 * h + 2 * GlassUF.Swing.DETACHED_GAP + 2 * Glass.Inset("small")
    end
    p:SetSize(w, h)
    put(p, e.x, e.y + dy, e.scale)
end

-- A bar was placed (a resize, a reset): its outline, when shown, follows.
function Zoom.Placed(bar)
    local p = proxies[bar]
    if p and p:IsShown() then placeProxy(bar) end
end

Zoom.proxiesShown = false
function Zoom.ShowProxies(on)
    Zoom.proxiesShown = on and true or false
    for _, bar in ipairs(Zoom.BARS) do
        local show = Zoom.proxiesShown and GlassUF.Castbar.bars[bar] ~= nil and Zoom.Enabled(bar)
        if show then placeProxy(bar) end
        if proxies[bar] or show then proxy(bar):SetShown(show) end
    end
end

local LABELS = { player = "Player cast bar (combat)", target = "Target cast bar (combat)",
                 focus = "Focus cast bar (combat)", pet = "Pet cast bar (combat)", swing = "Swing timer (combat)" }

-- The unlock-mode source for a zoom spot (Movers.lua's source contract).
function Zoom.MoverSource(bar)
    return {
        id = "zoom:" .. bar, label = LABELS[bar],
        frame = function() return proxy(bar) end,
        rel = function() return "UIParent", UIParent end,
        -- Where the outline shows (the lift included); a drop takes the
        -- partner's lift off, as a detached bar's does (Codex, #143).
        position = function()
            local e = Zoom.Entry(bar)
            return e.x, e.y + (GlassUF.Link.CAST[bar] and GlassUF.Castbar.Lift(true) or 0)
        end,
        set = function(x, y, live)
            if not live then
                local d = GlassUF.Castbar.PartnerLift(bar, true)
                local ok, ax, ay = Zoom.SetSpot(bar, x, y - d)   -- saved, then placed by refresh
                if not ok then return false end
                return true, ax, ay + d
            end
            if not (inLimits(x, "x") and inLimits(y, "y")) then return false end
            x, y = math.floor(x * 2 + 0.5) / 2, math.floor(y * 2 + 0.5) / 2
            put(proxy(bar), x, y, Zoom.Entry(bar).scale)
            return true, x, y
        end,
        save = function(x, y) return Zoom.SetSpot(bar, x, y - GlassUF.Castbar.PartnerLift(bar, true)) end,
        reset = function() return Zoom.ResetSpot(bar) end,
        follows = function() return false end,
        scale = function() return Zoom.Entry(bar).scale end,
        setScale = function(s) return Zoom.SetScale(bar, s) end,
    }
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local readRole

-- Called by Frames.Build (ADDON_LOADED, or later when the build was deferred
-- past PLAYER_LOGIN by combat): the role is read here too.
function Zoom.Configure(saved)
    db = saved
    readRole()
end

function readRole()
    local ok, g = pcall(UnitGUID, "player")
    if not ok or API.IsSecret(g) or type(g) ~= "string" or g == "" then return end
    guid = g
    if not db then return end   -- the settings arrive with Configure, which reads again
    local roles = db.zoomRole
    local r = type(roles) == "table" and roles[guid] or nil
    Zoom.role = ROLE_OK[r] and r or nil
end

local ev = CreateFrame("Frame")
API.RegisterEvents(ev, { "PLAYER_LOGIN" })
ev:SetScript("OnEvent", function()
    readRole()
    if Zoom.role then
        for _, bar in ipairs(Zoom.BARS) do refresh(bar) end
    end
end)

Zoom._test = { glides = glides, controller = controller, proxies = proxies, rectOf = rectOf, readRole = readRole,
               DURATION = DURATION }
