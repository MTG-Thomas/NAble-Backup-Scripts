<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Set Backup Logging Level
    # Adapted for NinjaOne from SetBackupLogging.v04.ps1
    # Source Revision: v04 - 2020-08-26, Author: Eric Harless, SolarWinds
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
    # Run on-demand from a NinjaOne device action as part of a troubleshooting runbook.
    # Sets the Backup Manager log verbosity level by modifying config.ini.
    # Optionally restarts the Backup Service to apply the new log level immediately.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  120 seconds
    #   Trigger:  On demand only (troubleshooting runbook)
    #
    # NinjaOne Script Variables (set in the Script Policy):
    #   logLevel  (string, required) - Logging level to apply:
    #                  Warning  (default - minimal logging)
    #                  Error    (errors only)
    #                  Log      (standard logging)
    #                  Debug    (verbose - use temporarily only, generates large logs)
    #   restartService (boolean, default false) - Restart Backup Service after applying log level
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed
    #   - config.ini at C:\Program Files\Backup Manager\config.ini
    #   - PowerShell 5.1+, run as System/Administrator
    #
    # Logging reference:
    #   https://documentation.n-able.com/backup/userguide/documentation/Content/backup-manager/backup-manager-guide/logging.htm
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

## ---- Read NinjaOne Script Variables ----
$LogLevel      = if ($env:logLevel)      { $env:logLevel.Trim()      } else { "Warning" }
$RestartSvc    = if ($env:restartService) { $env:restartService -ne 'false' } else { $false }

## ---- Validate log level ----
$ValidLevels = @("Warning","Error","Log","Debug")
if ($LogLevel -notin $ValidLevels) {
    Write-Output "ERROR: logLevel '$LogLevel' is not valid. Valid values: Warning, Error, Log, Debug"
    Exit 1
}

$config = "C:\Program Files\Backup Manager\config.ini"
if (-not (Test-Path $config)) {
    Write-Output "ERROR: config.ini not found at '$config' - is Cove Backup Manager installed?"
    Exit 1
}

Write-Output "Applying log level: $LogLevel (Restart: $RestartSvc)"

## ---- Build new [Logging] section ----
switch ($LogLevel) {
    "Log"     { $newLogging = "[Logging]`r`nLoggingLevel=Log`r`nSingleLogMaxSizeInMb=5`r`nTotalLogsMaxSizeInMb=50"   }
    "Error"   { $newLogging = "[Logging]`r`nLoggingLevel=Error`r`nSingleLogMaxSizeInMb=5`r`nTotalLogsMaxSizeInMb=50"  }
    "Warning" { $newLogging = "[Logging]`r`nLoggingLevel=Warning`r`nSingleLogMaxSizeInMb=5`r`nTotalLogsMaxSizeInMb=50"}
    "Debug"   { $newLogging = "[Logging]`r`nLoggingLevel=Debug`r`nSingleLogMaxSizeInMb=10`r`nTotalLogsMaxSizeInMb=200"}
}

## ---- Strip existing [Logging] section and append new one ----
try {
    $content = Get-Content $config
    $filtered = $content |
        Where-Object { $_ -notmatch '^\[Logging\]' } |
        Where-Object { $_ -notmatch '^LoggingLevel=' } |
        Where-Object { $_ -notmatch '^SingleLogMaxSizeInMb=' } |
        Where-Object { $_ -notmatch '^TotalLogsMaxSizeInMb=' }
    $filtered | Set-Content $config
    Start-Sleep -Seconds 1
    $newLogging | Out-File $config -Append -Encoding ASCII
    Write-Output "Log level updated to: $LogLevel"
} catch {
    Write-Output "ERROR: Failed to update config.ini: $_"
    Exit 1
}

## ---- Optionally restart service ----
if ($RestartSvc) {
    Write-Output "Stopping Backup Manager process..."
    Stop-Process -Name "BackupFP" -Force -EA SilentlyContinue
    Start-Sleep -Seconds 3

    Write-Output "Restarting Backup Service Controller..."
    try {
        Stop-Service  -Name "Backup Service Controller" -Force -EA SilentlyContinue
        Start-Sleep -Seconds 5
        Start-Service -Name "Backup Service Controller" -EA Stop
        $svc = Get-Service "Backup Service Controller" -EA SilentlyContinue
        Write-Output "Backup Service Controller: $($svc.Status)"
    } catch {
        Write-Output "WARNING: Service restart encountered an error: $_"
    }
}

Write-Output "Done. Log level is now: $LogLevel"
Exit 0
