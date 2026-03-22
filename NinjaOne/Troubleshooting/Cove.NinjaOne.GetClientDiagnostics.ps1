<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Client Diagnostics
    # Adapted for NinjaOne from GetClientErrors.v03.ps1
    # Source Revision: v03 - 2022-04-27, Author: Eric Harless, N-able
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
    # Run on-demand from a NinjaOne device action, or triggered by a Cove monitoring alert.
    # Executes a single-pass diagnostic using ClientTool.exe and outputs results to the
    # NinjaOne activity log. Optionally writes a diagnostic summary to the custom field
    # 'coveClientDiagnostics' for persistence in the device record.
    #
    # Collects:
    #   - Backup Service Controller status
    #   - Initialization errors (cloud auth failures)
    #   - Application status
    #   - Job status (Idle/Running/etc.)
    #   - VSS health check
    #   - Storage node connectivity
    #   - Current backup settings (with SHA-256 hash)
    #   - Current backup selections (with SHA-256 hash)
    #   - MySQL credential check (if MySQL detected)
    #   - Active backup filters
    #   - Backup schedules
    #   - Per-datasource session errors
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  300 seconds
    #   Trigger:  On demand (device action or linked to monitoring alert)
    #
    # NinjaOne Script Variables (set in the Script Policy):
    #   writeCustomField  (boolean, default true) - Write diagnostics to 'coveClientDiagnostics' field
    #
    # NinjaOne Custom Fields (optional, device-level):
    #   coveClientDiagnostics  Text (multiline) - populated with diagnostic output
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed
    #   - ClientTool.exe at C:\Program Files\Backup Manager\ClientTool.exe
    #   - Backup Service Controller must be running
    #   - PowerShell 5.1+, run as System/Administrator
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$False)] [bool]$WriteCustomField = $true
)

## ---- Read NinjaOne Script Variables ----
if ($env:writeCustomField -ne $null -and $env:writeCustomField -ne '') { $WriteCustomField = $env:writeCustomField -ne 'false' }

$clienttool = "C:\Program Files\Backup Manager\ClientTool.exe"
$output     = [System.Collections.Generic.List[string]]::new()

Function Hash-Value ($value) {
    (New-Object System.Security.Cryptography.SHA256Managed) |
        ForEach-Object { $_.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$value")) } |
        ForEach-Object { $_.ToString("x2") } | Write-Output
}

Function Add-Output ([string]$msg) {
    Write-Output $msg
    $output.Add($msg)
}

## ---- Check ClientTool.exe is present ----
if (-not (Test-Path $clienttool)) {
    Write-Output "ERROR: ClientTool.exe not found - is Cove Backup Manager installed?"
    Exit 1
}

## ---- Check Service ----
$BackupService = Get-Service "Backup Service Controller" -EA SilentlyContinue
if ($BackupService.Status -ne "Running") {
    Add-Output "ERROR: Backup Service Controller is not running (Status: $($BackupService.Status))"
    if ($WriteCustomField) {
        try { Ninja-Property-Set 'coveClientDiagnostics' ($output -join "`n") } catch {}
    }
    Exit 1
}

$BackupProcess = Get-Process "BackupFP" -EA SilentlyContinue

Add-Output "`n---- Cove Data Protection Diagnostics ----"
Add-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
Add-Output "Service Status: $($BackupService.Status)"

## ---- Initialization Errors ----
Add-Output "`n-- Initialization Errors --"
if ($null -eq $BackupProcess) {
    Add-Output "Backup Manager process (BackupFP.exe) is not running"
} else {
    try {
        $initerror = & $clienttool control.initialization-error.get | ConvertFrom-Json
        if ($initerror.code -gt 0) {
            Add-Output "ERROR: $($initerror.Message)"
        } else {
            Add-Output "Cloud Initialized OK"
        }
    } catch { Add-Output "WARNING: Could not retrieve init errors: $_" }
}

## ---- Application Status ----
Add-Output "`n-- Application Status --"
if ($BackupProcess) {
    try {
        $AppStatus = & $clienttool control.application-status.get
        Add-Output "Application Status: $AppStatus"
    } catch { Add-Output "WARNING: Could not retrieve application status: $_" }
}

## ---- Job Status ----
Add-Output "`n-- Job Status --"
if ($BackupProcess) {
    try {
        $JobStatus = & $clienttool control.status.get
        Add-Output "Job Status: $JobStatus"
    } catch { Add-Output "WARNING: Could not retrieve job status: $_" }
}

## ---- VSS Health Check ----
Add-Output "`n-- VSS Check --"
if ($BackupProcess) {
    try {
        $VssResult = & $clienttool vss.check 2>&1
        Add-Output $VssResult
    } catch { Add-Output "WARNING: VSS check failed: $_" }
}

## ---- Storage Node Connectivity ----
Add-Output "`n-- Storage Node Connectivity --"
if ($BackupProcess) {
    try {
        $StorageResult = & $clienttool storage.test 2>&1
        Add-Output $StorageResult
    } catch { Add-Output "WARNING: Storage test failed: $_" }
}

## ---- Backup Settings ----
Add-Output "`n-- Backup Settings --"
if ($BackupProcess) {
    try {
        $BackupSettings = & $clienttool control.setting.list
        Add-Output $BackupSettings
        Add-Output "Settings Hash: $(Hash-Value $BackupSettings)"
    } catch { Add-Output "WARNING: Could not retrieve settings: $_" }
}

## ---- Backup Selections ----
Add-Output "`n-- Backup Selections --"
if ($BackupProcess) {
    try {
        $BackupSelection = & $clienttool control.selection.list
        Add-Output $BackupSelection
        Add-Output "Selections Hash: $(Hash-Value $BackupSelection)"
    } catch { Add-Output "WARNING: Could not retrieve selections: $_" }
}

## ---- MySQL Check (if installed) ----
$MYSQLinstalled = ($null -ne (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -EA SilentlyContinue |
    Where-Object { $_.DisplayName -like "*MySQL*" }))
if ($MYSQLinstalled) {
    Add-Output "`n-- MySQL Installation Detected --"
    $MySQLService = Get-Service -Name "*mysql*" -EA SilentlyContinue | Select-Object -First 1 Status
    Add-Output "MySQL Service: $($MySQLService.Status)"
    if ($MySQLService.Status -eq "Running" -and $BackupProcess) {
        try {
            $MySQLconfigured = & $clienttool -machine-readable control.mysqldb.list -no-header -delimiter ","
            if ($null -eq $MySQLconfigured) {
                Add-Output "WARNING: MySQL Credentials Not Configured in Cove"
            } else {
                Add-Output "MySQL Backup Credentials configured"
            }
        } catch { Add-Output "WARNING: Could not check MySQL credentials: $_" }
    }
}

## ---- Backup Filters ----
Add-Output "`n-- Backup Filters --"
if ($BackupProcess) {
    try {
        $Filters = & $clienttool control.filter.list
        if ($Filters) {
            Add-Output $Filters
        } else {
            Add-Output "(No active backup filters)"
        }
    } catch { Add-Output "WARNING: Could not retrieve filters: $_" }
}

## ---- Backup Schedules ----
Add-Output "`n-- Backup Schedules --"
if ($BackupProcess) {
    try {
        $Schedules = & $clienttool control.schedule.list
        if ($Schedules -eq "No schedules found.") {
            Add-Output "WARNING: No Backup Schedules Configured"
        } else {
            Add-Output $Schedules
        }
    } catch { Add-Output "WARNING: Could not retrieve schedules: $_" }
}

## ---- Per-Datasource Session Errors ----
Add-Output "`n-- Per-Datasource Session Errors --"
if ($BackupProcess) {
    try {
        $Datasources = & $clienttool control.selection.list |
            ConvertFrom-String |
            Select-Object -Skip 2 |
            ForEach-Object { if ($_.P2 -eq "Inclusive") { $_.P1 } } |
            Select-Object -Unique

        foreach ($ds in $Datasources) {
            Add-Output "`n[$ds Errors]"
            try {
                $errors = & $clienttool control.session.error.list -datasource $ds -no-header 2>&1
                Add-Output $errors
            } catch { Add-Output "WARNING: Could not retrieve errors for $ds : $_" }
        }
    } catch { Add-Output "WARNING: Could not enumerate datasources: $_" }
}

Add-Output "`n---- End Diagnostics ----"

## ---- Write to NinjaOne custom field ----
if ($WriteCustomField) {
    $summary = $output -join "`n"
    try { Ninja-Property-Set 'coveClientDiagnostics' $summary } catch {}
}

Exit 0
