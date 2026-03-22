<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Get Device Statistics (All Devices)
    # Adapted for NinjaOne from GetDeviceStatistics.v07.ps1
    # Source Revision: v07 - 2021-06-24, Author: Eric Harless, N-able
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
    # Run as a NinjaOne Scheduled Task on a management workstation (NOT on backup devices).
    # Authenticates to the Cove backup.management console via API, enumerates all devices
    # under the specified partner, and exports a CSV with device statistics.
    # The CSV is saved to C:\ProgramData\NinjaRMM\Cove\ on the management workstation.
    # Credentials are read from NinjaOne organisation-level secure custom fields.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  600 seconds
    #   Schedule: Daily or weekly on a designated management workstation
    #
    # NinjaOne Custom Fields required (organisation-level secure):
    #   coveApiPartner   Secure - Exact Cove console partner name (case-sensitive)
    #   coveApiUser      Secure - Cove console login email
    #   coveApiPassword  Secure - Cove console login password
    #
    # NinjaOne Script Variables (optional):
    #   deviceCount  (integer, default 5000) - Maximum number of devices to retrieve
    #   exportPath   (string)  - Override CSV export path (default C:\ProgramData\NinjaRMM\Cove)
    #
    # Dependencies:
    #   - Outbound HTTPS to api.backup.management
    #   - PowerShell 5.1+
    #   - No Cove agent required on the management workstation
    #   - Sample scripts may contain non-public API calls subject to change
    #
    # Outputs:
    #   - CSV at <exportPath>\CoveDeviceStatistics_<date>.csv
    #   - Summary to NinjaOne activity log (stdout)
# -----------------------------------------------------------#>

#Requires -Version 5.1

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## ---- Read NinjaOne Custom Fields (organisation-level secure) ----
$CovePartner  = Ninja-Property-Get 'coveApiPartner'
$CoveUser     = Ninja-Property-Get 'coveApiUser'
$CovePassword = Ninja-Property-Get 'coveApiPassword'

## ---- Read NinjaOne Script Variables ----
$DeviceCount  = if ($env:deviceCount -and [int]::TryParse($env:deviceCount,[ref]$null)) { [int]$env:deviceCount } else { 5000 }
$ExportPath   = if ($env:exportPath)  { $env:exportPath } else { "C:\ProgramData\NinjaRMM\Cove" }

## ---- Validate credentials ----
if ([string]::IsNullOrWhiteSpace($CovePartner) -or
    [string]::IsNullOrWhiteSpace($CoveUser)    -or
    [string]::IsNullOrWhiteSpace($CovePassword)) {
    Write-Output "ERROR: coveApiPartner, coveApiUser, and coveApiPassword org-level secure custom fields must all be set."
    Exit 1
}

$urlJSON     = 'https://api.backup.management/jsonapi'
$Script:visa = $null

## ---- Authenticate ----
Function Send-APICredentialsCookie {
    $data = @{
        jsonrpc = '2.0'; id = '2'; method = 'Login'
        params  = @{ partner = $CovePartner; username = $CoveUser; password = $CovePassword }
    }
    try {
        $response = Invoke-WebRequest -Method POST -ContentType 'application/json' `
            -Body (ConvertTo-Json $data) -Uri $urlJSON -SessionVariable Script:websession -UseBasicParsing
        $auth = $response | ConvertFrom-Json
        if ($auth.visa) {
            $Script:visa   = $auth.visa
            $Script:UserId = $auth.result.result.id
            Write-Output "Authentication successful."
        } else {
            Write-Output "ERROR: Authentication failed. Check coveApiPartner, coveApiUser, coveApiPassword fields."
            Write-Output "Note: Multiple failed attempts may temporarily lock out the API user."
            Exit 1
        }
    } catch {
        Write-Output "ERROR: API authentication request failed: $_"
        Exit 1
    }
}

Function Convert-UnixTimeToDateTime($inputUnixTime) {
    if ($inputUnixTime -gt 0) {
        return ([datetime]'1970-01-01 00:00:00Z').ToUniversalTime().AddSeconds($inputUnixTime)
    }
    return ""
}

## ---- Get partner info ----
Function Send-GetPartnerInfo ($PartnerName) {
    $data = @{
        jsonrpc = '2.0'; id = '2'; visa = $Script:visa; method = 'GetPartnerInfo'
        params  = @{ name = [string]$PartnerName }
    }
    try {
        $response = Invoke-WebRequest -Method POST -ContentType 'application/json' `
            -Body (ConvertTo-Json $data -Depth 5) -Uri $urlJSON -SessionVariable Script:websession -UseBasicParsing
        $result = ($response | ConvertFrom-Json).result.result
        $Script:visa        = ($response | ConvertFrom-Json).visa
        $Script:PartnerId   = [int]$result.Id
        $Script:PartnerName = $result.Name
        $Script:Level       = $result.Level
        Write-Output "Partner: $Script:PartnerName (ID: $Script:PartnerId, Level: $Script:Level)"
    } catch {
        Write-Output "ERROR: GetPartnerInfo failed: $_"
        Exit 1
    }
}

## ---- Enumerate all devices ----
Function Send-GetDevices {
    $data = @{
        jsonrpc = '2.0'; id = '2'; visa = $Script:visa; method = 'EnumerateAccountStatistics'
        params  = @{
            query = @{
                PartnerId       = [int]$Script:PartnerId
                Filter          = ""
                Columns         = @("AU","AR","AN","MN","AL","LN","OP","OI","OS","OT","PD","AP","PF","PN","CD","TS","TL","T3","US","TB","I81","AA843","AA77")
                OrderBy         = "CD DESC"
                StartRecordNumber = 0
                RecordsCount    = $DeviceCount
                Totals          = @("COUNT(AT==1)","SUM(T3)","SUM(US)")
            }
        }
    }
    try {
        $response = Invoke-RestMethod -Method POST -ContentType 'application/json; charset=utf-8' `
            -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $data -Depth 6))) `
            -Uri $urlJSON -Headers @{ Authorization = "Bearer $Script:visa" }

        $Script:DeviceDetail = foreach ($d in $response.result.result) {
            [pscustomobject]@{
                AccountID    = [int]$d.AccountId
                PartnerID    = [string]$d.PartnerId
                PartnerName  = $d.Settings.AR -join ''
                DeviceName   = $d.Settings.AN -join ''
                ComputerName = $d.Settings.MN -join ''
                DeviceAlias  = $d.Settings.AL -join ''
                Product      = $d.Settings.PN -join ''
                ProductID    = $d.Settings.PD -join ''
                Profile      = $d.Settings.OP -join ''
                ProfileID    = $d.Settings.OI -join ''
                OS           = $d.Settings.OS -join ''
                OSType       = $d.Settings.OT -join ''
                DataSources  = $d.Settings.AP -join ''
                Location     = $d.Settings.LN -join ''
                Reference    = $d.Settings.PF -join ''
                SelectedGB   = [math]::Round(($d.Settings.T3 -join '') / 1GB, 3)
                UsedGB       = [math]::Round(($d.Settings.US -join '') / 1GB, 3)
                Created      = Convert-UnixTimeToDateTime ($d.Settings.CD -join '')
                TimeStamp    = Convert-UnixTimeToDateTime ($d.Settings.TS -join '')
                LastSuccess  = Convert-UnixTimeToDateTime ($d.Settings.TL -join '')
                Last28       = (($d.Settings.TB -join '')[-1..-28] -join '') -replace "8","!" -replace "7","!" -replace "6","?" -replace "5","+" -replace "2","-" -replace "1",">" -replace "0","X"
                Notes        = $d.Settings.AA843 -join ''
                TempInfo     = $d.Settings.AA77  -join ''
                Physicality  = $d.Settings.I81   -join ''
            }
        }
        Write-Output "Devices retrieved: $($Script:DeviceDetail.Count)"
    } catch {
        Write-Output "ERROR: EnumerateAccountStatistics failed: $_"
        Exit 1
    }
}

## ---- Main ----
Send-APICredentialsCookie
Send-GetPartnerInfo $CovePartner

Send-GetDevices

if ($Script:DeviceDetail.Count -eq 0) {
    Write-Output "No devices returned."
    Exit 0
}

## ---- Export CSV ----
try {
    if (-not (Test-Path $ExportPath)) { New-Item -Type Directory -Path $ExportPath -Force | Out-Null }
    $ShortDate   = Get-Date -Format "yyyy-MM-dd"
    $SafeName    = $Script:PartnerName -replace '[^a-zA-Z0-9_]',''
    $csvFile     = Join-Path $ExportPath "CoveDeviceStatistics_${ShortDate}_${SafeName}.csv"
    $Script:DeviceDetail | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Output "CSV exported: $csvFile"
} catch {
    Write-Output "WARNING: CSV export failed: $_"
}

## ---- Summary to stdout ----
$Script:DeviceDetail |
    Select-Object PartnerName,AccountID,DeviceName,ComputerName,Product,Profile,DataSources,SelectedGB,UsedGB,LastSuccess,Last28 |
    Sort-Object PartnerName,AccountId |
    Format-Table -AutoSize | Out-String | Write-Output

Exit 0
