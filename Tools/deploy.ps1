<#
    deploy.ps1 - Copy GlassUnitFrames (and optionally GlassProbe) into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    The glass material is the embedded LibGlass-1.0. The packager fetches it
    into Libs\LibGlass-1.0 (.pkgmeta externals); for a dev copy this script
    hands that job to the LibGlass checkout's own deploy.ps1, which checks the
    checkout, copies only the shipped files and prints its commit. The checkout
    is $env:LIBGLASS, else ..\LibGlass.

    Usage:
        pwsh Tools/deploy.ps1               # GlassUnitFrames + its LibGlass
        pwsh Tools/deploy.ps1 -Probe        # ...and GlassProbe
        pwsh Tools/deploy.ps1 -ProbeOnly    # just GlassProbe
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns",
    [switch]$Probe,
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $AddOnsPath)) { Write-Error "AddOns path not found: $AddOnsPath"; exit 1 }

$LibGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
if (-not (Test-Path -LiteralPath (Join-Path $LibGlass "Tools\deploy.ps1"))) {
    Write-Error "LibGlass checkout not found at $LibGlass (clone github.com/Spotnick2/LibGlass there, or set `$env:LIBGLASS)"
    exit 1
}

# The commit or tag .pkgmeta pins, which is what the packager will ship. A dev
# checkout elsewhere is legitimate (trying a library change before a pin bump),
# but an in-game check then tests something the release won't carry: say so.
function Test-LibGlassPin {
    $pin = (Get-Content -LiteralPath (Join-Path $RepoRoot ".pkgmeta")) |
        Where-Object { $_ -match '^\s+(commit|tag):\s*(\S+)\s*$' } | ForEach-Object { $Matches[2] } | Select-Object -First 1
    if (-not $pin) { Write-Host "  (no LibGlass pin found in .pkgmeta)" -ForegroundColor Yellow; return }
    $want = $null; $head = $null
    try {
        $want = (git -C $LibGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null)
        $head = (git -C $LibGlass rev-parse HEAD 2>$null)
        $dirty = (git -C $LibGlass status --porcelain 2>$null)
    } catch { }
    if (-not $want -or $want -ne $head -or $dirty) {
        Write-Host "  WARNING: the LibGlass checkout is not at the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }):" -ForegroundColor Yellow
        Write-Host "  this deploy tests a library the release won't ship." -ForegroundColor Yellow
    }
}

function Deploy-Addon {
    $dest = Join-Path $AddOnsPath "GlassUnitFrames"
    Test-LibGlassPin
    # The library first: its deploy checks the checkout and may refuse, and a
    # refusal must leave the deployed addon as it was (a new TOC naming a
    # library that never arrived loads no frames at all).
    & pwsh -NoProfile -File (Join-Path $LibGlass "Tools\deploy.ps1") -Addon GlassUnitFrames -AddOnsPath $AddOnsPath
    if ($LASTEXITCODE -ne 0) { Write-Error "LibGlass deploy refused; GlassUnitFrames was not touched"; exit 1 }
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

# The probe is standalone (its own MEDIA path): it gets its 12 legacy textures
# from Tools\GlassProbe\Media and the 15 current ones from the LibGlass checkout.
function Deploy-Probe {
    $dest = Join-Path $AddOnsPath "GlassProbe"
    Write-Host "Deploying GlassProbe -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Tools\GlassProbe") -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
        Write-Host "  $($_.Name)"
    }
    $media = Join-Path $dest "Media"
    New-Item -ItemType Directory -Force -Path $media | Out-Null
    $textures = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Tools\GlassProbe\Media") -Filter "*.tga") +
                @(Get-ChildItem -LiteralPath (Join-Path $LibGlass "Media") -Filter "*.tga")
    foreach ($t in $textures) { Copy-Item -LiteralPath $t.FullName -Destination (Join-Path $media $t.Name) -Force }
    Write-Host "  Media\  ($($textures.Count) textures)"
}

if (-not $ProbeOnly) { Deploy-Addon }
if ($Probe -or $ProbeOnly) { Deploy-Probe }

Write-Host ""
Write-Host "Changed or new files: /reload is enough (measured on 70009). A brand-new addon folder needs a client restart." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /glass help" -ForegroundColor Green
