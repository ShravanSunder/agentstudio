# AgentStudio IPC Terminal Runtime Surface Proof Follow-Up Plan

**Date:** 2026-06-16
**Parent goal:** `2026-06-15-command-planes-precursor`
**Parent PR:** #179, `ipc-runtime-lifecycle-followup`
**Status:** Follow-up split from the command-planes precursor proof gate.

## Purpose

Close the remaining live-product proof gap for headless terminal control.

The command-planes precursor proves the architecture cleanup, IPC query/layout
control, command-plane naming, runtime-command dispatch ownership, and docs. It
does not prove full live terminal runtime control because the debug app failed
to create a ready terminal surface during `ipc-terminal-smoke`.

## Current Evidence

Clean debug run:

- app identity: `Agent Studio Debug wpzc`;
- debug data root: `~/.agentstudio-db/wpzc/runs/ipc-proof-1781577761`;
- startup diagnostic action:
  `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke`;
- marker: `debug-observability-wpzc-1781577768-95699`;
- successful IPC control:
  `identify`, `list-panes`, `command-list`, raw JSON-RPC `pane.split`,
  `drawer.addPane`, and `drawer.toggle`;
- failed terminal runtime proof:
  `terminal.status` returned `runtime not ready`;
- Victoria diagnostic fields:
  `terminal_view.count=1`, `surface_reference.count=0`, `surface.count=0`,
  `valid_geometry.count=0`, `render_proof.succeeded=false`.

The failure is before command execution. The terminal pane exists, but the
surface reference and geometry proof do not.

## Scope

- Diagnose why debug startup produces a terminal view without a registered
  surface reference.
- Prove the terminal surface lifecycle reaches ready state in the isolated
  debug app.
- Exercise app-level IPC terminal control against a real ready terminal pane:
  `terminal.status`, `terminal.snapshot`, `terminal.send`, and
  `terminal.wait`.
- Keep public control as AgentStudio app-level IPC.
- Preserve the command-plane boundary from PR #179:
  IPC -> app/runtime ports -> runtime owners, with no direct atom mutation and
  no EventBus command routing.

## Non-Goals

- No public `zmx.*` IPC surface.
- No new raw terminal buffer readback permission.
- No broad command catalog expansion.
- No release tagging.
- No weakening of terminal surface readiness proof to synthetic unit coverage.

## Hypotheses To Test

1. The debug startup diagnostic runs before the terminal mount publishes a
   trusted surface reference.
2. The pane/view registry has a terminal view, but `SurfaceManager` creation
   fails or is not wired to the startup diagnostic probe.
3. The diagnostic waits for the wrong lifecycle fact: terminal view existence
   rather than surface reference plus valid geometry.
4. The isolated debug app path or Ghostty/zmx resource setup prevents surface
   creation before zmx writes logs.

## Implementation Sequence

### T1. Reproduce With Current PR Head

Commands:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 \
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke \
mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Proof:

- Victoria marker scoped to the new run.
- Debug data root and app pid recorded.
- `terminal_view.count`, `surface_reference.count`, `surface.count`,
  `valid_geometry.count`, and `render_proof.succeeded` captured.

### T2. Trace Surface Creation Failure

Inspect:

- startup diagnostic logs for `terminal.startup.surface_create_failed`;
- zmx logs under the isolated debug root;
- `SurfaceManager.createSurface` and `WorkspaceSurfaceCoordinator` terminal
  placeholder/bootstrap paths;
- `TerminalPaneMountView` surface attach/publish path.

Proof:

- A minimal root-cause note under `docs/wip/debugging/` or this plan with the
  exact failure stage.

### T3. Add A Product-Level Guard

Add or tighten a verifier/smoke assertion that fails when a terminal view exists
without a corresponding surface reference and valid geometry.

Proof:

- Red run reproduces the current failure.
- Green run passes only after the real surface lifecycle is fixed.

### T4. Prove IPC Terminal Control

Use the runtime metadata from the debug app and the app-level IPC client.

Required live operations:

- `identify`;
- `list-panes`;
- `terminal.status` for the target pane;
- `terminal.snapshot` and record `lastSequence`;
- `terminal.send` with a correlation id;
- `terminal.wait` after the snapshot sequence for a replayable runtime fact.

Proof:

- `verify-debug-observability` passes for the terminal smoke.
- VictoriaLogs show requested, dispatched, command_exercised, and render proof
  records for the same marker.
- No crash or command-bar UI path is used for headless terminal control.

## Validation Gates

- Focused tests for any changed surface/runtime/startup diagnostic code.
- `mise run lint`.
- `mise run test` or a narrower suite plus explicit reason if unrelated
  runtime infrastructure blocks the full suite.
- Live debug proof through the standard observability runner.

## Completion Condition

This follow-up is complete only when a fresh debug app run proves a ready
terminal surface and app-level IPC terminal control against that surface.
