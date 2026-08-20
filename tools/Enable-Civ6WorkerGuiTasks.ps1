#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TaskPrefix = 'Civ6DesyncLab',

    [string]$SteamPath = 'C:\Program Files (x86)\Steam\steam.exe',

    [string]$CapturePath = 'C:\ProgramData\Civ6DesyncLab\worker-screen.png'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function ConvertTo-EncodedPowerShellCommand {
    param([Parameter(Mandatory = $true)][string]$Script)

    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
}

if (-not (Test-Path -LiteralPath $SteamPath -PathType Leaf)) {
    throw "Steam was not found at '$SteamPath'. Pass the correct -SteamPath."
}

$captureDirectory = Split-Path -Parent $CapturePath
if (-not (Test-Path -LiteralPath $captureDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $captureDirectory -Force | Out-Null
}

$escapedSteamPath = $SteamPath.Replace("'", "''")
$escapedCapturePath = $CapturePath.Replace("'", "''")

$launchScript = @"
Start-Process -FilePath '$escapedSteamPath' -ArgumentList '-applaunch','289070'
"@

$captureScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
`$bitmap = New-Object System.Drawing.Bitmap(`$bounds.Width, `$bounds.Height)
`$graphics = [System.Drawing.Graphics]::FromImage(`$bitmap)
try {
    `$graphics.CopyFromScreen(`$bounds.Left, `$bounds.Top, 0, 0, `$bounds.Size)
    `$bitmap.Save('$escapedCapturePath', [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    `$graphics.Dispose()
    `$bitmap.Dispose()
}
"@

$launchAction = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -EncodedCommand ' + (ConvertTo-EncodedPowerShellCommand -Script $launchScript))
$captureAction = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -EncodedCommand ' + (ConvertTo-EncodedPowerShellCommand -Script $captureScript))

$principal = New-ScheduledTaskPrincipal `
    -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) `
    -LogonType Interactive `
    -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$launchTaskName = "$TaskPrefix-LaunchCiv6"
$captureTaskName = "$TaskPrefix-CaptureDesktop"

if ($PSCmdlet.ShouldProcess($launchTaskName, 'Register interactive Civ VI launch task')) {
    Register-ScheduledTask `
        -TaskName $launchTaskName `
        -Action $launchAction `
        -Principal $principal `
        -Settings $settings `
        -Description 'Launch Civ VI through Steam in the logged-in worker desktop.' `
        -Force | Out-Null
}

if ($PSCmdlet.ShouldProcess($captureTaskName, 'Register interactive worker desktop capture task')) {
    Register-ScheduledTask `
        -TaskName $captureTaskName `
        -Action $captureAction `
        -Principal $principal `
        -Settings $settings `
        -Description 'Capture the logged-in worker desktop for controller-side diagnostics.' `
        -Force | Out-Null
}

[ordered]@{
    status          = 'ready'
    user            = $principal.UserId
    launchTask      = $launchTaskName
    captureTask     = $captureTaskName
    capturePath     = $CapturePath
    steamPath       = (Resolve-Path -LiteralPath $SteamPath).Path
    interactiveOnly = $true
} | ConvertTo-Json -Depth 3
