<#
.SYNOPSIS
    Map wheel controls for a Milestone game without using its in-game menu.

.DESCRIPTION
    Milestone's rebind screen is unusable with many direct-drive wheels: an axis
    resting at an extreme reads as permanently deflected, so the "press a
    control" listener latches onto it and never sees the button you press. This
    does the same job from outside the game.

    It is action-oriented on purpose. These games bind in two layers -

        physical button  ->  logical slot   (WheelConfig.ini)
        logical slot     ->  game action    (settings.sav)

    - so putting "rewind" on a button actually means finding which Wheel_* slot
    RewindActivate listens to and pointing that slot at your button. You should
    not have to know that, so this works it out for you.

    Pedals are measured, never guessed: it watches which axis moves and in which
    direction, and derives the polarity from that. Copying another wheel's block
    is what leaves a game convinced a pedal is permanently held.

.PARAMETER GamePath
    Folder containing the game's WheelConfig.ini, if auto-detection fails.

.PARAMETER Product
    Device product key in hex, to skip the device menu.

.EXAMPLE
    .\WheelSetup.ps1
#>
[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$Product
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$probe = Join-Path $root 'tools\wheelprobe\wheelprobe.exe'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host "`n$m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "  OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  !    $m" -ForegroundColor Yellow }
function Die($m) { Write-Host "  X    $m" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $probe)) {
    Die "tools\wheelprobe\wheelprobe.exe is missing. Build it, or take it from the release."
}

# ---------------------------------------------------------------- the game
function Get-SteamLibraries {
    $bases = @()
    foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $v = Get-ItemProperty $k -EA SilentlyContinue
        foreach ($n in 'SteamPath', 'InstallPath') { if ($v -and $v.$n) { $bases += ($v.$n -replace '/', '\') } }
    }
    $bases += "${env:ProgramFiles(x86)}\Steam"
    $libs = @()
    foreach ($b in ($bases | Sort-Object -Unique)) {
        $vdf = Join-Path $b 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $libs += $b
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += $m.Groups[1].Value -replace '\\\\', '\'
            }
        }
    }
    $libs | Sort-Object -Unique
}

Say "Milestone wheel setup" 'White'
Head "Finding the game"
$wheelConfigs = @()
if ($GamePath) {
    $wheelConfigs = @(Get-ChildItem $GamePath -Recurse -Depth 4 -Filter 'WheelConfig.ini' -EA SilentlyContinue)
} else {
    # Always at <game>\<inner>\Config\WindowsNoEditor\WheelConfig.ini, so go
    # straight there. A blind -Recurse walks entire multi-GB game folders.
    foreach ($lib in Get-SteamLibraries) {
        $common = Join-Path $lib 'steamapps\common'
        if (-not (Test-Path $common)) { continue }
        foreach ($game in (Get-ChildItem $common -Directory -EA SilentlyContinue)) {
            foreach ($inner in (Get-ChildItem $game.FullName -Directory -EA SilentlyContinue)) {
                $c = Join-Path $inner.FullName 'Config\WindowsNoEditor\WheelConfig.ini'
                if (Test-Path $c) { $wheelConfigs += (Get-Item $c) }
            }
        }
    }
}
if (-not $wheelConfigs) { Die "No WheelConfig.ini found. Pass -GamePath <game folder>." }
if ($wheelConfigs.Count -gt 1) {
    Say "  Found several:"
    for ($i = 0; $i -lt $wheelConfigs.Count; $i++) { Say "    [$($i+1)] $($wheelConfigs[$i].FullName)" }
    $wc = $wheelConfigs[[int](Read-Host "  Which game? (1-$($wheelConfigs.Count))") - 1].FullName
} else { $wc = $wheelConfigs[0].FullName }
Ok $wc

# the game rewrites this file when it exits
$gameDir = $wc
while ($gameDir -and -not (Get-ChildItem $gameDir -Filter '*.exe' -EA SilentlyContinue)) { $gameDir = Split-Path $gameDir -Parent }
$running = Get-Process -EA SilentlyContinue | Where-Object { $_.Path -and $gameDir -and $_.Path.StartsWith($gameDir, [StringComparison]::OrdinalIgnoreCase) }
if ($running) { Die "$($running[0].ProcessName) is running - it rewrites WheelConfig.ini on exit. Close it first." }

# ------------------------------------------------- action -> slot, from the save
# settings.sav is a UE4 GVAS file whose ignitioninput block stores every binding
# as ActionName / KeyName property pairs. KeyName is a keyboard key, a Gamepad_*
# key, or the Wheel_* slot we care about.
function Get-ActionSlots {
    $sav = Get-ChildItem "$env:LOCALAPPDATA" -Recurse -Filter 'settings.sav' -Depth 4 -EA SilentlyContinue |
           Select-Object -First 1
    if (-not $sav) { return @{} }
    $b = [IO.File]::ReadAllBytes($sav.FullName)
    if ([Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'GVAS') { return @{} }

    # Walk UE4 tagged properties: FString name, FString type, int64 size, u8 guid, payload
    $map = @{}
    $pos = 0
    $needle = [Text.Encoding]::ASCII.GetBytes('ignitioninput')
    for ($i = 0; $i -lt $b.Length - $needle.Length; $i++) {
        $hit = $true
        for ($j = 0; $j -lt $needle.Length; $j++) { if ($b[$i + $j] -ne $needle[$j]) { $hit = $false; break } }
        if ($hit) { $pos = $i; break }
    }
    if (-not $pos) { return @{} }

    function ReadStr([byte[]]$buf, [ref]$o) {
        if ($o.Value + 4 -gt $buf.Length) { return $null }
        $n = [BitConverter]::ToInt32($buf, $o.Value); $o.Value += 4
        if ($n -eq 0) { return '' }
        if ($n -gt 0 -and $n -lt 512 -and $o.Value + $n -le $buf.Length) {
            $s = [Text.Encoding]::ASCII.GetString($buf, $o.Value, $n - 1); $o.Value += $n; return $s
        }
        if ($n -lt 0 -and $n -gt -512) {
            $n = -$n
            $s = [Text.Encoding]::Unicode.GetString($buf, $o.Value, ($n - 1) * 2); $o.Value += $n * 2; return $s
        }
        return $null
    }

    $o = $pos
    $action = $null
    while ($o -lt $b.Length - 8) {
        $save = $o
        $name = ReadStr $b ([ref]$o)
        if (-not $name -or $name -notmatch '^[\w]+$') { $o = $save + 1; continue }
        if ($name -eq 'None') { continue }
        $type = ReadStr $b ([ref]$o)
        if (-not $type -or $type -notlike '*Property') { $o = $save + 1; continue }
        $size = [BitConverter]::ToInt64($b, $o); $o += 9        # int64 size + guid flag
        if ($name -eq 'ActionName') { $p = $o; $action = ReadStr $b ([ref]$p) }
        elseif ($name -eq 'KeyName' -and $action) {
            $p = $o; $key = ReadStr $b ([ref]$p)
            if ($key -and $key.StartsWith('Wheel_')) {
                if (-not $map.ContainsKey($action)) { $map[$action] = $key }
            }
            $action = $null
        }
        $o += $size
    }
    $map
}

Head "Reading the game's action list"
$actionSlot = Get-ActionSlots
if ($actionSlot.Count) { Ok "$($actionSlot.Count) actions have a wheel binding" }
else { Warn "settings.sav not read - falling back to Gravel's known layout" }

# Gravel's defaults, verified by dumping settings.sav. Used when the save cannot
# be read, and to give friendly names to the actions worth binding.
$FRIENDLY = [ordered]@{
    'Gear up'          = @('GearUp',         'Wheel_RightShoulder')
    'Gear down'        = @('GearDown',       'Wheel_LeftShoulder')
    'Handbrake'        = @('Handbrake',      'Wheel_RightTrigger')
    'Rewind'           = @('RewindActivate', 'Wheel_LeftTrigger')
    'Change camera'    = @('SwitchCamera',   'Wheel_Special_Left')
    'Pause / start'    = @('Pause',          'Wheel_Special_Right')
    'Confirm'          = @('Confirm',        'Wheel_FaceButton_Bottom')
    'Back'             = @('Back',           'Wheel_FaceButton_Right')
    'Respawn'          = @('Respawn',        'Wheel_FaceButton_Top')
    'Photo mode'       = @('ReplayPhotoMode','Wheel_RightTrigger')
}

# --------------------------------------------------------------- the device
Head "Choosing the device"
$devs = @()
foreach ($line in (& $probe DEVICES)) {
    if ($line -match '^DEV (\w+) (\S+) (\d) (.+)$') {
        $devs += [pscustomobject]@{ Key = $Matches[1]; Type = $Matches[2]; Name = $Matches[4] }
    }
}
if (-not $devs) { Die "No DirectInput controllers attached." }
if ($Product) { $dev = $devs | Where-Object Key -eq $Product.ToLower() | Select-Object -First 1 }
if (-not $dev) {
    if ($devs.Count -eq 1) { $dev = $devs[0] }
    else {
        for ($i = 0; $i -lt $devs.Count; $i++) { Say "    [$($i+1)] $($devs[$i].Name)  ($($devs[$i].Key), $($devs[$i].Type))" }
        $dev = $devs[[int](Read-Host "  Which device? (1-$($devs.Count))") - 1]
    }
}
if (-not $dev) { Die "invalid choice" }
Ok "$($dev.Name)  key=$($dev.Key)"

# ------------------------------------------------------------------ helpers
function Sample($seconds) { & $probe $dev.Key $seconds }

function Read-Button($prompt, $seconds = 6) {
    Say "  $prompt" 'Yellow'
    Say "    (waiting $seconds seconds...)" 'DarkGray'
    $btn = $null
    foreach ($l in (Sample $seconds)) { if ($l -match '^BTN (\d+)$' -and -not $btn) { $btn = [int]$Matches[1] } }
    if ($btn) { Ok "button $btn" } else { Warn "nothing pressed" }
    $btn
}

$AXIS_NAMES = 'Axis1', 'Axis2', 'Axis3', 'Axis4', 'Axis5', 'Axis6', 'Axis7', 'Axis8'
function Read-Axis($prompt, $seconds = 6) {
    Say "  $prompt" 'Yellow'
    Say "    (waiting $seconds seconds...)" 'DarkGray'
    $min = @(); $max = @(); $first = $null
    foreach ($l in (Sample $seconds)) {
        if ($l -notmatch '^AX ') { continue }
        $v = $l.Substring(3) -split ' ' | ForEach-Object { [int]$_ }
        # the very first sample is DirectInput's pre-poll default of all 32767
        if (-not $first) { $first = $v; continue }
        if (-not $min.Count) { $min = $v.Clone(); $max = $v.Clone(); continue }
        for ($i = 0; $i -lt 8; $i++) {
            if ($v[$i] -lt $min[$i]) { $min[$i] = $v[$i] }
            if ($v[$i] -gt $max[$i]) { $max[$i] = $v[$i] }
        }
    }
    if (-not $min.Count) { Warn "no data"; return $null }
    $best = -1; $travel = 0
    for ($i = 0; $i -lt 8; $i++) { if (($max[$i] - $min[$i]) -gt $travel) { $travel = $max[$i] - $min[$i]; $best = $i } }
    if ($travel -lt 3000) { Warn "no movement detected"; return $null }
    # idles low -> &1.0&0.0 ; idles high -> &-1.0&1.0
    $restLow = ($min[$best] -lt (($max[$best] + $min[$best]) / 2))
    $pol = if ($restLow) { '1.0&0.0' } else { '-1.0&1.0' }
    Ok "$($AXIS_NAMES[$best])  range $($min[$best])..$($max[$best])  idles $(if($restLow){'low'}else{'high'})"
    [pscustomobject]@{ Axis = $AXIS_NAMES[$best]; Polarity = $pol }
}

# ------------------------------------------------- WheelConfig read / write
$nl = "`r`n"
$raw = [IO.File]::ReadAllText($wc)
if ($raw -notmatch "\r\n") { Die "WheelConfig.ini is not CRLF - refusing to guess line endings" }
$section = "[/Wheel.Config/$($dev.Key)]"
if ($raw -notmatch [regex]::Escape($section)) {
    Warn "this device has no section yet - it will be created from a shipped one"
    $tpl = [regex]::Match($raw, '\[/Wheel\.Config/c262046d\].*?(?=\r\n\[/Wheel\.Config/|\Z)', 'Singleline')
    if (-not $tpl.Success) { $tpl = [regex]::Match($raw, '\[/Wheel\.Config/\w+\].*?(?=\r\n\[/Wheel\.Config/|\Z)', 'Singleline') }
    $block = $tpl.Value -replace '^\[/Wheel\.Config/\w+\]', $section
    $block = $block -replace '(?m)^(Wheel_\w+)=Button\d+', '$1='          # start clean
    $block = $block -replace '(?m)^ProductName=.*', "ProductName=$($dev.Name)"
    $raw = $raw.TrimEnd("`r", "`n") + $nl + $nl + $block.TrimEnd("`r", "`n") + $nl
}

function Set-Field($key, $value) {
    $script:raw = [regex]::Replace($script:raw,
        "(?s)(\[/Wheel\.Config/$($dev.Key)\].*?)(?=\r\n\[/Wheel\.Config/|\Z)",
        {
            param($m)
            # [^\r\n]* stops before the CR so the file's CRLF endings survive
            [regex]::Replace($m.Groups[1].Value, "(?m)^$([regex]::Escape($key))=[^\r\n]*", "$key=$value")
        }, 1)
}
function Get-Field($key) {
    $m = [regex]::Match($raw, "(?s)\[/Wheel\.Config/$($dev.Key)\].*?(?=\r\n\[/Wheel\.Config/|\Z)")
    $f = [regex]::Match($m.Value, "(?m)^$([regex]::Escape($key))=([^\r\n]*)")
    if ($f.Success) { $f.Groups[1].Value } else { '' }
}

# ------------------------------------------------------------------- menu
$dirty = $false
while ($true) {
    Head "What would you like to do?"
    Say "    [1] Calibrate pedals   (measures which axis is which)"
    Say "    [2] Bind a control     (press the button you want to use)"
    Say "    [3] Show current mapping"
    Say "    [4] Save and exit"
    Say "    [5] Exit without saving"
    switch (Read-Host "  Choose") {
        '1' {
            Head "Pedal calibration"
            Say "  Work each pedal through its FULL travel when prompted." 'Gray'
            foreach ($p in @(
                @{ Field = 'Wheel_Steer';       Prompt = 'Turn the wheel fully left, then fully right' }
                @{ Field = 'Wheel_Accelerator'; Prompt = 'Press the THROTTLE fully, then release' }
                @{ Field = 'Wheel_Brake';       Prompt = 'Press the BRAKE fully, then release' }
                @{ Field = 'Wheel_Clutch';      Prompt = 'Press the CLUTCH fully (skip if none - just wait)' }
                @{ Field = 'Wheel_Handbrake';   Prompt = 'Pull the HANDBRAKE fully (skip if none - just wait)' }
            )) {
                $r = Read-Axis $p.Prompt
                if ($r) {
                    # steering is bidirectional and always uses the plain mapping
                    $v = if ($p.Field -eq 'Wheel_Steer') { "$($r.Axis)&1.0&0.0" } else { "$($r.Axis)&$($r.Polarity)" }
                    Set-Field $p.Field $v
                    $dirty = $true
                }
            }
        }
        '2' {
            Head "Bind a control"
            $names = @($FRIENDLY.Keys)
            for ($i = 0; $i -lt $names.Count; $i++) {
                $act, $fallback = $FRIENDLY[$names[$i]]
                $slot = if ($actionSlot.ContainsKey($act)) { $actionSlot[$act] } else { $fallback }
                $cur = Get-Field $slot
                Say ("    [{0}] {1,-16} -> {2,-26} {3}" -f ($i + 1), $names[$i], $slot, $(if ($cur) { "(now $cur)" } else { '' }))
            }
            $pick = [int](Read-Host "  Which control? (1-$($names.Count))") - 1
            if ($pick -lt 0 -or $pick -ge $names.Count) { Warn "invalid"; break }
            $act, $fallback = $FRIENDLY[$names[$pick]]
            $slot = if ($actionSlot.ContainsKey($act)) { $actionSlot[$act] } else { $fallback }
            $btn = Read-Button "Press the button you want for '$($names[$pick])'"
            if ($btn) {
                Set-Field $slot "Button$btn"
                Ok "$($names[$pick]) -> $slot = Button$btn"
                $dirty = $true
            }
        }
        '3' {
            Head "Current mapping for $($dev.Name)"
            $m = [regex]::Match($raw, "(?s)\[/Wheel\.Config/$($dev.Key)\].*?(?=\r\n\[/Wheel\.Config/|\Z)")
            foreach ($l in ($m.Value -split "`r`n")) {
                if ($l -match '^\w[\w_]*=(.+)$') { Say "    $l" }
            }
        }
        '4' {
            if ($dirty) {
                Copy-Item $wc "$wc.bak" -Force
                [IO.File]::WriteAllText($wc, $raw)
                $bare = ([regex]::Matches($raw, "(?<!\r)\n")).Count
                Ok "saved (backup: WheelConfig.ini.bak, bare LF: $bare)"
                Say "`n  Now run the game's wheel calibration once." 'Green'
            } else { Say "  nothing changed" }
            return
        }
        '5' { Say "  discarded"; return }
        default { Warn "pick 1-5" }
    }
}
