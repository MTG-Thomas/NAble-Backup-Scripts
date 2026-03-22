<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Exclude USB Drives from Backup
    # Adapted for NinjaOne from ExcludeUSB.v11.ps1
    # Source Revision: v11 - 2020-04-29, Author: Eric Harless, SolarWinds
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
    # Run as a one-shot NinjaOne Script Policy post-deployment as a backup hardening step.
    # Detects all USB bus-type disk volumes and:
    #   Method 1: Adds each USB volume to the Cove backup exclusion filter via ClientTool.exe
    #             (not compatible with profile-based filters)
    #   Method 2: Adds each USB volume to the Windows FilesNotToBackup registry key
    #             (works with profile-based filters and Windows Backup)
    # Note: This applies only to currently attached USB drives. Re-run when new USB drives
    # are plugged in, or run this on a recurring schedule to catch newly attached drives.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  120 seconds
    #   Trigger:  One-shot post-deployment; optionally on a daily schedule
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed
    #   - ClientTool.exe at C:\Program Files\Backup Manager\ClientTool.exe
    #   - PowerShell 5.1+, run as System/Administrator
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

$clienttool = "C:\Program Files\Backup Manager\clienttool.exe"

## ---- Verify installation ----
if (-not (Test-Path $clienttool)) {
    Write-Output "ERROR: ClientTool.exe not found - is Cove Backup Manager installed?"
    Exit 1
}

Write-Output "Scanning for USB bus-type disk volumes..."

## ---- Detect USB disk volumes ----
$usbVolumes = @()
try {
    Get-Disk | Select-Object Number | Update-Disk -EA SilentlyContinue | Out-Null
    $usbDisks = Get-Disk | Where-Object { $_.BusType -eq "USB" } | Select-Object Number
    foreach ($disk in $usbDisks) {
        $partitions = Get-Partition -DiskNumber $disk.Number -EA SilentlyContinue |
            Where-Object { $_.DriveLetter -ne "`0" -and $_.DriveLetter -ne $null }
        foreach ($part in $partitions) {
            $usbVolumes += "$($part.DriveLetter):\"
        }
    }
} catch {
    Write-Output "WARNING: Could not enumerate USB volumes: $_"
}

if ($usbVolumes.Count -eq 0) {
    Write-Output "No USB disk volumes found on this device. Nothing to exclude."
    Exit 0
}

Write-Output "USB volumes found: $($usbVolumes -join ', ')"

$exitCode = 0

foreach ($vol in $usbVolumes) {
    $volFilter = $vol -replace '\\','\\'

    ## ---- Method 1: ClientTool filter ----
    try {
        & $clienttool control.filter.modify -add $volFilter
        Write-Output "ClientTool filter added for: $vol"
    } catch {
        Write-Output "WARNING: ClientTool filter add failed for '$vol': $_"
    }

    ## ---- Method 2: Registry FilesNotToBackup ----
    $regValueName = "ExcludeUSB_$($vol[0])"
    try {
        $regArgs = @(
            "ADD",
            "HKLM\SYSTEM\ControlSet001\Control\BackupRestore\FilesNotToBackup",
            "/v", $regValueName,
            "/t", "REG_MULTI_SZ",
            "/d", "$vol*",
            "/f"
        )
        & REG @regArgs
        Write-Output "Registry exclusion added for: $vol"
    } catch {
        Write-Output "WARNING: Registry exclusion add failed for '$vol': $_"
        $exitCode = 1
    }
}

Write-Output "USB drive exclusion complete."
Exit $exitCode
