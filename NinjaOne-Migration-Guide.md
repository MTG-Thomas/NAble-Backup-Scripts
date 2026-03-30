# NinjaOne Migration Guide — Cove Data Protection Monitoring Scripts

> **Context**: This guide evaluates every script in this repository for adaptation to **NinjaOne** as the RMM platform, monitoring **N-able Cove Data Protection (Standalone Edition)**. The migration is FROM DattoRMM TO NinjaOne.
>
> **Disclaimer**: All scripts in this repository are sample code provided **AS IS** with no warranty. Test thoroughly before production use. Some scripts use non-public Cove APIs that may change without notice.

---

## Quick-Start: Already-Ready NinjaOne Scripts

Two deployment scripts in `Deployment/NinjaOne/` already support NinjaOne natively with no changes needed:

| Script | What It Does |
|--------|-------------|
| `Cove_NinjaOne_Deploy.v26.02.ps1` | Installs Cove Backup Manager using a `CoveInstallationID` NinjaOne device custom field (GUID format). HTTPS/HTTP fallback, idempotent (skips if already installed). **Use this one.** |
| `N-able_CoveDataProtection_DeployBackupManager_NinjaOne.v24.10.ps1` | Alternative deployment using `coveCustomerUID`, `coveBackupDefaultProfileID`, and `coveBackupDefaultProduct` custom fields. Useful for profile/product-based deployments. |

Official N-able documentation: <https://documentation.n-able.com/covedataprotection/USERGUIDE/documentation/Content/external-cove-integrations/ninjaOne/NinjaOne.htm>

---

## Full Script Inventory & Evaluation

| Script Name | Folder | Purpose | RMM Coupling | NinjaOne Use Case | Priority |
|---|---|---|---|---|---|
| `Cove.Monitoring.v20.minimalist.ps1` | Monitoring | Checks Cove service status, data sources, LSV sync %, and error counts on a local device. Outputs `WARNING:` prefixed lines for any threshold breach. | **None** — reads local `StatusReport.xml` and queries `ClientTool.exe`; no N-central dependency | **Script Policy (Condition)** — trigger alert on `WARNING:` output; optionally write summary to a NinjaOne WYSIWYG or text custom field | **HIGH** |
| `LSVSyncCheckFinal.v12.ps1` | LocalSpeedVault | Checks LSV sync percentage and cloud sync status by parsing `Status.xml`. Fails if sync is stuck or below threshold. | **None** — local XML read only; references SolarWinds branding but logic is fully standalone | **Script Condition** — run as scheduled check; exit non-zero on sync failure triggers NinjaOne alert | **HIGH** |
| `GetClientErrors.v03.ps1` | Troubleshooting | Runs `ClientTool.exe` commands to pull initialization errors, application status, current session errors, and recent backup session details. Loops/retries if service is not yet running. | **None** — pure `ClientTool.exe` wrapper; no N-central, no API | **Scheduled Script / Runbook** — run on demand or on backup alert; output to NinjaOne activity log or text custom field | **HIGH** |
| `SetBackupLogging.v04.ps1` | Troubleshooting | Sets the Backup Manager log verbosity level via `ClientTool.exe`. Used during troubleshooting to capture detailed logs. | **None** — `ClientTool.exe` only | **Script Policy (on demand)** — trigger before collecting logs; pass log level via NinjaOne script variable | **HIGH** |
| `CoveDataProtection.SetDefenderExclusions.v24.02.11.ps1` | Security | Adds Backup Manager and Recovery Console paths/processes to Windows Defender exclusions. Reduces AV interference with backup operations. | **None** — pure PowerShell Defender cmdlets; fully standalone | **Script Policy (one-shot deployment)** — run once per device post-install; no custom fields needed | **HIGH** |
| `SetLocalSpeedVault.v03.ps1` | LocalSpeedVault | Configures LSV path (local disk, network share, or disabled) via `ClientTool.exe`. Supports credentials for network LSV. | **None** — `ClientTool.exe` only | **Script Policy (Scheduled Task)** — deploy LSV config; pass path/mode/credentials via NinjaOne secure custom fields | **HIGH** |
| `Cove_NinjaOne_Deploy.v26.02.ps1` | Deployment/NinjaOne | Downloads and silently installs latest Cove Backup Manager using a NinjaOne device custom field for the Installation ID. | **NinjaOne native** — already uses `Ninja-Property-Get 'CoveInstallationID'` | **Script Policy (deployment)** — ready to use as-is; set `CoveInstallationID` (GUID) on the device | **HIGH** |
| `N-able_CoveDataProtection_DeployBackupManager_NinjaOne.v24.10.ps1` | Deployment/NinjaOne | Alternative deployment using UID + Profile ID + Product fields. | **NinjaOne native** — uses `Ninja-Property-Get` for three custom fields | **Script Policy (deployment)** — use when profile/product-name control is required | **HIGH** |
| `SyncOffsiteVault.v10.1.ps1` | LocalSpeedVault | Forces an immediate LSV → cloud sync via `ClientTool.exe`. Useful when LSV is behind after an outage. | **None** — `ClientTool.exe` only | **Script Policy (on demand)** — trigger manually or after LSV sync alert resolves | **MEDIUM** |
| `BulkGetDeviceErrors.v30.ps1` | Troubleshooting | Queries the Cove API for device-level errors across all managed devices. Posts errors to custom column AA2045; exports CSV. | **Low** — API-based; requires stored Cove API credentials (DPAPI); designed for console/workstation run not agent run | **Scheduled Task (management workstation)** — run from a NinjaOne-managed management host; store API credentials as NinjaOne org-level secure custom fields | **MEDIUM** |
| `GetDeviceStatistics.v07.ps1` | Reporting | Pulls per-device backup statistics (selected size, used storage, last backup time, device type) from Cove API. Exports to CSV. | **Low** — Cove API only; DPAPI credential storage | **Scheduled Task (management workstation)** — export stats to CSV/custom field on management host; feed into NinjaOne dashboard via custom fields | **MEDIUM** |
| `CoveDataProtection.HealthCheck.v07.ps1` | Prototype | Comprehensive per-device health check via Cove API. Requires PowerShell 7+. | **Low** — Cove API; DPAPI credentials | **Scheduled Task (management workstation)** — run from management host; output to CSV/custom field. Requires pwsh 7+ (available on NinjaOne agents with PS7 installed) | **MEDIUM** |
| `GetRecoveryTestStatistics.v03.ps1` | Reporting | Retrieves DR/recovery test results and metrics from Cove API. Exports to XLS/CSV. | **Low** — Cove API only | **Scheduled Task (management workstation)** — useful for monthly DR test evidence; output to custom field or attached report | **MEDIUM** |
| `ExcludeSpeedVault.v01.ps1` | LocalSpeedVault | Configures LSV exclusion filters via `ClientTool.exe`. | **None** — `ClientTool.exe` only | **Script Policy** — run post-LSV-configuration to set exclusions | **MEDIUM** |
| `GetAllDeviceInstallations.v08.ps1` | Reporting | Tracks installation history across all Cove devices from API. Useful for auditing upgrades. | **Low** — Cove API only | **Scheduled Task (management workstation)** | **LOW** |
| `GetDeletedDevices.v08.ps1` | Reporting | Lists devices deleted within the 28-day recovery window from API. | **Low** — Cove API only | **Scheduled Task (management workstation)** — periodic hygiene report | **LOW** |
| `GetSessionFiles.v22.ps1` | Reporting | Enumerates files within specific backup sessions via API. Useful for restore verification. | **Low** — Cove API only | **On-demand script** on management workstation | **LOW** |
| `GetMaxValuePlusReport.CoveDP.v24.05.21.multiselect.ps1` | Reporting | Generates MaxValue+ billing/capacity report from Cove API. Multiple partner selection. | **Low** — Cove API only | **Scheduled Task (management workstation)** — monthly billing run | **LOW** |
| `GetReports.CoveDP.v23.12.ps1` | Reporting | General reporting tool pulling multiple device metrics from Cove API. | **Low** — Cove API only | **Scheduled Task (management workstation)** | **LOW** |
| `AddNotifierUser.v05.ps1` | Reporting | Adds notification/alert email recipients to Cove devices via API. | **Low** — Cove API only | **One-shot script on management workstation** | **LOW** |
| `BulkSetSettingsMailAddress.v03.ps1` | Reporting | Bulk-updates notification email addresses across devices via API. | **Low** — Cove API only | **One-shot script on management workstation** | **LOW** |
| `GetDeviceLocation.v02.ps1` | Reporting | Retrieves device location metadata from Cove API. | **Low** — Cove API only | **Reporting only** | **LOW** |
| `Get-Foldersizes.ps1` | Reporting | Measures backup folder sizes locally. | **None** — local filesystem | **On-demand diagnostic script** | **LOW** |
| `CDP.DeleteOrphanedInactiveDevices.v25.02.23.ps1` | Retention | Deletes orphaned/inactive Cove devices via API (with confirmation). | **Low** — Cove API only; requires deletion confirmation | **Scheduled Task (management workstation)** — run with care; add NinjaOne approval step | **LOW** |
| `CleanupArchive.v24.ps1` | Retention | Removes archived backup data older than a specified threshold. | **Low** — Cove API only | **Scheduled Task (management workstation)** | **LOW** |
| `BulkSetArchiveSchedule.v04.ps1` | Retention | Sets archive schedules across multiple devices via API. | **Low** — Cove API only | **One-shot script on management workstation** | **LOW** |
| `ConvertToPassphrase.v05.ps1` | Security | Converts PrivateKey encryption to Passphrase encryption via Cove API remote commands. | **Low** — Cove API remote command | **On-demand script on management workstation** | **LOW** |
| `BulkSetGUIPassword.v11.ps1` | Security | Sets or clears the Backup Manager GUI password via Cove API remote commands. | **Low** — Cove API remote command | **On-demand script on management workstation** | **LOW** |
| `SetDeviceProduct.v18.ps1` | Settings | Sets the device retention product/policy via Cove API. | **Low** — Cove API | **One-shot script on management workstation** | **LOW** |
| `SetDeviceProfile.v18.ps1` | Settings | Assigns a backup profile to a device via Cove API. | **Low** — Cove API | **One-shot script on management workstation** | **LOW** |
| `CustomBackupThrottle.v05.ps1` | Settings | Sets schedule-based bandwidth throttling via `ClientTool.exe`. | **None** — `ClientTool.exe` only | **Script Policy** — deploy throttle schedule per device or device group | **LOW** |
| `ExcludeUSB.v11.ps1` | Settings | Adds USB/removable drives to backup exclusion filters via `ClientTool.exe` or registry. | **None** — `ClientTool.exe`/registry | **Script Policy** — deploy as post-install hardening step | **LOW** |
| `CDPAddNonInteractiveAPIUser.v08.ps1` | User | Creates a non-interactive (service account) API user in the Cove console. | **Low** — Cove API only | **One-shot setup script on management workstation** | **LOW** |
| `GetM365DeviceStatistics.v31.ps1` | M365 | Pulls M365 backup statistics (mailboxes, OneDrive, SharePoint) from Cove API. | **Low** — Cove API only | **Scheduled Task (management workstation)** — M365 capacity reporting | **LOW** |
| `CoveDataProtection.M365UserCleanup.v25.04.24.fromCSV.ps1` | M365 | Deprovisions M365 users from Cove backup based on a CSV input. | **Low** — Cove API only; CSV import | **On-demand script on management workstation** | **LOW** |
| `OffboardRestore.v10.ps1` | Clienttool | Performs automated file restores from backup sessions using `ClientTool.exe`. Filters by data source, session type, and date. | **None** — `ClientTool.exe` only | **On-demand runbook script** — run on device during offboarding/recovery | **LOW** |
| `RCsessions.v05.ps1` | Recovery Console | Monitors active Recovery Console sessions. | **None** — local only | **Diagnostic script** | **LOW** |
| `New-ScheduledTaskFromScript.v03.ps1` | Prototype | Helper to register a PowerShell script as a Windows scheduled task. | **None** — pure PowerShell | **Utility** — not needed with NinjaOne scheduled policies | **LOW** |
| `N-able.CoveDP.Migration.Prep.v24.07.23.ps1` | Migration | Migrates devices FROM N-central Integrated Cove TO Standalone Cove. Detects N-central integration, blocks N-central uninstall, updates device alias. | **HIGH** — requires N-central XML config files, `BackupIP.exe` migration flags, registry keys specific to N-central integration | ⚠️ **SKIP / Full Rewrite** — only relevant if migrating from N-central Integrated edition. Not applicable for DattoRMM → NinjaOne migration on Standalone Cove | **SKIP** |
| `GetMaxValuePlusReport.N-central.v21.ps1` | Reporting | Billing report variant built for the N-central Integrated edition. | **HIGH** — N-central edition specific | ⚠️ **SKIP** — use the `CoveDP` variant instead | **SKIP** |
| All `.amp` files | Multiple | N-able Automation Policy files for N-central/N-sight RMM. Binary/XML format specific to N-able RMM. | **HIGH** — N-central/N-sight only | ⚠️ **SKIP** — not applicable to NinjaOne; re-implement the underlying PowerShell scripts as NinjaOne Script Policies | **SKIP** |
| `Datto RMM/` folder | Deployment | Deployment scripts and AMP-equivalent files for DattoRMM. | **HIGH** — DattoRMM specific | ⚠️ **SKIP** — you are migrating away from DattoRMM | **SKIP** |
| `Kasaya VSA RMM/` folder | Deployment | Deployment scripts for Kaseya VSA. | **HIGH** — Kaseya specific | ⚠️ **SKIP** | **SKIP** |
| `N-able/` folder (Deployment) | Deployment | N-central/N-sight specific deployment scripts. | **HIGH** — N-central/N-sight only | ⚠️ **SKIP** | **SKIP** |
| macOS Bash scripts | macOS | User home merging, restore operations, user management. Written in Bash. | **None** — local Bash scripts | ⚠️ **SKIP** — Bash scripts; NinjaOne Mac scripting uses zsh/bash but these are highly macOS-user-management-specific and not backup monitoring | **SKIP** |
| Older Monitoring versions (v06–v19) | Monitoring | Previous iterations of the monitoring script. Superseded by v20. | Varies | ⚠️ **SKIP** — use `Cove.Monitoring.v20.minimalist.ps1` only | **SKIP** |
| `BulkGenerateRedeployCMDs.v33.ps1` | Deployment | Generates redeploy command strings for bulk device redeployment from a management workstation. Not an agent script. | **Low** — Cove API + DPAPI | **Workstation-only utility** — does not fit NinjaOne agent model | **SKIP** |

---

## High-Priority Script Adaptation Plans

### 1. `Cove.Monitoring.v20.minimalist.ps1` — Backup Status Monitor

**What it does today**: Reads `C:\ProgramData\MXB\Backup Manager\StatusReport.xml`, queries `ClientTool.exe` for session data and errors, outputs `WARNING:` lines for any threshold breach, and exits `1001` for N-sight RMM.

**Light-touch changes for NinjaOne**:

1. **Remove or replace the exit code** — Change `Exit 1001` to `Exit 1` (NinjaOne treats any non-zero exit as a script failure, which triggers an alert). Optionally keep `Exit 1001` if you configure the NinjaOne condition to check for specific exit codes.

2. **Optionally write status to a NinjaOne custom field** — Add the following snippet before the final `Exit` to populate a NinjaOne device text custom field with the monitoring summary:
   ```powershell
   # Write summary to NinjaOne custom field (requires 'coveMonitorStatus' text field on device)
   $summaryText = ($output -join "`n")
   Ninja-Property-Set 'coveMonitorStatus' $summaryText
   ```

3. **NinjaOne Script Policy setup**:
   - **Run as**: System (Local System account has read access to `C:\ProgramData\MXB`)
   - **Schedule**: Every 1–4 hours (match your `$ServerSuccessHoursInVal` threshold)
   - **Condition trigger**: Script exit code `!= 0` OR output contains `WARNING:`
   - **Parameters** (pass as NinjaOne script variables):
     - `$ServerSuccessHoursInVal` = 24 (servers)
     - `$WrkStnSuccessHoursInVal` = 72 (workstations)
     - `$SynchThreshold` = 90 (LSV sync %)
     - `$ErrorLimit` = 10

**Dependencies**:
- Cove Backup Manager must be installed (script exits gracefully if not)
- `ClientTool.exe` at `C:\Program Files\Backup Manager\ClientTool.exe`
- PowerShell 5.1+, run as Administrator/System
- No API credentials needed — fully local

---

### 2. `LSVSyncCheckFinal.v12.ps1` — LSV Sync Check

**What it does today**: Parses `Status.xml` from both Standalone (`C:\ProgramData\MXB`) and Integrated (`C:\ProgramData\Managed Online Backup`) paths. Reports sync % or failure.

**Light-touch changes for NinjaOne**:

1. **Standardize exit codes** — The script sets `$global:failed = 1` but the exit code behavior depends on the wrapper. Add an explicit `Exit 1` at the end if failed:
   ```powershell
   if ($global:failed) { Exit 1 } else { Exit 0 }
   ```

2. **Optionally write LSV status to a custom field**:
   ```powershell
   Ninja-Property-Set 'coveLsvSyncStatus' "$LSVSync"
   ```

3. **NinjaOne Script Policy setup**:
   - **Run as**: System
   - **Schedule**: Every 30–60 minutes
   - **Condition trigger**: Script exit code `!= 0`

**Dependencies**:
- Cove Backup Manager (Standalone edition) installed
- `C:\ProgramData\MXB\Backup Manager\StatusReport.xml` present
- PowerShell 5.1+
- No API credentials needed

---

### 3. `GetClientErrors.v03.ps1` — Local Client Error Diagnostics

**What it does today**: Runs `ClientTool.exe` commands in a loop to pull initialization errors, application status, active sessions, and recent error messages. Outputs to console.

**Light-touch changes for NinjaOne**:

1. **Remove the `Do...Until` loop** for use as a one-shot diagnostic. The loop is designed for interactive terminal use. Replace with a single-pass execution:
   ```powershell
   # Remove: Do { ... } Until ($counter -ge 3)
   # Keep the inner block as a flat script body
   ```

2. **Capture output to custom field**:
   ```powershell
   $diagnosticOutput = & "C:\Program Files\Backup Manager\ClientTool.exe" control.session-file-list.get ... | Out-String
   Ninja-Property-Set 'coveClientDiagnostics' $diagnosticOutput
   ```

3. **NinjaOne Script Policy setup**:
   - **Run as**: System
   - **Trigger**: On demand (linked to a NinjaOne condition alert) or scheduled daily
   - **Use as**: Runbook step in a NinjaOne workflow triggered by a Cove monitoring alert

**Dependencies**:
- `ClientTool.exe` at `C:\Program Files\Backup Manager\ClientTool.exe`
- Backup Service Controller must be running
- PowerShell 5.1+, Administrator/System

---

### 4. `SetBackupLogging.v04.ps1` — Set Log Verbosity

**What it does today**: Calls `ClientTool.exe control.setting.modify -name LogLevel -value <level>` to adjust backup log verbosity.

**Light-touch changes for NinjaOne**:

1. **Accept log level as a NinjaOne script variable** (already parameterized in most versions):
   ```powershell
   $LogLevel = $env:logLevel   # Pass via NinjaOne Script Variable
   if (-not $LogLevel) { $LogLevel = "Trace" }
   ```

2. **NinjaOne Script Policy setup**:
   - **Run as**: System
   - **Trigger**: On demand only (part of troubleshooting runbook)
   - **Script Variable**: `logLevel` (values: `Error`, `Warning`, `Info`, `Debug`, `Trace`)

**Dependencies**:
- `ClientTool.exe` installed
- Run as System/Administrator

---

### 5. `CoveDataProtection.SetDefenderExclusions.v24.02.11.ps1` — Defender Exclusions

**What it does today**: Adds Backup Manager and Recovery Console paths/executables to Windows Defender exclusion lists using `Add-MpPreference`.

**No changes needed for NinjaOne** — this script is already fully standalone and RMM-agnostic.

**NinjaOne Script Policy setup**:
- **Run as**: System
- **Trigger**: One-shot post-install (add to deployment workflow after `Cove_NinjaOne_Deploy.v26.02.ps1`)
- **Schedule**: Monthly (to re-apply after Windows updates that may reset Defender policy)
- **No custom fields or variables needed**

**Dependencies**:
- Windows Defender (`MpPreference` module)
- PowerShell 5.1+, Administrator/System
- No Cove installation required (safe to run pre-install)

---

### 6. `SetLocalSpeedVault.v03.ps1` — Configure LSV

**What it does today**: Calls `ClientTool.exe control.setting.modify` to set LSV path and enable/disable LSV. Supports local paths, network shares (with credentials), and NAS devices.

**Light-touch changes for NinjaOne**:

1. **Read configuration from NinjaOne custom fields**:
   ```powershell
   $LSVMode    = Ninja-Property-Get 'coveLsvMode'       # "Local", "Network", or "Disabled"
   $LSVPath    = Ninja-Property-Get 'coveLsvPath'       # UNC or local path
   $LSVUser    = Ninja-Property-Get 'coveLsvUsername'   # Network LSV only
   $LSVPass    = Ninja-Property-Get 'coveLsvPassword'   # Use NinjaOne secure custom field
   ```

2. **NinjaOne custom field types**:
   - `coveLsvMode` — Text custom field (device level)
   - `coveLsvPath` — Text custom field (device level)
   - `coveLsvUsername` — Text custom field (device level)
   - `coveLsvPassword` — **Secure** custom field (device level) — stored encrypted in NinjaOne

3. **NinjaOne Script Policy setup**:
   - **Run as**: System
   - **Trigger**: One-shot post-install or on change

**Dependencies**:
- `ClientTool.exe` installed
- Network access to LSV path if network mode
- Run as System/Administrator

---

## NinjaOne Custom Fields Reference

The following custom fields are referenced across the above adaptation plans. Create these in your NinjaOne environment under **Administration > Devices > Custom Fields**.

| Field Name | Type | Scope | Used By |
|---|---|---|---|
| `CoveInstallationID` | Text | Device | `Cove_NinjaOne_Deploy.v26.02.ps1` |
| `coveCustomerUID` | Text | Device | `N-able_CoveDataProtection_DeployBackupManager_NinjaOne.v24.10.ps1` |
| `coveBackupDefaultProfileID` | Text | Device | `N-able_CoveDataProtection_DeployBackupManager_NinjaOne.v24.10.ps1` |
| `coveBackupDefaultProduct` | Text | Device | `N-able_CoveDataProtection_DeployBackupManager_NinjaOne.v24.10.ps1` |
| `coveMonitorStatus` | Text (multiline/WYSIWYG) | Device | `Cove.Monitoring.v20.minimalist.ps1` (optional output) |
| `coveLsvSyncStatus` | Text | Device | `LSVSyncCheckFinal.v12.ps1` (optional output) |
| `coveClientDiagnostics` | Text (multiline) | Device | `GetClientErrors.v03.ps1` (optional output) |
| `coveLsvMode` | Text | Device | `SetLocalSpeedVault.v03.ps1` |
| `coveLsvPath` | Text | Device | `SetLocalSpeedVault.v03.ps1` |
| `coveLsvUsername` | Text | Device | `SetLocalSpeedVault.v03.ps1` |
| `coveLsvPassword` | Secure | Device | `SetLocalSpeedVault.v03.ps1` |

For API-based scripts running on a **management workstation** (Reporting, Troubleshooting bulk scripts), store Cove console credentials as NinjaOne **organisation-level secure custom fields**:

| Field Name | Type | Scope | Used By |
|---|---|---|---|
| `coveApiUser` | Secure | Organisation | All API-based reporting/troubleshooting scripts |
| `coveApiPassword` | Secure | Organisation | All API-based reporting/troubleshooting scripts |

### Configuration rule

When adapting scripts for NinjaOne, use **Script Policy parameters** for runtime tuning values and **custom fields** for persistent device data or script output.

For the monitoring scripts, that means values like `serverSuccessHours`, `workstationSuccessHours`, `synchThreshold`, `errorLimit`, and `writeCustomField` should remain script variables, while status summaries such as `coveMonitorStatus` should be written to a device custom field.

---

## Scripts Requiring Full Rewrite (N-central/Legacy Coupling)

The following scripts have deep N-central or legacy-RMM dependencies and cannot be lightly adapted. They would require a **full rewrite** to work in the NinjaOne + Standalone Cove context:

| Script | Reason for Full Rewrite |
|---|---|
| `N-able.CoveDP.Migration.Prep.v24.07.23.ps1` | Reads N-central integration XML (`MSPBackupManagerConfig.xml`), calls `BackupIP.exe -migration` flag, modifies N-central-specific registry keys, and blocks N-central agent from managing Cove. Not applicable to Standalone Cove or DattoRMM→NinjaOne migration. |
| `GetMaxValuePlusReport.N-central.v21.ps1` | Uses N-central Integrated edition API endpoints and authentication. Use the `CoveDP` variant (`v24.05.21`) instead. |
| All `.amp` files | N-able Automation Policy binary/XML format. Must be re-implemented as NinjaOne Script Policies with equivalent PowerShell. The underlying PowerShell logic is already available in the companion `.ps1` files in the same folders. |
| `Datto RMM/` deployment folder | Contains DattoRMM-specific component XML and variable injection patterns. Superseded by `Deployment/NinjaOne/` scripts. |
| `Kasaya VSA RMM/` deployment folder | Kaseya VSA-specific. Not applicable. |
| `N-able/` deployment subfolder | N-central/N-sight specific deployment wrappers. |

---

## Recommended NinjaOne Implementation Order

1. **Deploy**: Run `Cove_NinjaOne_Deploy.v26.02.ps1` via NinjaOne Script Policy to install Cove on new devices. Set `CoveInstallationID` GUID on each device.
2. **Harden**: Run `CoveDataProtection.SetDefenderExclusions.v24.02.11.ps1` as a post-install step.
3. **Configure LSV** (where applicable): Run `SetLocalSpeedVault.v03.ps1` with device-level custom fields.
4. **Monitor**: Add `Cove.Monitoring.v20.minimalist.ps1` as a recurring Script Policy (every 1–4 hours). Configure a NinjaOne Condition to alert on exit code `!= 0` or output containing `WARNING:`.
5. **Monitor LSV sync**: Add `LSVSyncCheckFinal.v12.ps1` as a recurring Script Policy (every 30–60 minutes) on devices with LSV enabled.
6. **Troubleshoot**: Add `GetClientErrors.v03.ps1` as an on-demand script in the NinjaOne device action menu. Link it to a runbook triggered by backup monitoring alerts.
7. **Reporting** (optional): Run `GetDeviceStatistics.v07.ps1` and `GetMaxValuePlusReport.CoveDP.v24.05.21.multiselect.ps1` from a NinjaOne-managed management workstation on a weekly/monthly schedule. Store output in NinjaOne custom fields or attached CSV reports.
