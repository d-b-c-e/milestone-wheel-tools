param([string]$PackageRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PackageRoot 'tools\SetupUx.psm1') -Force
Import-Module (Join-Path $PackageRoot 'tools\InstallPackage.psm1') -Force
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('milestone-install-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$sourceRoot = $PackageRoot
$PackageRoot = Join-Path $fixture 'package'
[IO.Directory]::CreateDirectory($PackageRoot) | Out-Null
foreach ($relative in Get-PackageFiles) {
    $to = Join-Path $PackageRoot $relative
    [IO.Directory]::CreateDirectory((Split-Path $to -Parent)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $to
}
$manifestPath = Join-Path $PackageRoot 'package-manifest.json'
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'package-manifest.json')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'package-manifest.json') -Destination $manifestPath
} else {
    $files = @(Get-PackageFiles | ForEach-Object { [pscustomobject]@{ Path=$_.Replace('\','/'); SHA256=(Get-FileHash -LiteralPath (Join-Path $PackageRoot $_)).Hash } })
    $metadata = @{ Product='milestone-wheel-tools'; Version=([IO.File]::ReadAllText((Join-Path $PackageRoot 'VERSION'))).Trim(); SourceCommit=('a'*40); Files=$files }
    [IO.File]::WriteAllText($manifestPath, ($metadata | ConvertTo-Json -Depth 6))
}
$checks = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:checks++ }
function Reject([scriptblock]$Action, [string]$Message, [string]$Pattern) {
    $failed = $false
    $errorText = ''
    try { & $Action | Out-Null } catch { $failed = $true; $errorText = $_.Exception.Message }
    Assert $failed $Message
    if ($Pattern) { Assert ($errorText -match $Pattern) "Wrong failure for $Message : $errorText" }
}
function Entry([string]$Name, [string]$Text) { [pscustomobject]@{ Path=(Join-Path $fixture $Name); Bytes=[Text.Encoding]::UTF8.GetBytes($Text) } }
function Get-Process { @() }
try {
    Assert-PackageManifest $PackageRoot
    $manifestText = [IO.File]::ReadAllText($manifestPath)
    Remove-Item -LiteralPath $manifestPath
    Reject { & (Join-Path $PackageRoot 'Install.ps1') -GamePath $fixture } 'Missing manifest was accepted.' 'Package manifest missing'
    [IO.File]::WriteAllText($manifestPath, $manifestText)
    foreach ($relative in 'dist\dinput8.dll','WheelSetup.ps1') {
        $path = Join-Path $PackageRoot $relative
        $originalBytes = [IO.File]::ReadAllBytes($path)
        [IO.File]::AppendAllText($path, 'fixture alteration')
        Reject { & (Join-Path $PackageRoot 'Install.ps1') -GamePath $fixture } "Modified payload was accepted: $relative" 'Package hash mismatch'
        [IO.File]::WriteAllBytes($path, $originalBytes)
    }
    foreach ($change in 'duplicate','missing','unexpected','product','version') {
        $bad = $manifestText | ConvertFrom-Json
        switch ($change) {
            'duplicate' { $bad.Files[1].Path = $bad.Files[0].Path }
            'missing' { $bad.Files = @($bad.Files | Select-Object -Skip 1) }
            'unexpected' { $bad.Files[0].Path = '../escape.txt' }
            'product' { $bad.Product = 'other-product' }
            'version' { $bad.Version = '999' }
        }
        [IO.File]::WriteAllText($manifestPath, ($bad | ConvertTo-Json -Depth 6))
        Reject { Assert-PackageManifest $PackageRoot } "Invalid $change manifest was accepted."
    }
    [IO.File]::WriteAllText($manifestPath, $manifestText)
    $old = Join-Path $fixture 'existing.ini'
    $empty = Join-Path $fixture 'empty.ini'
    [IO.File]::WriteAllText($old, 'owner data')
    [IO.File]::WriteAllBytes($empty, [byte[]]@())
    $items = @((Entry 'existing.ini' 'replacement'),(Entry 'new\new.ini' 'new file'),(Entry 'empty.ini' 'new nonempty'))
    Reject { Invoke-PackageInstall $items $fixture (Join-Path $fixture 'rollback') -FailAfterWrite 3 } 'Injected write failure was not reported.'
    Assert ([IO.File]::ReadAllText($old) -ceq 'owner data') 'Rollback lost existing data.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $fixture 'new\new.ini'))) 'Rollback left a newly created file.'
    Assert ((Get-Item -LiteralPath $empty).Length -eq 0) 'Rollback did not preserve an empty file.'
    Assert ([IO.File]::ReadAllText((Join-Path $fixture 'rollback\000-existing.ini')) -ceq 'owner data') 'Backup bytes differ.'
    Assert ((Get-Item -LiteralPath (Join-Path $fixture 'rollback\002-empty.ini')).Length -eq 0) 'Empty-file backup missing.'
    Reject { Invoke-PackageInstall @((Entry '..\escape.ini' 'bad')) $fixture (Join-Path $fixture 'outside') } 'An install path escaped its game folder.'
    Reject { Invoke-PackageInstall @($items[0],$items[0]) $fixture (Join-Path $fixture 'duplicate') } 'Duplicate target was not rejected.'
    Assert ([IO.File]::ReadAllText($old) -ceq 'owner data') 'Preflight failure changed files.'
    $script:closedChecks = 0
    $guard = { $script:closedChecks++; if ($script:closedChecks -eq 3) { throw 'fixture game started' } }
    Reject { Invoke-PackageInstall $items $fixture (Join-Path $fixture 'guarded') -BeforeWrite $guard } 'Running-game guard was ignored.'
    Assert ([IO.File]::ReadAllText($old) -ceq 'owner data') 'Game-start failure did not restore previous file.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $fixture 'new\new.ini'))) 'Guard failed before writing a new file.'
    $script:closedChecks = 0
    $persistentGuard = { $script:closedChecks++; if ($script:closedChecks -ge 3) { throw 'fixture game remains open' } }
    Reject { Invoke-PackageInstall $items $fixture (Join-Path $fixture 'still-running') -BeforeWrite $persistentGuard } 'A still-running game did not block rollback writes.'
    Assert ([IO.File]::ReadAllText($old) -ceq 'replacement') 'Rollback wrote files while the game was reported open.'
    Assert ([IO.File]::ReadAllText((Join-Path $fixture 'still-running\000-existing.ini')) -ceq 'owner data') 'Interrupted rollback has no recovery copy.'
    [IO.File]::WriteAllText($old, 'owner data')
    $script:closedChecks = 0
    $concurrent = { $script:closedChecks++; if ($script:closedChecks -eq 2) { [IO.File]::WriteAllText($old, 'owner changed it') } }
    Reject { Invoke-PackageInstall $items $fixture (Join-Path $fixture 'concurrent') -BeforeWrite $concurrent } 'Concurrent edit was not detected.'
    Assert ([IO.File]::ReadAllText($old) -ceq 'owner changed it') 'Concurrent owner edit was overwritten.'
    [IO.File]::WriteAllText($old, 'owner data')
    $result = Invoke-PackageInstall $items $fixture (Join-Path $fixture 'success')
    Assert ($result.ChangedFiles -eq 3) 'Transaction did not install all files.'
    Assert ([IO.File]::ReadAllText($old) -ceq 'replacement') 'Successful install content is wrong.'
    Assert (@(Get-ChildItem $fixture -Recurse -Filter '.dbce-write-*').Count -eq 0) 'Temporary writer files leaked.'

    $template = "[/Wheel.Config/c262046d]`r`nProductName=Template`r`nWheel_Steer=Axis1&1.0&0.0`r`nWheel_RightTrigger=Button1`r`nMaxRotationAngle=900.0`r`n`r`n"
    $profile = Add-WheelProfile $template '0006346e' 'Fixture Wheel'
    Assert ($profile.Contains('ProductName=Fixture Wheel')) 'Fresh profile has no friendly name.'
    Assert ((Get-WheelField $profile '0006346e' 'Wheel_Steer') -eq '') 'Fresh profile guessed an axis.'
    Assert ((Get-WheelField $profile '0006346e' 'Wheel_RightTrigger') -eq '') 'Fresh profile guessed a button.'
    Assert ($profile -notmatch '(?<!\r)\n') 'Profile creation damaged CRLF.'
    Assert ((Add-WheelProfile $profile '0006346e' 'Another name') -ceq $profile) 'Existing profile was changed.'
    Reject { Add-WheelProfile '[unknown]' '0006346e' 'Wheel' } 'Missing verified profile template accepted.'

    # Real packaged scripts, inert exe sentinel and no native input execution.
    $gameRoot = Join-Path $fixture 'Gravel'
    $game = Join-Path $gameRoot 'gravel\Binaries\Win64'
    $wheel = Join-Path $gameRoot 'gravel\Config\WindowsNoEditor\WheelConfig.ini'
    [IO.Directory]::CreateDirectory($game) | Out-Null
    [IO.Directory]::CreateDirectory((Split-Path $wheel -Parent)) | Out-Null
    [IO.File]::WriteAllText((Join-Path $game 'gravel-Win64-Shipping.exe'), 'inert fixture: never execute')
    [IO.File]::WriteAllText($wheel, $profile)
    $ini = Join-Path $game 'milestone_mod.ini'
    $custom = "[proxy]`r`nproduct=0006346e`r`n[telemetry]`r`nenabled=0`r`nhost=192.0.2.25`r`nport=8000`r`nformat=custom-owner`r`n[custom]`r`nkeep=yes`r`n"
    [IO.File]::WriteAllText($ini, $custom, [Text.Encoding]::Unicode)
    $iniHash = Get-ByteHash ([IO.File]::ReadAllBytes($ini))
    $wheelHash = Get-ByteHash ([IO.File]::ReadAllBytes($wheel))
    [IO.File]::WriteAllText((Join-Path $game 'dinput8.dll'), 'another proxy')
    Reject { & (Join-Path $PackageRoot 'Install.ps1') -GamePath $game } 'An unrelated proxy was replaced.'
    Assert ([IO.File]::ReadAllText((Join-Path $game 'dinput8.dll')) -eq 'another proxy') 'Unrelated proxy bytes changed.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'DBCE-Wheel-Backups'))) 'Rejected install mutated backup state.'
    Remove-Item -LiteralPath (Join-Path $game 'dinput8.dll')
    & (Join-Path $PackageRoot 'Install.ps1') -GamePath $game
    Assert ((Get-ByteHash ([IO.File]::ReadAllBytes($ini))) -eq $iniHash) 'Update changed encoding or custom INI bytes.'
    Assert ((Get-ByteHash ([IO.File]::ReadAllBytes($wheel))) -eq $wheelHash) 'Update changed existing wheel profile.'
    $receipt = [IO.File]::ReadAllText((Join-Path $game 'milestone_install.json')) | ConvertFrom-Json
    Assert ($receipt.GameRoot -eq $gameRoot) 'Canonical game layout was resolved incorrectly.'
    foreach ($item in $receipt.OwnedFiles) { Assert ((Get-ByteHash ([IO.File]::ReadAllBytes($item.Path))) -eq $item.Hash) "Installed receipt mismatch: $($item.Path)" }
    $launcher = [IO.File]::ReadAllText((Join-Path $gameRoot 'Wheel settings.bat'))
    Assert ($launcher.Contains('-ModConfig') -and $launcher.Contains($ini)) 'Launcher omitted exact game configuration.'
    $lockedFile = Join-Path $game 'DBCE-Wheel-Setup\dist\wheelprobe.exe'
    $lock = [IO.File]::Open($lockedFile, 'Open', 'Read', [IO.FileShare]::Read)
    try { Reject { & (Join-Path $PackageRoot 'Uninstall.ps1') -GamePath $game } 'Locked late removal did not fail visibly.' }
    finally { $lock.Dispose() }
    foreach ($item in $receipt.OwnedFiles) { Assert ((Get-ByteHash ([IO.File]::ReadAllBytes($item.Path))) -eq $item.Hash) "Removal rollback did not restore $($item.Path)" }
    $modified = Join-Path $game 'DBCE-Wheel-Setup\QUICKSTART.md'
    [IO.File]::AppendAllText($modified, 'owner note')
    & (Join-Path $PackageRoot 'Uninstall.ps1') -GamePath $game
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'dinput8.dll'))) 'Uninstall left the installed proxy.'
    Assert ([IO.File]::ReadAllText($modified).EndsWith('owner note')) 'Uninstall deleted an edited setup file.'
    Assert ((Get-ByteHash ([IO.File]::ReadAllBytes($ini))) -eq $iniHash) 'Uninstall changed owner INI.'
    Assert ((Get-ByteHash ([IO.File]::ReadAllBytes($wheel))) -eq $wheelHash) 'Uninstall changed owner profile.'
    $other = Join-Path $fixture 'UnsupportedGame'
    [IO.Directory]::CreateDirectory($other) | Out-Null
    Reject { & (Join-Path $PackageRoot 'Install.ps1') -GamePath $other -Product 0006346e } 'Unsupported game folder accepted.'
    Assert (@(Get-ChildItem -LiteralPath $other).Count -eq 0) 'Unsupported game folder was modified.'
    $incomplete = Join-Path $fixture 'incomplete-package'
    [IO.Directory]::CreateDirectory((Join-Path $incomplete 'tools')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $incomplete 'lib\toolkit\powershell')) | Out-Null
    foreach ($relative in 'Install.ps1','tools\SetupUx.psm1','tools\InstallPackage.psm1','lib\toolkit\powershell\DbceWheel.psm1') {
        Copy-Item -LiteralPath (Join-Path $PackageRoot $relative) -Destination (Join-Path $incomplete $relative)
    }
    Reject { & (Join-Path $incomplete 'Install.ps1') -GamePath $game } 'An incomplete package was installed.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'dinput8.dll'))) 'Incomplete package changed the runtime.'
    Write-Host "PASS: $checks install/package checks. No game or hardware was opened."
} finally { Write-Host "Fixture: $fixture" }
