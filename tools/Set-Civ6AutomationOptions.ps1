[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CivRoot = (Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VI"),

    [ValidateRange(640, 16384)]
    [int]$RenderWidth = 1600,

    [ValidateRange(480, 16384)]
    [int]$RenderHeight = 900,

    [ValidateSet(0, 1)]
    [int]$FullScreen = 0,

    [ValidateSet(0, 1)]
    [int]$TunerEnabled = 1,

    [ValidateSet(0, 1)]
    [int]$PlayIntroVideo = 0,

    [ValidateSet(0, 1)]
    [int]$AutoEndTurn = 0,

    [ValidateRange(-1, 2)]
    [int]$TutorialLevel = -1,

    [ValidateSet(0, 1)]
    [int]$HasChosenTutorialLevel = 1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Update-CivOptionFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Updates,

        [Parameter(Mandatory = $true)]
        [string]$BackupStamp
    )

    $original = [System.IO.File]::ReadAllText($Path)
    $updated = $original
    $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }

    foreach ($entry in $Updates.GetEnumerator()) {
        $name = [string]$entry.Key
        $replacement = '{0} {1}' -f $name, $entry.Value
        $pattern = '(?m)^' + [regex]::Escape($name) + '[ \t]+[^\r\n]*'

        if ([regex]::IsMatch($updated, $pattern)) {
            $updated = [regex]::Replace($updated, $pattern, $replacement)
        }
        else {
            if ($updated.Length -gt 0 -and -not $updated.EndsWith("`n")) {
                $updated += $newline
            }
            $updated += $replacement + $newline
        }
    }

    if ($updated -eq $original) {
        return [pscustomobject]@{
            path       = $Path
            changed    = $false
            backupPath = $null
        }
    }

    $backupPath = '{0}.{1}.bak' -f $Path, $BackupStamp
    if ($PSCmdlet.ShouldProcess($Path, 'Back up and update Civ VI options')) {
        [System.IO.File]::Copy($Path, $backupPath, $false)
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $updated, $utf8NoBom)
    }

    return [pscustomobject]@{
        path       = $Path
        changed    = $true
        backupPath = $backupPath
    }
}

$resolvedRoot = [System.IO.Path]::GetFullPath($CivRoot)
$appOptionsPath = Join-Path $resolvedRoot 'AppOptions.txt'
$userOptionsPath = Join-Path $resolvedRoot 'UserOptions.txt'

$optionPaths = @($appOptionsPath, $userOptionsPath)
$missing = @($optionPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count -gt 0) {
    $missingList = $missing -join "', '"
    throw "Civ VI option files do not exist: '$missingList'. Launch Civ VI once, reach the main menu, and exit cleanly before running this script."
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$results = @(
    Update-CivOptionFile `
        -Path $appOptionsPath `
        -Updates ([ordered]@{
            EnableTuner  = $TunerEnabled
            FullScreen   = $FullScreen
            RenderWidth  = $RenderWidth
            RenderHeight = $RenderHeight
            PlayIntroVideo = $PlayIntroVideo
        }) `
        -BackupStamp $stamp
    Update-CivOptionFile `
        -Path $userOptionsPath `
        -Updates ([ordered]@{
            AutoEndTurn           = $AutoEndTurn
            TutorialLevel         = $TutorialLevel
            HasChosenTutorialLevel = $HasChosenTutorialLevel
        }) `
        -BackupStamp $stamp
)

foreach ($result in $results) {
    $backupDisplay = if ($null -eq $result.backupPath) { '(none)' } else { $result.backupPath }
    Write-Host ('{0}: changed={1}; backup={2}' -f $result.path, $result.changed, $backupDisplay)
}

if ($TunerEnabled -eq 1) {
    Write-Warning 'EnableTuner=1 disables Steam achievements. Set -TunerEnabled 0 for the strict vanilla V000 baseline.'
}
