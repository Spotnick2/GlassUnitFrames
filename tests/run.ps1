<#
    run.ps1 - Syntax-check the addon and run every tests\test_*.lua under Lua 5.1.

    Usage:
        pwsh tests/run.ps1
        pwsh tests/run.ps1 -Lua "C:\path\to\lua5.1.exe"
#>

param(
    [string]$Lua = "C:\Program Files (x86)\Lua\5.1\lua.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Lua)) { Write-Error "Lua 5.1 not found at $Lua (pass -Lua <path>)"; exit 1 }
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    # The TOC is the list, so a new file cannot go unchecked. Only our own .lua
    # lines: the embedded LibGlass (the TOC's .xml line) is checked in its repo,
    # and the tests load it from $env:LIBGLASS (default ..\LibGlass).
    $luac = Join-Path (Split-Path -Parent $Lua) "luac.exe"
    $tocFiles = Get-Content "GlassUnitFrames.toc" | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -notmatch "^#" -and $_ -match "[.]lua$" }
    if (-not (Test-Path $luac)) {
        Write-Host "luac -p SKIPPED: no luac.exe beside $Lua - syntax was NOT checked" -ForegroundColor Yellow
    } else {
        & $luac -p @tocFiles "Tools\GlassProbe\GlassProbe.lua"
        if ($LASTEXITCODE -ne 0) { Write-Host "luac -p FAILED" -ForegroundColor Red; exit 1 }
        Remove-Item -LiteralPath "luac.out" -ErrorAction SilentlyContinue
        Write-Host "luac -p: ok ($($tocFiles.Count) addon files + probe)" -ForegroundColor DarkGray
    }

    $failed = 0
    Get-ChildItem (Join-Path $PSScriptRoot "test_*.lua") | Sort-Object Name | ForEach-Object {
        Write-Host "-- $($_.Name) " -NoNewline -ForegroundColor Cyan
        & $Lua $_.FullName
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($failed -gt 0) { Write-Host "$failed test file(s) FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "All test files passed." -ForegroundColor Green
}
finally { Pop-Location }
