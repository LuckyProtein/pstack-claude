$ErrorActionPreference = 'Stop'

# A Linux Muse under WSL can reach this script through powershell.exe on the
# interop PATH. The sh hook owns that session, so stand down.
if ($env:MUSE_PLUGIN_ROOT -and $env:MUSE_PLUGIN_ROOT.StartsWith('/')) {
    exit 0
}
if ($PSScriptRoot -like '\\wsl*') {
    exit 0
}

# Muse runs hooks with a scrubbed environment, USERPROFILE among the
# variables dropped, so the profile root falls back to the OS folder.
$sheetRoot = $env:XDG_CONFIG_HOME
if (-not $sheetRoot) {
    $profile = if ($env:USERPROFILE) { $env:USERPROFILE } else { [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile) }
    $sheetRoot = Join-Path $profile '.config'
}
$sheet = Join-Path (Join-Path $sheetRoot 'muse') 'pstack-models.md'

function ReadSheetOrNull([string] $path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        # Windows PowerShell 5.1's `>` writes UTF-16 LE with a byte-order mark.
        $encoding = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [System.Text.Encoding]::Unicode } else { [System.Text.UTF8Encoding]::new($false) }
        $lines = $encoding.GetString($bytes).TrimStart([char]0xFEFF) -split "`n" | ForEach-Object { $_ -replace "`r$", '' }
        return , @($lines)
    } catch {
        return $null
    }
}

$sheetLines = ReadSheetOrNull $sheet
$found = $null -ne $sheetLines
if (-not $found) {
    $sheetLines = @()
}
if ($found -and $sheetLines -ccontains 'session hook: off') {
    exit 0
}

function TrimSheet([string] $s) {
    $s.Trim([char[]]" `t")
}

function TestRoleValue([string] $value) {
    if ($value -eq '') {
        return $false
    }
    foreach ($raw in $value.Split(',')) {
        $entry = TrimSheet $raw
        if ($entry -eq '') {
            return $false
        }
        if ($entry -cmatch '[ \t]+@([a-z]+)$' -and $efforts -ccontains $Matches[1]) {
            $entry = $entry.Substring(0, $entry.Length - $Matches[0].Length)
        }
        if ($entry -ceq 'inherit-parent' -or $entry -ceq 'auto') {
            continue
        }
        if ($entry -cnotmatch '^[a-z0-9][a-z0-9.-]*$') {
            return $false
        }
    }
    return $true
}

$roleLines = @()
if ($found) {
    # models.json is the one list of roles and effort levels. sheet.awk gets
    # the same list stamped in by the generator.
    $models = [System.IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) 'models.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $roles = @($models.roles | ForEach-Object { $_.role })
    $efforts = @($models.efforts)

    $valueOf = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in $sheetLines) {
        if ($line.Length -eq 0 -or $line -cmatch '^[ \t]') {
            continue
        }
        $colon = $line.IndexOf(':')
        if ($colon -lt 0) {
            continue
        }
        $key = TrimSheet $line.Substring(0, $colon)
        if ($roles -ccontains $key -or $key -ceq 'default effort') {
            $valueOf[$key] = TrimSheet $line.Substring($colon + 1)
        }
    }
    foreach ($role in $roles) {
        if ($valueOf.ContainsKey($role) -and (TestRoleValue $valueOf[$role])) {
            $roleLines += "$($role): $($valueOf[$role])"
        }
    }
    if ($valueOf.ContainsKey('default effort') -and ($valueOf['default effort'] -ceq 'session' -or $efforts -ccontains $valueOf['default effort'])) {
        $roleLines += "default effort: $($valueOf['default effort'])"
    }
}

$mandate = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'session-start-muse.md'), [System.Text.Encoding]::UTF8)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
if ($roleLines.Count -eq 0) {
    [Console]::Write($mandate)
    exit 0
}
$separator = if ($mandate.EndsWith("`n")) { "`n" } else { "`n`n" }
$note = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'session-start-muse-sheet.md'), [System.Text.Encoding]::UTF8).TrimEnd([char[]]"`r`n")
[Console]::Write($mandate + $separator + $note + "`n" + ($roleLines -join "`n") + "`n")
