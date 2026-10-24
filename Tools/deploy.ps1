<#
    deploy.ps1 - Copy GlassUnitFrames (and optionally its probe) into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    The glass material is the embedded LibGlass-1.0. The packager fetches it
    into Libs\LibGlass-1.0 (.pkgmeta externals); for a dev copy this script
    hands that job to the LibGlass checkout's own deploy.ps1, which checks the
    checkout, copies only the shipped files and prints its commit. The checkout
    is $env:LIBGLASS, else ..\LibGlass. The flight times are the embedded
    LibTaxiTime-1.0 (#153), deployed the same way by its checkout
    ($env:LIBTAXITIME, else ..\LibTaxiTime).

    The probe, CastProbe, is a ForeverProbe module (#112): its host is deployed
    first from the ForeverProbe checkout ($env:FOREVERPROBE, else ..\ForeverProbe),
    by that checkout's own deploy.ps1.

    Usage:
        pwsh Tools/deploy.ps1               # GlassUnitFrames + its LibGlass and LibTaxiTime
        pwsh Tools/deploy.ps1 -Probe        # ...and the probes (CastProbe, BarProbe, LayoutProbe, ThreatProbe), with ForeverProbe
        pwsh Tools/deploy.ps1 -ProbeOnly    # just the probes, with ForeverProbe
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_forever_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns",
    [switch]$Probe,
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }

$Siblings = Split-Path -Parent $RepoRoot
# The embedded libraries: name, checkout, its env var.
$Libs = @(
    @{ Name = "LibGlass-1.0"; Checkout = $(if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path $Siblings "LibGlass" }); Env = "LIBGLASS"; Repo = "LibGlass" },
    @{ Name = "LibTaxiTime-1.0"; Checkout = $(if ($env:LIBTAXITIME) { $env:LIBTAXITIME } else { Join-Path $Siblings "LibTaxiTime" }); Env = "LIBTAXITIME"; Repo = "LibTaxiTime" }
)
foreach ($lib in $Libs) {
    if (-not (Test-Path -LiteralPath (Join-Path $lib.Checkout "Tools\deploy.ps1"))) {
        Write-Error "$($lib.Name) checkout not found at $($lib.Checkout) (clone github.com/Spotnick2/$($lib.Repo) there, or set `$env:$($lib.Env))"
        exit 1
    }
}

# The commit or tag .pkgmeta pins, which is what the packager will ship. A dev
# checkout elsewhere is legitimate (trying a library change before a pin bump),
# but an in-game check then tests something the release won't carry: say so.
. (Join-Path $PSScriptRoot "LibPin.ps1")

function Deploy-Addon {
    $dest = Join-Path $AddOnsPath "GlassUnitFrames"
    # The libraries first: each deploy checks its checkout and may refuse, and a
    # refusal must leave the deployed addon as it was (a new TOC naming a
    # library that never arrived loads no frames at all).
    foreach ($lib in $Libs) {
        Test-LibCheckout (Join-Path $RepoRoot ".pkgmeta") $lib.Name $lib.Checkout "this deploy tests a library the release won't ship"
        & pwsh -NoProfile -File (Join-Path $lib.Checkout "Tools\deploy.ps1") -Addon GlassUnitFrames -AddOnsPath $AddOnsPath
        if ($LASTEXITCODE -ne 0) { Write-Error "$($lib.Name) deploy refused; GlassUnitFrames was not touched"; exit 1 }
    }
    Write-Host "Deploying GlassUnitFrames -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $files = @("GlassUnitFrames.toc") + (Get-ChildItem -LiteralPath $RepoRoot -Filter "*.lua" | Select-Object -ExpandProperty Name)
    foreach ($f in $files) {
        $src = Join-Path $RepoRoot $f
        if ($f -like "*.toc") {
            (Get-Content -LiteralPath $src -Raw) -replace '## Version: @project-version@', '## Version: dev' |
                Set-Content -LiteralPath (Join-Path $dest $f) -NoNewline
        } else {
            Copy-Item -LiteralPath $src -Destination (Join-Path $dest $f) -Force
        }
        Write-Host "  $f"
    }
    # A Lua file removed from the repo must not linger where the client finds it.
    $soundDest = Join-Path $dest "Sounds"
    New-Item -ItemType Directory -Force -Path $soundDest | Out-Null
    foreach ($soundFile in @("BoxingArenaSound.ogg", "COPYING.txt", "README.txt")) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot "Sounds\$soundFile") -Destination (Join-Path $soundDest $soundFile) -Force
    }
    Get-ChildItem -LiteralPath $dest -File | Where-Object { $files -notcontains $_.Name } | ForEach-Object {
        Write-Host "  removing stale $($_.Name)" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $_.FullName -Force
    }
    # The textures now ship inside Libs\LibGlass-1.0\Media; the old folder is dead weight.
    $oldMedia = Join-Path $dest "Media"
    if (Test-Path -LiteralPath $oldMedia) {
        Write-Host "  removing stale Media\ (textures now come from LibGlass)" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $oldMedia -Recurse -Force
    }
}

# The probes (CastProbe, BarProbe, LayoutProbe, ThreatProbe): the host first (its deploy checks the
# checkout and may refuse, and a refusal leaves the probes as they were), then
# each module's files.
$ForeverProbe = if ($env:FOREVERPROBE) { $env:FOREVERPROBE } else { Join-Path (Split-Path -Parent $RepoRoot) "ForeverProbe" }

function Deploy-Probe {
    if (-not (Test-Path -LiteralPath (Join-Path $ForeverProbe "Tools\deploy.ps1"))) {
        Write-Error "ForeverProbe checkout not found at $ForeverProbe (or set `$env:FOREVERPROBE)"; exit 1
    }
    & pwsh -NoProfile -File (Join-Path $ForeverProbe "Tools\deploy.ps1") -AddOnsPath $AddOnsPath
    if ($LASTEXITCODE -ne 0) { Write-Error "ForeverProbe deploy refused; the probes were not touched"; exit 1 }
    foreach ($name in @("CastProbe", "BarProbe", "LayoutProbe", "ThreatProbe")) {
        $dest = Join-Path $AddOnsPath $name
        Write-Host "Deploying $name -> $dest" -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Tools\$name") -File |
            Where-Object { $_.Extension -in ".toc", ".lua" } | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
                Write-Host "  $($_.Name)"
            }
    }
    # GlassProbe was retired (#112); an old deployed copy would still load.
    $old = Join-Path $AddOnsPath "GlassProbe"
    if (Test-Path -LiteralPath $old) {
        Write-Host "  NOTE: $old is the retired GlassProbe; delete it when convenient" -ForegroundColor DarkYellow
    }
}

if (-not $ProbeOnly) { Deploy-Addon }
if ($Probe -or $ProbeOnly) { Deploy-Probe }

Write-Host ""
Write-Host "/reload loads changed files and new addon folders alike (ForeverProbe guide, section 7)." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /glass help" -ForegroundColor Green
