Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'SetupUx.psm1')

function Get-ByteHash([byte[]]$Bytes) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Assert-PackagePath([string]$Path, [string]$AllowedRoot) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "Install path is outside the selected game: $full" }
    return $full
}

function Write-PackageBytes([string]$Path, [byte[]]$Bytes) {
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    $temp = Join-Path (Split-Path $Path -Parent) ('.dbce-write-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temp, $Path, "$temp.previous")
            Remove-Item -LiteralPath "$temp.previous"
        } else { [IO.File]::Move($temp, $Path) }
    } finally { if ([IO.File]::Exists($temp)) { Remove-Item -LiteralPath $temp } }
}

function Invoke-PackageInstall {
    param([object[]]$Entries, [string]$AllowedRoot, [string]$BackupRoot,
          [scriptblock]$BeforeWrite, [int]$FailAfterWrite = -1)
    $BackupRoot = Assert-PackagePath $BackupRoot $AllowedRoot
    if (Test-Path -LiteralPath $BackupRoot) { throw 'The backup folder already exists; choose a new install transaction.' }
    $seen = @{}
    $items = @()
    foreach ($entry in $Entries) {
        $path = Assert-PackagePath $entry.Path $AllowedRoot
        if ($seen.ContainsKey($path)) { throw "Duplicate install target: $path" }
        $seen[$path] = $true
        $old = if ([IO.File]::Exists($path)) { ,([IO.File]::ReadAllBytes($path)) } else { $null }
        $data = [byte[]]$entry.Bytes
        $items += [pscustomobject]@{
            Path=$path; Bytes=$data; NewHash=(Get-ByteHash $data)
            Original=$old; OriginalHash=$(if ($null -ne $old) { Get-ByteHash $old } else { $null })
            Backup=$(if ($null -ne $old) { Join-Path $BackupRoot (('{0:D3}-' -f $items.Count) + [IO.Path]::GetFileName($path)) } else { $null })
        }
    }
    if ($BeforeWrite) { & $BeforeWrite }
    [IO.Directory]::CreateDirectory($BackupRoot) | Out-Null
    foreach ($item in $items) { if ($null -ne $item.Original) { [IO.File]::WriteAllBytes($item.Backup, $item.Original) } }
    $record = @($items | Select-Object Path,OriginalHash,NewHash,Backup)
    [IO.File]::WriteAllText((Join-Path $BackupRoot 'manifest.json'), ($record | ConvertTo-Json -Depth 5))
    $applied = @()
    try {
        foreach ($item in $items) {
            if ($BeforeWrite) { & $BeforeWrite }
            $current = if ([IO.File]::Exists($item.Path)) { Get-ByteHash ([IO.File]::ReadAllBytes($item.Path)) } else { $null }
            if ($current -cne $item.OriginalHash) { throw "Another process changed $($item.Path); install stopped." }
            if ($item.NewHash -ceq $item.OriginalHash) { continue }
            $applied += $item
            Write-PackageBytes $item.Path $item.Bytes
            if ($applied.Count -eq $FailAfterWrite) { throw 'Injected fixture install failure.' }
        }
    } catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        [array]::Reverse($applied)
        foreach ($item in $applied) {
            try {
                if ($BeforeWrite) { & $BeforeWrite }
                $current = if ([IO.File]::Exists($item.Path)) { Get-ByteHash ([IO.File]::ReadAllBytes($item.Path)) } else { $null }
                if ($current -ceq $item.OriginalHash) { continue }
                if ($current -cne $item.NewHash) { throw 'Changed externally; left untouched.' }
                if ($null -ne $item.Original) { Write-PackageBytes $item.Path $item.Original }
                else { Remove-Item -LiteralPath $item.Path }
            } catch { $rollbackErrors += "$($item.Path): $($_.Exception.Message)" }
        }
        if ($rollbackErrors.Count) { throw "$failure Rollback needs attention: $($rollbackErrors -join '; '). Backups: $BackupRoot" }
        throw "$failure Previous files restored. Backups: $BackupRoot"
    }
    [pscustomobject]@{ BackupRoot=$BackupRoot; Files=$record; ChangedFiles=$applied.Count }
}

function Add-WheelProfile([string]$Text, [string]$Product, [string]$Name) {
    if ($Product -notmatch '^[0-9a-fA-F]{8}$') { throw 'Wheel identity must be eight hexadecimal digits.' }
    if ($Text -notmatch "\r\n") { throw 'WheelConfig.ini must retain its CRLF line endings.' }
    if ((Get-WheelBlock $Text $Product).Success) { return $Text }
    $template = Get-WheelBlock $Text 'c262046d'
    if (-not $template.Success) { throw 'The verified Gravel wheel template was not found. Existing mappings were kept.' }
    $block = $template.Value -replace '^\[/Wheel\.Config/\w+\]', "[/Wheel.Config/$Product]"
    $block = $block -replace '(?m)^(Wheel_\w+)=[^\r\n]*', '$1='
    $block = [regex]::Replace($block, '(?m)^ProductName=[^\r\n]*', { "ProductName=$Name" })
    return $Text.TrimEnd("`r","`n") + "`r`n`r`n" + $block.TrimEnd("`r","`n") + "`r`n"
}

function Invoke-PackageRemoval {
    param([object[]]$Entries, [string]$AllowedRoot, [string]$BackupRoot, [scriptblock]$BeforeWrite)
    $BackupRoot = Assert-PackagePath $BackupRoot $AllowedRoot
    if (Test-Path -LiteralPath $BackupRoot) { throw 'The removal backup folder already exists.' }
    $items = @()
    $seen = @{}
    foreach ($entry in $Entries) {
        $path = Assert-PackagePath $entry.Path $AllowedRoot
        if ($seen.ContainsKey($path)) { throw "Duplicate removal target: $path" }
        $seen[$path] = $true
        $bytes = [IO.File]::ReadAllBytes($path)
        $hash = Get-ByteHash $bytes
        if ($hash -ine $entry.Hash) { throw "File changed before removal: $path" }
        $items += [pscustomobject]@{ Path=$path; Bytes=$bytes; Hash=$hash; Backup=(Join-Path $BackupRoot (('{0:D3}-' -f $items.Count) + [IO.Path]::GetFileName($path))) }
    }
    if ($BeforeWrite) { & $BeforeWrite }
    [IO.Directory]::CreateDirectory($BackupRoot) | Out-Null
    foreach ($item in $items) { [IO.File]::WriteAllBytes($item.Backup, $item.Bytes) }
    [IO.File]::WriteAllText((Join-Path $BackupRoot 'manifest.json'), (@($items | Select-Object Path,Hash,Backup) | ConvertTo-Json -Depth 5))
    $removed = @()
    try {
        foreach ($item in $items) {
            if ($BeforeWrite) { & $BeforeWrite }
            if ((Get-ByteHash ([IO.File]::ReadAllBytes($item.Path))) -cne $item.Hash) { throw "File changed during removal: $($item.Path)" }
            $removed += $item
            Remove-Item -LiteralPath $item.Path -ErrorAction Stop
        }
    } catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        [array]::Reverse($removed)
        foreach ($item in $removed) {
            try {
                if ($BeforeWrite) { & $BeforeWrite }
                if ([IO.File]::Exists($item.Path)) {
                    if ((Get-ByteHash ([IO.File]::ReadAllBytes($item.Path))) -cne $item.Hash) { throw 'External replacement left untouched.' }
                    continue
                }
                Write-PackageBytes $item.Path $item.Bytes
            } catch { $rollbackErrors += "$($item.Path): $($_.Exception.Message)" }
        }
        if ($rollbackErrors.Count) { throw "$failure Removal rollback needs attention: $($rollbackErrors -join '; '). Backups: $BackupRoot" }
        throw "$failure Removed files restored. Backups: $BackupRoot"
    }
    [pscustomobject]@{ BackupRoot=$BackupRoot; RemovedFiles=$removed.Count }
}

function Get-SetupPackageFiles {
    @('WheelSetup.ps1','WheelSetup.bat','Uninstall.ps1','Uninstall.bat','tools\SetupUx.psm1',
      'tools\InstallPackage.psm1','lib\toolkit\powershell\DbceWheel.psm1','dist\wheelprobe.exe','VERSION','QUICKSTART.md',
      'docs\troubleshooting.md','docs\forza-format.md')
}

function Get-PackageFiles {
    @('Install.ps1','Install.bat','README.md','LICENSE','dist\dinput8.dll','games\gravel\milestone_mod.ini','lib\toolkit\VERSION',
      'docs\directinput-sixdof.md','docs\UX-OVERNIGHT-2026-09-16.md') + @(Get-SetupPackageFiles) | Sort-Object -Unique
}

function Assert-PackageManifest([string]$Root) {
    $manifestPath = Join-Path $Root 'package-manifest.json'
    if (-not [IO.File]::Exists($manifestPath)) { throw 'Package manifest missing. Extract the complete ZIP; source developers must build and run tools\Package.ps1 first.' }
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    if ($manifest.Product -cne 'milestone-wheel-tools' -or $manifest.SourceCommit -notmatch '^[a-fA-F0-9]{40}$') { throw 'Package identity is invalid. Extract a fresh complete package.' }
    $versionPath = Join-Path $Root 'VERSION'
    if (-not [IO.File]::Exists($versionPath) -or $manifest.Version -cne ([IO.File]::ReadAllText($versionPath)).Trim()) { throw 'Package version does not match its manifest.' }
    $expected = @(Get-PackageFiles | ForEach-Object { $_.Replace('\','/') })
    $files = @($manifest.Files)
    if ($files.Count -ne $expected.Count) { throw 'Package manifest file count is incorrect.' }
    $seen = @{}
    foreach ($file in $files) {
        if ($file.Path -cnotin $expected -or $seen.ContainsKey($file.Path)) { throw "Unexpected or duplicate package path: $($file.Path)" }
        $seen[$file.Path] = $true
        $path = Assert-PackagePath (Join-Path $Root $file.Path) $Root
        if (-not [IO.File]::Exists($path)) { throw "Package file missing: $($file.Path). Extract the complete ZIP again." }
        if ($file.SHA256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-ByteHash ([IO.File]::ReadAllBytes($path))) -ine $file.SHA256) {
            throw "Package hash mismatch: $($file.Path). Extract the complete ZIP again; no game files were changed."
        }
    }
}

Export-ModuleMember -Function Get-ByteHash,Assert-PackagePath,Invoke-PackageInstall,Invoke-PackageRemoval,Add-WheelProfile,Get-SetupPackageFiles,Get-PackageFiles,Assert-PackageManifest
