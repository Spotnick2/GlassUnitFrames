-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassUF.API. Nothing is injected into _G.

GlassUF = GlassUF or {}
local API = {}
GlassUF.API = API

-- The build the notes in docs/FOREVER-PROBE.md were measured on. Bump only
-- after re-measuring in game; tests/test_toc.lua pins the same literal.
GlassUF.MEASURED_ON_BUILD = "1.60.1.70009"

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

-- Secure buttons register BOTH mouse edges; the client acts on exactly one,
-- per ActionButtonUseKeyDown (measured in Priestly, see the porting guide).
-- Never set "typerelease" on these buttons: that double-acts.
function API.ClickEdges()
    return "LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp"
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
