<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Exclude SpeedVault Path
    # Adapted for NinjaOne from ExcludeSpeedVault.v01.ps1
    # Source Revision: v01 - 2021-01-18, Author: Eric Harless, SolarWinds
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
    # Run as a one-shot NinjaOne Script Policy after LSV is configured.
    # Adds the LSV / seed storage path (*\storage\cabs\gen*\*) to the Cove backup exclusion
    # filter AND to the Windows FilesNotToBackup registry key (prevents Windows Backup from
    # backing up the LSV data store).
    # Note: The ClientTool filter method is not compatible with profile-based filters.
    # The registry method works with both local and profile-based filter configurations.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:  System (Local System)
    #   Timeout: 60 seconds
    #   Trigger: One-shot after LSV configuration
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed
    #   - ClientTool.exe at C:\Program Files\Backup Manager\ClientTool.exe
    #   - PowerShell 5.1+, run as System/Administrator
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

$clienttool    = "C:\Program Files\Backup Manager\clienttool.exe"
$filterPattern = "*\storage\cabs\gen*\*"
$regKey        = "HKLM:\SYSTEM\ControlSet001\Control\BackupRestore\FilesNotToBackup"
$regValueName  = "ExcludeLSV"

## ---- Verify Backup Manager is installed ----
if (-not (Test-Path $clienttool)) {
    Write-Output "ERROR: ClientTool.exe not found - is Cove Backup Manager installed?"
    Exit 1
}

Write-Output "Setting backup filter and registry exclusion for LSV/seed paths..."

## ---- Method 1: ClientTool filter (not supported with profile-based filters) ----
try {
    & $clienttool control.filter.modify -add $filterPattern
    Write-Output "ClientTool filter added: $filterPattern"
} catch {
    Write-Output "WARNING: ClientTool filter add failed (may already be set or profile-managed): $_"
}

## ---- Method 2: Registry FilesNotToBackup key (works with profile-based filters) ----
try {
    $regArgs = @(
        "ADD",
        "HKLM\SYSTEM\ControlSet001\Control\BackupRestore\FilesNotToBackup",
        "/v", $regValueName,
        "/t", "REG_MULTI_SZ",
        "/d", $filterPattern,
        "/f"
    )
    & REG @regArgs
    Write-Output "Registry exclusion added: $regKey\$regValueName = $filterPattern"
} catch {
    Write-Output "WARNING: Registry exclusion add failed: $_"
}

Write-Output "LSV/seed path exclusions configured."
Exit 0
