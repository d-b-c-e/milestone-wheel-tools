param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'tools\SetupUx.psm1') -Force
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('milestone-ux-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$checks = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert $threw $Message
}
$oldLocal = $env:LOCALAPPDATA
$oldFixture = $env:MILESTONE_UX_FIXTURE
try {
    $preference = Join-Path $fixture 'settings-view.json'
    Assert ((Get-SettingsView $preference) -eq 'Simple') 'New users must start in Simple.'
    [IO.File]::WriteAllText($preference, '{}')
    Assert ((Get-SettingsView $preference) -eq 'Simple') 'An empty preference object must start in Simple.'
    [IO.File]::WriteAllText($preference, '{"Other":"kept"}')
    Assert ((Get-SettingsView $preference) -eq 'Simple') 'Upgrades without a view must start in Simple.'
    [IO.File]::WriteAllText($preference, '{"Other":"kept","View":"Unknown"}')
    Assert ((Get-SettingsView $preference) -eq 'Simple') 'Unknown view must fall back to Simple.'
    Save-SettingsView $preference 'Advanced'
    Assert ((Get-SettingsView $preference) -eq 'Advanced') 'Explicit Advanced must persist.'
    Assert ((Get-Content $preference -Raw | ConvertFrom-Json).Other -eq 'kept') 'View save lost another preference.'
    Save-SettingsView $preference 'Simple'
    Assert ((Get-SettingsView $preference) -eq 'Simple') 'Explicit Simple must persist.'
    $lock = [IO.File]::Open($preference, 'Open', 'Read', 'None')
    try { Assert-Throws { Save-SettingsView $preference 'Advanced' } 'A denied view save must report failure.' }
    finally { $lock.Dispose() }
    Assert ((Get-SettingsView $preference) -eq 'Simple') 'A failed view save changed the previous choice.'
    [IO.File]::WriteAllText($preference, '{broken')
    Assert-Throws { Get-SettingsView $preference } 'Malformed preference needs a visible failure.'
    Assert-Throws { Save-SettingsView $preference 'Advanced' } 'Malformed preference must not be silently overwritten.'
    Remove-Item -LiteralPath $preference
    Assert-Throws { Save-SettingsView (Join-Path $preference 'child.json') 'Wrong' } 'Invalid view cannot be saved.'

    $text = "[/Wheel.Config/0006346e]`r`nProductName=Fixture wheel`r`nWheel_Steer=Axis1&1.0&0.0`r`nWheel_Accelerator=Axis3&1.0&0.0`r`nWheel_Brake=Axis6&1.0&0.0`r`nWheel_Handbrake=Axis7&1.0&0.0`r`nWheel_Clutch=`r`nWheel_RightTrigger=Button9`r`nWheel_Special_Left=Button8`r`nForceFeedback=0.0`r`nMaxRotationAngle=540.0`r`nCustomOwnerValue=42`r`n`r`n[/Wheel.Config/second]`r`nWheel_Handbrake=Axis2&1.0&0.0`r`n"
    $changed = Set-WheelField $text '0006346e' 'Wheel_Handbrake' 'Axis3&-1.0&1.0'
    Assert ((Get-WheelField $changed '0006346e' 'Wheel_RightTrigger') -eq 'Button9') 'Axis edits must preserve handbrake button.'
    Assert ((Get-WheelField $changed 'second' 'Wheel_Handbrake') -eq 'Axis2&1.0&0.0') 'Other device was changed.'
    Assert ((Get-WheelField $changed '0006346e' 'ForceFeedback') -eq '0.0') 'FFB Off must be preserved.'
    Assert ($changed -notmatch '(?<!\r)\n') 'CRLF was damaged.'
    Assert-Throws { Set-WheelField $text '0006346e' 'Unknown' '1' } 'Missing fields must not report a false save.'
    Assert ((Format-WheelAssignment 'Button128') -eq 'Button 128') 'Button labels must be one-based.'
    Assert ((Format-WheelAssignment 'Axis3&-1.0&1.0') -eq 'Axis 3 (inverted)') 'Simple must not dump raw transforms.'

    $low = Find-AxisMapping @('AX 0 0 0 0 0 0 0 0') @('AX 0 0 65535 0 0 0 0 0')
    Assert ($low.Value -eq 'Axis3&1.0&0.0') 'Low-rest polarity incorrect.'
    $high = Find-AxisMapping @('AX 0 0 65535 0 0 0 0 0') @('AX 0 0 0 0 0 0 0 0')
    Assert ($high.Value -eq 'Axis3&-1.0&1.0') 'High-rest polarity incorrect.'
    Assert-Throws { Find-AxisMapping @('AX 0 0 0 0 0 0 0 0') @('AX 0 0 0 0 0 0 0 0') } 'No movement must preserve the old mapping.'
    Assert-Throws { Find-AxisMapping @('AX 0 0 0 0 0 0 0 0') @('AX 65535 65535 0 0 0 0 0 0') } 'Ambiguous movement must not bind arbitrarily.'
    Assert-Throws { Find-AxisMapping @('AX -1 0 0 0 0 0 0 0') @('AX 0 0 65535 0 0 0 0 0') } 'Malformed device input must fail visibly.'

    $wc = Join-Path $fixture 'Gravel\gravel\Config\WindowsNoEditor\WheelConfig.ini'
    [IO.Directory]::CreateDirectory((Split-Path $wc -Parent)) | Out-Null
    [IO.File]::WriteAllText($wc, $text)
    $backup = Save-WheelConfig $wc $text $changed
    Assert ([IO.File]::ReadAllText($backup) -ceq $text) 'Save must back up original mappings.'
    Assert ([IO.File]::ReadAllText($wc) -ceq $changed) 'Save did not apply exactly the candidate.'
    Assert-Throws { Save-WheelConfig $wc $text $changed } 'Concurrent owner edits must not be overwritten.'
    [IO.File]::WriteAllText($wc, $text)
    $lock = [IO.File]::Open($wc, 'Open', 'Read', 'None')
    try { Assert-Throws { Save-WheelConfig $wc $text $changed } 'A denied mapping save must report failure.' }
    finally { $lock.Dispose() }
    Assert ([IO.File]::ReadAllText($wc) -ceq $text) 'A failed mapping save changed the old bindings.'

    # A tiny fixture executable emits recorded input text. It never loads DirectInput.
    $probeFolder = Join-Path $fixture 'dist'
    [IO.Directory]::CreateDirectory($probeFolder) | Out-Null
    $source = Join-Path $fixture 'probe.cs'
    [IO.File]::WriteAllText($source, @'
using System;
using System.IO;
class FixtureProbe {
    static void Main(string[] args) {
        if (args[0] == "DEVICES") { Console.WriteLine("DEV 0006346e DRIVING 1 Fixture wheel"); return; }
        string file = Environment.GetEnvironmentVariable("MILESTONE_UX_FIXTURE");
        int count = File.Exists(file) ? Int32.Parse(File.ReadAllText(file)) : 0;
        File.WriteAllText(file, (count + 1).ToString());
        Console.WriteLine(count % 2 == 0 ? "AX 0 0 65535 0 0 0 0 0" : "AX 0 0 0 0 0 0 0 0");
    }
}
'@)
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:exe "/out:$probeFolder\wheelprobe.exe" $source
    if ($LASTEXITCODE) { throw 'Fixture input-reader compilation failed.' }
    $env:MILESTONE_UX_FIXTURE = Join-Path $fixture 'sample-count.txt'
    $env:LOCALAPPDATA = Join-Path $fixture 'local'
    [IO.Directory]::CreateDirectory($env:LOCALAPPDATA) | Out-Null
    foreach ($sub in 'tools','lib\toolkit\powershell','games\gravel') { [IO.Directory]::CreateDirectory((Join-Path $fixture $sub)) | Out-Null }
    Copy-Item (Join-Path $repo 'WheelSetup.ps1') $fixture
    Copy-Item (Join-Path $repo 'Install.ps1') $fixture
    Copy-Item (Join-Path $repo 'Uninstall.ps1') $fixture
    Copy-Item (Join-Path $repo 'tools\SetupUx.psm1') (Join-Path $fixture 'tools')
    Copy-Item (Join-Path $repo 'games\gravel\milestone_mod.ini') (Join-Path $fixture 'games\gravel')
    [IO.File]::WriteAllText((Join-Path $fixture 'lib\toolkit\powershell\DbceWheel.psm1'), 'function Get-SteamLibraries { @() }; Export-ModuleMember -Function Get-SteamLibraries')
    [IO.File]::WriteAllText((Join-Path $fixture 'dist\dinput8.dll'), 'milestone_mod fixture - never loaded')
    function Read-Host($Prompt) {
        if (-not $global:MilestoneUxFixtureAnswers.Count) { throw "Fixture prompt was not expected: $Prompt" }
        $value = $global:MilestoneUxFixtureAnswers.Dequeue()
        Write-Host "  $Prompt : $value"
        return $value
    }
    function Get-Process { @() }
    function Run-Setup([string[]]$Choices) {
        $global:MilestoneUxFixtureAnswers = New-Object 'Collections.Generic.Queue[string]'
        foreach ($choice in $Choices) { $global:MilestoneUxFixtureAnswers.Enqueue($choice) }
        & (Join-Path $fixture 'WheelSetup.ps1') -GamePath (Split-Path $wc -Parent) -PreferencesPath $preference
        Assert ($global:MilestoneUxFixtureAnswers.Count -eq 0) 'Fixture interaction ended before all actions.'
    }
    Run-Setup @('2','v','2','r','','v','1','3','4','5','6','x')
    Assert ([IO.File]::ReadAllText($wc) -ceq $text) 'View changes or navigation changed mappings.'
    Assert ((Get-SettingsView $preference) -eq 'Simple') 'Round trip did not retain explicit Simple.'
    Run-Setup @('2','a4','b','','','','s')
    Assert ([IO.File]::ReadAllText($wc) -ceq $text) 'Cancelled handbrake capture changed mappings.'
    Run-Setup @('2','a4','b','','','s','s')
    Assert ((Get-WheelField ([IO.File]::ReadAllText($wc)) '0006346e' 'Wheel_Handbrake') -eq 'Axis3&-1.0&1.0') 'Accepted individual handbrake calibration was not saved.'
    Assert ((Get-WheelField ([IO.File]::ReadAllText($wc)) '0006346e' 'Wheel_RightTrigger') -eq 'Button9') 'Accepted handbrake axis removed its button.'

    $game = Join-Path $fixture 'game-binaries'
    [IO.Directory]::CreateDirectory($game) | Out-Null
    $config = Join-Path $game 'milestone_mod.ini'
    $custom = [IO.File]::ReadAllText((Join-Path $repo 'games\gravel\milestone_mod.ini'))
    $custom = Set-ModSetting $custom 'telemetry' 'enabled' '0'
    $custom = Set-ModSetting $custom 'telemetry' 'port' '9123'
    $custom = Set-ModSetting $custom 'telemetry' 'host' '192.0.2.25'
    $custom = Set-ModSetting $custom 'ffb' 'gain' '0.25'
    [IO.File]::WriteAllText($config, $custom)
    & (Join-Path $fixture 'Install.ps1') -GamePath $game -SkipWheelConfig
    Assert ([IO.File]::ReadAllText($config) -ceq $custom) 'Ordinary update replaced owner settings.'
    & (Join-Path $fixture 'Install.ps1') -GamePath $game -SkipWheelConfig -Port 9456
    $updated = [IO.File]::ReadAllText($config)
    Assert ((Get-ModSetting $updated 'telemetry' 'port') -eq '9456') 'Explicit connection override was ignored.'
    Assert ((Get-ModSetting $updated 'telemetry' 'enabled') -eq '0') 'Explicit port override enabled telemetry.'
    Assert ((Get-ModSetting $updated 'telemetry' 'host') -eq '192.0.2.25') 'Explicit port override changed host.'
    Assert ((Get-ModSetting $updated 'ffb' 'gain') -eq '0.25') 'Explicit port override changed tune.'
    Assert (@(Get-ChildItem $game -Filter '*.bak-*').Count -eq 1) 'Explicit update did not create one settings backup.'
    & (Join-Path $fixture 'Uninstall.ps1') -GamePath $game
    Assert (-not (Test-Path (Join-Path $game 'dinput8.dll'))) 'Uninstall must remove its own proxy.'
    Assert ([IO.File]::ReadAllText($config) -ceq $updated) 'Ordinary uninstall must retain personal settings.'
    Assert (@(Get-ChildItem $game -Filter '*.bak-*').Count -eq 1) 'Ordinary uninstall must retain backups.'
    [IO.File]::WriteAllText((Join-Path $game 'dinput8.dll'), 'another proxy')
    & (Join-Path $fixture 'Uninstall.ps1') -GamePath $game
    Assert ([IO.File]::ReadAllText((Join-Path $game 'dinput8.dll')) -eq 'another proxy') 'Uninstall must preserve another proxy.'
    $freshGame = Join-Path $fixture 'fresh-game'
    [IO.Directory]::CreateDirectory($freshGame) | Out-Null
    & (Join-Path $fixture 'Install.ps1') -GamePath $freshGame -SkipWheelConfig -Product '11112222'
    $fresh = [IO.File]::ReadAllText((Join-Path $freshGame 'milestone_mod.ini'))
    Assert ((Get-ModSetting $fresh 'proxy' 'product') -eq '11112222') 'Fresh install must use the chosen wheel.'
    Assert ((Get-ModSetting $fresh 'telemetry' 'port') -eq '5300') 'Fresh install receiver port changed.'
    Assert ((Get-ModSetting $fresh 'telemetry' 'format') -eq 'fh4') 'Fresh install receiver format changed.'
    Write-Host "PASS: $checks offline UX/migration checks. No game or hardware was opened."
} finally {
    $env:LOCALAPPDATA = $oldLocal
    $env:MILESTONE_UX_FIXTURE = $oldFixture
    Remove-Variable -Name MilestoneUxFixtureAnswers -Scope Global -ErrorAction SilentlyContinue
    # Keep fixture and transcript paths for review; no recursive cleanup targets.
    Write-Host "Fixture: $fixture"
}
