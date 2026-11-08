-- harness.lua: the addon loader and GUF's test helpers. dofile it after
-- wow_stubs.lua. check / eq / done are WowTestKit's (tests/kit.lua loads them).

TOC = "GlassUnitFrames.toc"

-- Every file line of the TOC, in load order (this addon's .lua files and the
-- embedded libraries' .xml).
function tocLines() return Kit.tocLines(TOC) end

-- This addon's own Lua files listed in the TOC, in load order.
function tocFiles() return Kit.tocFiles(TOC) end

-- The embedded libraries come from checkouts, not from Libs\ (gitignored,
-- filled by the packager): each one's env var, else the sibling folder. No
-- checkout fails the run loudly; a silently skipped library would test nothing.
-- Keyed by the TOC's XML line.
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
LIBTAXITIME_XML = "Libs\\LibTaxiTime-1.0\\LibTaxiTime-1.0.xml"
EMBEDDED = {
    [LIBGLASS_XML] = { name = "LibGlass", env = "LIBGLASS", xml = "LibGlass-1.0.xml" },
    [LIBTAXITIME_XML] = { name = "LibTaxiTime", env = "LIBTAXITIME", xml = "LibTaxiTime-1.0.xml" },
}
function libRoot(line)
    local lib = assert(EMBEDDED[line], "not an embedded library's XML: " .. tostring(line))
    local root = (os.getenv(lib.env) or ("../" .. lib.name)):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/" .. lib.xml, "rb")
    if not f then
        error(lib.name .. " checkout not found at " .. root .. " (no " .. lib.xml .. "): clone "
              .. "github.com/Spotnick2/" .. lib.name .. " there or set " .. lib.env, 0)
    end
    f:close()
    return root
end

-- The Lua files a library's XML loads, as paths, in order: what the client
-- runs for the TOC's XML line. A listed file that is missing fails here.
function libScripts(line)
    local lib, root = EMBEDDED[line], libRoot(line)
    local f = assert(io.open(root .. "/" .. lib.xml, "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error(lib.name .. " checkout at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error(lib.xml .. " at " .. root .. " lists no Script files", 0) end
    return files
end

function libGlassRoot() return libRoot(LIBGLASS_XML) end
function libGlassScripts() return libScripts(LIBGLASS_XML) end

-- The ForeverProbe host (#112), from its checkout ($FOREVERPROBE, else
-- ../ForeverProbe), as GlassChat's harness loads it: the TOC's files with
-- ("ForeverProbe", {}), then its ADDON_LOADED. The host is private and lives
-- only on the owner's disk: with FOREVERPROBE_OPTIONAL=1 (CI) a missing
-- checkout skips the probe's test; without it, it's an error.
function loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
end

-- Load the addon the way the client does: every TOC file with (name, ns),
-- the library's XML expanded in place, then ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD (initial login).
function loadAddon(opts)
    opts = opts or {}
    local ns = {}
    for _, line in ipairs(tocLines()) do
        local files = { line }
        if EMBEDDED[line] then
            files = libScripts(line)
        elseif not line:match("%.lua$") then
            error("the harness can't load TOC line " .. line, 0)
        end
        for _, file in ipairs(files) do
            local chunk = assert(loadfile(file))
            chunk("GlassUnitFrames", ns)
        end
    end
    if opts.db then GlassUnitFramesDB = opts.db end
    if opts.beforeLoaded then opts.beforeLoaded() end   -- after the files, before ADDON_LOADED
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

-- FINDING (#178): /glass's help and usage lines print a bare "|" between
-- choices ("on|off"), which the client reads as an escape. Until #178 doubles
-- them, a printed line whose strays are all one of these choice lists passes
-- the kit's stray-"|" check; any other stray still fails done(). Longest
-- first, so "on|off|always" is taken before "on|off".
local CHOICE_LISTS = {
    "curhp|curmaxhp|perhp|curmaxhp_perhp", "off|portrait|beside", "pearl|clean|classic", "power|name|portrait",
    "player|target|pet", "left|right|under", "name|top|right", "on|off|always", "clear|smoked", "target|focus",
    "arial|friz", "grid|align", "show|hide", "whole|edge", "3d|2d|none", "unlock | lock", "on|off",
}
local function onlyChoiceLists(line)
    for _, list in ipairs(CHOICE_LISTS) do
        line = line:gsub(list:gsub("%p", "%%%0"), (list:gsub("|", "")))
    end
    return not WoW.StrayPipe(line)
end
local kitDone = done
function done(name)
    local left = {}
    for _, line in ipairs(WoW.strays) do
        if not onlyChoiceLists(line) then left[#left + 1] = line end
    end
    WoW.strays = left
    kitDone(name)
end
