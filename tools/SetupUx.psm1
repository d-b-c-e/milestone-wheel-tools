# Offline-testable presentation and mapping helpers. No device acquisition here.
Set-StrictMode -Version Latest

function Get-SettingsView([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'Simple' }
    try { $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "Settings view could not be read. Your wheel mappings are unchanged. $($_.Exception.Message)" }
    if ($null -eq $state -or $state -isnot [pscustomobject]) { throw 'Settings view must be a JSON object. Your wheel mappings are unchanged.' }
    $property = $state.PSObject.Properties['View']
    if ($null -ne $property -and $property.Value -eq 'Advanced') { return 'Advanced' }
    return 'Simple'
}

function Save-SettingsView([string]$Path, [ValidateSet('Simple','Advanced')][string]$View) {
    $state = [pscustomobject]@{}
    if (Test-Path -LiteralPath $Path) { $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    if ($null -eq $state -or $state -isnot [pscustomobject]) { throw 'Settings view must be a JSON object. The previous file was kept.' }
    $state | Add-Member -NotePropertyName View -NotePropertyValue $View -Force
    $folder = Split-Path $Path -Parent
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $temp = Join-Path $folder ('.view-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, ($state | ConvertTo-Json -Depth 16))
        if (Test-Path -LiteralPath $Path) {
            # Windows PowerShell 5.1 marshals a null backup path as an invalid empty string.
            [IO.File]::Replace($temp, $Path, "$temp.previous")
            Remove-Item -LiteralPath "$temp.previous"
        }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}

function Get-WheelBlock([string]$Text, [string]$Product) {
    [regex]::Match($Text, '(?s)\[/Wheel\.Config/' + [regex]::Escape($Product) + '\].*?(?=\r\n\[/Wheel\.Config/|\Z)')
}

function Get-WheelField([string]$Text, [string]$Product, [string]$Key) {
    $block = Get-WheelBlock $Text $Product
    $field = [regex]::Match($block.Value, '(?m)^' + [regex]::Escape($Key) + '=([^\r\n]*)')
    if ($field.Success) { return $field.Groups[1].Value }
    return ''
}

function Set-WheelField([string]$Text, [string]$Product, [string]$Key, [string]$Value) {
    $block = Get-WheelBlock $Text $Product
    if (-not $block.Success) { throw 'This device has no wheel profile.' }
    $field = [regex]::Match($block.Value, '(?m)^' + [regex]::Escape($Key) + '=[^\r\n]*')
    if (-not $field.Success) { throw "This game profile does not expose $Key. The assignment was kept." }
    if ($Value -match '[\r\n]') { throw 'A mapping must fit on one line.' }
    # Literal insertion preserves dollar signs, other devices and CRLF endings.
    $updated = $block.Value.Remove($field.Index, $field.Length).Insert($field.Index, "$Key=$Value")
    return $Text.Remove($block.Index, $block.Length).Insert($block.Index, $updated)
}

function Format-WheelAssignment([string]$Value, [switch]$Advanced) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Not bound' }
    if ($Value -match '^Button(\d+)$') { $label = "Button $($Matches[1])" }
    elseif ($Value -match '^Axis(\d+)(?:&(-?[0-9.]+)&(-?[0-9.]+))?$') {
        $label = "Axis $($Matches[1])"
        if ($Matches.ContainsKey(2) -and $Matches[2].StartsWith('-')) { $label += ' (inverted)' }
    } else { $label = 'Existing custom assignment' }
    if ($Advanced) { return "$label  [$Value]" }
    return $label
}

function Get-AxisSamples([string[]]$Lines) {
    foreach ($line in $Lines) {
        if ($line -notmatch '^AX ((?:-?\d+ ){7}-?\d+)$') { continue }
        $values = @($Matches[1] -split ' ' | ForEach-Object { [int]$_ })
        if (@($values | Where-Object { $_ -lt 0 -or $_ -gt 65535 }).Count) { continue }
        # An object keeps each eight-value sample together in the pipeline.
        [pscustomobject]@{ Values = $values }
    }
}

function Find-AxisMapping([string[]]$RestLines, [string[]]$TravelLines, [switch]$Steering) {
    $rest = @(Get-AxisSamples $RestLines)
    $travel = @(Get-AxisSamples $TravelLines)
    if (-not $rest.Count -or -not $travel.Count) { throw 'No input received. Check the device connection and try again.' }
    $baseline = $rest[-1].Values
    $best = -1; $bestTravel = 0; $secondTravel = 0; $full = 0
    for ($axis = 0; $axis -lt 8; $axis++) {
        $values = @($travel | ForEach-Object { $_.Values[$axis] })
        $range = $values | Measure-Object -Minimum -Maximum
        if ($Steering) { $movement = $range.Maximum - $range.Minimum }
        else { $movement = [Math]::Max([Math]::Abs($range.Maximum - $baseline[$axis]), [Math]::Abs($range.Minimum - $baseline[$axis])) }
        if ($movement -gt $bestTravel) {
            $secondTravel = $bestTravel; $bestTravel = $movement; $best = $axis
            $full = if (($range.Maximum - $baseline[$axis]) -ge ($baseline[$axis] - $range.Minimum)) { $range.Maximum } else { $range.Minimum }
        } elseif ($movement -gt $secondTravel) { $secondTravel = $movement }
    }
    if ($bestTravel -lt 3000) { throw 'No clear movement detected. The previous assignment was kept.' }
    if ($secondTravel -ge ($bestTravel * 0.6)) { throw 'More than one axis moved. Move only the requested control and try again.' }
    $inverted = -not $Steering -and $full -lt $baseline[$best]
    $polarity = if ($inverted) { '-1.0&1.0' } else { '1.0&0.0' }
    [pscustomobject]@{ Axis = $best; Value = "Axis$($best + 1)&$polarity"; Inverted = $inverted; Rest = $baseline[$best]; Full = $full }
}

function Save-WheelConfig([string]$Path, [string]$Original, [string]$Text) {
    if ([IO.File]::ReadAllText($Path) -cne $Original) { throw 'The game or another tool changed the mappings. Close setup and reopen it before saving.' }
    if ($Text -match '(?<!\r)\n') { throw 'The mappings contain invalid line endings; nothing was saved.' }
    $temp = Join-Path (Split-Path $Path -Parent) ('.wheel-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backup = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,6))"
    try {
        [IO.File]::WriteAllText($temp, $Text)
        [IO.File]::Replace($temp, $Path, $backup)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
    return $backup
}

function Get-ModSetting([string]$Text, [string]$Section, [string]$Key) {
    $block = [regex]::Match($Text, '(?ms)^\[' + [regex]::Escape($Section) + '\][^\r\n]*\r?\n.*?(?=^\[|\z)')
    $field = [regex]::Match($block.Value, '(?m)^' + [regex]::Escape($Key) + '=([^\r\n]*)')
    if ($field.Success) { return $field.Groups[1].Value.Trim() }
    return ''
}

function Set-ModSetting([string]$Text, [string]$Section, [string]$Key, [string]$Value) {
    $block = [regex]::Match($Text, '(?ms)^\[' + [regex]::Escape($Section) + '\][^\r\n]*\r?\n.*?(?=^\[|\z)')
    if (-not $block.Success) { throw "Missing [$Section] configuration section. Existing settings were kept." }
    $field = [regex]::Match($block.Value, '(?m)^' + [regex]::Escape($Key) + '=[^\r\n]*')
    if (-not $field.Success) { throw "Missing $Key in [$Section]. Existing settings were kept." }
    $updated = $block.Value.Remove($field.Index, $field.Length).Insert($field.Index, "$Key=$Value")
    return $Text.Remove($block.Index, $block.Length).Insert($block.Index, $updated)
}

Export-ModuleMember -Function Get-SettingsView,Save-SettingsView,Get-WheelBlock,Get-WheelField,Set-WheelField,Format-WheelAssignment,Get-AxisSamples,Find-AxisMapping,Save-WheelConfig,Get-ModSetting,Set-ModSetting
