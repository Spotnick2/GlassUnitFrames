<#
    deploy.ps1 - Copy GlassProbe (and, later, GlassUnitFrames) into the Forever AddOns folder.

    Media\late.tga is held back unless -Late is given: it exists to test whether
    /reload picks up a texture file that did not exist when the client started.

    Usage:
        pwsh Tools/deploy.ps1                 # GlassProbe, without late.tga
        pwsh Tools/deploy.ps1 -Late           # ...and add late.tga
        pwsh Tools/deploy.ps1 -AddOnsPath "D:\...\_classic_beta_\Interface\AddOns"
#>

param(
    [string]$AddOnsPath = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns",
    [switch]$Late
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $AddOnsPath)) {
    Write-Error "AddOns path not found: $AddOnsPath"
    exit 1
}

$src = Join-Path $RepoRoot "Tools\GlassProbe"
$dest = Join-Path $AddOnsPath "GlassProbe"
$media = Join-Path $dest "Media"
Write-Host "Deploying GlassProbe -> $dest" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $media | Out-Null

Get-ChildItem -LiteralPath $src -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Force
    Write-Host "  $($_.Name)"
}

$textures = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "Media") -Filter "*.tga" |
    Where-Object { $Late -or $_.Name -ne "late.tga" }
foreach ($t in $textures) {
    Copy-Item -LiteralPath $t.FullName -Destination (Join-Path $media $t.Name) -Force
}
Write-Host "  Media\  ($($textures.Count) textures$(if (-not $Late) { ', late.tga held back' }))"

Write-Host ""
Write-Host "New or changed files: /reload is enough (measured on 70009). A brand-new addon folder needs a client restart." -ForegroundColor Yellow
Write-Host "In game:  /console scriptErrors 1   then   /gprobe help" -ForegroundColor Green
