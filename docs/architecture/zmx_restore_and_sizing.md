# Zmx Restore and Sizing

## Goal

Keep session restore reliable while ensuring restored panes get correct terminal geometry (`cols`/`rows`) without requiring manual input.

## Identity Source of Truth

`PaneId` is the primary identity. zmx session names are deterministic derived keys.
Canonical derivation and lookup ownership live in:
[Session Lifecycle — Identity Contract (Canonical)](session_lifecycle.md#identity-contract-canonical).

## Lifecycle Facts (Ghostty + zmx)

1. Ghostty surface creation, geometry, visibility, and focus are separate concerns.
2. `ghostty_surface_set_size` updates terminal geometry even when a surface is not visible.
3. `ghostty_surface_set_occlusion` controls visibility/occlusion separately from geometry.
4. zmx can attach at placeholder size and reconcile later resize, but this may cause temporary reflow/flicker.
5. For best UX, attach should prefer known-good geometry when available.

## Runtime Flow

1. Pane startup launches an interactive shell first (`zsh -i -l`).
2. Zmx attach command is stored as `deferredStartupCommand`.
3. Ghostty surface waits for readiness:
   - surface is in a window,
   - content size is non-zero,
   - process is still alive,
   - deferred attach was not already sent.
4. Once ready, AgentStudio injects zmx attach text and sends a real Return key event.

This prevents early attach against placeholder geometry during startup.

## Two Attach Paths (Current + Target)

1. Active/visible panes:
   - Keep strict readiness (window + non-zero content size + process alive).
   - Attach after first stable size signal.
2. Background panes:
   - Preferred target: attach with persisted geometry (no visibility requirement), then reconcile on reveal.
   - Fallback: shell warm in background, deferred attach when visibility gate opens.

This split maps directly to anti-flicker goals for LUNA-295 while preserving startup safety for visible panes.

## Why Not Immediate Attach

Immediate attach during startup was tested and produced unstable behavior:

1. restored panes could keep wrong width/column state,
2. startup flicker increased,
3. attach timing was sensitive to view/window ordering.

Deferred attach after readiness is the stable default.

## Restart Reconcile Policy (LUNA-324)

On app launch, restore flow should reconcile persisted state against live zmx daemons before surface creation:

1. Run one `zmx list` snapshot (with `ZMX_DIR`) and build live session set.
2. Classify persisted sessions:
   - persisted + live: mark runnable and restore surface.
   - persisted + missing: mark expired and show restart placeholder.
3. Classify runtime-only sessions:
   - live + not persisted: orphan candidate (grace period before kill).
4. Start periodic health monitoring after restore.

`sessionId` in this document means the zmx daemon session name, not the primary
pane identity.

## Orphan Cleanup TTL Policy

1. Orphans are never killed immediately at discovery.
2. Apply a grace TTL (for example, 60s) before cleanup.
3. Re-check liveness before kill at TTL expiration.
4. Log discovery time, kill attempt time, and outcome.

## Test Coverage

### Unit

1. `DeferredStartupReadinessTests`
   - validates readiness policy for scheduling and execution.
   - protects sizing gate semantics (window + non-zero dimensions required).

2. `ZmxBackendTests`
   - validates zmx session name format, attach command shape, env handling, and kill/discover logic.

### Integration

1. `ZmxBackendIntegrationTests`
   - validates behavior against a real zmx binary with isolated `ZMX_DIR`.

### End-to-End

1. `ZmxE2ETests`
   - full lifecycle: create, health check, orphan discovery, kill.
   - restore semantics: backend recreation can rediscover and kill existing live sessions.

## What Is Not Fully Automated Yet

GUI-level verification of rendered prompt wrapping/visual flicker across pane resize still requires manual validation, because current test targets do not drive AppKit layout + Ghostty rendering end-to-end.

The automated suites cover the attach/sizing gate policy and zmx daemon lifecycle to reduce regression risk in restore behavior.

## Ticket Mapping

- `LUNA-295`: `Two Attach Paths (Current + Target)` → see also [Contract 5a: Attach Readiness Policy](pane_runtime_architecture.md#contract-5a-attach-readiness-policy-luna-295)
- `LUNA-324`: `Restart Reconcile Policy (LUNA-324)` and `Orphan Cleanup TTL Policy` → see also [Contract 5b: Restart Reconcile Policy](pane_runtime_architecture.md#contract-5b-restart-reconcile-policy-luna-324)
- `LUNA-342`: `Lifecycle Facts (Ghostty + zmx)` and contract wording in this document
