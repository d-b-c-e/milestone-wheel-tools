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
    $previousText = $null
    $repair = $false
    if (Test-Path -LiteralPath $Path) {
        # Only an explicit view selection reaches this function. A read failure
        # is not permission to repair; malformed JSON is, with its bytes backed up.
        $previousText = [IO.File]::ReadAllText($Path)
        try { $state = $previousText | ConvertFrom-Json }
        catch { $repair = $true }
        if ($null -eq $state -or $state -isnot [pscustomobject]) { $repair = $true }
        if ($repair) { $state = [pscustomobject]@{} }
    }
    $state | Add-Member -NotePropertyName View -NotePropertyValue $View -Force
    $folder = Split-Path $Path -Parent
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $temp = Join-Path $folder ('.view-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temp, ($state | ConvertTo-Json -Depth 16))
        if (Test-Path -LiteralPath $Path) {
            if ([IO.File]::ReadAllText($Path) -cne $previousText) { throw 'The view preference changed in another setup window. Choose the view again.' }
            # Windows PowerShell 5.1 marshals a null backup path as an invalid empty string.
            $backup = if ($repair) { "$Path.invalid-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,6)).bak" } else { "$temp.previous" }
            [IO.File]::Replace($temp, $Path, $backup)
            if ($repair) { Write-Warning "View preference repaired. Previous file kept at: $backup. Game settings were not changed." }
            else { Remove-Item -LiteralPath $backup }
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

function Get-TelemetryBlock([string]$Text) {
    $blocks = [regex]::Matches($Text, '(?ims)^[ \t]*\[telemetry\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)')
    if ($blocks.Count -ne 1) { throw 'The settings need one [telemetry] section. Restore a known working configuration before editing.' }
    return $blocks[0]
}

function Get-TelemetryState([string]$Text) {
    $block = Get-TelemetryBlock $Text
    $values = @{}
    foreach ($key in 'enabled','host','port','format') {
        $fields = [regex]::Matches($block.Value, '(?im)^[ \t]*' + $key + '[ \t]*=([^\r\n]*)')
        if ($fields.Count -ne 1) { throw "Telemetry needs exactly one $key setting. Restore a known working configuration before editing." }
        $values[$key] = $fields[0].Groups[1].Value.Trim()
    }
    return [pscustomobject]$values
}

function Assert-TelemetryConnection([string]$Address, [string]$Port, [string]$Format) {
    # The unchanged runtime uses inet_pton(AF_INET), with no hostname lookup.
    if ($Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'Use a dotted IPv4 address, such as 127.0.0.1 for this PC. Hostnames and IPv6 are not supported by this mod.' }
    foreach ($part in ($Address -split '\.')) {
        if ([int]$part -gt 255 -or ($part.Length -gt 1 -and $part.StartsWith('0'))) { throw 'The receiver IPv4 address is invalid. Use four numbers from 0 to 255 without leading zeros.' }
    }
    if ($Address -eq '0.0.0.0' -or $Address -eq '255.255.255.255' -or [int]($Address -split '\.')[0] -ge 224) { throw 'Choose the receiver PC address. Unspecified, multicast and broadcast destinations are not supported here.' }
    $number = 0
    if ($Port -notmatch '^\d+$' -or -not [int]::TryParse($Port, [ref]$number) -or $number -lt 1 -or $number -gt 65535) { throw 'Port must be a whole number from 1 to 65535, matching the receiver.' }
    if ($Format -notin @('fh4','fm7','sled')) { throw 'Choose Forza Horizon 4/5, Forza Motorsport 7, or the Sled receiver format.' }
}

function Get-TelemetryReceiver([string]$Format) {
    switch ($Format) {
        'fh4' { return 'Forza Horizon 4 / 5 (324 bytes)' }
        'fm7' { return 'Forza Motorsport 7 (311 bytes)' }
        'sled' { return 'Forza Sled (232 bytes; physics only)' }
        default { return "Unrecognized saved format: $Format" }
    }
}

function Get-TelemetryConnectionSummary($State) {
    try { Assert-TelemetryConnection $State.host $State.port $State.format }
    catch { return 'Connection needs review in Advanced; saved values were kept.' }
    if ($State.host -eq '127.0.0.1' -and $State.port -eq '5300') {
        if ($State.format -eq 'fh4') { return 'Matches the fresh-installer connection preset.' }
        if ($State.format -eq 'fm7') { return 'Matches the shipped Gravel connection preset.' }
    }
    return 'Custom connection active. Review in Advanced.'
}

function Set-TelemetryFields([string]$Text, [hashtable]$Changes) {
    $state = Get-TelemetryState $Text
    foreach ($key in $Changes.Keys) {
        if ($key -notin @('enabled','host','port','format')) { throw "Telemetry edit cannot change $key." }
        if ([string]$Changes[$key] -match '[\r\n]') { throw 'A telemetry value must fit on one line.' }
    }
    if ($Changes.ContainsKey('enabled') -and [string]$Changes.enabled -notin @('0','1')) { throw 'Telemetry must be Off or On.' }
    $connectionKeys = @($Changes.Keys | Where-Object { $_ -in @('host','port','format') })
    if ($connectionKeys.Count -gt 0 -and $connectionKeys.Count -ne 3) { throw 'Apply the receiver address, port and format together.' }
    if ($connectionKeys.Count) { Assert-TelemetryConnection $Changes.host $Changes.port $Changes.format }
    elseif ($Changes.ContainsKey('enabled') -and [string]$Changes.enabled -eq '1') { Assert-TelemetryConnection $state.host $state.port $state.format }
    foreach ($key in $Changes.Keys) {
        $block = Get-TelemetryBlock $Text
        $field = [regex]::Match($block.Value, '(?im)^([ \t]*' + $key + '[ \t]*=)([^\r\n]*)')
        $updated = $block.Value.Remove($field.Index, $field.Length).Insert($field.Index, $field.Groups[1].Value + [string]$Changes[$key])
        $Text = $Text.Remove($block.Index, $block.Length).Insert($block.Index, $updated)
    }
    return $Text
}

function Save-TelemetryConfig([string]$Path, [string]$Original, [string]$Text) {
    if ($Text -ceq $Original) { return $null }
    if ([IO.File]::ReadAllText($Path) -cne $Original) { throw 'Another tool changed the telemetry settings. Cancel and reopen the editor before applying.' }
    $temp = Join-Path (Split-Path $Path -Parent) ('.telemetry-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backup = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0,6))"
    try {
        [IO.File]::WriteAllText($temp, $Text)
        [IO.File]::Replace($temp, $Path, $backup)
    } catch {
        throw [IO.IOException]::new('Could not save telemetry. Close the game or other editor, then retry. The previous settings were kept.', $_.Exception)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
    return $backup
}

Export-ModuleMember -Function Get-SettingsView,Save-SettingsView,Get-WheelBlock,Get-WheelField,Set-WheelField,Format-WheelAssignment,Get-AxisSamples,Find-AxisMapping,Save-WheelConfig,Get-ModSetting,Set-ModSetting,Get-TelemetryState,Assert-TelemetryConnection,Get-TelemetryReceiver,Get-TelemetryConnectionSummary,Set-TelemetryFields,Save-TelemetryConfig
