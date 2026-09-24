# Stale debug IPC escrow convention in scripts and docs (follow-up)

Found 2026-09-24 during drawer S8 headless proof. Not fixed in the drawer PR.

## What changed
`AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW` no longer means "enable escrow". It names
the owner-only file that the debug app writes its credential to:
- The document is `IPCDebugCredentialEscrowDocument`: `{runtimeId, socketPath, token}`.
  See `Sources/AgentStudioProgrammaticControl/IPCDebugCredentialEscrowDocument.swift`.
- The app writes it through `AgentStudioIPCFilesystem.writeDebugCredentialEscrow`
  (`Sources/AgentStudioAppIPC/AgentStudioIPCPaths.swift:197`).
- That write requires the file's parent directory to exist. The file is created
  with mode 0600.
- The app reads the variable in `AppDelegate+IPC.swift`
  (`appIPCDebugCredentialEscrowURL`).

With `=1`, the app resolves the relative path `1`, so the escrow write fails.
The app still reports authenticated IPC, but no credential reaches any client.
`$DATA_DIR/ipc/debug-token` is never written.

## Where the old `=1` / `ipc/debug-token` convention remains
Scripts:
- `scripts/verify-sidebar-performance-workload.sh`
- `scripts/verify-title-pane-performance-workload.sh`
- `scripts/verify-agentstudio-ipc-phase-a-smoke.sh`
- `scripts/verify-git-refresh-performance-workload.sh`
- `scripts/run-bridge-packaged-product-journey.sh`
- `scripts/verify-sidebar-native-table-pilot.sh`

Docs:
- `docs/architecture/observability/observability_and_traceability.md` (IPC escrow section)
- `docs/wip/2026-09-07-app-only-reliability-audit/takeover-state.md`
- Several older plans under `docs/specs/*/plans/`. These are historical; update
  them only if they are still followed.

## Working pattern (drawer S8 driver)
1. Set `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=<data root>/debug-credential.json`.
   Create the data root first with mode 0700.
2. Wait until the file's `runtimeId` equals the one in `<data root>/ipc/runtime.json`.
3. Read `token` into memory only.
4. Send `auth.login {token}`.

Reference implementation: the drawer S8 scratch driver `s8_driver.py`
(`escrow_path`, `start_app`).
