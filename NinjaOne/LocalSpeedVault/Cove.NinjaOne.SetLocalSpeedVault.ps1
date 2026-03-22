<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Set LocalSpeedVault
    # Adapted for NinjaOne from SetLocalSpeedVault.v03.ps1
    # Source Revision: v03 - 2021-03-06, Author: Eric Harless, SolarWinds MSP | N-able
    # NinjaOne Adaptation: 2026
# -----------------------------------------------------------#>

<# ----- Legal: ----
    # Sample scripts are not supported under any N-able support program or service.
    # The sample scripts are provided AS IS without warranty of any kind.
    # N-able expressly disclaims all implied warranties including, warranties
    # of merchantability or of fitness for a particular purpose.
    # In no event shall N-able or any other party be liable for damages arising
    # out of the use of or inability to use the sample scripts.
# -----------------------------------------------------------#>

<# ----- NinjaOne Behavior: ----
    # Run as a one-shot NinjaOne Script Policy after Cove deployment to configure the LSV path.
    # Reads mode, path, and optional credentials from NinjaOne device custom fields.
    # Modes: Local | Network | Disable
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  120 seconds
    #   Trigger:  One-shot (post-deployment or on LSV change)
    #
    # NinjaOne Custom Fields required (device-level):
    #   coveLsvMode      Text  - "Local", "Network", or "Disable"
    #   coveLsvPath      Text  - Local path (e.g. D:\SpeedVault) or UNC path (e.g. \\nas\share)
    #   coveLsvUsername  Text  - Network LSV only: username (e.g. workgroup\user or server\user)
    #   coveLsvPassword  Secure- Network LSV only: password (stored as NinjaOne Secure field)
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed
    #   - ClientTool.exe at C:\Program Files\Backup Manager\ClientTool.exe
    #   - Cannot modify LSV paths set via a Cove Profile
    #   - PowerShell 5.1+, run as System/Administrator
    #   - LSV is not supported for Documents Only license types
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

## ---- Read NinjaOne Custom Fields ----
$LSVMode     = Ninja-Property-Get 'coveLsvMode'
$LSVPath     = Ninja-Property-Get 'coveLsvPath'
$LSVUsername = Ninja-Property-Get 'coveLsvUsername'
$LSVPassword = Ninja-Property-Get 'coveLsvPassword'

## ---- Validate LSVMode ----
if ([string]::IsNullOrWhiteSpace($LSVMode)) {
    Write-Output "ERROR: coveLsvMode custom field is not set. Valid values: Local, Network, Disable"
    Exit 1
}

$LSVMode = $LSVMode.Trim()
if ($LSVMode -notin @("Local","Network","Disable")) {
    Write-Output "ERROR: coveLsvMode '$LSVMode' is invalid. Valid values: Local, Network, Disable"
    Exit 1
}

$clienttool = "C:\Program Files\Backup Manager\ClientTool.exe"
if (-not (Test-Path $clienttool)) {
    Write-Output "ERROR: ClientTool.exe not found at $clienttool - is Cove Backup Manager installed?"
    Exit 1
}

Write-Output "LSV Mode: $LSVMode"
if ($LSVPath) { Write-Output "LSV Path: $LSVPath" }

Switch ($LSVMode) {

    'Disable' {
        Write-Output "Disabling LocalSpeedVault..."
        & $clienttool control.setting.modify -name LocalSpeedVaultEnabled -value 0
        Write-Output "LocalSpeedVault disabled."
    }

    'Local' {
        if ([string]::IsNullOrWhiteSpace($LSVPath)) {
            Write-Output "ERROR: coveLsvPath must be set for Local mode (e.g. D:\SpeedVault)"
            Exit 1
        }
        ## Create path if it does not exist
        if (-not (Test-Path $LSVPath)) {
            Write-Output "LSV path '$LSVPath' not found - attempting to create..."
            try {
                New-Item -Type Directory -Path $LSVPath -Force | Out-Null
                Write-Output "Directory created: $LSVPath"
            } catch {
                Write-Output "ERROR: Cannot create LSV path '$LSVPath': $_"
                Exit 1
            }
        }
        if (-not (Test-Path $LSVPath)) {
            Write-Output "ERROR: LSV path '$LSVPath' could not be created or does not exist."
            Exit 1
        }
        Write-Output "Setting Local LSV path to: $LSVPath"
        & $clienttool control.setting.modify -name LocalSpeedVaultEnabled -value 1 -name LocalSpeedVaultLocation -value $LSVPath
        Write-Output "Local LSV configured successfully."
    }

    'Network' {
        if ([string]::IsNullOrWhiteSpace($LSVPath)) {
            Write-Output "ERROR: coveLsvPath must be set for Network mode (e.g. \\nas\share)"
            Exit 1
        }
        if ([string]::IsNullOrWhiteSpace($LSVUsername) -or [string]::IsNullOrWhiteSpace($LSVPassword)) {
            Write-Output "ERROR: coveLsvUsername and coveLsvPassword must both be set for Network mode"
            Exit 1
        }
        ## Warn if the share path is already accessible as a mapped drive (security risk)
        $parentPath = "\\" + ($LSVPath.Split("\") | Select-Object -Index 2)
        $existingDrive = Get-PSDrive | Where-Object { $_.DisplayRoot -like "*$parentPath*" }
        if ($existingDrive) {
            Write-Output "WARNING: A drive is already mapped to the LSV parent path '$parentPath'. This may not be a secure path."
            Write-Output "Mapped drive: $($existingDrive.Name) -> $($existingDrive.DisplayRoot)"
        }
        Write-Output "Setting Network LSV path to: $LSVPath (user: $LSVUsername)"
        & $clienttool control.setting.modify `
            -name LocalSpeedVaultEnabled  -value 1 `
            -name LocalSpeedVaultLocation -value $LSVPath `
            -name LocalSpeedVaultUser     -value $LSVUsername `
            -name LocalSpeedVaultPassword -value $LSVPassword
        Write-Output "Network LSV configured successfully."
    }
}

Exit 0
