param([string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'InstallPackage.psm1') -Force
$version = ([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
$source = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE) { throw 'Source commit could not be read.' }
if (& git -C $root status --porcelain --untracked-files=no) { throw 'Commit the built binaries and source before packaging.' }
$name = "milestone-wheel-tools-$version-$($source.Substring(0,8))"
$destination = Join-Path $OutputRoot $name
if (Test-Path -LiteralPath $destination) { throw "Package already exists: $destination" }
[IO.Directory]::CreateDirectory($destination) | Out-Null
$files = @(Get-PackageFiles)
$manifest = @()
foreach ($relative in ($files | Sort-Object -Unique)) {
    $from = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $from)) { throw "Package input missing: $relative" }
    $to = Join-Path $destination $relative
    [IO.Directory]::CreateDirectory((Split-Path $to -Parent)) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to
    $manifest += [pscustomobject]@{ Path=$relative.Replace('\','/'); SHA256=(Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$metadata = [pscustomobject]@{ Product='milestone-wheel-tools'; Version=$version; SourceCommit=$source; CreatedUtc=[DateTime]::UtcNow.ToString('o'); Files=$manifest }
[IO.File]::WriteAllText((Join-Path $destination 'package-manifest.json'), ($metadata | ConvertTo-Json -Depth 6))
Assert-PackageManifest $destination
$zip = "$destination.zip"
Compress-Archive -Path (Join-Path $destination '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Output $destination
Get-FileHash -LiteralPath $zip -Algorithm SHA256
