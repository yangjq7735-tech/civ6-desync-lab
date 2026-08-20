#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'Civ6DesyncLab\civ6-mcp'),
    [string]$ReferenceRepository = 'https://github.com/lmwilki/civ6-mcp.git'
)

$ErrorActionPreference = 'Stop'

function Find-Executable {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string[]]$Candidates = @()
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
    }
}

$winget = Find-Executable -Name 'winget.exe' -Candidates @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe')
)
if (-not $winget) {
    throw 'WinGet was not found. Install Microsoft App Installer, then rerun this script.'
}

$git = Find-Executable -Name 'git.exe' -Candidates @(
    'C:\Program Files\Git\cmd\git.exe',
    'C:\Program Files\Git\bin\git.exe'
)
if (-not $git) {
    Invoke-Native -FilePath $winget -ArgumentList @(
        'install', '--id', 'Git.Git', '-e', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    $git = Find-Executable -Name 'git.exe' -Candidates @(
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files\Git\bin\git.exe'
    )
}
if (-not $git) {
    throw 'Git installation completed but git.exe could not be located.'
}

$uvCandidates = @(
    Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') `
        -Filter 'uv.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
)
$uv = Find-Executable -Name 'uv.exe' -Candidates $uvCandidates
if (-not $uv) {
    Invoke-Native -FilePath $winget -ArgumentList @(
        'install', '--id', 'astral-sh.uv', '-e', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    $uvCandidates = @(
        Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') `
            -Filter 'uv.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    )
    $uv = Find-Executable -Name 'uv.exe' -Candidates $uvCandidates
}
if (-not $uv) {
    throw 'uv installation completed but uv.exe could not be located.'
}

$runtimeParent = Split-Path -Parent $RuntimeRoot
New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null

if (-not (Test-Path -LiteralPath $RuntimeRoot)) {
    Invoke-Native -FilePath $git -ArgumentList @('clone', $ReferenceRepository, $RuntimeRoot)
} elseif (-not (Test-Path -LiteralPath (Join-Path $RuntimeRoot '.git'))) {
    throw "Runtime path exists but is not a Git checkout: $RuntimeRoot"
}

$status = & $git -C $RuntimeRoot status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect the reference checkout at '$RuntimeRoot'."
}
if ($status) {
    throw "Reference checkout is not clean. Refusing to alter it: $RuntimeRoot"
}

Invoke-Native -FilePath $uv -ArgumentList @(
    'sync', '--frozen', '--extra', 'launcher-windows', '--directory', $RuntimeRoot
)
Invoke-Native -FilePath $uv -ArgumentList @(
    'run', '--frozen', '--directory', $RuntimeRoot, 'pytest', 'tests', '-q'
)

[ordered]@{
    status = 'ready'
    git = $git
    uv = $uv
    referenceRuntime = (Resolve-Path -LiteralPath $RuntimeRoot).Path
    referenceCommit = (& $git -C $RuntimeRoot rev-parse HEAD).Trim()
    tests = 'pytest tests -q passed'
} | ConvertTo-Json -Depth 3
