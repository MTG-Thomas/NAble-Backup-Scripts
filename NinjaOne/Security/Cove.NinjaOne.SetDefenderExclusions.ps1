<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Set Windows Defender Exclusions
    # Adapted for NinjaOne from CoveDataProtection.SetDefenderExclusions.v24.02.11.ps1
    # Source Revision: v24.02.11 - 2024-02-11, Author: Eric Harless, N-able
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
    # Run as a one-shot NinjaOne Script Policy immediately after Cove deployment.
    # Adds Backup Manager and Recovery Console paths and executables to Windows Defender
    # exclusions, reducing AV interference with backup and recovery operations.
    # Safe to run before Backup Manager installation (creates exclusions pre-emptively).
    # No custom fields or variables needed.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  60 seconds
    #   Trigger:  One-shot post-install (link as next step after Cove_NinjaOne_Deploy.v26.02.ps1)
    #             Also suitable as a monthly maintenance schedule to re-apply after Windows updates
    #
    # Dependencies:
    #   - Windows Defender (Add-MpPreference cmdlet)
    #   - PowerShell 5.1+, run as System/Administrator
    #   - No Cove installation required (safe to run pre-install)
    #
    # References:
    #   https://documentation.n-able.com/covedataprotection/USERGUIDE/documentation/Content/backup-manager/backup-manager-installation/reqs.htm
    #   https://documentation.n-able.com/covedataprotection/USERGUIDE/documentation/Content/advanced-recovery/recovery-console/installation.htm
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

$ExcludePath = @(
    "C:\Program Files\Backup Manager",
    "C:\Program Files\RecoveryConsole",
    "C:\Program Files\RecoveryConsole\vddk",
    "C:\ProgramData\Managed Online Backup",
    "C:\ProgramData\MXB",
    "*\StandbyImage",
    "*\OneTimeRestore"
)

$ExcludeProcess = @(
    "C:\Program Files\Backup Manager\BackupFP.exe",
    "C:\Program Files\Backup Manager\BackupIP.exe",
    "C:\Program Files\Backup Manager\BackupUP.exe",
    "C:\Program Files\Backup Manager\ClientTool.exe",
    "C:\Program Files\Backup Manager\BRMigrationTool.exe",
    "C:\Program Files\Backup Manager\ProcessController.exe",
    "C:\Program Files\RecoveryConsole\BackupFP.exe",
    "C:\Program Files\RecoveryConsole\BackupIP.exe",
    "C:\Program Files\RecoveryConsole\BackupUP.exe",
    "C:\Program Files\RecoveryConsole\ClientTool.exe",
    "C:\Program Files\RecoveryConsole\RecoveryConsole.exe",
    "C:\Program Files\RecoveryConsole\ProcessController.exe",
    "C:\Program Files\RecoveryConsole\BRMigrationTool.exe",
    "C:\Program Files\Recovery Service\*\AuthTool.exe",
    "C:\Program Files\Recovery Service\*\unified_entry.exe",
    "C:\Program Files\Recovery Service\*\BM\RecoveryFP.exe",
    "C:\Program Files\Recovery Service\*\BM\VdrAgent.exe",
    "C:\Program Files\Recovery Service\*\BM\ProcessController.exe",
    "C:\Program Files\Recovery Service\*\BM\RecoveryProcessController.exe",
    "C:\Program Files\Recovery Service\*\BM\ClientTool.exe",
    "C:\Program Files\Recovery Service\*\VdrTool.exe"
)

## ---- Check Windows Defender is available ----
if (-not (Get-Command Add-MpPreference -EA SilentlyContinue)) {
    Write-Output "WARNING: Windows Defender (Add-MpPreference) is not available on this device."
    Write-Output "This device may be using a third-party AV. Add exclusions manually."
    Exit 0
}

## ---- Apply exclusions ----
try {
    Add-MpPreference -ExclusionPath $ExcludePath -ExclusionProcess $ExcludeProcess
    Write-Output "Cove Data Protection Defender exclusions applied successfully."
} catch {
    Write-Output "ERROR: Failed to apply Defender exclusions: $_"
    Exit 1
}

## ---- Report current exclusions ----
$Exclude = Get-MpPreference | Select-Object Exclusion*
Write-Output "`nDefender Process Exclusions:"
$Exclude.ExclusionProcess | ForEach-Object { Write-Output "  $_" }
Write-Output "`nDefender Path Exclusions:"
$Exclude.ExclusionPath    | ForEach-Object { Write-Output "  $_" }

Exit 0
