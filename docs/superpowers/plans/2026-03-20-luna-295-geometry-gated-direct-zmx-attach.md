# LUNA-295 Geometry-Gated Direct Zmx Attach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate shell-injected zmx restore by making zmx panes start only after trusted geometry is known, then launching `zmx attach ...` directly as the Ghostty child process with zero visible flicker.

**Architecture:** Agent Studio remains a Metal `ghostty_surface_t` consumer. This slice introduces a dedicated terminal-restore feature that computes exact pane frames after startup layout stabilizes, uses the existing `VisibilityTier`, `PaneLifecycleEvent`, and `MachineState` primitives, and launches all zmx panes with direct `.surfaceCommand(zmx attach ...)`. The old deferred-shell attach hack is removed as a hard cutover. Programmatic zmx control-plane APIs and any upstream library proposal are explicitly separate follow-up work, not part of this slice.

**Tech Stack:** Swift 6.2, AppKit, GhosttyKit/libghostty surface API, zmx CLI attach process, async/await, `AsyncStream`, Swift Testing, `mise` build/test/lint, Peekaboo for visual verification.

---

## Why This Plan Exists

Agent Studio currently restores zmx-backed panes with a workaround:

1. create a Ghostty surface
2. start a normal interactive shell first
3. wait until a post-layout readiness heuristic says the surface is safe
4. inject `zmx attach ...` as terminal text
5. send a synthetic Return key

That workaround exists because earlier direct startup attempts raced against placeholder terminal geometry. zmx reattached at the wrong size, replayed terminal state into the wrong grid, and wrapped prompts incorrectly. The workaround fixed some startup-width bugs for visible panes, but it also caused the shell-to-attach flicker and prevented true hidden/background restore.

This slice keeps Ghostty’s proven Metal surface renderer and zmx’s proven attach relay, and fixes the actual load-bearing problem: **zmx must not start until the pane frame is known and the surface can be created with trusted geometry**.

There is now a concrete reproduction of the placeholder-frame bug in the current app code, not just a theoretical race:

1. `splitRight` in `PaneTabViewController` dispatches `.insertPane(source: .newTerminal, ...)`
2. `PaneCoordinator.executeInsertPane(...)` creates the new pane immediately
3. `createView(...)` / `createViewForContent(...)` pass `initialFrame: nil` into `Ghostty.SurfaceConfiguration`
4. `Ghostty.SurfaceView.init` falls back to `NSRect(x: 0, y: 0, width: 800, height: 600)`
5. only after AppKit layout churn does the surface resize to its actual host frame

Observed trace evidence from the current app:

- new pane `019D1F63-61E8-799B-A624-F966F8A7006B`
  - `sizeDidChange logical={800, 600}`
  - `createSurface success ... frame={{0, 0}, {800, 600}}`
  - `displaySurface ... hostBounds={{0, 0}, {800, 600}}`
  - then later resized to `2796 x 1147`

- new pane `019D1F63-7681-708A-9922-5D868B994455`
  - same initial `800x600`
  - then later resized to about `1396 x 1147`

This proves the placeholder frame is still active on the **new split-pane path**, not only on launch restore. That is in scope for this plan. A geometry-gated direct-attach design that fixes restore but still allows new panes to start at `800x600` is not acceptable.

## Current Broken Path to Replace

These files define the current workaround and are the primary replacement targets:

- [PaneCoordinator+ViewLifecycle.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.luna-295-pane-attach-orchestration-priority-scheduling-anti-flicker/Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift)
  - currently chooses `.deferredInShell(command:)` for zmx-backed terminal creation.
- [GhosttySurfaceView.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.luna-295-pane-attach-orchestration-priority-scheduling-anti-flicker/Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift)
  - currently owns deferred startup command scheduling, text injection, synthetic Return key, and the concrete `initialFrame == nil ? 800x600` fallback via `super.init(frame: config?.initialFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600))`.
- [DeferredStartupReadiness.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.luna-295-pane-attach-orchestration-priority-scheduling-anti-flicker/Sources/AgentStudio/Features/Terminal/Ghostty/DeferredStartupReadiness.swift)
  - codifies the visible-window-first workaround gate.
- [AppDelegate.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.luna-295-pane-attach-orchestration-priority-scheduling-anti-flicker/Sources/AgentStudio/App/AppDelegate.swift)
  - kicks the current restore flow from boot.

The new design must remove all zmx-pane dependence on:

- shell-first startup
- text injection of `zmx attach ...`
- synthetic Return key execution
- “reveal the pane, then let restore happen” behavior

## Design Decision From Reassessment

This slice intentionally does **not** replace zmx’s attach relay process.

Why:

- zmx `attach` is not just a control-plane command; it is the long-running PTY/socket byte relay.
- `ghostty_surface_t` does not expose the PTY data plane or a raw VT replay pipe to the host.
- Therefore, the lowest-risk design is to keep `zmx attach` as the Ghostty child process and fix geometry/scheduling so it starts under the correct conditions.

Out of scope for this slice:

- socket-level replacement of zmx’s attach relay
- local in-app data-plane zmx client
- upstream programmatic zmx library work

Those may be worthwhile follow-up slices once the geometry-gated direct attach path proves out.

This plan also intentionally lands before the broader stable-terminal-host remodel in `2026-03-22-luna-295-stable-terminal-host-architecture.md`. That follow-up may reduce host churn during split mutations, but it must not inherit a creation path that still silently boots new zmx panes at placeholder `800x600`. This plan removes the placeholder-first creation defect first.

## Ticket Requirement Traceability

| `LUNA-295` Requirement / Criterion | Covered By |
|---|---|
| Session restore works reliably | Tasks 0, 2, 3, 4, 5 |
| Correct cols/rows at startup without manual input | Tasks 0, 1, 2, 4, 5 |
| No visible flicker on startup and tab switch | Tasks 2, 3, 4 |
| Priority order: visible panes first, then eligible hidden panes | Tasks 1, 3, 4b |
| Background warming shortly after launch for existing sessions | Tasks 1, 3, 4 |
| Event-driven composition, no new Combine/NotificationCenter | Tasks 3, 4 |
| Event routing is workspace-correct | Tasks 3, 4 |
| Scheduling is deterministic and test-covered | Tasks 3, 4 |
| Tab switch promotes destination pane/drawers immediately | Tasks 3, 4 |
| Background work cannot starve visible work | Tasks 3, 4 |
| Startup and tab-switch flicker ideally zero for background tabs | Tasks 2, 3, 4 |

## Trusted Geometry Definition

“Trusted geometry” means the exact pane frame Agent Studio expects a pane host view to occupy after startup layout has stabilized, such that Ghostty will derive the same effective terminal grid it would derive if the pane were already visible.

For this slice:

- Agent Studio owns pane-frame truth after startup layout is stable.
- `TerminalPaneGeometryResolver` returns exact pane `CGRect` frames in logical points.
- Ghostty derives effective cols/rows from the actual host view/frame and backing scale.
- The restore path must give Ghostty the correct pane frame before `ghostty_surface_new` launches `zmx attach`.
- The **new split-pane path** must do the same. Creating a new zmx pane with `initialFrame: nil` and letting `Ghostty.SurfaceView` fall back to `800x600` violates the geometry contract just as much as a bad restore does.

The implementation must not treat any of these as trusted:

- the placeholder `800x600` `Ghostty.SurfaceView` frame
- zero-size bounds
- “non-zero is good enough” geometry
- persisted last-session pane geometry from an earlier run

If, after startup layout stabilizes, Agent Studio cannot determine a pane’s frame from canonical app state, that is a defect to investigate and fix. It is not an accepted fallback mode for this slice.

## Geometry Resolver Contract

The geometry resolver is responsible for computing pane frames from the same app-owned layout truth the visible UI uses.

It must:

- start from the **terminal container bounds**, not the whole window frame
- account for restored sidebar width and tab bar height
- account for split divider thickness at every split level
- account for drawer containment rules for visible drawer panes
- return pane frames in logical points

It must **not**:

- return backing pixels as its primary contract
- guess from stale persisted pane size
- skip divider thickness or terminal-container chrome

Backing-pixel conversion happens later, using the known main-window/screen scale factor, not `convertToBacking()` on a detached hidden view.

## Startup Layout Stabilization Rule

Trusted pane geometry may only be computed after:

1. the main window has been shown
2. any launch-time frame correction / maximize has been applied
3. the first MainActor turn after show has completed
4. content-view layout has been forced/stabilized
5. restored sidebar width and other layout-affecting app state are in place

In practice, the restore path should sequence startup geometry like this:

```swift
mainWindowController?.showWindow(nil)
window.setFrame(screen.visibleFrame, display: true)
await Task.yield()
window.contentView?.layoutSubtreeIfNeeded()
let paneFrames = geometryResolver.resolve(...)
```

Assume Swift 6.2 and macOS 26 only. Do not add legacy timing shims unless the implementation proves a modern path is insufficient.

## Hard Invariants

1. Zmx panes must launch `zmx attach ...` only after trusted geometry exists.
2. The old deferred-shell hack must be structurally unreachable for zmx panes.
3. Visible panes always outrank hidden panes.
4. Visible includes currently open/onscreen drawer panes.
5. Within the visible tier, the active pane wins first by tie-breaker, then other visible panes in stable layout order.
6. Hidden work must never starve visible work.
7. Revealing a pane must not be the thing that starts restore.
8. Failure reveals a restore placeholder, never a live shell fallback.
9. No anti-flicker overlay is allowed in this design, but a truthful full-pane `Restoring terminal…` state is allowed while a pane is genuinely still restoring.
10. New zmx panes and restored zmx panes both use direct `.surfaceCommand(zmx attach ...)`.
11. This is a hard cutover: no dual restore paths, no compatibility shims, no feature flags for the old hack.
12. A newly created split pane must never create its surface at placeholder `800x600` and resize later. Trusted geometry is required before surface creation on the split path too.

## Attach Outcome Transition Rule

This slice must define a concrete way to leave the truthful `Restoring terminal…` state.

For v1, use this rule:

- **Immediate failure:** if the `zmx attach` child exits during the startup window, transition to restore placeholder.
- **Successful startup:** if the `zmx attach` child remains alive through a short startup grace window and no surface/process failure signal has fired, transition from `Restoring terminal…` to the live terminal view.

This is a deliberate startup-success heuristic, not a claim that Ghostty exposes a first-class “attach succeeded” callback today.

Implementation requirements:

- the startup grace window must be explicit and test-covered
- failure path must be immediate on early process death
- success path must not reveal half-restored shell-intermediate content
- if future Ghostty integration exposes a stronger first-render/ready signal, it can replace this heuristic in a follow-up slice

## Non-Goals

The following are explicitly out of scope for this slice:

- switching Agent Studio away from Ghostty’s Metal/surface rendering path
- replacing zmx’s attach relay with a Swift/socket-only data-plane client
- adding a UI overlay to hide flicker
- preserving the old deferred-shell restore path in parallel
- changing `vendor/zmx`
- upstream zmx library contribution work
- the broader stable-terminal-host remodel beyond the geometry contract needed to eliminate placeholder-first zmx startup

---

## File Structure

### New Feature Slice

- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreTypes.swift`
  - Sendable types: restore policy, phase, failure reason, reveal state.
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreStateMachine.swift`
  - `MachineState`-based restore transitions using the existing `Infrastructure/StateMachine` pattern.
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
  - `@MainActor` scheduler using existing `VisibilityTier` and visible-first restore ordering.
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift`
  - Side-effects boundary bridging pane/store identity, geometry resolver results, and direct `surfaceCommand(zmx attach ...)`.
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift`
  - Deterministically compute exact pane frames from window content rect + layout model, including hidden tabs.
- Create: `Sources/AgentStudio/Features/Terminal/Restore/RestorePlaceholderState.swift`
  - Models failure state so reveal shows restore UI instead of a fallback shell.

### Existing Integration Points

- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
  - Construct the new restore scheduler/runtime and inject visibility-tier resolver.
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
  - Replace restored-zmx `.deferredInShell(command:)` path with geometry-gated `.surfaceCommand(zmxAttachCommand)`.
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
  - Start restore orchestration at boot and route failure states to placeholders.
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Emit active-tab/active-pane changes so tab-switch destination pane and drawers promote immediately.
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
  - Route split/new-pane creation through the same geometry-gated path so `.insertPane(source: .newTerminal, ...)` does not create a surface with `initialFrame: nil`.
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
  - Accept explicit initial frame for restore-driven surface creation and publish the existing lifecycle facts needed for restore.
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
  - Ensure occlusion/focus semantics are correct for hidden but already-started surfaces.
- Modify: `Sources/AgentStudio/Core/Models/SessionConfiguration.swift`
  - Add app-wide background restore policy setting.
- Modify: `Sources/AgentStudio/App/SettingsView.swift`
  - Expose app-wide background restore policy UI.
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift`
  - Only if needed for externally meaningful restore-status events; do not put all restore-internal sequencing on the shared bus.
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
  - Only if needed for externally meaningful restore-status events.
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeFactories.swift`
  - Only if needed for externally meaningful restore-status envelope emission.
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift`
  - Use the coordinator-provided visibility-tier resolver instead of the no-resolver default.
- Delete if unused: `Sources/AgentStudio/Features/Terminal/Ghostty/DeferredStartupReadiness.swift`
  - Remove dead workaround code if nothing else needs it after hard cutover.

### Tests

- Create: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreTypesTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalPaneGeometryResolverTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Restore/HiddenSurfaceReadinessTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreStateMachineTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreSchedulerTests.swift`
- Create: `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`
- Modify or delete: `Tests/AgentStudioTests/Features/Terminal/Ghostty/DeferredStartupReadinessTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift`

### Docs

- Create: `docs/architecture/luna-295-geometry-gated-direct-zmx-attach.md`
  - Product-facing architecture doc for this slice.
- Create: `docs/guides/luna-295-followups.md`
  - Explicitly list deferred follow-ups: control-plane zmx client, upstream library proposal, custom relay exploration.

### Source Material

- Linear ticket: `LUNA-295`
- Architecture references:
  - `docs/architecture/zmx_restore_and_sizing.md`
  - `docs/architecture/pane_runtime_architecture.md`
  - `docs/architecture/pane_runtime_eventbus_design.md`
  - `docs/architecture/window_system_design.md`
  - `docs/architecture/ghostty_surface_architecture.md`

---

### Task 1: Add Restore Types, App-Wide Policy, and Geometry Contracts

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreTypes.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Restore/RestorePlaceholderState.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift`
- Modify: `Sources/AgentStudio/Core/Models/SessionConfiguration.swift`
- Modify: `Sources/AgentStudio/App/SettingsView.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreTypesTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalPaneGeometryResolverTests.swift`
- Test: `Tests/AgentStudioTests/Core/Models/SessionConfigurationTests.swift`

- [ ] **Step 1: Write the failing type, policy, and geometry tests**

```swift
@Test func backgroundRestorePolicy_defaultsToExistingSessionsOnly()
@Test func visibleTier_sorting_prefersVisibleBeforeHidden()
@Test func geometryResolver_derivesExactPaneFrames_fromWindowAndLayout()
@Test func geometryResolver_neverReturnsPlaceholder800x600()
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-1 swift test --filter "TerminalRestoreTypesTests|TerminalPaneGeometryResolverTests|SessionConfigurationTests"`
Expected: FAIL with missing types, missing setting cases, and missing geometry resolver.

- [ ] **Step 3: Add the new restore types and app-wide setting**

```swift
enum BackgroundRestorePolicy: String, Codable, Sendable {
    case off
    case existingSessionsOnly
    case allTerminalPanes
}
```

- [ ] **Step 4: Implement the deterministic geometry resolver**

The resolver must:
- accept current window content rect
- accept the terminal container bounds after startup layout stabilization
- accept tab layout / arrangement model
- return exact pane `CGRect` frames in points
- work for active and hidden tabs
- avoid persisted “last session size” shortcuts
- treat “unknown pane frame after startup layout” as a bug, not an acceptable fallback
- subtract split divider thickness at every split level
- derive frames for visible drawer panes using the same containment rules the visible UI uses

- [ ] **Step 5: Wire the app-wide setting into `SessionConfiguration` and `SettingsView`**

Add:
- persistent config field
- default `.existingSessionsOnly`
- settings copy that explains only existing background sessions are pre-restored by default

- [ ] **Step 6: Run the focused tests to verify they pass**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-1 swift test --filter "TerminalRestoreTypesTests|TerminalPaneGeometryResolverTests|SessionConfigurationTests"`
Expected: PASS

- [ ] **Step 7: If and only if the user later requests commits, commit this task’s files**

Suggested message:

```bash
git add Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreTypes.swift \
  Sources/AgentStudio/Features/Terminal/Restore/RestorePlaceholderState.swift \
  Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift \
  Sources/AgentStudio/Core/Models/SessionConfiguration.swift \
  Sources/AgentStudio/App/SettingsView.swift \
  Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreTypesTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Restore/TerminalPaneGeometryResolverTests.swift \
  Tests/AgentStudioTests/Core/Models/SessionConfigurationTests.swift
git commit -m "feat: add restore types and deterministic pane geometry"
```

### Task 2: Make Ghostty Surface Creation Accept Trusted Initial Geometry

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Delete if unused: `Sources/AgentStudio/Features/Terminal/Ghostty/DeferredStartupReadiness.swift`
- Modify or delete: `Tests/AgentStudioTests/Features/Terminal/Ghostty/DeferredStartupReadinessTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/HiddenSurfaceReadinessTests.swift`

- [ ] **Step 1: Write the failing surface-geometry tests**

```swift
@Test func restoredSurface_usesExplicitInitialGeometry_beforeProcessLaunch()
@Test func newSplitPane_usesExplicitInitialGeometry_beforeProcessLaunch()
@Test func splitRight_neverCreatesSurfaceAtPlaceholder800x600()
@Test func zmxSurface_neverUsesDeferredShellAttach()
@Test func restoredSurface_staysHidden_untilAttachOutcomeKnown()
@Test func hiddenAttachedSurface_clearsFocus_whenOccluded()
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-2 swift test --filter "HiddenSurfaceReadinessTests|DeferredStartupReadinessTests"`
Expected: FAIL with missing explicit initial-geometry support.

- [ ] **Step 3: Refactor `GhosttySurfaceView` to accept explicit initial frame for zmx-driven surfaces**

Requirements:
- zmx panes get an initial frame before `ghostty_surface_new`
- placeholder `800x600` is no longer used as restore geometry
- placeholder `800x600` is no longer used as split/new-pane geometry
- `initialFrame == nil` is treated as a programmer error on the zmx restore/new-pane path, not a silent fallback
- the surface can still be occluded/hidden while preserving trusted size
- backing-scale-aware sizing still flows through the existing `convertToBacking` path after surface creation
- add a runtime guard that the zmx restore path never uses the placeholder frame
- add a runtime guard that the new split-pane path never uses the placeholder frame

- [ ] **Step 4: Remove the restored-zmx deferred-shell attach path**

Requirements:
- zmx panes must not use `.deferredInShell(command:)`
- zmx panes must not use text injection or synthetic Return
- delete or fully retire workaround-only code if it becomes unused

- [ ] **Step 5: Fix hidden-surface focus/occlusion semantics in `SurfaceManager`**

Goal:
- hidden surfaces stay render-suppressed
- focus state is never left stale
- reveal does not trigger any intermediate shell frame

- [ ] **Step 6: Run the focused tests to verify they pass**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-2 swift test --filter "HiddenSurfaceReadinessTests|DeferredStartupReadinessTests"`
Expected: PASS

- [ ] **Step 7: If and only if the user later requests commits, commit this task’s files**

Suggested message:

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
  Tests/AgentStudioTests/Features/Terminal/Restore/HiddenSurfaceReadinessTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/DeferredStartupReadinessTests.swift
git commit -m "feat: launch restored ghostty surfaces with trusted initial geometry"
```

### Task 3: Add the Restore State Machine, Events, and Scheduler

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreStateMachine.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreStateMachineTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreSchedulerTests.swift`

- [ ] **Step 1: Write the failing reducer, event, and scheduler tests**

```swift
@Test func stateMachine_requiresTrustedGeometry_beforeStartingSurface()
@Test func scheduler_restoresVisiblePanes_beforeEligibleHiddenPanes()
@Test func scheduler_restoresVisibleDrawerPanes_asVisibleWork()
@Test func scheduler_startsEligibleHiddenExistingSession_beforeReveal()
@Test func scheduler_skipsBackgroundPane_withoutExistingSession_underDefaultPolicy()
@Test func scheduler_promotes_destinationPaneAndDrawers_onTabSwitch()
@Test func scheduler_preemptsPendingBackgroundWork_whenVisibleWorkArrives()
@Test func stateMachine_exposesTruthfulRestoringState_forVisiblePaneInFlight()
@Test func scheduler_recordsPlaceholderFailure_insteadOfShellFallback()
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-3 swift test --filter "TerminalRestoreStateMachineTests|TerminalRestoreSchedulerTests"`
Expected: FAIL with missing state-machine/scheduler implementations.

- [ ] **Step 3: Implement the pure state machine**

```swift
struct TerminalRestoreState: MachineState {
    let phase: TerminalRestorePhase
    // restore-specific fields

    static func transition(
        from state: Self,
        on event: TerminalRestoreEvent
    ) -> Transition<Self, TerminalRestoreEffect> { ... }
}
```

Reducer rule:
- no surface start before trusted geometry
- no shell fallback transition
- no overlay state
- visible in-flight restore maps to a truthful full-pane restoring state
- failure produces placeholder state
- tab-switch promotion is an explicit state-machine input
- attach success/failure is driven by explicit events, not ad hoc booleans

- [ ] **Step 4: Reuse existing lifecycle events and add only truly restore-specific events**

Use existing `PaneLifecycleEvent` facts where they already exist:
- `surfaceCreated`
- `sizeObserved`
- `sizeStabilized`
- `attachStarted`
- `attachSucceeded`
- `attachFailed`
- `paneClosed`
- `activePaneChanged`
- `drawerExpanded`
- `drawerCollapsed`
- `tabSwitched`

Only add restore-specific events for semantics not already represented, such as:
- `geometryResolved`
- `processHealthChecked(alive: Bool)`
- `promotedToVisible`

- [ ] **Step 5: Implement the scheduler**

Rules:
- visible panes first
- visible drawer panes count as visible panes
- hidden eligible panes last
- hidden restore is delayed and limited to existing sessions by default
- active pane wins first inside the visible tier, then other visible panes in stable layout order
- pending hidden work must be preemptable before process launch
- visible work must never queue behind running or queued hidden work
- reveal must wait until the restore result is known
- visible panes are created sequentially on the main thread with `Task.yield()` between creations to keep UI responsive

- [ ] **Step 6: Run the focused tests to verify they pass**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-3 swift test --filter "TerminalRestoreStateMachineTests|TerminalRestoreSchedulerTests"`
Expected: PASS

- [ ] **Step 7: If and only if the user later requests commits, commit this task’s files**

Suggested message:

```bash
git add Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreStateMachine.swift \
  Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift \
  Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreStateMachineTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreSchedulerTests.swift
git commit -m "feat: add luna-295 restore scheduler and state machine"
```

### Task 4a: Add `TerminalRestoreRuntime` and Replace the Boot/View Restore Path

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/Core/Stores/ZmxBackend.swift`
- Test: `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/ZmxBackendTests.swift`

- [ ] **Step 1: Write the failing integration tests**

```swift
@Test func boot_restore_startsActivePane_with_directSurfaceCommandAttach() async throws
@Test func boot_restore_startsVisibleDrawerPanes_asVisiblePanes() async throws
@Test func boot_restore_startsEligibleHiddenExistingSession_whileStillHidden() async throws
@Test func newZmxPane_uses_directSurfaceCommandAttach_notDeferredShell() async throws
@Test func tabSwitch_promotes_destinationPaneAndDrawers_immediately() async throws
@Test func backgroundRestore_doesNotStarveVisibleWork() async throws
@Test func zmxPane_usesExactTrustedFrame_notPlaceholderGeometry() async throws
@Test func restoredPane_reveal_is_gated_untilAttachedOrPlaceholderFailed() async throws
@Test func visiblePane_showsTruthfulRestoringState_whileAttachInFlight() async throws
@Test func visiblePane_transitionsFromRestoringState_afterStartupGrace_whenProcessSurvives() async throws
@Test func visiblePane_transitionsToPlaceholder_immediately_onEarlyAttachProcessExit() async throws
@Test func zmxPane_cannotEnterDeferredShellAttachPath() async throws
@Test func hidden_restore_failure_showsPlaceholder_onReveal() async throws
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-4a swift test --filter "Luna295DirectZmxAttachIntegrationTests|ZmxBackendTests"`
Expected: FAIL with missing runtime wiring and direct surface-command restore path.

- [ ] **Step 3: Extend `ZmxBackend` only as needed for this slice**

Use `ZmxBackend` for:
- deterministic attach command construction
- existing-session detection / probe helpers needed by default background policy

Do not add socket-level attach replacement logic in this slice.

- [ ] **Step 4: Add `TerminalRestoreRuntime` and inject it from `PaneCoordinator`**

Responsibilities:
- bridge pane/store identity to concrete session IDs
- decide whether a pane is eligible for hidden restore
- build the direct `zmx attach` surface command only after trusted geometry exists
- surface placeholder state to views

- [ ] **Step 5: Replace the current restore boot path**

In `AppDelegate` and `PaneCoordinator+ViewLifecycle`:
- all visible panes restore first
- visible drawer panes restore as visible panes
- delayed hidden restore for existing sessions only
- use `.surfaceCommand(zmxAttachCommand)` for all zmx panes
- visible panes show a truthful `Restoring terminal…` state while attach is still in flight
- no half-restored terminal content is revealed
- no shell injection path
- no visible fallback shell on failure
- no anti-flicker overlay path

- [ ] **Step 6: Make startup layout timing explicit in code**

Requirements:
- run pane-frame resolution only after `showWindow`, launch frame adjustment, `Task.yield()`, and forced content-view layout
- use the settled window content rect and restored sidebar width
- do not compute hidden-pane frames before startup layout has stabilized

- [ ] **Step 7: Run the focused tests to verify they pass**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-4a swift test --filter "Luna295DirectZmxAttachIntegrationTests|ZmxBackendTests"`
Expected: PASS

- [ ] **Step 8: If and only if the user later requests commits, commit this task’s files**

Suggested message:

```bash
git add Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift \
  Sources/AgentStudio/App/PaneCoordinator.swift \
  Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Sources/AgentStudio/App/AppDelegate.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
  Sources/AgentStudio/Core/Stores/ZmxBackend.swift \
  Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift \
  Tests/AgentStudioTests/Core/Stores/ZmxBackendTests.swift
git commit -m "feat: replace deferred shell restore with direct zmx attach"
```

### Task 4b: Integrate Externally Meaningful Restore Status With Existing Runtime Bus

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeFactories.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift`
- Test: `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`

- [ ] **Step 1: Write the failing bus/status integration tests**

```swift
@Test func externallyMeaningfulRestoreStatus_flows_through_runtime_envelopes() async throws
@Test func notificationReducer_orders_visible_restore_status_ahead_of_hidden_status() async throws
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-4b swift test --filter "Luna295DirectZmxAttachIntegrationTests|NotificationReducerTests"`
Expected: FAIL with missing externally visible restore-status routing.

- [ ] **Step 3: Emit only externally meaningful restore-status events to the shared bus**

Use:
- `PaneRuntimeEventBus.shared`
- `RuntimeEnvelope`
- `PaneEnvelope` for pane-scoped externally meaningful status
- `SystemEnvelope` only where the event is truly non-pane-scoped

Do not mirror every restore-internal sequencing event onto the shared bus.

- [ ] **Step 4: Inject the visibility-tier resolver into `NotificationReducer`**

This restores parity with the architecture docs and keeps visible work ahead of hidden restore noise.

- [ ] **Step 5: Run the focused tests to verify they pass**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-4b swift test --filter "Luna295DirectZmxAttachIntegrationTests|NotificationReducerTests"`
Expected: PASS

- [ ] **Step 6: If and only if the user later requests commits, commit this task’s files**

Suggested message:

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeFactories.swift \
  Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift \
  Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift
git commit -m "feat: integrate restore status with runtime event bus"
```

### Task 5: Prove Current `vendor/zmx` Behavior Before Calling the Slice Done

**Files:**
- Modify: `Tests/AgentStudioTests/Integration/ZmxBackendIntegrationTests.swift`
- Modify: `Tests/AgentStudioTests/Integration/ZmxE2ETests.swift`
- Test: `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`

- [ ] **Step 1: Write the failing proof tests against the current vendor**

```swift
@Test func currentVendorZmx_directAttach_restoresExistingSession_afterTrustedGeometry() async throws
@Test func currentVendorZmx_hiddenDirectAttach_restoresWhileOccluded() async throws
@Test func currentVendorZmx_doesNotRegressToNoRestoreOnAttach() async throws
```

- [ ] **Step 2: Run the focused proof tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan-5 swift test --filter "Luna295DirectZmxAttachIntegrationTests|ZmxBackendIntegrationTests|ZmxE2ETests"`
Expected: Either PASS with current vendor behavior confirmed, or FAIL with concrete evidence that current `vendor/zmx` behavior blocks this slice.

- [ ] **Step 3: If these proof tests fail, stop and reassess before continuing broader implementation**

This is a hard checkpoint. Do not claim the slice is viable on the current vendor unless these tests pass.

- [ ] **Step 4: If and only if the user later requests commits, commit proof-test updates**

Suggested message:

```bash
git add Tests/AgentStudioTests/Integration/ZmxBackendIntegrationTests.swift \
  Tests/AgentStudioTests/Integration/ZmxE2ETests.swift \
  Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift
git commit -m "test: prove current zmx vendor behavior for direct attach restore"
```

### Task 6: Verification and Follow-Up Docs

**Files:**
- Create: `docs/architecture/luna-295-geometry-gated-direct-zmx-attach.md`
- Create: `docs/guides/luna-295-followups.md`

- [ ] **Step 1: Write the architecture doc**

Cover:
- backstory and why the old hack existed
- trusted geometry requirement
- startup layout stabilization timing
- direct `surfaceCommand(zmx attach ...)` design for all zmx panes
- visible-first / hidden-second scheduling
- hidden restore policy
- truthful `Restoring terminal…` state for visible in-flight panes
- placeholder failure behavior
- why no overlay exists

- [ ] **Step 2: Write the follow-up doc**

List deferred work clearly:
- socket-level zmx control-plane client
- upstream zmx programmatic library proposal
- custom Agent Studio attach relay exploration

- [ ] **Step 3: Run full project verification**

Run: `mise run test`
Expected: all tests pass, zero failures

Run: `mise run lint`
Expected: zero violations

- [ ] **Step 4: Perform manual visual verification**

Run:

```bash
pkill -9 -f "AgentStudio"
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Verify:
- active pane restores with no shell flash
- visible drawer panes restore as visible content
- hidden pane with existing session reveals already-restored terminal state
- tab switch does not trigger a shell-to-attach transition
- visible panes in flight show an intentional restoring state, not stale old content or blank jank
- failed hidden restore reveals a placeholder instead of a live shell

- [ ] **Step 5: If and only if the user later requests commits, commit these docs**

Suggested message:

```bash
git add docs/architecture/luna-295-geometry-gated-direct-zmx-attach.md \
  docs/guides/luna-295-followups.md
git commit -m "docs: capture luna-295 direct attach architecture and followups"
```

---

## Notes for the Implementer

- Do not modify `vendor/zmx`.
- Do not add a parallel compatibility path.
- Do not keep the old and new restore systems alive at the same time.
- Do not reintroduce shell-injected attach as a fallback.
- Do not introduce an anti-flicker overlay. The goal is to prevent flicker by sequencing and reveal gating.
- Do not treat hidden-pane reveal as the moment restore starts.
- Do not shortcut hidden restore through persisted stale size. Use deterministic current-layout geometry.
- Do not compute hidden-pane frames before startup layout has stabilized.
- Do not special-case restored zmx panes and new zmx panes into different startup strategies.
- Do not start a zmx pane until exact/trusted geometry is available.

## Review Limitation

This plan should normally go through the plan-document-reviewer loop. Since explicit subagent permission has now been granted, re-run that review loop after any substantive plan rewrite before execution.
