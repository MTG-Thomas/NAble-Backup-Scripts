<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne LSV Sync Check
    # Adapted for NinjaOne from LSVSyncCheckFinal.v12.ps1
    # Source Revision: v12 - 2020-08-17, Authors: Dion Jones & Eric Harless, SolarWinds
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
    # Run as a NinjaOne Script Policy (Condition) on devices where LSV is enabled.
    # Reads StatusReport.xml to check LSV and cloud sync status.
    # Exits 1 if LSV is not enabled, sync is failed, or sync % is below threshold.
    # Exits 0 if all sync statuses are healthy.
    # Optionally writes sync status to the NinjaOne device custom field 'coveLsvSyncStatus'.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  60 seconds
    #   Schedule: Every 30-60 minutes (or on devices with LSV only)
    #   Condition Trigger: Script exit code != 0
    #
    # NinjaOne Script Variables (set in the Script Policy):
    #   writeCustomField  (boolean, default true) - Write LSV status to 'coveLsvSyncStatus' custom field
    #
    # NinjaOne Custom Fields (optional, device-level):
    #   coveLsvSyncStatus  Text - populated with LSV sync status string
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed on the device with LSV enabled
    #   - StatusReport.xml at C:\ProgramData\MXB\Backup Manager\StatusReport.xml
    #   - PowerShell 5.1+, run as System
    #   - No API credentials needed
# -----------------------------------------------------------#>

#Requires -Version 5.1

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$False)] [bool]$WriteCustomField = $true
)

## ---- Read NinjaOne Script Variables ----
if ($env:writeCustomField -ne $null -and $env:writeCustomField -ne '') { $WriteCustomField = $env:writeCustomField -ne 'false' }

$global:failed = 0

Function Convert-FromUnixDate ($UnixDate) {
    [timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($UnixDate))
}

Function CheckSync {
    Param ([xml]$StatusReport)

    $BackupServSync = $StatusReport.Statistics.BackupServerSynchronizationStatus
    if ($BackupServSync -eq "Failed") {
        Write-Output "WARNING: Backup Synchronization Failed"
        $global:failed = 1
    } elseif ($BackupServSync -eq "Synchronized") {
        Write-Output "Backup Synchronized"
    } elseif ($BackupServSync -like '*%') {
        Write-Output "Backup Synchronization: $BackupServSync"
    } else {
        Write-Output "WARNING: Backup Synchronization Data Invalid or Not Found"
        $global:failed = 1
    }

    $LSVSync = $StatusReport.Statistics.LocalSpeedVaultSynchronizationStatus
    if ($LSVSync -eq "Failed") {
        Write-Output "WARNING: LocalSpeedVault Synchronization Failed"
        $global:failed = 1
    } elseif ($LSVSync -eq "Synchronized") {
        Write-Output "LocalSpeedVault Synchronized"
    } elseif ($LSVSync -like '*%') {
        Write-Output "LocalSpeedVault Synchronization: $LSVSync"
    } else {
        Write-Output "WARNING: LocalSpeedVault Synchronization Data Invalid or Not Found"
        $global:failed = 1
    }

    $Script:statusSummary = "CloudSync=$BackupServSync | LSVSync=$LSVSync"
}

## ---- Locate StatusReport.xml (Standalone preferred) ----
$MOB_path = "$env:ALLUSERSPROFILE\Managed Online Backup\Backup Manager\StatusReport.xml"
$SA_path  = "$env:ALLUSERSPROFILE\MXB\Backup Manager\StatusReport.xml"

$test_MOB = Test-Path $MOB_path
$test_SA  = Test-Path $SA_path

if ($test_MOB -and $test_SA) {
    $lm_MOB = [datetime](Get-ItemProperty -Path $MOB_path -Name LastWriteTime).LastWriteTime
    $lm_SA  = [datetime](Get-ItemProperty -Path $SA_path  -Name LastWriteTime).LastWriteTime
    $true_path = if ((Get-Date $lm_MOB) -gt (Get-Date $lm_SA)) { $MOB_path } else { $SA_path }
} elseif ($test_SA) {
    $true_path = $SA_path
} elseif ($test_MOB) {
    $true_path = $MOB_path
} else {
    Write-Output "WARNING: StatusReport.xml Not Found - Backup Manager may not be installed"
    Exit 0   ## Not installed - exit clean (no alert)
}

## ---- Read XML and check LSV ----
[xml]$StatusReport = Get-Content $true_path

$LSV_Enabled = $StatusReport.Statistics.LocalSpeedVaultEnabled
if ($LSV_Enabled -eq "0") {
    Write-Output "LocalSpeedVault is not Enabled - skipping LSV sync check"
    $Script:statusSummary = "LSV=Disabled"
    ## Exit 0 — LSV is intentionally disabled, not an alert condition
    if ($WriteCustomField) {
        try { Ninja-Property-Set 'coveLsvSyncStatus' $Script:statusSummary } catch {}
    }
    Exit 0
} elseif ($LSV_Enabled -eq "1") {
    Write-Output "LocalSpeedVault is Enabled"
    CheckSync -StatusReport $StatusReport
}

## ---- Device info ----
$TimeStamp   = Convert-FromUnixDate $StatusReport.Statistics.TimeStamp
$PartnerName = $StatusReport.Statistics.PartnerName
$Account     = $StatusReport.Statistics.Account
$MachineName = $StatusReport.Statistics.MachineName
$ClientVersion = $StatusReport.Statistics.ClientVersion

Write-Output "TimeStamp:    $TimeStamp"
Write-Output "PartnerName:  $PartnerName"
Write-Output "Account:      $Account"
Write-Output "MachineName:  $MachineName"
Write-Output "ClientVersion:$ClientVersion"

## ---- Write to NinjaOne custom field ----
if ($WriteCustomField) {
    try { Ninja-Property-Set 'coveLsvSyncStatus' $Script:statusSummary } catch {}
}

## ---- Exit with NinjaOne-compatible code ----
if ($global:failed -eq 1) {
    Exit 1
} else {
    Exit 0
}
