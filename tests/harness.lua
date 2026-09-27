-- harness.lua: assertions and the addon loader. dofile it after wow_stubs.lua.

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function done(name)
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- Lua files listed in the TOC, in load order.
function tocFiles()
    local files = {}
    for line in io.lines("GlassUnitFrames.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = line end
    end
    return files
end

-- Load the addon the way the client does: every TOC file with (name, ns),
-- then ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD (initial login).
function loadAddon(opts)
    opts = opts or {}
    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(file))
        chunk("GlassUnitFrames", ns)
    end
    if opts.db then GlassUnitFramesDB = opts.db end
    WoW.fire("ADDON_LOADED", "GlassUnitFrames")
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", opts.initialLogin ~= false, false)
    WoW.applyUnitWatch()
    WoW.tick()
    return GlassUF
end

-- The standard cast of units for most tests.
function standardUnits()
    WoW.SetUnit("player", { name = "Morphisto", class = "WARLOCK", player = true, health = 1240, maxHealth = 1550,
                            power = 920, maxPower = 1270 })
    WoW.SetUnit("target", { name = "Defias Pillager", reaction = 2, health = 830, maxHealth = 1317 })
    WoW.SetUnit("pet", { name = "Hathnos", reaction = 5, health = 400, maxHealth = 400, powerToken = "FOCUS" })
    WoW.SetUnit("targettarget", { name = "Morphisto", class = "WARLOCK", player = true, health = 1240, maxHealth = 1550 })
    WoW.SetUnit("targettargettarget", { name = "Defias Pillager", reaction = 2, health = 830, maxHealth = 1317 })
    WoW.SetUnit("focus", { name = "Hogger", reaction = 2, health = 666, maxHealth = 800 })
    WoW.SetUnit("focustarget", { name = "Morphisto", class = "WARLOCK", player = true, health = 1240, maxHealth = 1550 })
end

function button(unit) return GlassUF.Frames.byUnit[unit] end

-- Text a FontString holds: a plain string, or a table for secret-formatted text.
function textOf(fs) return fs._text end
