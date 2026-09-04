<#
.SYNOPSIS
    Remove the Milestone telemetry mod from a game.

.DESCRIPTION
    Deletes dinput8.dll, milestone_mod.ini and any log it wrote, but only when
    the DLL is actually ours - a dinput8.dll belonging to another tool is left
    alone. The WheelConfig.ini entry is left in place: it is harmless, and
    removing it would lose your calibrated pedal axes.

.EXAMPLE
    .\Uninstall.ps1
    .\Uninstall.ps1 -GamePath "D:\...\Binaries\Win64"
#>
[CmdletBinding()]
param(
    [string]$Game,
    [string]$GamePath
)

$ErrorActionPreference = 'Stop'
function Ok($m) { Write-Host "  OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  !    $m" -ForegroundColor Yellow }
function Die($m) { Write-Host "  X    $m" -ForegroundColor Red; exit 1 }

Write-Host "Milestone telemetry mod - uninstaller" -ForegroundColor White

if (-not $GamePath) {
    # Reuse the installer's search by asking it where things are.
    $KNOWN = 'Gravel', 'MXGP3', 'MXGP PRO', 'MotoGP18', 'MotoGP19', 'Monster Energy Supercross'
    # Steam discovery and DirectInput enumeration come from dbce-wheel-mod-toolkit's
    # PowerShell module, vendored under lib\toolkit (tools\Sync-Toolkit.ps1).
    $toolkit = Join-Path $PSScriptRoot 'lib\toolkit\powershell\DbceWheel.psm1'
    if (-not (Test-Path $toolkit)) { Die "lib\toolkit is missing - run tools\Sync-Toolkit.ps1, or re-download the release" }
    Import-Module $toolkit -Force
    $libs = @(Get-SteamLibraries)
    $hits = @()
    foreach ($l in ($libs | Sort-Object -Unique)) {
        $common = Join-Path $l 'steamapps\common'
        if (-not (Test-Path $common)) { continue }
        foreach ($d in $KNOWN) {
            Get-ChildItem (Join-Path $common $d) -Recurse -Filter 'milestone_mod.ini' -EA SilentlyContinue |
                ForEach-Object { $hits += $_.DirectoryName }
        }
    }
    if (-not $hits) { Die "No installation found. Use -GamePath." }
    if ($hits.Count -gt 1) {
        for ($i = 0; $i -lt $hits.Count; $i++) { Write-Host "    [$($i+1)] $($hits[$i])" }
        $pick = Read-Host "  Which one? (1-$($hits.Count))"
        $GamePath = $hits[[int]$pick - 1]
    } else { $GamePath = $hits[0] }
}
if (-not (Test-Path $GamePath)) { Die "no such folder: $GamePath" }

$running = Get-Process -EA SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($GamePath, [StringComparison]::OrdinalIgnoreCase) }
if ($running) { Die "$($running[0].ProcessName) is running - close the game first." }

$dll = Join-Path $GamePath 'dinput8.dll'
if (Test-Path $dll) {
    if (Select-String -Path $dll -Pattern 'milestone_mod' -Quiet -EA SilentlyContinue) {
        Remove-Item $dll -Force; Ok "removed dinput8.dll"
    } else {
        Warn "dinput8.dll here belongs to another tool - left alone"
    }
}
foreach ($f in 'milestone_mod.ini', 'milestone_mod.ini.bak', 'milestone_mod.log') {
    $p = Join-Path $GamePath $f
    if (Test-Path $p) { Remove-Item $p -Force; Ok "removed $f" }
}
Write-Host "`n  The wheel's WheelConfig.ini entry was left in place - it is harmless," -ForegroundColor Gray
Write-Host "  and removing it would lose your calibrated pedal axes." -ForegroundColor Gray
