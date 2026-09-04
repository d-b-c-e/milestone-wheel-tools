<#
.SYNOPSIS
    Install the Milestone telemetry mod into a game. Finds the game, detects
    your wheel, writes the config and verifies the result.

.DESCRIPTION
    Run it with no arguments and it will:
      1. find supported Milestone games in your Steam libraries
      2. detect your steering wheel and work out its DirectInput product key
      3. copy dinput8.dll and a per-game milestone_mod.ini next to the game exe
      4. add the wheel to the game's WheelConfig.ini so it appears as a wheel
      5. tell you exactly what to set in SimHub

    Nothing is overwritten without asking, and an existing dinput8.dll from a
    different tool is never replaced.

.PARAMETER Game
    Skip the menu and install for this game (e.g. Gravel).

.PARAMETER GamePath
    Install into a specific folder holding the shipping exe, for a game or
    store this script does not know about.

.PARAMETER Port
    UDP port to send telemetry to. Must match SimHub. Default 5300.

.PARAMETER Format
    fh4 (Forza Horizon 4/5, 324 bytes) or fm7 (Forza Motorsport 7, 311) or
    sled (232). Must match the game you pick in SimHub. Default fh4.

.PARAMETER Product
    Wheel product key in hex, if auto-detection picks the wrong device.

.PARAMETER SkipWheelConfig
    Do not touch the game's WheelConfig.ini.

.EXAMPLE
    .\Install.ps1
    .\Install.ps1 -Game Gravel -Port 8000 -Format fh4
    .\Install.ps1 -GamePath "D:\Games\MXGP3\MXGP3\Binaries\Win64"
#>
[CmdletBinding()]
param(
    [string]$Game,
    [string]$GamePath,
    [int]$Port = 5300,
    [ValidateSet('fh4', 'fm7', 'sled')][string]$Format = 'fh4',
    [string]$Product,
    [switch]$SkipWheelConfig
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Step($m) { Write-Host "`n$m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "  OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  !    $m" -ForegroundColor Yellow }
function Die($m) { Write-Host "  X    $m" -ForegroundColor Red; exit 1 }

# Games this script knows how to find, and their quirks. All are Milestone
# titles on the same UE4 engine, so the same mod applies to each.
$KNOWN = @(
    @{ Name = 'Gravel';                     AppId = 558260;  Dir = 'Gravel';                     Exe = 'gravel' }
    @{ Name = 'MXGP3';                      AppId = 511660;  Dir = 'MXGP3';                      Exe = 'MXGP3' }
    @{ Name = 'MXGP PRO';                   AppId = 843270;  Dir = 'MXGP PRO';                   Exe = 'MXGPPRO' }
    @{ Name = 'MotoGP 18';                  AppId = 775900;  Dir = 'MotoGP18';                   Exe = 'MotoGP18' }
    @{ Name = 'MotoGP 19';                  AppId = 1004010; Dir = 'MotoGP19';                   Exe = 'MotoGP19' }
    @{ Name = 'Monster Energy Supercross';  AppId = 606290;  Dir = 'Monster Energy Supercross';  Exe = 'Supercross' }
)

Say "Milestone telemetry mod - installer" 'White'

# ---------------------------------------------------------------- the DLL
$dll = Join-Path $root 'build\dinput8.dll'
if (-not (Test-Path $dll)) { $dll = Join-Path $root 'dist\dinput8.dll' }
if (-not (Test-Path $dll)) {
    Die "dinput8.dll not found. Download it from the Releases page into dist\, or build it with .\build.sh"
}
Ok "using $((Resolve-Path $dll).Path)"

# Steam discovery and DirectInput enumeration come from dbce-wheel-mod-toolkit's
# PowerShell module, vendored under lib\toolkit (tools\Sync-Toolkit.ps1).
$toolkit = Join-Path $root 'lib\toolkit\powershell\DbceWheel.psm1'
if (-not (Test-Path $toolkit)) { Die "lib\toolkit is missing - run tools\Sync-Toolkit.ps1, or re-download the release" }
Import-Module $toolkit -Force

# ------------------------------------------------------------ find the game


Step "Looking for supported games"
$found = @()
foreach ($lib in Get-SteamLibraries) {
    foreach ($g in $KNOWN) {
        $p = Join-Path $lib "steamapps\common\$($g.Dir)\$($g.Exe)\Binaries\Win64"
        if (Test-Path $p) {
            $exe = Get-ChildItem $p -Filter '*-Shipping.exe' -EA SilentlyContinue | Select-Object -First 1
            if ($exe) { $found += [pscustomobject]@{ Name = $g.Name; Path = $p; Exe = $exe.Name; Root = (Join-Path $lib "steamapps\common\$($g.Dir)") } }
        }
    }
}

if ($GamePath) {
    if (-not (Test-Path $GamePath)) { Die "no such folder: $GamePath" }
    $exe = Get-ChildItem $GamePath -Filter '*-Shipping.exe' -EA SilentlyContinue | Select-Object -First 1
    if (-not $exe) { Warn "no *-Shipping.exe here; installing anyway" }
    $target = [pscustomobject]@{ Name = (Split-Path $GamePath -Leaf); Path = $GamePath; Exe = $exe.Name; Root = $null }
} elseif ($Game) {
    $target = $found | Where-Object Name -eq $Game | Select-Object -First 1
    if (-not $target) { Die "$Game not found in your Steam libraries. Use -GamePath instead." }
} elseif ($found.Count -eq 1) {
    $target = $found[0]
} elseif ($found.Count -eq 0) {
    Die "No supported game found. Use -GamePath <folder with the shipping exe>."
} else {
    Say "  Found several:"
    for ($i = 0; $i -lt $found.Count; $i++) { Say "    [$($i+1)] $($found[$i].Name)  -  $($found[$i].Path)" }
    $pick = Read-Host "  Which one? (1-$($found.Count))"
    $target = $found[[int]$pick - 1]
    if (-not $target) { Die "invalid choice" }
}
Ok "$($target.Name)  ->  $($target.Path)"

# --------------------------------------------------------- detect the wheel
# DirectInput builds guidProduct.Data1 as (PID << 16) | VID, which is exactly
# the key both this mod and Milestone's WheelConfig.ini use.
# Get-DirectInputDevices (toolkit) carries the two COM marshalling workarounds
# that used to be inlined here; this keeps the property names the rest of the
# script reads.
function Get-Wheels {
    Get-DirectInputDevices | ForEach-Object {
        [pscustomobject]@{ Key = $_.Key; Name = $_.Name; Type = $_.Type; FFB = $_.ForceFeedback }
    }
}

Step "Detecting your wheel"
if ($Product) {
    $productKey = $Product.ToLower()
    Ok "using the key you gave: $productKey"
} else {
    $devs = @(Get-Wheels)
    if (-not $devs) { Die "No DirectInput game controllers attached. Plug the wheel in and switch it on." }
    # A wheel is force-feedback capable and not a plain gamepad. Direct-drive
    # bases report as 0x18 (six-degrees-of-freedom) rather than 0x16 (driving),
    # which is the whole reason this mod exists, so accept both.
    $wheels = @($devs | Where-Object { $_.FFB -and $_.Type -ne 0x15 })
    if (-not $wheels) { $wheels = $devs }
    if ($wheels.Count -eq 1) {
        $productKey = $wheels[0].Key
        Ok "$($wheels[0].Name)  (key $productKey$(if($wheels[0].Type -eq 0x18){', reports as 6-DOF - exactly what this fixes'}))"
    } else {
        Say "  Several candidates:"
        for ($i = 0; $i -lt $wheels.Count; $i++) {
            Say "    [$($i+1)] $($wheels[$i].Name)  key=$($wheels[$i].Key)"
        }
        $pick = Read-Host "  Which is your wheel? (1-$($wheels.Count))"
        $sel = $wheels[[int]$pick - 1]
        if (-not $sel) { Die "invalid choice" }
        $productKey = $sel.Key
        Ok "$($sel.Name)  (key $productKey)"
    }
}

# ------------------------------------------------------------------ install
Step "Installing"

# The DLL is locked while the game runs, and the game also rewrites its own
# WheelConfig.ini on exit - so refuse rather than fail halfway.
$running = Get-Process -EA SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($target.Path, [StringComparison]::OrdinalIgnoreCase) }
if ($running) {
    Warn "$($running[0].ProcessName) is running - the files are locked."
    Die  "Close the game completely, then run this again."
}

$destDll = Join-Path $target.Path 'dinput8.dll'
if (Test-Path $destDll) {
    if ((Get-FileHash $destDll).Hash -ne (Get-FileHash $dll).Hash) {
        $mine = Select-String -Path $destDll -Pattern 'milestone_mod' -Quiet -EA SilentlyContinue
        if (-not $mine) {
            Warn "A DIFFERENT dinput8.dll is already here - FFB Arcade Plugin, DevReorder or similar."
            Warn "Only one can exist in a folder. Aborting rather than break it."
            Die "Move the existing dinput8.dll aside first if you are sure."
        }
    }
}
Copy-Item $dll $destDll -Force
Ok "dinput8.dll"

$iniSrc = Join-Path $root "games\$($target.Name.ToLower() -replace '\s','')\milestone_mod.ini"
if (-not (Test-Path $iniSrc)) { $iniSrc = Join-Path $root 'games\gravel\milestone_mod.ini' }
$ini = Get-Content $iniSrc -Raw
$ini = $ini -replace '(?m)^product=.*', "product=$productKey"
$ini = $ini -replace '(?m)^port=.*',    "port=$Port"
$ini = $ini -replace '(?m)^format=.*',  "format=$Format"
$destIni = Join-Path $target.Path 'milestone_mod.ini'
if (Test-Path $destIni) {
    Copy-Item $destIni "$destIni.bak" -Force
    Warn "existing milestone_mod.ini backed up to milestone_mod.ini.bak"
}
Set-Content $destIni $ini -NoNewline
Ok "milestone_mod.ini  (product=$productKey, port=$Port, format=$Format)"

# ---------------------------------------------------- the wheel whitelist
if (-not $SkipWheelConfig -and $target.Root) {
    $wc = Join-Path $target.Root "$(Split-Path (Split-Path (Split-Path $target.Path -Parent) -Parent) -Leaf)\Config\WindowsNoEditor\WheelConfig.ini"
    if (-not (Test-Path $wc)) {
        $wc = Get-ChildItem $target.Root -Recurse -Filter 'WheelConfig.ini' -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }
    if ($wc -and (Test-Path $wc)) {
        Step "Adding the wheel to the game's device list"
        if ((Get-Content $wc -Raw) -match [regex]::Escape("/Wheel.Config/$productKey")) {
            Ok "already listed"
        } else {
            $py = Get-Command python -EA SilentlyContinue
            if ($py) {
                & python (Join-Path $root 'tools\wheelconfig.py') --ini $wc --product $productKey `
                    --name "Wheel $productKey" --steer Axis1 --polarity low | Out-Null
                Ok "added (run the game's wheel calibration once)"
                Warn "pedal axes are a guess - run tools\Measure-WheelAxes.ps1 to set them properly"
            } else {
                Warn "Python not found, so WheelConfig.ini was left alone."
                Warn "Add the wheel manually, or install Python and re-run."
            }
        }
    }
}

# ------------------------------------------------------------------- done
Step "Done"
Say @"
  Next:
    1. In SimHub choose the game matching format=$Format
         fh4  -> Forza Horizon 4  or  Forza Horizon 5
         fm7  -> Forza Motorsport 7
       and set its UDP port to $Port.
    2. Launch the game and drive.

  If nothing shows up, milestone_mod.log appears next to the game exe and
  SimHub's own log (SimHub\Logs\SimHub.txt) says whether it accepted the
  data. See docs\troubleshooting.md.
"@ 'Gray'
