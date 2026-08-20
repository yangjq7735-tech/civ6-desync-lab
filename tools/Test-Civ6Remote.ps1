[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^SHA256:[A-Za-z0-9+/]+={0,2}$')]
    [string]$ExpectedHostFingerprint,

    [string]$IdentityFile = (Join-Path $env:USERPROFILE '.ssh\civ6_desync_lab_ed25519'),

    [ValidateRange(1, 65535)]
    [int]$Port = 22,

    [ValidateRange(1, 30)]
    [int]$ConnectTimeoutSeconds = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-RequiredCommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Required OpenSSH command '$Name' was not found."
    }

    return $command.Source
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$TargetPort,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($HostName, $TargetPort)
        return ($task.Wait($TimeoutMilliseconds) -and $client.Connected)
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

$identityPath = [System.IO.Path]::GetFullPath($IdentityFile)
if (-not (Test-Path -LiteralPath $identityPath -PathType Leaf)) {
    throw "SSH identity file was not found at '$identityPath'."
}

$sshPath = Get-RequiredCommandPath -Name 'ssh.exe'
$sshKeygenPath = Get-RequiredCommandPath -Name 'ssh-keygen.exe'
$sshKeyscanPath = Get-RequiredCommandPath -Name 'ssh-keyscan.exe'
$timeoutMilliseconds = $ConnectTimeoutSeconds * 1000

if (-not (Test-TcpPort -HostName $ComputerName -TargetPort $Port -TimeoutMilliseconds $timeoutMilliseconds)) {
    throw "SSH port $Port is not reachable at '$ComputerName'. Verify PC B is awake, sshd is running, and its Private/LocalSubnet firewall rule is active."
}

$temporaryKnownHosts = Join-Path ([System.IO.Path]::GetTempPath()) (
    'civ6-ssh-known-hosts-{0}' -f ([guid]::NewGuid().ToString('N'))
)

try {
    $scanOutput = @(
        & $sshKeyscanPath `
            -T $ConnectTimeoutSeconds `
            -p $Port `
            -t ed25519 `
            $ComputerName 2>$null
    )

    $hostKeyLines = @($scanOutput | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($hostKeyLines.Count -ne 1) {
        throw "Expected one ED25519 host key from '$ComputerName'; received $($hostKeyLines.Count)."
    }

    $hostKeyLines | Set-Content -LiteralPath $temporaryKnownHosts -Encoding ascii
    $fingerprintOutput = @(& $sshKeygenPath -lf $temporaryKnownHosts -E sha256 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "ssh-keygen could not calculate the PC B host fingerprint: $($fingerprintOutput -join ' ')"
    }

    $fingerprintMatch = [regex]::Match(
        ($fingerprintOutput -join ' '),
        'SHA256:[A-Za-z0-9+/]+={0,2}'
    )
    if (-not $fingerprintMatch.Success) {
        throw "No SHA-256 host fingerprint was found in ssh-keygen output: $($fingerprintOutput -join ' ')"
    }

    $actualFingerprint = $fingerprintMatch.Value
    if ($actualFingerprint -cne $ExpectedHostFingerprint) {
        throw "PC B host-key mismatch. Expected '$ExpectedHostFingerprint' but received '$actualFingerprint'. Refusing to connect."
    }

    $remoteProbe = @'
$result = [ordered]@{
    computerName      = $env:COMPUTERNAME
    userName          = $env:USERNAME
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    capturedAtUtc     = [DateTime]::UtcNow.ToString('o')
}
$result | ConvertTo-Json -Compress
'@
    $encodedProbe = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($remoteProbe)
    )
    $destination = '{0}@{1}' -f $UserName, $ComputerName
    $sshArguments = @(
        '-i', $identityPath,
        '-p', [string]$Port,
        '-o', 'BatchMode=yes',
        '-o', ('ConnectTimeout={0}' -f $ConnectTimeoutSeconds),
        '-o', 'IdentitiesOnly=yes',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', ('UserKnownHostsFile={0}' -f $temporaryKnownHosts),
        $destination,
        'powershell.exe',
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        $encodedProbe
    )

    $probeOutput = @(& $sshPath @sshArguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "SSH key authentication failed for '$destination': $($probeOutput -join ' ')"
    }

    $remoteJson = $probeOutput -join [Environment]::NewLine
    try {
        $remote = $remoteJson | ConvertFrom-Json
    }
    catch {
        throw "PC B returned unexpected probe output instead of JSON: $remoteJson"
    }

    [pscustomobject][ordered]@{
        connectionVerified = $true
        computerName       = $ComputerName
        port               = $Port
        userName           = $UserName
        hostFingerprint    = $actualFingerprint
        remoteComputerName = $remote.computerName
        remoteUserName     = $remote.userName
        powershellVersion  = $remote.powershellVersion
        capturedAtUtc      = $remote.capturedAtUtc
    } | Format-List

    Write-Host 'PASS: PC B SSH host identity and key authentication verified.'
}
finally {
    if (Test-Path -LiteralPath $temporaryKnownHosts -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryKnownHosts -Force
    }
}
