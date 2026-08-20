#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ControllerPublicKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMcDepdfnlefcsYnzJpWMFRPptZVbT5J/AnrHcGtFsUI civ6-desync-lab-automation'
)

$ErrorActionPreference = 'Stop'

$sshd = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
if (-not $sshd) {
    throw 'Windows OpenSSH Server is not installed. Install the OpenSSH Server optional capability, then rerun this script.'
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdministrator) {
    throw 'Run this script from an elevated PowerShell session on PC B.'
}

$sshProgramData = Join-Path $env:ProgramData 'ssh'
$authorizedKeys = Join-Path $sshProgramData 'administrators_authorized_keys'
New-Item -ItemType Directory -Path $sshProgramData -Force | Out-Null

$existingKeys = if (Test-Path -LiteralPath $authorizedKeys) {
    @(Get-Content -LiteralPath $authorizedKeys | Where-Object { $_.Trim() })
} else {
    @()
}

if ($existingKeys -notcontains $ControllerPublicKey) {
    Add-Content -LiteralPath $authorizedKeys -Value $ControllerPublicKey -Encoding ascii
}

# Windows OpenSSH rejects this file when inherited/user ACL entries remain.
& icacls.exe $authorizedKeys '/inheritance:r' | Out-Null
& icacls.exe $authorizedKeys '/grant:r' '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to apply the required ACL to '$authorizedKeys'."
}

Set-Service -Name 'sshd' -StartupType Automatic
Start-Service -Name 'sshd'

$firewallRuleName = 'Civ6DesyncLab-OpenSSH-Private'
$firewallRule = Get-NetFirewallRule -Name $firewallRuleName -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    New-NetFirewallRule `
        -Name $firewallRuleName `
        -DisplayName 'Civ6 Desync Lab OpenSSH (Private)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow `
        -Profile Private `
        -RemoteAddress LocalSubnet | Out-Null
} else {
    Set-NetFirewallRule -Name $firewallRuleName -Enabled True -Profile Private -Action Allow
}

$sshKeygen = Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe'
$hostPublicKey = Join-Path $sshProgramData 'ssh_host_ed25519_key.pub'
if (-not (Test-Path -LiteralPath $hostPublicKey)) {
    & $sshKeygen -A
}

$fingerprintLine = (& $sshKeygen -lf $hostPublicKey -E sha256 2>&1) -join ' '
$fingerprint = if ($fingerprintLine -match '(SHA256:[A-Za-z0-9+/=]+)') {
    $Matches[1]
} else {
    $fingerprintLine
}

$addresses = @(
    Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*'
        } |
        Select-Object InterfaceAlias, IPAddress, PrefixLength
)

[ordered]@{
    status                  = 'ready'
    computerName            = $env:COMPUTERNAME
    userName                = $env:USERNAME
    authorizedKeysPath      = $authorizedKeys
    controllerKeyInstalled  = $true
    controllerKeyFingerprint = 'SHA256:kbvA0ggH/viDLxqyts3Tfn3e2mTa0kijFrdkZDOTZgc'
    sshdStatus              = (Get-Service -Name 'sshd').Status.ToString()
    hostKeyFingerprint      = $fingerprint
    ipv4Addresses           = $addresses
} | ConvertTo-Json -Depth 4
