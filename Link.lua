-- GlassUnitFrames: the group layout link (#132; the plan is GlassUI's
-- docs/GROUP-LAYOUT.md, sections 4 and 5, GlassUI#28). While Glass Raid
-- Frames shows its centred layout ("hud"), the player and target frames sit
-- left and right of its grid (horizontally only: they keep their own height,
-- GlassUI#32), and their cast bars above it.
--
-- - GRF announces the layout (GlassRaidFrames.LayoutChanged, never in combat)
--   and answers GlassRaidFrames.LayoutState(): role, l, b, w, h (the grid and
--   its pets), top (the grid's top), base (the baseline), mode. UIParent
--   units from its bottom-left corner.
-- - The places are a session-only override, never saved: db.pos and the cast
--   bars' saves are set aside, kept intact, and back when the link lets go.
-- - Precedence for the cast bars: the combat zoom, then this, then the saves.
-- - Out of combat only; a place refused by combat waits in the one queue.
-- - The move glides (the zoom's technique): the secure buttons snap, their
--   insecure visuals (body, portrait tile) ease from where they were.
-- Without Glass Raid Frames, or with any state but a valid "hud", the frames
-- use their own positions exactly as before.

GlassUF = GlassUF or {}
local API = GlassUF.API

local Link = {}
GlassUF.Link = Link

Link.EVENT = "GlassRaidFrames.LayoutChanged"
Link.OUT_EVENT = "GlassUnitFrames.LayoutChanged"   -- ours (section 5b): GlassActionBars' pet bar follows
Link.NOTE = "placed by the group layout (Glass Raid Frames)"
Link.GAP = 24          -- between a frame and the grid's union
Link.CAST = { player = 73, target = 41 }   -- a cast bar's centre above the grid's top
Link.CAST_W, Link.CAST_H = 360, 22
local DURATION = 0.3

Link.enabled = true    -- db.groupLink ~= false
Link.latest = nil      -- the newest valid state GRF gave
Link.applied = nil     -- the state the frames are placed by (nil: their own positions)
local db

local function finite(v)
    return type(v) == "number" and not API.IsSecret(v) and v == v and v > -math.huge and v < math.huge
end

-- A state we can place by, copied, or nil.
local function valid(role, l, b, w, h, top, base, mode)
    if not (finite(l) and finite(b) and finite(w) and finite(h) and finite(top) and finite(base)) then return nil end
    if w <= 0 or h <= 0 or API.IsSecret(mode) or type(mode) ~= "string" then return nil end
    return { role = (not API.IsSecret(role) and type(role) == "string") and role or nil,
             l = l, b = b, w = w, h = h, top = top, base = base, mode = mode }
end

--------------------------------------------------------------------------------
-- What the link places
--------------------------------------------------------------------------------

local OWNED = { player = true, target = true }

-- Is this frame (or this cast bar) placed by the group layout right now?
function Link.Owns(unit) return Link.applied ~= nil and OWNED[unit] == true end

-- The frame's centre x, from UIParent's left edge, while placed. Only x: its
-- height stays its own (GlassUI#32; Frames' applyPosition keeps the vertical anchor).
function Link.PointOf(unit)
    local s = Link.applied
    if not (s and OWNED[unit]) then return nil end
    local w = GlassUF.Frames.WidthOf(unit)
    if not w then return nil end
    if unit == "player" then return s.l - Link.GAP - w / 2 end
    return s.l + s.w + Link.GAP + w / 2
end

-- A cast bar's place while linked: x, y (CENTER offsets from the screen's
-- centre, as Castbar's geometry), w, h. Detached, scale 1.
function Link.CastOf(unit)
    local s = Link.applied
    if not (s and Link.CAST[unit]) then return nil end
    local ux, uy = UIParent:GetCenter()
    if not (finite(ux) and finite(uy)) then return nil end
    return s.l + s.w / 2 - ux, s.top + Link.CAST[unit] - uy, Link.CAST_W, Link.CAST_H
end

function Link.Placing() return Link.applied ~= nil end

-- Is `unit` carried, through its leaders, by a frame the link places?
function Link.Carried(unit)
    local L = GlassUF.Frames.LAYOUT[unit]
    while L and L.anchorTo do
        if Link.Owns(L.anchorTo) then return true end
        L = GlassUF.Frames.LAYOUT[L.anchorTo]
    end
    return false
end

--------------------------------------------------------------------------------
-- The glide: each moving button's visuals (its body and portrait tile, each
-- anchored by one point to the button) are offset by where they were minus
-- where they land, and the offset eases to zero. The buttons themselves have
-- already snapped: nothing protected ever anchors to a visual.
--------------------------------------------------------------------------------

local controller = CreateFrame("Frame", nil, UIParent)
controller:Hide()
local glides = {}   -- visual -> { b, pt, dx, dy, t }

local function visuals(b)
    local list = { { b.body, b.bodyPoint } }
    if b.tile then list[2] = { b.tile, b.tilePoint } end
    return list
end

-- A region's centre in UIParent units, or nil.
local function centre(r)
    local ok, x, y = pcall(r.GetCenter, r)
    local e, u = r:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (ok and finite(x) and finite(y) and finite(e) and finite(u) and e > 0 and u > 0) then return nil end
    return x * e / u, y * e / u
end

local function offset(v, b, pt, dx, dy)
    v:ClearAllPoints()
    v:SetPoint(pt, b, pt, dx, dy)
end

-- A button's visuals back on it, no glide (any place that isn't the link's).
function Link.Snap(b)
    if not b or not b.body then return end
    for _, v in ipairs(visuals(b)) do
        if glides[v[1]] then
            glides[v[1]] = nil
            offset(v[1], b, v[2], 0, 0)
        end
    end
    if not next(glides) then controller:Hide() end
end

local function ease(k) return 1 - (1 - k) * (1 - k) * (1 - k) end   -- ease-out cubic, as the zoom

controller:SetScript("OnUpdate", function(self, elapsed)
    for v, g in pairs(glides) do
        g.t = g.t + elapsed
        local k = math.min(1, g.t / DURATION)
        local left = 1 - ease(k)
        offset(v, g.b, g.pt, g.dx * left, g.dy * left)
        if k >= 1 then glides[v] = nil end
    end
    if not next(glides) then self:Hide() end
end)

-- Where every shown button's visuals are on screen now (a glide in flight
-- included: a new move retargets from the point on screen).
local function capture()
    local seen = {}
    for _, b in pairs(GlassUF.Frames.byUnit) do
        if b.body and b:IsVisible() then
            for _, v in ipairs(visuals(b)) do
                local x, y = centre(v[1])
                if x then seen[v[1]] = { b = b, pt = v[2], x = x, y = y } end
            end
        end
    end
    return seen
end

-- The buttons have moved: each visual starts from where it was.
local function glideFrom(seen)
    for v, s in pairs(seen) do
        glides[v] = nil
        offset(v, s.b, s.pt, 0, 0)
        local x, y = centre(v)
        local k = UIParent:GetEffectiveScale() / s.b:GetEffectiveScale()
        if x and math.abs(s.x - x) + math.abs(s.y - y) > 0.5 then
            local dx, dy = (s.x - x) * k, (s.y - y) * k
            offset(v, s.b, s.pt, dx, dy)
            glides[v] = { b = s.b, pt = s.pt, dx = dx, dy = dy, t = 0 }
        end
    end
    if next(glides) then controller:Show() end
end

--------------------------------------------------------------------------------
-- Our own announcement (the plan's section 5b, GlassUI#33 and #34): where the
-- player and pet frames are, and how far the link moved each horizontally, so
-- GlassActionBars' stance and pet bars can follow. Out of combat, after every
-- place or unplace; GlassUF.LayoutState() answers the same.
--------------------------------------------------------------------------------

-- A button's rect in UIParent units from its bottom-left: l, b, w, h, or nil.
local function rectOf(b)
    if not b then return nil end
    local ok, l, bt, w, h = pcall(b.GetRect, b)
    local e, u = b:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (ok and finite(l) and finite(bt) and finite(w) and finite(h) and finite(e) and finite(u) and u > 0) then
        return nil
    end
    local k = e / u
    return { l = l * k, b = bt * k, w = w * k, h = h * k }
end

local built = false

-- How far the link moved the player frame horizontally: its linked centre
-- minus its own (0 when not linked: PointOf is nil).
local function playerDX()
    local now, own = Link.PointOf("player"), GlassUF.Frames.OwnCenterX("player")
    if not (now and own) then return 0 end
    return now - own
end

-- The pet's: the player's when it rides it; a pet saved on the screen stays put (0).
local function petDX(dx)
    local Frames = GlassUF.Frames
    if not (Frames.byUnit.pet and Frames.RidesLeader("pet")) then return 0 end
    return dx
end

function GlassUF.LayoutState()
    if not built then return nil end
    local by = GlassUF.Frames.byUnit
    local dx = playerDX()
    return { linked = Link.applied ~= nil, player = rectOf(by.player), pet = rectOf(by.pet), dx = dx, petDx = petDX(dx) }
end

local function announce()
    local reg = rawget(_G, "EventRegistry")
    if not (type(reg) == "table" and type(reg.TriggerEvent) == "function") then return end
    local s = GlassUF.LayoutState()
    if not s then return end
    local p, q = s.player or {}, s.pet or {}
    local ok, err = pcall(reg.TriggerEvent, reg, Link.OUT_EVENT, s.linked, p.l, p.b, p.w, p.h, q.l, q.b, q.w, q.h,
                          s.dx, s.petDx)
    if not ok then API.Fail("link announce", err) end
end
Link._announce = announce

--------------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------------

local snapNext = false   -- the first place after the build snaps (the frames just appeared)

-- Place everything for the current state. Out of combat (the queue's caller).
local function reconcile()
    if not built then return end
    local want = (Link.enabled and Link.latest and Link.latest.mode == "hud") and Link.latest or nil
    local was = Link.applied
    if want == was then return end
    local Frames, Castbar = GlassUF.Frames, GlassUF.Castbar
    local changed = (want ~= nil) ~= (was ~= nil)
    if changed then GlassUF.Movers.CancelDrag() end   -- a frame mid-drag is becoming the layout's, or its own
    local seen = (not snapNext) and capture() or {}
    snapNext = false
    Link.applied = want
    -- The leaders: their followers ride along through their anchors. An
    -- absolute follower save stays where it was saved (the owner's choice).
    for unit in pairs(OWNED) do Frames.ApplyPosition(unit) end
    glideFrom(seen)
    for unit in pairs(Link.CAST) do
        local c = Castbar.bars[unit]
        if c then GlassUF.Zoom.Move(c) end   -- the zoom's own glide: one controller per host
    end
    GlassUF.Movers.SyncBars()   -- a linked cast bar is detached: its (locked) mover appears
    GlassUF.Movers.Refresh()
    announce()
    if changed and GlassUF.ReportSuite then GlassUF.ReportSuite() end
    if changed and GlassUF.Options and GlassUF.Options.Refresh then GlassUF.Options.Refresh() end
end

-- Re-place when combat allows (silent: GRF holds its layout in combat anyway).
local function request(message)
    if not built then return end
    GlassUF.WhenOutOfCombat("link", reconcile, message or false)
end
Link._reconcile = reconcile

-- GRF said where its layout is. Any state but a valid one counts as none.
local function onLayout(_, role, l, b, w, h, top, base, mode)
    Link.latest = valid(role, l, b, w, h, top, base, mode)
    request()
end

local reg = rawget(_G, "EventRegistry")
if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
    local ok, err = pcall(reg.RegisterCallback, reg, Link.EVENT, onLayout, Link)
    if not ok then API.Fail("link subscribe", err) end
end

-- After the (possibly deferred) build: GRF may have announced before we
-- loaded, so its state is read once, under a guard.
function Link.Built()
    built = true
    local G = rawget(_G, "GlassRaidFrames")
    local fn = type(G) == "table" and rawget(G, "LayoutState")
    if type(fn) == "function" then
        local ok, s = pcall(fn)
        if ok and type(s) == "table" then
            local okRead, st = pcall(function() return valid(s.role, s.l, s.b, s.w, s.h, s.top, s.base, s.mode) end)
            Link.latest = okRead and st or nil
        elseif not ok then
            API.Fail("link state", s)
        end
    end
    snapNext = true
    request()
end

-- A placed frame changed width (its portrait shown or hidden; out of combat,
-- the portrait's caller makes sure): it keeps its edge by the grid.
function Link.WidthChanged(unit)
    if not Link.Owns(unit) then return end
    GlassUF.Frames.ApplyPosition(unit)
    announce()   -- the player's width moves the pet's dx too
end

function Link.Configure(saved)
    db = saved
    Link.enabled = db.groupLink ~= false
end

-- The setting (GlassUF.Settings.SetGroupLink saves it). Applied now, or when combat ends.
function Link.SetEnabled(on)
    Link.enabled = on and true or false
    request("the frames move when combat ends")
    return true
end

-- For the Glass UI page (Report) and our own: plain values.
function Link.Status()
    if not Link.enabled then return "off" end
    if Link.applied then return "placing" end
    return "waiting"
end

Link._test = { glides = glides, controller = controller, valid = valid, DURATION = DURATION,
               reset = function() built, snapNext = false, false; Link.latest, Link.applied = nil, nil end }
