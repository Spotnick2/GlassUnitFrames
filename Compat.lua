-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassUF.API. Nothing is injected into _G.

GlassUF = GlassUF or {}
local API = {}
GlassUF.API = API

-- The build the notes in docs/FOREVER-PROBE.md were measured on. Bump only
-- after re-measuring in game; tests/test_toc.lua pins the same literal.
GlassUF.MEASURED_ON_BUILD = "1.60.1.70338"

function API.Print(msg)
    print("|cff7fd4ffGlassUF|r " .. msg)
end

-- True for a Retail secret value. Such a value may be handed back to the
-- client (StatusBar, SetFormattedText, SetText) but never compared, added,
-- concatenated, tostring'd or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- A development copy: deploy.ps1 stamps "dev", a checkout run as-is still
-- carries the packager's keyword, and an unreadable version counts as dev. A
-- packaged release carries its tag. The keyword is assembled, never written
-- out: the packager replaces it in every file it ships, so a literal here
-- would make a release count itself as dev (AltStable shipped that bug).
local VERSION_KEYWORD = "@" .. "project-version" .. "@"

function API.IsDevBuild()
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, "GlassUnitFrames", "Version")
    if not ok or type(v) ~= "string" or v == "" then return true end
    return v == "dev" or v:sub(1, 4) == "dev-" or v == VERSION_KEYWORD
end

-- RegisterEvent/RegisterUnitEvent throw on an unknown name and return false
-- on a refusal. Both count as failure, and every failure is reported: a
-- silently missing handler is the bug this exists to prevent.
GlassUF.eventFailures = {}

local function report(name, why)
    table.insert(GlassUF.eventFailures, name .. ": " .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
end

function API.RegisterEvents(frame, events)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterEvent, frame, name)
        if not ok then report(name, tostring(registered))
        elseif registered == false then report(name, "refused") end
    end
end

function API.RegisterUnitEvents(frame, events, unit)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterUnitEvent, frame, name, unit)
        if not ok then report(name .. "/" .. unit, tostring(registered))
        elseif registered == false then report(name .. "/" .. unit, "refused") end
    end
end

-- Unit buttons register the UP edge only ("AnyUp"), as SUF and DinoUF (which
-- ships on this client) do. The porting guide's both-edges rule was measured
-- on SecureActionButtonTemplate, whose handler picks one edge; the
-- SecureUnitButtonTemplate handler dispatches on every registered edge, so
-- both edges could open the menu on press and toggle it shut on release.
-- Never set "typerelease" either.
function API.UnitButtonClicks()
    return "AnyUp"
end

-- 0..1 fraction -> 0..100, evaluated by the client so a secret health value
-- never meets Lua arithmetic. Built once; nil if the curve API is missing.
local percentCurve
function API.PercentCurve()
    if percentCurve == nil and C_CurveUtil and C_CurveUtil.CreateCurve then
        local curve = C_CurveUtil.CreateCurve()
        local types = Enum and Enum.LuaCurveType
        if types and types.Linear then curve:SetType(types.Linear) end
        curve:AddPoint(0, 0)
        curve:AddPoint(1, 100)
        percentCurve = curve
    end
    return percentCurve or nil
end

-- Health percent (0..100) as whatever the client returns: possibly secret.
function API.HealthPercent(unit)
    local curve = API.PercentCurve()
    if not (curve and UnitHealthPercent) then return nil end
    return UnitHealthPercent(unit, true, curve)
end

-- Power percent (0..100) of the unit's display power, as the client returns it.
function API.PowerPercent(unit)
    local curve = API.PercentCurve()
    if not (curve and UnitPowerPercent) then return nil end
    return UnitPowerPercent(unit, nil, false, curve)
end

-- Opacity for a unit's power display: 0 when the unit has no power left, 1
-- otherwise, computed by the CLIENT from a colour curve over the power
-- fraction, so a secret power or max never meets Lua (DinoUF drives combo
-- points the same way, modules/basecombopoints.lua). The result may itself be
-- secret: hand it straight to SetAlpha. nil if the API is missing.
-- A step colour curve: alpha 0 below `threshold`, 1 at or above it. Step
-- type when the client has it; the extra point just below the threshold makes
-- a linear curve step too (the measured power fade works either way, so
-- nothing may depend on Step existing).
local function stepCurve(threshold)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local curve = C_CurveUtil.CreateColorCurve()
    local types = Enum and Enum.LuaCurveType
    if types and types.Step then curve:SetType(types.Step) end
    curve:AddPoint(0, CreateColor(1, 1, 1, 0))
    if threshold > 0.002 then curve:AddPoint(threshold - 0.001, CreateColor(1, 1, 1, 0)) end
    curve:AddPoint(threshold, CreateColor(1, 1, 1, 1))
    return curve
end

-- The client evaluates `curve` over the unit's power fraction; returns the
-- alpha (possibly secret: straight to SetAlpha) or nil.
local function curveAlpha(unit, powerType, unmodified, curve)
    if not (curve and UnitPowerPercent) then return nil end
    local color = UnitPowerPercent(unit, powerType, unmodified, curve)
    if not color then return nil end
    local _, _, _, a = color:GetRGBA()
    return a
end

local visibleCurve
function API.PowerAlpha(unit)
    visibleCurve = visibleCurve or stepCurve(0.001)
    return curveAlpha(unit, nil, false, visibleCurve)
end

-- CreateFrame with a template that may be missing on this client. A missing
-- template doesn't throw, it returns a bare frame (Priestly, FOREVER-PROBE),
-- so `proof` names a field the template would have made. Returns the frame and
-- whether the template really applied.
function API.SafeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

-- Combo point pip `i` (1-5): lit once the player has i points, evaluated by
-- the client from a step colour curve. DinoUF's
-- Forever path, exactly: UnitPowerPercent("player", 4 /*ComboPoints*/, true,
-- curve) (modules/basecombopoints.lua). The alpha may be secret: straight to
-- SetAlpha. nil if the API is missing.
local COMBO_POINTS = 4
local comboCurves = {}
function API.ComboAlpha(i)
    -- Midway between i-1 and i points, so float rounding (or a strict Step
    -- lookup) at exactly i/5 can't leave pip i dark with i points.
    comboCurves[i] = comboCurves[i] or stepCurve((i - 0.5) / 5)
    return curveAlpha("player", COMBO_POINTS, true, comboCurves[i])
end

-- The one place failures are recorded (first error per key), read by
-- /glass secrets and the tests. Engine, Frames and Auras all report here.
GlassUF.paintFailures = GlassUF.paintFailures or {}
function API.Fail(key, err)
    if GlassUF.paintFailures[key] == nil then GlassUF.paintFailures[key] = tostring(err) end
end

-- Load a load-on-demand Blizzard addon. Returns true, or false and the reason
-- the client gave (e.g. "DISABLED", "MISSING").
function API.LoadBlizzardAddOn(name)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn) then return false, "no C_AddOns" end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    if ok and loaded then return true end
    local okL, done, reason = pcall(C_AddOns.LoadAddOn, name)
    if okL and done then return true end
    return false, okL and tostring(reason) or tostring(done)
end

-- Aura-container enums from Blizzard_AuraContainer / FrameXML (not in the
-- dump). Sort: method AND direction, or neither (a method without a
-- direction is rejected by the engine).
function API.AuraSort()
    local m, d = rawget(_G, "AuraContainerSortMethod"), rawget(_G, "AuraContainerSortDirection")
    local method = m and (m.ExpirationOnly or m.Default)
    local dir = d and d.Normal
    if method ~= nil and dir ~= nil then return method, dir end
    return nil, nil
end

-- AnchorUtil flow-layout enums: horizontal axis, and Right/Down growth.
function API.FlowLayout()
    local au = rawget(_G, "AnchorUtil")
    local axis = au and au.FlowLayoutAxis and au.FlowLayoutAxis.Horizontal
    local fd = au and au.FlowDirection
    return axis, fd and fd.Right, fd and fd.Down
end

-- Heal prediction (#13). One calculator per frame, clamped to maximum health
-- when the client offers the mode, so the clip frame does the missing-health
-- cut. Returns nil when the API is absent.
function API.NewHealCalculator()
    -- rawget: an optional API may be absent; a presence check must not assume it.
    local create = rawget(_G, "CreateUnitHealPredictionCalculator")
    if not (create and rawget(_G, "UnitGetDetailedHealPrediction")) then return nil end
    local ok, calc = pcall(create)
    if not ok or not calc then return nil end
    -- DinoUF (incheal.lua, v2.3): on Forever the bar rendered EMPTY until the
    -- overflow percent was set to 1. SetIncomingHealOverflowPercent is in the dump.
    if calc.SetIncomingHealOverflowPercent then pcall(calc.SetIncomingHealOverflowPercent, calc, 1) end
    -- Clamp to maximum health when the enum exists (it is not in the dump).
    local modes = Enum and Enum.UnitIncomingHealClampMode
    if modes and modes.MaximumHealth ~= nil and calc.SetIncomingHealClampMode then
        pcall(calc.SetIncomingHealClampMode, calc, modes.MaximumHealth)
    end
    return calc
end

-- Fill `calc` for `unit` and return (all incoming heals, maximum health), both
-- as the client returns them (secret). GetIncomingHeals' FIRST return is the
-- processed all-healer total ("player" only selects the per-healer breakdown).
function API.IncomingHeals(unit, calc)
    UnitGetDetailedHealPrediction(unit, "player", calc)
    local incoming = calc:GetIncomingHeals()
    return incoming, calc:GetMaximumHealth()
end

-- The client's world latency in seconds (GetNetStats' 4th return, else its
-- 3rd), or nil when unreadable. Only the latency block's fallback (#72): it
-- measured 33 ms where a cast's keypress-to-start took 139 ms.
function API.NetLatency()
    local fn = rawget(_G, "GetNetStats")
    if not fn then return nil end
    local ok, _, _, home, world = pcall(fn)
    if not ok then return nil end
    local function ms(v)
        if API.IsSecret(v) or type(v) ~= "number" or v <= 0 then return nil end
        return v / 1000
    end
    return ms(world) or ms(home)
end

-- Cast/channel timing as a LuaDurationObject, or nil. Lua never reads the
-- start/end numbers; StatusBar:SetTimerDuration animates natively.
function API.CastDuration(unit)
    local d = UnitCastingDuration and UnitCastingDuration(unit)
    if d then return d, false end
    d = UnitChannelDuration and UnitChannelDuration(unit)
    if d then return d, true end
    return nil
end

function API.TimerDirection(channel)
    local dirs = Enum and Enum.StatusBarTimerDirection
    if not dirs then return nil end
    if channel then return dirs.RemainingTime end
    return dirs.ElapsedTime
end

-- Class colour from the documented API (RAID_CLASS_COLORS is a FrameXML
-- table the dump cannot confirm). Returns r, g, b or nil.
function API.ClassColor(classFile)
    if API.IsSecret(classFile) then return nil end   -- before ANY test of it
    if not (classFile and C_ClassColor and C_ClassColor.GetClassColor) then return nil end
    local c = C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
    return nil
end
