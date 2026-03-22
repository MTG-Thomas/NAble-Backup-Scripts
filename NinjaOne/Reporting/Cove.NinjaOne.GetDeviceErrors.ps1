<# ----- About: ----
    # N-able | Cove Data Protection | NinjaOne Get Device Errors (All Devices)
    # Adapted for NinjaOne from BulkGetDeviceErrors.v30.ps1
    # Source Revision: v30 - 2023-06-28, Author: Eric Harless, N-able
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
    # Authenticates to the Cove backup.management console via API and retrieves the most
    # recent error message for each device that has had an error in the last N days.
    # Exports errors to CSV and optionally writes each device's last error to a Cove
    # custom console column (AA2045) for visibility in the Cove backup.management console.
    # Credentials are read from NinjaOne organisation-level secure custom fields.
    #
    # NinjaOne Script Policy Settings:
    #   Run As:   System (Local System)
    #   Timeout:  600 seconds
    #   Schedule: Daily on a designated management workstation
    #
    # NinjaOne Custom Fields required (organisation-level secure):
    #   coveApiPartner   Secure - Exact Cove console partner name (case-sensitive)
    #   coveApiUser      Secure - Cove console login email
    #   coveApiPassword  Secure - Cove console login password
    #
    # NinjaOne Script Variables (optional):
    #   errorDays      (integer, default 14)    - Age in days of devices to include
    #   deviceCount    (integer, default 2000)  - Maximum devices to retrieve
    #   exportPath     (string)                 - Override CSV export path
    #   updateColumn   (boolean, default true)  - Write last error to Cove column AA2045
    #   columnCode     (string, default AA2045) - Custom column short ID to update/clear
    #
    # Dependencies:
    #   - Outbound HTTPS to api.backup.management
    #   - PowerShell 5.1+
    #   - Note: AA2045 custom column must be added to the Cove console to be visible
    #   - Sample scripts may contain non-public API calls subject to change
    #
    # Outputs:
    #   - CSV at <exportPath>\CoveDeviceErrors_<date>.csv
    #   - Summary to NinjaOne activity log (stdout)
# -----------------------------------------------------------#>

#Requires -Version 5.1

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## ---- Read NinjaOne Custom Fields ----
$CovePartner  = Ninja-Property-Get 'coveApiPartner'
$CoveUser     = Ninja-Property-Get 'coveApiUser'
$CovePassword = Ninja-Property-Get 'coveApiPassword'

## ---- Read NinjaOne Script Variables ----
$Days         = if ($env:errorDays    -and [int]::TryParse($env:errorDays,   [ref]$null)) { [int]$env:errorDays   } else { 14 }
$DeviceCount  = if ($env:deviceCount  -and [int]::TryParse($env:deviceCount, [ref]$null)) { [int]$env:deviceCount } else { 2000 }
$ExportPath   = if ($env:exportPath)  { $env:exportPath } else { "C:\ProgramData\NinjaRMM\Cove" }
$UpdateColumn = if ($env:updateColumn -ne $null -and $env:updateColumn -ne '') { $env:updateColumn -ne 'false' } else { $true }
$ColumnCode   = if ($env:columnCode)  { $env:columnCode } else { "AA2045" }

## ---- Validate credentials ----
if ([string]::IsNullOrWhiteSpace($CovePartner) -or
    [string]::IsNullOrWhiteSpace($CoveUser)    -or
    [string]::IsNullOrWhiteSpace($CovePassword)) {
    Write-Output "ERROR: coveApiPartner, coveApiUser, and coveApiPassword org-level secure custom fields must all be set."
    Exit 1
}

$urlJSON     = 'https://api.backup.management/jsonapi'
$Script:visa = $null

Function Convert-UnixTimeToDateTime($inputUnixTime) {
    if ($inputUnixTime -gt 0) {
        return ([datetime]'1970-01-01 00:00:00Z').ToUniversalTime().AddSeconds($inputUnixTime)
    }
    return ""
}

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
            $Script:visa = $auth.visa
            Write-Output "Authentication successful."
        } else {
            Write-Output "ERROR: Authentication failed. Check API credential custom fields."
            Exit 1
        }
    } catch {
        Write-Output "ERROR: API authentication request failed: $_"
        Exit 1
    }
}

## ---- Get partner info ----
Function Send-GetPartnerInfo ($PartnerName) {
    $data = @{
        jsonrpc = '2.0'; id = '2'; visa = $Script:visa; method = 'GetPartnerInfo'
        params  = @{ name = [string]$PartnerName }
    }
    $response    = Invoke-WebRequest -Method POST -ContentType 'application/json' `
        -Body (ConvertTo-Json $data -Depth 5) -Uri $urlJSON -SessionVariable Script:websession -UseBasicParsing
    $result      = ($response | ConvertFrom-Json).result.result
    $Script:visa = ($response | ConvertFrom-Json).visa
    $Script:PartnerId   = [int]$result.Id
    $Script:PartnerName = $result.Name
    Write-Output "Partner: $Script:PartnerName (ID: $Script:PartnerId)"
}

## ---- Get devices with errors ----
Function Send-GetErrorDevices {
    $DeviceFilter = "(T7 >= 1) AND (TS > $Days.days().ago())"

    $data = @{
        jsonrpc = '2.0'; id = '2'; visa = $Script:visa; method = 'EnumerateAccountStatistics'
        params  = @{
            query = @{
                PartnerId         = [int]$Script:PartnerId
                Filter            = $DeviceFilter
                Columns           = @("AU","AR","AN","AL","LN","OP","OI","OS","PD","AP","PF","PN","AA843","AA77","T7","TS")
                OrderBy           = "CD DESC"
                StartRecordNumber = 0
                RecordsCount      = $DeviceCount
                Totals            = @("COUNT(AT==1)","SUM(T3)","SUM(US)")
            }
        }
    }
    try {
        $response = Invoke-RestMethod -Method POST -ContentType 'application/json; charset=utf-8' `
            -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $data -Depth 6))) `
            -Uri $urlJSON -Headers @{ Authorization = "Bearer $Script:visa" }

        $Script:DeviceDetail = foreach ($d in $response.result.result) {
            [pscustomobject]@{
                AccountID   = [int]$d.AccountId
                PartnerName = $d.Settings.AR -join ''
                DeviceName  = $d.Settings.AN -join ''
                DeviceAlias = $d.Settings.AL -join ''
                Product     = $d.Settings.PN -join ''
                Profile     = $d.Settings.OP -join ''
                OS          = $d.Settings.OS -join ''
                DataSources = $d.Settings.AP -join ''
                Location    = $d.Settings.LN -join ''
                ErrorCount  = [int]($d.Settings.T7 -join '')
                TimeStamp   = Convert-UnixTimeToDateTime ($d.Settings.TS -join '')
                LastError   = ""
            }
        }
        Write-Output "Devices with errors in last $Days days: $($Script:DeviceDetail.Count)"
    } catch {
        Write-Output "ERROR: EnumerateAccountStatistics failed: $_"
        Exit 1
    }
}

## ---- Get errors per device ----
Function Get-DeviceError ($DeviceId) {
    $url2 = "https://backup.management/web/accounts/properties/api/errors/recent?accounts.SelectedAccount.Id=$DeviceId"
    try {
        $response = Invoke-RestMethod -Uri $url2 -Method GET -WebSession $Script:websession `
            -Headers @{ Authorization = "Bearer $Script:visa" } -ContentType 'application/json; charset=utf-8' `
            -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 200
        if ($response -and $response -ne '') {
            $cleaned = $response `
                -replace 'true,','"true",' `
                -replace '\[ESCAPE\[','' `
                -replace '\]\]','' `
                -replace '\\','\\' `
                -replace '&quot;','' `
                -replace ',\n        \n    ]',"`n     ]" `
                -replace '\(','(' `
                -replace '\)',')'
            $parsed = $cleaned | ConvertFrom-Json -ErrorAction SilentlyContinue
            return ($parsed.collection | Select-Object -First 1).message
        }
    } catch {}
    return ""
}

## ---- Update Cove custom column ----
Function Send-UpdateCustomColumn ($DeviceId, $ColumnId, $Message) {
    $data = @{
        jsonrpc = '2.0'; id = '2'; visa = $Script:visa
        method  = 'UpdateAccountCustomColumnValues'
        params  = @{ accountId = $DeviceId; values = @(,@($ColumnId,$Message)) }
    }
    try {
        Invoke-RestMethod -Method POST -ContentType 'application/json; charset=utf-8' `
            -Body (ConvertTo-Json $data -Depth 6) -Uri $urlJSON | Out-Null
    } catch {}
}

## ---- Main ----
Send-APICredentialsCookie
Send-GetPartnerInfo $CovePartner
Send-GetErrorDevices

if ($Script:DeviceDetail.Count -eq 0) {
    Write-Output "No devices with errors found in the last $Days days."
    Exit 0
}

## ---- Enrich with last error message and optionally update Cove column ----
$i = 0
foreach ($device in $Script:DeviceDetail) {
    $i++
    Write-Output "[$i/$($Script:DeviceDetail.Count)] Getting errors for DeviceID $($device.AccountID)..."
    $lastError = Get-DeviceError $device.AccountID
    $device.LastError = $lastError

    if ($UpdateColumn) {
        if ($lastError) {
            Send-UpdateCustomColumn $device.AccountID $ColumnCode $lastError
        } else {
            Send-UpdateCustomColumn $device.AccountID $ColumnCode ""
        }
    }
}

## ---- Export CSV ----
try {
    if (-not (Test-Path $ExportPath)) { New-Item -Type Directory -Path $ExportPath -Force | Out-Null }
    $ShortDate = Get-Date -Format "yyyy-MM-dd"
    $SafeName  = $Script:PartnerName -replace '[^a-zA-Z0-9_]',''
    $csvFile   = Join-Path $ExportPath "CoveDeviceErrors_${ShortDate}_${SafeName}.csv"
    $Script:DeviceDetail | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Output "CSV exported: $csvFile"
} catch {
    Write-Output "WARNING: CSV export failed: $_"
}

## ---- Summary ----
$Script:DeviceDetail |
    Select-Object PartnerName,AccountID,DeviceName,Product,Profile,ErrorCount,LastError,TimeStamp |
    Sort-Object PartnerName,AccountId |
    Format-Table -AutoSize | Out-String | Write-Output

Exit 0
