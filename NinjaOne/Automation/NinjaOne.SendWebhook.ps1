<# ----- About: ----
    # Generic Webhook Sender for NinjaOne Monitoring Scripts
    # Abstracted webhook delivery for any monitoring failure
# -----------------------------------------------------------#>

<# ----- Usage: ----
    # To be called from other NinjaOne scripts with monitoring context:
    # 
    # & "C:\Path\To\NinjaOne.SendWebhook.ps1" `
    #   -ConditionName "Cove Backup Failure" `
    #   -Severity "MAJOR" `
    #   -Message "Backup failed with errors..." `
    #   -AlertData "{ 'errors': 2, 'lastSuccess': '2026-04-14T02:53:14Z' }"
#
    # Or via NinjaOne Script Policy with parameters
# -----------------------------------------------------------#>

#Requires -Version 5.1

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]  [string]$ConditionName,
    [Parameter(Mandatory=$false)] [string]$Severity        = "MAJOR",
    [Parameter(Mandatory=$false)] [string]$Priority        = "HIGH",
    [Parameter(Mandatory=$true)]  [string]$Message,
    [Parameter(Mandatory=$false)] [string]$AlertData        = "{}"
)

# ---- Webhook Configuration ----
# These could be NinjaOne script variables for per-environment configuration
$BifrostWebhookUrl = $env:webhookUrl
$BifrostSecret     = $env:webhookSecret

if (-not $BifrostWebhookUrl) {
    $BifrostWebhookUrl = "https://dev.bifrost.midtowntg.com/api/hooks/d597a682-8e33-4cf9-87f6-56f925955b9b"
}

if (-not $BifrostSecret) {
    Write-Output "WARNING: webhookSecret environment variable is required."
    Exit 0
}

## ---- Send Bifrost Webhook ----
Function Send-BifrostWebhook {
    param(
        [Parameter(Mandatory=$true)][string]$WebhookUrl,
        [Parameter(Mandatory=$true)][string]$Secret,
        [Parameter(Mandatory=$true)][hashtable]$Payload
    )
    
    try {
        $jsonPayload = $Payload | ConvertTo-Json -Depth 10 -Compress
        
        # Compute HMAC-SHA256 signature
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Secret)
        $signature = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($jsonPayload))
        $signatureHex = [BitConverter]::ToString($signature).Replace("-", "").ToLower()
        
        $headers = @{
            "Content-Type" = "application/json"
            "X-Signature-256" = $signatureHex
        }
        
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method POST -Headers $headers -Body $jsonPayload -TimeoutSec 30
        Write-Output "Webhook sent successfully to Bifrost"
        return @{ Success = $true; Response = $response }
    }
    catch {
        Write-Output "Failed to send webhook: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

## ---- Gather Device Context from NinjaOne Environment Variables ----
$DeviceId          = $env:NINJA_DEVICE_ID
$OrgId             = $env:NINJA_ORGANIZATION_ID
$DeviceName        = $env:NINJA_DEVICE_NAME
$OrgName           = $env:NINJA_ORGANIZATION_NAME

if (-not $DeviceName) { $DeviceName = $env:COMPUTERNAME }
if (-not $DeviceId)   { $DeviceId   = "0" }
if (-not $OrgId)      { $OrgId      = "0" }
if (-not $OrgName)    { $OrgName    = "Unknown" }

## ---- Build Webhook Payload ----
$timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$seriesUid = [Guid]::NewGuid().ToString()

$webhookPayload = @{
    activityType  = "CONDITION_TRIGGERED"
    deviceId      = [int]$DeviceId
    device        = @{
        systemName = $DeviceName
        displayName = $DeviceName
        id = [int]$DeviceId
        references = @{
            organization = @{
                id = $OrgId
                name = $OrgName
            }
        }
    }
    conditionName = $ConditionName
    severity      = $Severity
    priority      = $Priority
    message       = $Message
    alertData     = $AlertData
    seriesUid     = $seriesUid
    timestamp     = $timestamp
}

## ---- Send the Webhook ----
$result = Send-BifrostWebhook -WebhookUrl $BifrostWebhookUrl -Secret $BifrostSecret -Payload $webhookPayload

## ---- Output Result ----
if ($result.Success) {
    Write-Output "SUCCESS: Webhook sent for condition '$ConditionName'"
    Write-Output "Series UID: $seriesUid"
    Exit 0
} else {
    Write-Output "WARNING: Webhook send failed - $($result.Error)"
    # Exit 0 because the calling monitor should decide if this is a failure
    Exit 0
}
