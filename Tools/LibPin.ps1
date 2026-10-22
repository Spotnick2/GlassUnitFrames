<#
    LibPin.ps1 - Dot-sourced by tests\run.ps1 and Tools\deploy.ps1: the
    embedded libraries' pins, read from .pkgmeta (the one place they are
    written, as tests/fetch_lib.sh reads them), and a check that a dev
    checkout is at its pin.
#>

# The commit or tag .pkgmeta pins for Libs/<Lib> (e.g. "LibGlass-1.0"), or $null.
function Get-LibPin([string]$Pkgmeta, [string]$Lib) {
    $inExternals = $false; $inLib = $false
    foreach ($line in (Get-Content -LiteralPath $Pkgmeta)) {
        if ($line -match '^externals:') { $inExternals = $true; continue }
        if ($inExternals -and $line -match '^[^ #]') { $inExternals = $false }
        if (-not $inExternals) { continue }
        if ($line -eq "  Libs/${Lib}:") { $inLib = $true; continue }
        if ($inLib -and $line -match '^  [^ ]') { $inLib = $false }
        if ($inLib -and $line -match '^\s+(commit|tag):\s*(\S+)\s*$') { return $Matches[2] }
    }
    return $null
}

# Warn when a library checkout is not at its .pkgmeta pin (or is dirty): a run
# or deploy against it tests something the release won't ship.
function Test-LibCheckout([string]$Pkgmeta, [string]$Lib, [string]$Checkout, [string]$Why) {
    $pin = Get-LibPin $Pkgmeta $Lib
    if (-not $pin) { Write-Host "  (no $Lib pin found in .pkgmeta)" -ForegroundColor Yellow; return }
    $want = $null; $head = $null; $dirty = $null
    try {
        $want = (git -C $Checkout rev-parse --verify --quiet "$pin^{commit}" 2>$null)
        $head = (git -C $Checkout rev-parse HEAD 2>$null)
        $dirty = (git -C $Checkout status --porcelain 2>$null)
    } catch { }
    if (-not $want -or $want -ne $head -or $dirty) {
        Write-Host "WARNING: $Lib at $Checkout is not the .pkgmeta pin ($pin)$(if ($dirty) { ', or has uncommitted changes' }); $Why" -ForegroundColor Yellow
    } else {
        Write-Host "${Lib}: $Checkout at the pin ($pin)" -ForegroundColor DarkGray
    }
}
