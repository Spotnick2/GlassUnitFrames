<#
    deploy.ps1 - Copy GlassUnitFrames (and optionally GlassProbe) into the Forever AddOns folder.

    The repo keeps "## Version: @project-version@" for the packager; the deployed
    copy gets "dev". The repo copy is never modified.

    Usage:
        pwsh Tools/deploy.ps1               # GlassUnitFrames
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

function Copy-Media([string]$dest) {
    $media = Join-Path $dest "Media"
    New-Item -ItemType Directory -Force -Path $media | Out-Null
    $textures = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Media") -Filter "*.tga"
    foreach ($t in $textures) { Copy-Item -LiteralPath $t.FullName -Destination (Join-Path $media $t.Name) -Force }
    Write-Host "  Media\  ($($textures.Count) textures)"
}

function Deploy-Addon {
    $dest = Join-Path $AddOnsPath "GlassUnitFrames"
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
    Copy-Media $dest
}

function Deploy-Probe {
    $dest = Join-Path $AddOnsPath "GlassProbe"
    Write-Host "Deploying GlassProbe -> $dest" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Tools\GlassProbe") -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
        Write-Host "  $($_.Name)"
    }
    Copy-Media $dest
}

if (-not $ProbeOnly) { Deploy-Addon }
if ($Probe -or $ProbeOnly) { Deploy-Probe }

Write-Host ""
Write-Host "Changed or new files: /reload is enough (measured on 70009). A brand-new addon folder needs a client restart." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /glass help" -ForegroundColor Green
