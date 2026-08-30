<#
.SYNOPSIS
    Measure a wheel's pedal axes and emit the matching Gravel WheelConfig lines.

.DESCRIPTION
    Milestone games (Gravel, MXGP, MotoGP, Ride) map pedals in WheelConfig.ini as

        Wheel_Brake=Axis6&<scale>&<offset>

    where the axis number is a DirectInput slot and the two floats map the axis's
    normalised 0..1 travel onto the game's 0..1 pedal range:

        released -> 0.0     fully pressed -> 1.0

    Logitech and Fanatec pedals idle at MAXIMUM, so they need the inverted
    &-1.0&1.0. A MOZA idles at MINIMUM, so it needs &1.0&0.0. Getting this
    backwards leaves the game believing a pedal is permanently held down, which
    breaks the rebind screen: the "press a control" listener latches onto the
    stuck axis and never sees the button you actually press.

    This walks through each pedal, records which axis moved and in which
    direction, and prints the correct config lines. -Apply writes them.

    AXIS NUMBERING
    Reads via the multimedia joystick API, whose six axes correspond to the
    DirectInput slots Gravel counts as:

        X -> Axis1    Y -> Axis2    Z -> Axis3
        R -> Axis6 (Rz)   U -> Axis7 (Slider0)   V -> Axis8 (Slider1)

    Rx/Ry (Axis4/Axis5) are not visible here. If a pedal reports on none of the
    six, it is on one of those two and needs a DirectInput-level capture.

.EXAMPLE
    .\Measure-WheelAxes.ps1
    .\Measure-WheelAxes.ps1 -Apply
#>
[CmdletBinding()]
param(
    [int]$JoystickId = -1,
    [int]$SecondsPerPedal = 6,
    [switch]$Apply,
    [string]$WheelConfig = 'D:\Program Files (x86)\Steam\steamapps\common\Gravel\gravel\Config\WindowsNoEditor\WheelConfig.ini',
    [string]$Section = '0006346e'
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class MM {
  [StructLayout(LayoutKind.Sequential)]
  public struct JOYINFOEX {
    public int dwSize, dwFlags, dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos;
    public int dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2;
  }
  [DllImport("winmm.dll")] public static extern int joyGetPosEx(int id, ref JOYINFOEX pji);
}
'@ -ErrorAction SilentlyContinue

# winmm axis -> the Axis number Gravel uses
$AxisMap = [ordered]@{ X = 1; Y = 2; Z = 3; R = 6; U = 7; V = 8 }

function Read-Axes([int]$id) {
    $ji = New-Object MM+JOYINFOEX
    $ji.dwSize = [Runtime.InteropServices.Marshal]::SizeOf($ji)
    $ji.dwFlags = 0xFF
    if ([MM]::joyGetPosEx($id, [ref]$ji) -ne 0) { return $null }
    [ordered]@{ X=$ji.dwXpos; Y=$ji.dwYpos; Z=$ji.dwZpos; R=$ji.dwRpos; U=$ji.dwUpos; V=$ji.dwVpos; Buttons=$ji.dwButtons }
}

# ---------------------------------------------------------------- find device
if ($JoystickId -lt 0) {
    foreach ($i in 0..15) { if (Read-Axes $i) { $JoystickId = $i; break } }
}
if ($JoystickId -lt 0) { throw "No joystick found. Is the wheel powered on and connected?" }
Write-Host "Using joystick slot $JoystickId" -ForegroundColor Cyan

function Sample-Window([string]$label, [int]$seconds) {
    Write-Host ""
    Write-Host "  >>> $label" -ForegroundColor Yellow
    for ($i = 3; $i -ge 1; $i--) { Write-Host "      starting in $i..." ; Start-Sleep -Milliseconds 700 }
    Write-Host "      GO - $seconds seconds" -ForegroundColor Green

    $min = @{}; $max = @{}
    foreach ($k in $AxisMap.Keys) { $min[$k] = [int]::MaxValue; $max[$k] = [int]::MinValue }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $seconds) {
        $a = Read-Axes $JoystickId
        if ($null -eq $a) { continue }
        foreach ($k in $AxisMap.Keys) {
            if ($a[$k] -lt $min[$k]) { $min[$k] = $a[$k] }
            if ($a[$k] -gt $max[$k]) { $max[$k] = $a[$k] }
        }
    }
    Write-Host "      done." -ForegroundColor DarkGray
    return @{ Min = $min; Max = $max }
}

Write-Host ""
Write-Host "Keep hands and feet OFF the wheel and pedals for the first step." -ForegroundColor Cyan
$rest = Sample-Window "REST - do not touch anything" 3

Write-Host ""
Write-Host "Resting values:" -ForegroundColor Cyan
foreach ($k in $AxisMap.Keys) {
    "    {0} (Axis{1,-1})  rest = {2}" -f $k, $AxisMap[$k], $rest.Min[$k]
}

$pedals = @(
    @{ Name = 'Accelerator'; Prompt = 'Press the THROTTLE fully, hold a moment, release' },
    @{ Name = 'Brake';       Prompt = 'Press the BRAKE fully, hold a moment, release' },
    @{ Name = 'Clutch';      Prompt = 'Press the CLUTCH fully (skip if none - just wait)' },
    @{ Name = 'Handbrake';   Prompt = 'Pull the HANDBRAKE fully (skip if none - just wait)' }
)

$results = @()
foreach ($p in $pedals) {
    $s = Sample-Window $p.Prompt $SecondsPerPedal
    # the axis that travelled furthest from its resting value
    $best = $null; $bestTravel = 0
    foreach ($k in $AxisMap.Keys) {
        $r = $rest.Min[$k]
        $travel = [Math]::Max([Math]::Abs($s.Max[$k] - $r), [Math]::Abs($r - $s.Min[$k]))
        if ($travel -gt $bestTravel) { $bestTravel = $travel; $best = $k }
    }
    if ($bestTravel -lt 3000) {
        Write-Host ("      no movement detected for {0} - skipping" -f $p.Name) -ForegroundColor DarkGray
        continue
    }
    $r = $rest.Min[$best]
    $pressedHigh = ($s.Max[$best] - $r) -ge ($r - $s.Min[$best])
    # released must map to 0.0 and pressed to 1.0
    #   idles LOW  -> scale 1.0  offset 0.0
    #   idles HIGH -> scale -1.0 offset 1.0
    $scale  = if ($pressedHigh) { '1.0' }  else { '-1.0' }
    $offset = if ($pressedHigh) { '0.0' }  else { '1.0' }
    $results += [pscustomobject]@{
        Pedal   = $p.Name
        Axis    = "Axis$($AxisMap[$best])"
        Winmm   = $best
        Rest    = $r
        Min     = $s.Min[$best]
        Max     = $s.Max[$best]
        Travel  = $bestTravel
        Line    = "Wheel_$($p.Name)=Axis$($AxisMap[$best])&$scale&$offset"
    }
    "      -> {0} is {1} ({2})  rest={3} range={4}..{5}" -f $p.Name, "Axis$($AxisMap[$best])", $best, $r, $s.Min[$best], $s.Max[$best]
}

Write-Host ""
Write-Host "================ RESULT ================" -ForegroundColor Cyan
if (-not $results) { Write-Host "  Nothing detected. Are the pedals connected to the base?" -ForegroundColor Red; return }
$results | Format-Table Pedal, Axis, Winmm, Rest, Min, Max, Travel -AutoSize
Write-Host "WheelConfig.ini lines for [/Wheel.Config/$Section]:" -ForegroundColor Cyan
$results | ForEach-Object { "    $($_.Line)" }

# a pedal that idles at an extreme AND never leaves it is what breaks rebinding
$stuck = $results | Where-Object { $_.Travel -lt 8000 }
if ($stuck) {
    Write-Host ""
    Write-Host "WARNING: these barely moved - check they are the right pedal:" -ForegroundColor Yellow
    $stuck | ForEach-Object { "    $($_.Pedal) travelled only $($_.Travel)" }
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Re-run with -Apply to write these into WheelConfig.ini (Gravel must be closed)." -ForegroundColor DarkGray
    return
}

# ------------------------------------------------------------------- apply
if (Get-Process -Name 'gravel*' -EA SilentlyContinue) {
    throw "Gravel is running - it rewrites WheelConfig.ini on exit. Close it first."
}
if (-not (Test-Path $WheelConfig)) { throw "not found: $WheelConfig" }
Copy-Item $WheelConfig "$WheelConfig.bak-measure" -Force

$text = [IO.File]::ReadAllText($WheelConfig)
$pattern = "(?s)(\[/Wheel\.Config/$Section\].*?)(?=\r\n\[/Wheel\.Config/|$)"
$m = [regex]::Match($text, $pattern)
if (-not $m.Success) { throw "section [/Wheel.Config/$Section] not found" }
$block = $m.Groups[1].Value
foreach ($r in $results) {
    $key = ($r.Line -split '=')[0]
    # [^\r\n]* stops before the CR so the file's CRLF endings survive
    $block = [regex]::Replace($block, "(?m)^$key=[^\r\n]*", $r.Line)
}
$text = $text.Remove($m.Groups[1].Index, $m.Groups[1].Length).Insert($m.Groups[1].Index, $block)
[IO.File]::WriteAllText($WheelConfig, $text)
Write-Host ""
Write-Host "Written. Backup: $WheelConfig.bak-measure" -ForegroundColor Green
Write-Host "Now run the in-game wheel calibration." -ForegroundColor Green
