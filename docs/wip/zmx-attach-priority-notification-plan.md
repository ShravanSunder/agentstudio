# ZMX Attach + Sizing + Priority Plan (Notification-Driven)

## Problem Statement

Session restore is partially working, but the user-visible experience is inconsistent:

1. startup width/columns can be wrong until manual interaction,
2. tab switch can show flicker (shell -> attach transition),
3. hidden panes are not reliably warmed in background,
4. attach ordering needs strict priority around active pane and drawers.

## Requirements (from user)

1. Session restore must work reliably.
2. Terminal cols/rows should be correct at startup without manual Enter.
3. No visible flicker on startup and tab switch.
4. Priority order:
   1. active tab active pane first,
   2. active pane drawer panes next,
   3. other visible panes in active tab,
   4. hidden/background panes last.
5. Background warming should happen soon after launch.
6. Swift 6.2 style, testable components, clear separation of concerns.

## Architectural Direction

Use a notification-driven composition model with strict layering:

1. `PaneAttachStateMachine` (pure reducer)
   - No AppKit, Ghostty, SurfaceManager imports.
   - Input: typed domain events.
   - Output: state transitions + side-effect intents.

2. `PaneAttachSchedulerService` (`@MainActor`, orchestration only)
   - Owns attach queues, priorities, retries, concurrency.
   - Consumes events from notification bridge/store.
   - Delegates effects through protocol boundaries.

3. `PaneAttachRuntime` protocol (side-effects boundary)
   - create/ensure surface
   - start deferred attach injection
   - observe size/visibility readiness
   - cancel/retry attach

4. Thin composition in existing files
   - `TerminalViewCoordinator`: create surfaces and forward events.
   - `GhosttySurfaceView`: publish size/readiness notifications.
   - `TerminalTabViewController` / action path: publish visibility/focus/drawer events.

## Why Notification Routing

Notifications provide low-coupling event transport between UI lifecycle and orchestration:

1. Ghostty view publishes facts (`sizeChanged`, `windowAttached`, `deferredAttachSent`).
2. Scheduler consumes facts and computes next actions.
3. Coordinator performs effects and emits completion/failure events.
4. Future observability and Linear-tracked follow-ups can reuse the same event bus.

## State Machine

## States

1. `idle`
2. `surfaceReady`
3. `sizePending`
4. `sizeReady`
5. `attachQueued`
6. `attaching`
7. `attached`
8. `failed(retryCount, lastError)`

## Priority Tiers

1. `p0_activePane`
2. `p1_activeDrawer`
3. `p2_visibleActiveTab`
4. `p3_background`

## Events

1. `appLaunchRestored`
2. `surfaceCreated(paneId)`
3. `sizeObserved(paneId, cols, rows, timestamp)`
4. `sizeStabilized(paneId)`
5. `tabSwitched(activeTabId)`
6. `activePaneChanged(paneId)`
7. `drawerExpanded(parentPaneId)`
8. `drawerCollapsed(parentPaneId)`
9. `attachStarted(paneId)`
10. `attachSucceeded(paneId)`
11. `attachFailed(paneId, error)`
12. `paneClosed(paneId)`

## Critical Invariants

1. Attach starts only when pane is `sizeReady`.
2. Visible tiers preempt background work.
3. Active pane and active drawers always outrank all others.
4. Any geometry change can demote `attached -> sizePending` for resize reconciliation.

## Scheduling Policy

1. Two logical queues:
   1. readiness queue (`surfaceReady -> sizeReady`)
   2. attach queue (`sizeReady -> attached`)
2. Concurrency:
   1. visible work: serial (1),
   2. background work: 1 initially (can tune to 2 later).
3. Preemption:
   - if background attach is running and a `p0/p1` target appears, promote and process foreground next.
4. Retry:
   - bounded retries with backoff for attach failures.

## Hidden Pane Strategy

Adopt hybrid strategy:

1. Visible panes/drawers:
   - exact size readiness and immediate attach by tier.
2. Hidden panes:
   - background warm readiness + low-priority attach.
3. On tab switch:
   - promote destination pane to `p0` and destination drawer panes to `p1`.

This avoids a full offscreen mounting system while preserving visible-first behavior.

## Implementation Slices

## Slice 1: Domain model + reducer

1. Add:
   - `Sources/AgentStudio/App/PaneAttachStateMachine.swift`
   - `Sources/AgentStudio/App/PaneAttachTypes.swift`
2. Add unit tests:
   - `Tests/AgentStudioTests/App/PaneAttachStateMachineTests.swift`

## Slice 2: Scheduler service

1. Add:
   - `Sources/AgentStudio/App/PaneAttachSchedulerService.swift`
2. Add tests:
   - `Tests/AgentStudioTests/App/PaneAttachSchedulerServiceTests.swift`

## Slice 3: Notification routing

1. Extend names in:
   - `Sources/AgentStudio/App/NotificationNames.swift`
2. Emit size/readiness from:
   - `Sources/AgentStudio/Ghostty/GhosttySurfaceView.swift`
3. Emit visibility/focus/drawer priority events from:
   - `Sources/AgentStudio/App/TerminalTabViewController.swift`
   - `Sources/AgentStudio/App/ActionExecutor.swift` (or coordinator after action execution)

## Slice 4: Coordinator integration

1. Compose service in:
   - `Sources/AgentStudio/App/TerminalViewCoordinator.swift`
2. Keep current `PaneRestorePriorityPlanner` as initial plan seed.
3. Keep side-effects in coordinator/runtime boundary only.

## Slice 5: UX anti-flicker

1. Add temporary attach overlay for visible panes not yet attached.
2. Clear overlay on `attachSucceeded`.

## Testing Plan

1. Unit:
   - state transitions,
   - priority recompute correctness,
   - retry/backoff behavior.
2. Integration:
   - startup ordering,
   - tab switch promotion,
   - drawer expansion promotion,
   - no background starvation.
3. Regression:
   - cols/rows stable without manual input,
   - reduced startup/tab-switch flicker.

## Logging / Observability

Add structured logs for each pane:

1. `pane_attach_enqueued`
2. `pane_attach_started`
3. `pane_attach_succeeded`
4. `pane_attach_failed`
5. `pane_size_ready`
6. `pane_priority_changed`

And one startup summary:

1. total panes,
2. attached panes,
3. average attach latency,
4. p95 attach latency.

## Rollback / Safety

1. Keep feature flag:
   - `AGENTSTUDIO_ATTACH_SCHEDULER=on/off`
2. Preserve existing deferred path as fallback behind flag.

