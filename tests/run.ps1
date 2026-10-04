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

    # The tests load the LibGlass checkout as it is; CI loads the .pkgmeta pin.
    # Running against something else is fine (a library change before a pin
    # bump) but must not pass for a check of what ships.
    $libGlass = if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent $RepoRoot) "LibGlass" }
    $pin = (Get-Content ".pkgmeta") | Where-Object { $_ -match '^\s+(commit|tag):\s*(\S+)\s*$' } |
        ForEach-Object { $Matches[2] } | Select-Object -First 1
    if ($pin -and (Test-Path -LiteralPath $libGlass)) {
        $want = git -C $libGlass rev-parse --verify --quiet "$pin^{commit}" 2>$null
        $head = git -C $libGlass rev-parse HEAD 2>$null
        $dirty = git -C $libGlass status --porcelain 2>$null
        if (-not $want -or $want -ne $head -or $dirty) {
            Write-Host "WARNING: LibGlass at $libGlass is not the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }); CI tests the pin" -ForegroundColor Yellow
        } else {
            Write-Host "LibGlass: $libGlass at the pin ($pin)" -ForegroundColor DarkGray
        }
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
