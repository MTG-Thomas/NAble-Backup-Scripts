<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Monitor
    # Adapted for NinjaOne from Cove.Monitoring.v20.minimalist.ps1
    # Source Revision: v20 - 2025-02-11, Author: Eric Harless, N-able
    # NinjaOne Adaptation: 2026
    # Reddit https://www.reddit.com/r/Nable/
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
    # Run as a NinjaOne Script Policy (Condition) on a recurring schedule (every 1-4 hours).
    # Reads local StatusReport.xml and queries ClientTool.exe for session/error data.
    # Outputs WARNING: prefixed lines for any threshold breach.
    # Exits with code 1 if any warning is found - NinjaOne treats non-zero exit as a condition failure.
    # Optionally writes a summary to the NinjaOne device custom field 'coveMonitorStatus'.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  300 seconds
    #   Schedule: Every 1-4 hours
    #   Condition Trigger: Script exit code != 0
    #
    # NinjaOne Script Variables (set in the Script Policy):
    #   serverSuccessHours    (integer, default 24)   - Hours since last success before warning on servers
    #   workstationSuccessHours (integer, default 72) - Hours since last success before warning on workstations
    #   synchThreshold        (integer, default 90)   - LSV sync % below which a warning is raised
    #   errorLimit            (integer, default 10)   - Max error messages displayed per data source
    #   writeCustomField      (boolean, default true) - Write summary to 'coveMonitorStatus' custom field
    #
    # NinjaOne Custom Fields (optional, device-level):
    #   coveMonitorStatus     Text/WYSIWYG - populated with monitoring summary when writeCustomField = true
    #
    # Dependencies:
    #   - Cove Backup Manager (Standalone) installed on the device
    #   - ClientTool.exe at C:\Program Files\Backup Manager\ClientTool.exe
    #   - PowerShell 5.1+, run as Administrator/System
    #   - No API credentials needed
# -----------------------------------------------------------#>

#Requires -Version 5.1 -RunAsAdministrator

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$False)][ValidateSet("FileSystem","SystemState","NetworkShares","VssMsSql","Exchange","MySql","VMware","VssHyperV","VssSharePoint","Oracle")] $Datasource,
    [Parameter(Mandatory=$False)] [int]$ServerSuccessHoursInVal    = 24,
    [Parameter(Mandatory=$False)] [int]$WrkStnSuccessHoursInVal    = 72,
    [Parameter(Mandatory=$False)] [int]$ErrorLimit                 = 10,
    [Parameter(Mandatory=$False)] [int]$SynchThreshold             = 90,
    [Parameter(Mandatory=$False)] [bool]$WriteCustomField          = $true
)

## ---- Read NinjaOne Script Variables (override Param defaults if set) ----
if ($env:serverSuccessHours     -and [int]::TryParse($env:serverSuccessHours,     [ref]$null)) { $ServerSuccessHoursInVal  = [int]$env:serverSuccessHours }
if ($env:workstationSuccessHours -and [int]::TryParse($env:workstationSuccessHours,[ref]$null)) { $WrkStnSuccessHoursInVal  = [int]$env:workstationSuccessHours }
if ($env:synchThreshold          -and [int]::TryParse($env:synchThreshold,         [ref]$null)) { $SynchThreshold           = [int]$env:synchThreshold }
if ($env:errorLimit              -and [int]::TryParse($env:errorLimit,             [ref]$null)) { $ErrorLimit               = [int]$env:errorLimit }
if ($env:writeCustomField -ne $null -and $env:writeCustomField -ne '') { $WriteCustomField = $env:writeCustomField -ne 'false' }

$global:failed   = 0
$global:output   = [System.Collections.Generic.List[string]]::new()

## ---- Helper Functions ----

Function Convert-UnixTimeToDateTime($inputUnixTime) {
    if ($inputUnixTime -gt 0) {
        $epoch = (Get-Date -Date "1970-01-01 00:00:00Z").ToUniversalTime()
        return $epoch.AddSeconds($inputUnixTime)
    } else { return "" }
}

Function RND {
    Param(
        [Parameter(ValueFromPipeline,Position=3)]$Value,
        [Parameter(Position=0)][string]$unit = "MB",
        [Parameter(Position=1)][int]$decimal = 2
    )
    "$([math]::Round(($Value/"1$Unit"),$decimal)) $Unit"
}

Function Out-Line ([string]$msg, [switch]$Warn) {
    if ($Warn) {
        Write-Warning $msg
        $global:output.Add("WARNING: $msg")
        $global:failed = 1
    } else {
        Write-Output $msg
        $global:output.Add($msg)
    }
}

## ---- Script Variables ----
$Script:BackupServiceOutVal         = -1
$Script:BackupServiceOutTxt         = "Not Installed"
$Script:CoveDeviceNameOutTxt        = "Undefined"
$Script:MachineNameOutTxt           = "Undefined"
$Script:CustomerNameOutTxt          = "Undefined"
$Script:OsVersionOutTxt             = "Undefined"
$Script:ClientVerOutTxt             = "Undefined"
$Script:ProfileNameOutTxt           = "Undefined"
$Script:LSVEnabledOutTxt            = "Undefined"
$Script:LSVSyncStatusOutTxt         = "Undefined"
$Script:CloudSyncStatusOutTxt       = "Undefined"
$Script:TotalSelectedGBOutTxt       = "Undefined"
$Script:TotalUsedGBOutTxt           = "Undefined"
$script:StatusReportxml             = "C:\ProgramData\MXB\Backup Manager\StatusReport.xml"

## ---- Get Backup Service / Process State ----
Function Get-BackupState {
    $Script:BackupService = Get-Service -Name "Backup Service Controller" -EA SilentlyContinue

    if ($BackupService.Status -eq "Running") {
        $Script:BackupServiceOutVal = 1
        $Script:BackupServiceOutTxt = $BackupService.Status
        $BackupFP = "C:\Program Files\Backup Manager\BackupFP.exe"
        $Script:FunctionalProcess = Get-Process -Name "BackupFP" -EA SilentlyContinue |
            Where-Object { $_.Path -eq $BackupFP }
    } elseif (($BackupService.Status -ne "Running") -and ($null -ne $BackupService.Status)) {
        $Script:BackupServiceOutVal = 0
        $Script:BackupServiceOutTxt = $BackupService.Status
        Out-Line "Service Status | $BackupServiceOutTxt" -Warn
        return
    } elseif (($null -eq $BackupService.Status) -and (Test-Path $script:StatusReportxml)) {
        $Script:BackupServiceOutVal = -2
        $Script:BackupServiceOutTxt = "Previously Installed"
        Out-Line "Service Status | $BackupServiceOutTxt" -Warn
        return
    } else {
        $Script:BackupServiceOutVal = -1
        $Script:BackupServiceOutTxt = "Not Installed"
        Out-Line "Service Status | $BackupServiceOutTxt"
        return
    }
}

## ---- Read base device data from StatusReport.xml ----
Function Get-StatusReportBase {
    if (Test-Path $script:StatusReportxml) {
        $xml = [Xml](Get-Content $script:StatusReportxml)
        $Script:CoveDeviceNameOutTxt = $xml.SelectSingleNode("//Account")."#text"
        $Script:MachineNameOutTxt    = $xml.SelectSingleNode("//MachineName")."#text"
        $Script:CustomerNameOutTxt   = $xml.SelectSingleNode("//PartnerName")."#text"
        $Script:OsVersionOutTxt      = $xml.SelectSingleNode("//OsVersion")."#text"
        $Script:ClientVerOutTxt      = $xml.SelectSingleNode("//ClientVersion")."#text"
        $Script:TimeZoneOutVal       = $xml.SelectSingleNode("//TimeZone")."#text"
        $Script:TimeStampOutVal      = $xml.SelectSingleNode("//TimeStamp")."#text"
        $Script:TimeStampUTCOutTxt   = Convert-UnixTimeToDateTime $Script:TimeStampOutVal
        $Script:ProfileNameOutTxt    = $xml.SelectSingleNode("//ProfileName")."#text"
        if ($null -eq $Script:ProfileNameOutTxt) { $Script:ProfileNameOutTxt = "Undefined" }

        if ($Script:OsVersionOutTxt -like "*Server*") {
            [int]$Script:SuccessHoursInVal = $ServerSuccessHoursInVal
        } else {
            [int]$Script:SuccessHoursInVal = $WrkStnSuccessHoursInVal
        }

        Out-Line "`n[Device]"
        Out-Line "Device Name               | $Script:CoveDeviceNameOutTxt"
        Out-Line "Machine Name              | $Script:MachineNameOutTxt"
        Out-Line "Customer Name             | $Script:CustomerNameOutTxt"
        Out-Line "TimeStamp(UTC)            | $Script:TimeStampUTCOutTxt"
        Out-Line "OS Version                | $Script:OsVersionOutTxt"
        Out-Line "Client Version            | $Script:ClientVerOutTxt"
        Out-Line "Profile Name              | $Script:ProfileNameOutTxt"
        Out-Line "Success Threshold (HRS)   | $Script:SuccessHoursInVal"
    } else {
        Out-Line "[$script:StatusReportxml] not found" -Warn
    }
}

## ---- Get active data sources from ClientTool.exe ----
Function Get-Datasources {
    $retrycounter = 0
    $clienttool = "C:\Program Files\Backup Manager\ClientTool.exe"
    if ($null -eq $Script:FunctionalProcess) {
        Out-Line "Backup Manager Not Running" -Warn
    } else {
        Do {
            $BackupStatus = & $clienttool -machine-readable control.status.get
            if ($BackupStatus -eq "Suspended") {
                Start-Sleep -Seconds 30
                $retrycounter++
            } else {
                try {
                    $ErrorActionPreference = 'Stop'
                    $script:Datasources = & $clienttool -machine-readable control.selection.list |
                        ConvertFrom-String |
                        Select-Object -Skip 1 -Property P1,P2 -Unique |
                        ForEach-Object { if ($_.P2 -eq "Inclusive") { $_.P1 } }
                    $Script:DataSourcesOutTxt = $Datasources -join ", "
                    Out-Line "`n[Configured Datasources]"
                    Out-Line "Data Sources              | $Script:DataSourcesOutTxt"
                } catch {}
            }
        } until (($BackupStatus -ne "Suspended") -or ($retrycounter -ge 5))
    }
}

## ---- Get LSV and cloud sync status ----
Function Get-Status ([int]$SynchThreshold) {
    $clienttool = "C:\Program Files\Backup Manager\ClientTool.exe"
    $retrycounter = 0
    Do {
        $BackupStatus = & $clienttool -machine-readable control.status.get
        if ($BackupStatus -ne "Suspended") {
            try {
                $ErrorActionPreference = 'SilentlyContinue'
                $Script:LSVSettings = & $clienttool control.setting.list
            } catch {
                Out-Line "ClientTool error: $_" -Warn
            }
        }
    } until (($BackupStatus -ne "Suspended") -or ($retrycounter -ge 5))

    if (Test-Path $script:StatusReportxml) {
        $xml = [Xml](Get-Content $script:StatusReportxml)
        $Script:LocalSpeedVaultEnabled               = $xml.SelectSingleNode("//LocalSpeedVaultEnabled")."#text"
        $Script:BackupServerSynchronizationStatus    = $xml.SelectSingleNode("//BackupServerSynchronizationStatus")."#text"
        $Script:LocalSpeedVaultSynchronizationStatus = $xml.SelectSingleNode("//LocalSpeedVaultSynchronizationStatus")."#text"
        $Script:SelectedSize                         = $xml.SelectSingleNode("//PluginTotal-LastCompletedSessionSelectedSize")."#text"
        $Script:UsedStorage                          = $xml.SelectSingleNode("//UsedStorage")."#text"

        if (($Script:LocalSpeedVaultEnabled -eq 1) -and $Script:LSVSettings) {
            $LSVPath = ($Script:LSVSettings | Where-Object { $_ -like "LocalSpeedVaultLocation *" }) -replace "LocalSpeedVaultLocation ",""
            $LSVUser = ($Script:LSVSettings | Where-Object { $_ -like "LocalSpeedVaultUser *" }) -replace "LocalSpeedVaultUser     ",""
        }

        $Script:TotalSelectedGBOutTxt   = ($Script:SelectedSize  | RND GB 2)
        $Script:TotalUsedGBOutTxt       = ($Script:UsedStorage    | RND GB 2)
        $Script:LSVEnabledOutTxt        = $Script:LocalSpeedVaultEnabled -replace "1","True" -replace "0","False"
        $Script:LSVEnabledOutVal        = $Script:LocalSpeedVaultEnabled
        $Script:CloudSyncStatusOutTxt   = $Script:BackupServerSynchronizationStatus
        $Script:LSVSyncStatusOutTxt     = if ($Script:LocalSpeedVaultEnabled -eq 1) { $Script:LocalSpeedVaultSynchronizationStatus } else { "Disabled" }

        Out-Line "`n[LocalSpeedVault Status]"
        Out-Line "LSV Enabled               | $Script:LSVEnabledOutTxt"
        Out-Line "LSV Sync Status           | $Script:LSVSyncStatusOutTxt"
        Out-Line "Cloud Sync Status         | $Script:CloudSyncStatusOutTxt"
        Out-Line "Selected Size             | $Script:TotalSelectedGBOutTxt"
        Out-Line "Used Storage              | $Script:TotalUsedGBOutTxt"
        if ($LSVPath) { Out-Line "LSV Path                  | $LSVPath" }

        if (($Script:LocalSpeedVaultEnabled -eq 1) -and (
            ($Script:BackupServerSynchronizationStatus -eq "Failed") -or
            ($Script:LocalSpeedVaultSynchronizationStatus -eq "Failed"))) {
            Out-Line "LSV or Cloud Sync Failed" -Warn
        } elseif (($Script:LocalSpeedVaultEnabled -eq 1) -and
            ($Script:BackupServerSynchronizationStatus -notlike "Synchronized") -and
            ($Script:BackupServerSynchronizationStatus -match '\d+%')) {
            $pct = [int]($Script:BackupServerSynchronizationStatus -replace '%','')
            if ($pct -lt $SynchThreshold) { Out-Line "Cloud sync $pct% is below threshold $SynchThreshold%" -Warn }
        } elseif (($Script:LocalSpeedVaultEnabled -eq 1) -and
            ($Script:LocalSpeedVaultSynchronizationStatus -notlike "Synchronized") -and
            ($Script:LocalSpeedVaultSynchronizationStatus -match '\d+%')) {
            $pct = [int]($Script:LocalSpeedVaultSynchronizationStatus -replace '%','')
            if ($pct -lt $SynchThreshold) { Out-Line "LSV sync $pct% is below threshold $SynchThreshold%" -Warn }
        }
    }
}

## ---- Get per-datasource session stats and errors from StatusReport.xml ----
Function Get-StatusReport {
    if (-not (Test-Path $script:StatusReportxml)) {
        Out-Line "[$script:StatusReportxml] not found" -Warn
        return
    }
    $xml = [Xml](Get-Content $script:StatusReportxml)

    $ReplaceDatasourceforXMLLookup = @{
        'FileSystem'    = 'FileSystem'
        'SystemState'   = 'VssSystemState'
        'VMware'        = 'VMWare'
        'VssHyperV'     = 'VssHyperV'
        'VssMsSql'      = 'VssMsSql'
        'Exchange'      = 'Exchange'
        'MySql'         = 'MySql'
        'NetworkShares' = 'NetworkShares'
        'VssSharePoint' = 'VssSharePoint'
        'Total'         = 'Total'
    }

    $ReplaceStatus = @{
        'Never' = 'NoBackup (o)'; '' = 'NoBackup (o)'; '0' = 'NoBackup (o)'
        '1' = 'InProcess (>)';  '2' = 'Failed (-)';      '3' = 'Aborted (x)'
        '4' = 'Unknown (?)';    '5' = 'Completed (+)';   '6' = 'Interrupted (&)'
        '7' = 'NotStarted (!)'; '8' = 'CompletedWithErrors (#)'; '9' = 'InProgressWithFaults (%)'
        '10' = 'OverQuota ($)'; '11' = 'NoSelection (0)';'12' = 'Restarted (*)'
    }

    $ReplaceArray = @(
        @('0','o'),@('1','>'),@('2','-'),@('3','x'),@('4','?'),
        @('5','+'),@('6','&'),@('7','!'),@('8','#'),@('9','%')
    )

    $XMLDataSource  = $ReplaceDatasourceforXMLLookup[$datasource]
    $PluginColorBar = $xml.SelectSingleNode("//Plugin$XMLDataSource-ColorBar")."#text"

    if ($PluginColorBar) {
        $ReplaceArray | ForEach-Object { $PluginColorBar = $PluginColorBar -replace $_[0],$_[1] }
        $ColorBarReversed = ($PluginColorBar[-1..-($PluginColorBar.Length)] -join "")

        $LastSessionStatus   = $ReplaceStatus[$xml.SelectSingleNode("//Plugin$XMLDataSource-LastSessionStatus")."#text"]
        $LastSessionTime     = Convert-UnixTimeToDateTime($xml.SelectSingleNode("//Plugin$XMLDataSource-LastSessionTimestamp")."#text")

        $LastSuccessStatusRaw = $xml.SelectSingleNode("//Plugin$XMLDataSource-LastSuccessfulSessionStatus")."#text"
        if ($null -eq $LastSuccessStatusRaw) {
            Out-Line "`n[$datasource Session]"
            Out-Line "28-Day Status             | $ColorBarReversed"
            Out-Line "Last Success              | Never"
            Out-Line "No prior $datasource backup has completed" -Warn
        } else {
            $LastSuccessStatus = $ReplaceStatus[$LastSuccessStatusRaw]
            $LastSuccessTime   = Convert-UnixTimeToDateTime($xml.SelectSingleNode("//Plugin$XMLDataSource-LastSuccessfulSessionTimestamp")."#text")
            $LastCompleteStatus= $ReplaceStatus[$xml.SelectSingleNode("//Plugin$XMLDataSource-LastCompletedSessionStatus")."#text"]
            $LastCompleteTime  = Convert-UnixTimeToDateTime($xml.SelectSingleNode("//Plugin$XMLDataSource-LastCompletedSessionTimestamp")."#text")
            $LastErrorCount    = $xml.SelectSingleNode("//Plugin$XMLDataSource-LastSessionErrorsCount")."#text"
            $SessionDurationHrs= ($xml.SelectSingleNode("//Plugin$XMLDataSource-SessionDuration")."#text" / 60 / 60)
            $Retention         = $xml.SelectSingleNode("//Plugin$XMLDataSource-Retention")."#text"
            $RetentionUnits    = $xml.SelectSingleNode("//RetentionUnits")."#text"

            Out-Line "`n[$datasource Session]"
            Out-Line "28-Day Status             | $ColorBarReversed"
            Out-Line "Last Session (UTC)        | $LastSessionTime $LastSessionStatus"
            Out-Line "Last Success (UTC)        | $LastSuccessTime $LastSuccessStatus"
            Out-Line "Last Complete (UTC)       | $LastCompleteTime $LastCompleteStatus"
            Out-Line "Session Duration (HRS)    | $([math]::Round($SessionDurationHrs,2))"
            Out-Line "Last Error Count          | $LastErrorCount"
            Out-Line "Retention                 | $Retention $RetentionUnits"

            if ($LastSuccessTime) {
                $HoursSinceLast = [math]::Round((New-TimeSpan -Start $LastSuccessTime -End (Get-Date).ToUniversalTime()).TotalHours, 2)
                if ($HoursSinceLast -le $Script:SuccessHoursInVal) {
                    Out-Line "Last Success              | $HoursSinceLast(HRS) Ago"
                } else {
                    Out-Line "Last Success $HoursSinceLast(HRS) Ago exceeds threshold $($Script:SuccessHoursInVal)(HRS)" -Warn
                }
            }

            if ([int]$LastErrorCount -ge 1) {
                Get-BackupErrors $datasource $ErrorLimit
            }
        }
    } else {
        Out-Line "No prior $datasource backup has completed" -Warn
    }
}

## ---- Get errors for a data source via ClientTool.exe ----
Function Get-BackupErrors ($datasource, $limit) {
    $retrycounter = 0
    $clienttool   = "C:\Program Files\Backup Manager\ClientTool.exe"
    if ($null -eq $Script:FunctionalProcess) {
        Out-Line "Backup Manager Not Running" -Warn
        return
    }
    Do {
        $BackupStatus = & $clienttool -machine-readable control.status.get
        if ($BackupStatus -ne "Suspended") {
            try {
                $ErrorActionPreference = 'Stop'
                $sessionsTSV = "C:\ProgramData\MXB\Backup Manager\$datasource.Sessions.tsv"
                $errorsTSV   = "C:\ProgramData\MXB\Backup Manager\$datasource.Errors.tsv"
                & $clienttool -machine-readable control.session.list -datasource $datasource > $sessionsTSV
                $sessions    = Import-Csv -Delimiter "`t" -Path $sessionsTSV
                $lastsession = ($sessions | Where-Object { ($_.type -eq "Backup") -and ($_.State -ne "Skipped") })[0]
                & $clienttool -machine-readable control.session.error.list -datasource $datasource -limit $limit -time $lastsession.start > $errorsTSV
                $sessionerrors = Import-Csv -Delimiter "`t" -Path $errorsTSV
                if ($sessionerrors) {
                    Out-Line "[$datasource] Errors Found" -Warn
                    $sessionerrors | Select-Object DateTime,Content,Path | Sort-Object -Descending DateTime |
                        Format-Table | Out-String | ForEach-Object { Out-Line $_ }
                } else {
                    Out-Line "[$datasource Errors] None"
                }
            } catch {
                Out-Line "[$datasource] Error retrieving session errors: $_" -Warn
            }
        }
        $retrycounter++
    } until (($BackupStatus -ne "Suspended") -or ($retrycounter -ge 5))
}

## ---- Main Execution ----

Get-BackupState

if ($Script:BackupServiceOutVal -lt 0) {
    # Not installed — exit cleanly (no alert)
    Write-Output "Cove Backup Manager not installed on this device."
    Exit 0
}

if ($Script:BackupServiceOutVal -eq 0) {
    # Service present but not running — already flagged as failed inside Get-BackupState
    if ($WriteCustomField) {
        try { Ninja-Property-Set 'coveMonitorStatus' ($global:output -join "`n") } catch {}
    }
    Exit 1
}

Get-StatusReportBase
Get-Status $SynchThreshold
Get-Datasources

foreach ($datasource in $script:Datasources) {
    Out-Line "`n--------- --------- --------- --------- --------- ---------"
    Get-StatusReport
    Start-Sleep -Seconds 2
}

## ---- Write summary to NinjaOne custom field (optional) ----
if ($WriteCustomField) {
    $summary = $global:output -join "`n"
    try { Ninja-Property-Set 'coveMonitorStatus' $summary } catch {}
}

## ---- Exit with NinjaOne-compatible code ----
if ($global:failed -eq 1) {
    Exit 1   ## Non-zero exit triggers NinjaOne condition alert
} else {
    Exit 0
}
