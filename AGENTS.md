# Repository guidance

This fork contains sample N-able/Cove backup scripts and MTG NinjaOne adaptations. These scripts are provided AS IS and are outside N-able's support program; review and test them before production use. Start with `README.md`, the relevant folder README, `NinjaOne/README.md`, and `NinjaOne-Migration-Guide.md` for NinjaOne work.

## Boundaries

- Preserve Standalone versus N-central/RMM Integrated edition assumptions. The NinjaOne adaptations target Standalone Cove; do not mix editions or deployment credentials.
- `Deployment/`, `Migration/`, `Retention/`, `Security/`, and LocalSpeedVault configuration can mutate protected devices or backup history. Reporting scripts may also update Cove columns; names alone do not establish read-only behavior.
- Retention cleanup, uninstall/redeploy, migration, encryption-mode conversion, exclusions, and service restart require the exact authorized scope. Migration prep requires approval and a scheduled migration call/date as documented in `Migration/README.md`.

## Implementation and verification

Use NinjaOne script variables for runtime thresholds and booleans; custom fields for persistent device inputs and outputs. Keep passwords and API credentials in secure custom fields, never emitted in diagnostics or checked into scripts. Management-workstation API reporting scripts must not be deployed indiscriminately to endpoints.

Inspect each script's parameters, dependencies, edition handling, and mutation paths before selecting a validation plan. No repository-wide automated test or CI gate was found in the current tree. Syntax review is insufficient proof of safe backup behavior: use non-production targets, preserve backup configuration, and verify the resulting device/API state before broad rollout. Retain vendor disclaimers and versioned script names; older integration READMEs may defer to current vendor documentation.
