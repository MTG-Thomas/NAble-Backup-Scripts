<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Set Backup Bandwidth Throttle
    # Adapted for NinjaOne from CustomBackupThrottle.v05.ps1
    # Source Revision: v05 - 2020-04-27, Author: Eric Harless, SolarWinds
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
    # Run as a one-shot NinjaOne Script Policy to configure bandwidth throttle schedules.
    # Reads a throttle schedule from NinjaOne script variable or uses a built-in default.
    # Applies throttle rules for each day of the week via ClientTool.exe.
    # Note: The NinjaOne Script Policy schedule replaces the original self-scheduling task logic.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  120 seconds
    #   Trigger:  One-shot (post-deployment or on throttle policy change)
    #
    # NinjaOne Script Variables (optional):
    #   uploadKbps    (integer, default 4096)  - Upload throttle in Kbps (business hours)
    #   downloadKbps  (integer, default 4096)  - Download throttle in Kbps (business hours)
    #   onAt          (string,  default 08:00) - Throttle start time (HH:mm)
    #   offAt         (string,  default 18:00) - Throttle end time (HH:mm)
    #   throttleWeekends (boolean, default false) - Apply throttle on Saturday/Sunday
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed
    #   - ClientTool.exe at C:\Program Files\Backup Manager\ClientTool.exe
    #   - Backup Service Controller must be running
    #   - PowerShell 5.1+, run as System/Administrator
    #
    # ClientTool throttle reference:
    #   https://documentation.n-able.com/covedataprotection/USERGUIDE/documentation/Content/backup-manager/backup-manager-guide/command-line.htm
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

$clienttool = "C:\Program Files\Backup Manager\ClientTool.exe"

## ---- Verify installation ----
if (-not (Test-Path $clienttool)) {
    Write-Output "ERROR: ClientTool.exe not found - is Cove Backup Manager installed?"
    Exit 1
}

## ---- Read NinjaOne Script Variables ----
$UpKbps          = if ($env:uploadKbps   -and [int]::TryParse($env:uploadKbps,  [ref]$null)) { [int]$env:uploadKbps   } else { 4096 }
$DownKbps        = if ($env:downloadKbps -and [int]::TryParse($env:downloadKbps,[ref]$null)) { [int]$env:downloadKbps } else { 4096 }
$OnAt            = if ($env:onAt)         { $env:onAt }  else { "08:00" }
$OffAt           = if ($env:offAt)        { $env:offAt } else { "18:00" }
$ThrottleWeekend = if ($env:throttleWeekends -ne $null -and $env:throttleWeekends -ne '') { $env:throttleWeekends -ne 'false' } else { $false }

Write-Output "Applying bandwidth throttle schedule:"
Write-Output "  Upload:   $UpKbps Kbps   Download: $DownKbps Kbps"
Write-Output "  Hours:    $OnAt - $OffAt"
Write-Output "  Weekends: $ThrottleWeekend"

## ---- Define throttle schedule ----
# Each entry: Day, ThrottleEnabled, OnTime, OffTime
$schedule = @(
    @{ Day = "Monday";    Limit = $true  }
    @{ Day = "Tuesday";   Limit = $true  }
    @{ Day = "Wednesday"; Limit = $true  }
    @{ Day = "Thursday";  Limit = $true  }
    @{ Day = "Friday";    Limit = $true  }
    @{ Day = "Saturday";  Limit = $ThrottleWeekend }
    @{ Day = "Sunday";    Limit = $ThrottleWeekend }
)

## ---- Apply throttle rules via ClientTool ----
foreach ($entry in $schedule) {
    $limitStr = if ($entry.Limit) { "true" } else { "false" }

    # Stagger on/off times per day by 1 minute to avoid duplicate schedule collisions
    $dayIndex = @("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday").IndexOf($entry.Day)
    $onParts  = $OnAt.Split(":")
    $offParts = $OffAt.Split(":")
    $onMin    = [int]$onParts[1]  + $dayIndex
    $offMin   = [int]$offParts[1] + $dayIndex
    $onTime   = "{0}:{1:D2}" -f $onParts[0],  ($onMin  % 60)
    $offTime  = "{0}:{1:D2}" -f $offParts[0], ($offMin % 60)

    $args = @(
        "control.setting.modify",
        "-name", "BandwidthScheduleEnabled",  "-value", "true",
        "-name", "BandwidthSchedule$($entry.Day)Limit",  "-value", $limitStr,
        "-name", "BandwidthSchedule$($entry.Day)On",     "-value", $onTime,
        "-name", "BandwidthSchedule$($entry.Day)Off",    "-value", $offTime,
        "-name", "BandwidthSchedule$($entry.Day)UpKbps", "-value", $UpKbps,
        "-name", "BandwidthSchedule$($entry.Day)DnKbps", "-value", $DownKbps
    )

    try {
        & $clienttool @args
        Write-Output "$($entry.Day): Limit=$limitStr, $onTime-$offTime, Up=$UpKbps Kbps, Dn=$DownKbps Kbps"
    } catch {
        Write-Output "WARNING: Failed to set throttle for $($entry.Day): $_"
    }
}

Write-Output "Bandwidth throttle schedule applied."
Exit 0
