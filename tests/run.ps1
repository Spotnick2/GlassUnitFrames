<#
    run.ps1 - Syntax-check the addon and the probes, and run every tests\test_*.lua under Lua 5.1,
    through WowTestKit at the commit tests\kit.pin names (its scripts\run.ps1).

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
        pwsh tests/run.ps1 -KitDev      # the ..\WowTestKit working copy, not the pin
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe",
    [switch]$KitDev
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# The tests load each library checkout as it is; CI loads the .pkgmeta pins.
# Running against something else is fine (a library change before a pin
# bump) but must not pass for a check of what ships.
. (Join-Path $RepoRoot "Tools\LibPin.ps1")
$siblings = Split-Path -Parent $RepoRoot
foreach ($lib in @(@("LibGlass-1.0", $env:LIBGLASS, "LibGlass"), @("LibTaxiTime-1.0", $env:LIBTAXITIME, "LibTaxiTime"))) {
    $checkout = if ($lib[1]) { $lib[1] } else { Join-Path $siblings $lib[2] }
    if (Test-Path -LiteralPath $checkout) {
        Test-LibCheckout (Join-Path $RepoRoot ".pkgmeta") $lib[0] $checkout "CI tests the pin"
    }
}

# The kit syntax-checks the TOC's .lua files (the TOC is the list, so a new
# file cannot go unchecked); the probes are checked with them. The embedded
# libraries (the TOC's .xml lines) are checked in their own repos, and the
# tests load them from $env:LIBGLASS / $env:LIBTAXITIME (default ..\LibGlass,
# ..\LibTaxiTime).
$probes = @("Tools\CastProbe\CastProbe.lua", "Tools\BarProbe\BarProbe.lua", "Tools\LayoutProbe\LayoutProbe.lua",
            "Tools\ThreatProbe\ThreatProbe.lua", "Tools\ThreatProbe\Preview.lua")

. (Join-Path $PSScriptRoot "kit.ps1")
$kit = Get-WowTestKit -RepoRoot $RepoRoot -KitDev:$KitDev
& (Join-Path $kit "scripts\run.ps1") -RepoRoot $RepoRoot -Toc "GlassUnitFrames.toc" -Extra $probes -Lua $Lua
exit $LASTEXITCODE
