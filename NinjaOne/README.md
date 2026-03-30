# NinjaOne Automation Scripts — Cove Data Protection

Ready-to-load NinjaOne Script Policies adapted from the source scripts in this repository.
All scripts target the **Standalone edition** of N-able Cove Data Protection and are designed
for a migration from DattoRMM to NinjaOne.

See [`NinjaOne-Migration-Guide.md`](../NinjaOne-Migration-Guide.md) for full evaluation,
priority ratings, custom fields reference, and implementation order.

---

## Folder Contents

| Script | Type | Schedule | Run On |
|---|---|---|---|
| **Monitoring/** | | | |
| `Cove.NinjaOne.Monitor.ps1` | Condition Script | Every 1–4 hours | Each protected device |
| **LocalSpeedVault/** | | | |
| `Cove.NinjaOne.LSVSyncCheck.ps1` | Condition Script | Every 30–60 min | Devices with LSV enabled |
| `Cove.NinjaOne.SetLocalSpeedVault.ps1` | Configuration Script | One-shot | Each protected device |
| `Cove.NinjaOne.ExcludeSpeedVault.ps1` | Configuration Script | One-shot | Devices with LSV |
| **Troubleshooting/** | | | |
| `Cove.NinjaOne.GetClientDiagnostics.ps1` | Diagnostic Script | On demand | Each protected device |
| `Cove.NinjaOne.SetBackupLogging.ps1` | Diagnostic Script | On demand | Each protected device |
| **Security/** | | | |
| `Cove.NinjaOne.SetDefenderExclusions.ps1` | Configuration Script | One-shot / Monthly | Each protected device |
| **Reporting/** | | | |
| `Cove.NinjaOne.GetDeviceStatistics.ps1` | Reporting Script | Daily / Weekly | Management workstation only |
| `Cove.NinjaOne.GetDeviceErrors.ps1` | Reporting Script | Daily | Management workstation only |
| **Settings/** | | | |
| `Cove.NinjaOne.SetBandwidthThrottle.ps1` | Configuration Script | One-shot | Each protected device |
| `Cove.NinjaOne.ExcludeUSBDrives.ps1` | Configuration Script | One-shot / Daily | Each protected device |

The deployment scripts for NinjaOne are in [`../Deployment/NinjaOne/`](../Deployment/NinjaOne/).

---

## NinjaOne Custom Fields

Create these in **NinjaOne → Administration → Devices → Custom Fields** before deploying:

### Device-level fields

| Field Name | Type | Used By |
|---|---|---|
| `CoveInstallationID` | Text | `Deployment/NinjaOne/Cove_NinjaOne_Deploy.v26.02.ps1` |
| `coveMonitorStatus` | Text (multiline) | `Cove.NinjaOne.Monitor.ps1` |
| `coveLsvSyncStatus` | Text | `Cove.NinjaOne.LSVSyncCheck.ps1` |
| `coveClientDiagnostics` | Text (multiline) | `Cove.NinjaOne.GetClientDiagnostics.ps1` |
| `coveLsvMode` | Text | `Cove.NinjaOne.SetLocalSpeedVault.ps1` — values: `Local`, `Network`, `Disable` |
| `coveLsvPath` | Text | `Cove.NinjaOne.SetLocalSpeedVault.ps1` |
| `coveLsvUsername` | Text | `Cove.NinjaOne.SetLocalSpeedVault.ps1` (Network mode) |
| `coveLsvPassword` | **Secure** | `Cove.NinjaOne.SetLocalSpeedVault.ps1` (Network mode) |

### Organisation-level fields (for management workstation API scripts)

| Field Name | Type | Used By |
|---|---|---|
| `coveApiPartner` | **Secure** | `GetDeviceStatistics`, `GetDeviceErrors` |
| `coveApiUser` | **Secure** | `GetDeviceStatistics`, `GetDeviceErrors` |
| `coveApiPassword` | **Secure** | `GetDeviceStatistics`, `GetDeviceErrors` |

---

## Configuration Pattern

Use **NinjaOne Script Variables** for runtime tuning and **custom fields** for persistent device state or script output.

For example, the monitor script reads `serverSuccessHours`, `workstationSuccessHours`, `synchThreshold`, `errorLimit`, and `writeCustomField` as script variables, while writing the summary to the device-level `coveMonitorStatus` custom field when enabled.

Prefer this split during future script analysis:

- **Script variables** for thresholds, limits, booleans, and other run-time behavior.
- **Custom fields** for device-specific inputs, stored credentials, and output that should persist on the device.

---

## Script Variables Quick Reference

Each script reads NinjaOne Script Variables via `$env:variableName`.
Set these in the NinjaOne Script Policy → Parameters section.

### `Cove.NinjaOne.Monitor.ps1`

| Variable | Default | Description |
|---|---|---|
| `serverSuccessHours` | `24` | Hours since last success before warning — servers |
| `workstationSuccessHours` | `72` | Hours since last success before warning — workstations |
| `synchThreshold` | `90` | LSV sync % below which a warning is raised |
| `errorLimit` | `10` | Max error messages shown per data source |
| `writeCustomField` | `true` | Write summary to `coveMonitorStatus` custom field |

### `Cove.NinjaOne.LSVSyncCheck.ps1`

| Variable | Default | Description |
|---|---|---|
| `writeCustomField` | `true` | Write status to `coveLsvSyncStatus` custom field |

### `Cove.NinjaOne.GetClientDiagnostics.ps1`

| Variable | Default | Description |
|---|---|---|
| `writeCustomField` | `true` | Write output to `coveClientDiagnostics` custom field |

### `Cove.NinjaOne.SetBackupLogging.ps1`

| Variable | Default | Description |
|---|---|---|
| `logLevel` | `Warning` | `Warning`, `Error`, `Log`, or `Debug` |
| `restartService` | `false` | Restart Backup Service after applying |

### `Cove.NinjaOne.SetLocalSpeedVault.ps1`

All configuration read from device custom fields (see above) — no script variables.

### `Cove.NinjaOne.SetBandwidthThrottle.ps1`

| Variable | Default | Description |
|---|---|---|
| `uploadKbps` | `4096` | Upload throttle Kbps during business hours |
| `downloadKbps` | `4096` | Download throttle Kbps during business hours |
| `onAt` | `08:00` | Throttle start time (HH:mm) |
| `offAt` | `18:00` | Throttle end time (HH:mm) |
| `throttleWeekends` | `false` | Apply throttle on Saturday/Sunday |

### `Cove.NinjaOne.GetDeviceStatistics.ps1` and `Cove.NinjaOne.GetDeviceErrors.ps1`

| Variable | Default | Description |
|---|---|---|
| `deviceCount` | `5000` / `2000` | Maximum devices to retrieve |
| `exportPath` | `C:\ProgramData\NinjaRMM\Cove` | CSV export directory |
| `errorDays` | `14` | (GetDeviceErrors only) Age in days of devices to include |
| `updateColumn` | `true` | (GetDeviceErrors only) Update Cove custom column AA2045 |
| `columnCode` | `AA2045` | (GetDeviceErrors only) Column code to update |

---

## Recommended Implementation Order

1. Set `CoveInstallationID` on each device → run `Deployment/NinjaOne/Cove_NinjaOne_Deploy.v26.02.ps1`
2. Run `Cove.NinjaOne.SetDefenderExclusions.ps1` (post-install hardening)
3. Set `coveLsvMode` / `coveLsvPath` → run `Cove.NinjaOne.SetLocalSpeedVault.ps1` (LSV devices)
4. Run `Cove.NinjaOne.ExcludeSpeedVault.ps1` (after LSV is configured)
5. Run `Cove.NinjaOne.ExcludeUSBDrives.ps1` (optional USB exclusion hardening)
6. Configure `Cove.NinjaOne.SetBandwidthThrottle.ps1` Script Policy (optional throttle)
7. Add `Cove.NinjaOne.Monitor.ps1` as a recurring Condition Policy (every 1–4 hours)
8. Add `Cove.NinjaOne.LSVSyncCheck.ps1` as a recurring Condition Policy (every 30–60 min, LSV devices only)
9. Add `Cove.NinjaOne.GetClientDiagnostics.ps1` as an on-demand device action
10. Add `Cove.NinjaOne.SetBackupLogging.ps1` as an on-demand device action (troubleshooting runbook)
11. Set `coveApiPartner` / `coveApiUser` / `coveApiPassword` org fields → add `Cove.NinjaOne.GetDeviceStatistics.ps1` and `Cove.NinjaOne.GetDeviceErrors.ps1` as scheduled tasks on a management workstation

---

> **Disclaimer**: All scripts are provided AS IS without warranty. Test in a non-production
> environment before deploying. Some scripts use non-public Cove APIs that may change.
