# Stable Terminal Host Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current terminal-pane hosting and Ghostty runtime boundary with a stable native-host architecture that prevents panes from going blank during split/layout churn and removes the threading ambiguity that the recent `@MainActor` crash exposed.

**Architecture:** Split the current Ghostty runtime wrapper into explicit nonisolated C-callback handling and `@MainActor` routing/lifecycle synchronization, then refactor `AgentStudioTerminalView` into a stable `TerminalPaneHostView` that owns a dedicated `GhosttyMountView`. Visible resize becomes host-layout-driven from actual post-layout bounds, while structural tree mutations trigger explicit focus, occlusion, and redraw reconciliation across all affected visible terminal panes.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI hosting, Swift Testing, Ghostty/libghostty, zmx, mise, swift-format, swiftlint

---

## Prerequisite

This plan assumes the geometry/lifecycle-store plan lands first:

- `docs/superpowers/plans/2026-03-22-luna-295-lifecycle-store-geometry.md`

This host refactor should consume:

- `WindowLifecycleStore.terminalContainerBounds`
- `WindowLifecycleStore.isLaunchLayoutSettled`

and should not preserve the old closure chain (`terminalContainerBoundsProvider`, `onRestoreHostReady`, cached restore bounds, arm flags) as a second geometry source.

## Current Problem Model

### User-visible symptom

- Creating or splitting panes can make an existing terminal pane go visually blank.
- The shell/zmx session is still alive.
- Pressing Enter or otherwise producing new PTY output makes the text reappear.

### Why this points at hosting/repaint, not just zmx session identity

- A dead session would not consistently repaint on fresh PTY output.
- Multiple visible panes can be affected by later split churn.
- The recent `@MainActor` misuse in `Ghostty.App` proved the current runtime wrapper is mixing incompatible concerns and threading contracts in one type.

### What broke in the recent Ghostty runtime fix

The crash exposed this structural problem:

```text
Ghostty.App was doing all of these in one type:

1. Own ghostty_app_t lifetime
2. Own C callback statics invoked from Ghostty renderer / I/O threads
3. Route actions into main-actor terminal runtime logic
4. Observe app lifecycle and sync focus on the main actor
```

That type cannot safely have one isolation policy. The current “remove class-level `@MainActor` and annotate individual methods” fix is correct, but it also proves the type is oversized and too easy to misuse again.

### Current terminal host structure

```text
SwiftUI split tree
  -> PaneLeafContainer
    -> PaneViewRepresentable
      -> paneView.swiftUIContainer
        -> ManagementModeContainerView
          -> AgentStudioTerminalView
            -> Ghostty.SurfaceView
```

### Current coupling problems

- `AgentStudioTerminalView` is both the pane’s AppKit identity and the direct Ghostty parent.
- `displaySurface(...)` removes and re-adds `Ghostty.SurfaceView` inside the same stable terminal host.
- The split subtree can churn structurally while terminal host identity is implicit.
- Focus reconciliation is mostly keyed off active selection changes.
- Visible size can currently be sent through several overlapping paths:
  - `GhosttySurfaceView.setFrameSize(...)`
  - `GhosttySurfaceView.viewDidMoveToWindow()` async resend
  - `GhosttySurfaceView.viewDidChangeBackingProperties()`
  - `AgentStudioTerminalView.layout()`
  - `AgentStudioTerminalView.forceGeometrySync(...)`
  - `PaneTabViewController.syncVisibleTerminalGeometry(...)`

## Target Architecture

### Runtime boundary split

```text
GhosttyAppHandle
  owns ghostty_app_t, init/deinit, tick()
  nonisolated, @unchecked Sendable

GhosttyCallbackRouter
  owns C callback statics from ghostty_runtime_config_s
  nonisolated only
  reconstructs Swift objects from userdata
  hops to @MainActor only when required

GhosttyActionRouter
  @MainActor
  routes Ghostty action callbacks into SurfaceManager / RuntimeRegistry / TerminalRuntime

GhosttyFocusSynchronizer
  @MainActor
  observes lifecycle state and calls ghostty_app_set_focus
```

### Terminal host tree

```text
PaneLeafContainer
  -> PaneViewRepresentable
    -> paneView.swiftUIContainer
      -> ManagementModeContainerView
        -> TerminalPaneHostView
          -> GhosttyMountView
            -> Ghostty.SurfaceView
```

Important boundary note:

- `GhosttyMountView` being the only parent of `Ghostty.SurfaceView` is an **Agent Studio host invariant**, not a Ghostty vendor contract.

## Architecture Diagrams

### Current vs target host tree

```text
CURRENT
-------
SwiftUI split tree
  -> PaneLeafContainer
    -> PaneViewRepresentable
      -> paneView.swiftUIContainer
        -> ManagementModeContainerView
          -> AgentStudioTerminalView
            -> Ghostty.SurfaceView


TARGET
------
SwiftUI split tree
  -> PaneLeafContainer
    -> PaneViewRepresentable
      -> paneView.swiftUIContainer
        -> ManagementModeContainerView
          -> TerminalPaneHostView
            -> GhosttyMountView
              -> Ghostty.SurfaceView
```

### Why the target is safer

```text
CURRENT
-------
pane identity
  = terminal host
  = direct Ghostty parent

if split-tree structure churns,
the renderer child can still be removed and re-added,
and repaint timing can drift from the host lifecycle


TARGET
------
pane identity
  = TerminalPaneHostView

renderer parent
  = GhosttyMountView

split-tree churn still resizes/repositions the host,
but renderer mount/unmount is isolated behind one explicit boundary
```

### Runtime responsibility split

```text
                  +----------------------+
                  |  GhosttyAppHandle    |
                  |----------------------|
                  | ghostty_app_t        |
                  | init / deinit        |
                  | tick()               |
                  +----------+-----------+
                             |
                             v
                  +----------------------+
renderer / I/O -> | GhosttyCallbackRouter| -> Task { @MainActor ... } when needed
threads           |----------------------|
                  | C callback statics   |
                  | userdata lookup      |
                  +----------+-----------+
                             |
                 +-----------+------------+
                 |                        |
                 v                        v
     +----------------------+   +------------------------+
     | GhosttyActionRouter  |   | GhosttyFocusSynchronizer|
     |----------------------|   |-------------------------|
     | SurfaceManager       |   | App/window lifecycle    |
     | RuntimeRegistry      |   | ghostty_app_set_focus   |
     | TerminalRuntime      |   |                         |
     +----------------------+   +-------------------------+
```

### Host, lifecycle, and runtime boundaries

```text
+---------------------------------------------------------------+
| Workspace / UI structure                                      |
|---------------------------------------------------------------|
| WorkspaceStore                                                |
| PaneCoordinator                                               |
| PaneLeafContainer / split tree                                |
+-------------------------------+-------------------------------+
                                |
                                v
+---------------------------------------------------------------+
| Terminal host boundary                                        |
|---------------------------------------------------------------|
| ViewRegistry (stable terminal-host reuse)                     |
| TerminalPaneHostView                                          |
| GhosttyMountView                                              |
| TerminalHostMetrics                                           |
| TerminalStructureMutationContext                              |
+-------------------------------+-------------------------------+
                                |
                                v
+---------------------------------------------------------------+
| Runtime / renderer boundary                                   |
|---------------------------------------------------------------|
| SurfaceManager                                                |
| GhosttyAppHandle                                              |
| GhosttyCallbackRouter                                         |
| GhosttyActionRouter                                           |
| GhosttyFocusSynchronizer                                      |
| Ghostty.SurfaceView                                           |
| zmx child process                                             |
+---------------------------------------------------------------+
```

### Visible resize authority

```text
model-resolved frame
  -> expectation / verification only

actual post-layout host bounds
  -> authoritative visible size
  -> ghostty_surface_set_size
  -> redraw if needed
```

### Structural mutation reconciliation

```text
split / reveal / arrangement mutation
            |
            v
  ViewRegistry reuses stable terminal hosts
            |
            v
  AppKit layout settles host bounds
            |
            v
  TerminalPaneHostView applies visible size
            |
            v
  reconciliation generation runs:
    - focus sync
    - occlusion sync
    - redraw sync
            |
            v
  visible panes remain painted without waiting
  for the next PTY output
```

### New invariants

1. `1 pane = 1 stable TerminalPaneHostView`.
2. `1 stable host = 1 stable GhosttyMountView`.
3. `Ghostty.SurfaceView` is parented only under `GhosttyMountView`.
4. Ghostty runtime C callbacks are never in a type that also owns main-actor UI/lifecycle logic.
5. Visible-pane Ghostty size comes from actual post-layout host bounds.
6. Structural tree mutation triggers reconciliation even if `activePaneId` is unchanged.
7. Focus, occlusion, redraw, and size are separate signals and stay separate in the design.
8. A running zmx session must never require new PTY output just to become visible again.

## File Structure Map

### New files

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`
  Owns `ghostty_app_t`, init/deinit, userdata lifetime, and `tick()`.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyCallbackRouter.swift`
  Owns the C callback statics currently mixed into `Ghostty.App`.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
  `@MainActor` routing layer from callback facts into domain/runtime work.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyFocusSynchronizer.swift`
  `@MainActor` lifecycle focus synchronizer.
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift`
  Renamed/refactored successor to `AgentStudioTerminalView`.
- `Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift`
  Dedicated mount/unmount parent for `Ghostty.SurfaceView`.
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalHostMetrics.swift`
  Typed host diagnostics: measured bounds, applied size, redraw generation, focus generation, occlusion generation, parent identity, and related proof state.
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalStructureMutationContext.swift`
  Typed generation and reason metadata for terminal tree churn.
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyCallbackRouterTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyFocusSynchronizerTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneHostViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalStructureMutationContextTests.swift`
- `Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift`
- `Tests/AgentStudioTests/Helpers/MockGhosttySurfaceFactory.swift`

### Moved / renamed files

- `Sources/AgentStudio/Features/Terminal/Views/AgentStudioTerminalView.swift`
  Move to `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift`

### Existing files that must be modified

- `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
  Keep the canonical pane-id -> pane-view map, and add stable terminal host reuse here instead of introducing a second registry.
- `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- `docs/architecture/ghostty_surface_architecture.md`
- `docs/architecture/component_architecture.md`
- `docs/architecture/directory_structure.md`
- `AGENTS.md`

## Lifecycle Matrix

Every flow below must be explicitly covered by implementation and proof.

```text
+------------------------+--------------------------+--------------------------------------------+
| Flow                   | Current hot path         | Final required behavior                     |
+------------------------+--------------------------+--------------------------------------------+
| Split insert           | ActionExecution + sync   | old panes never blank                       |
| Arrangement switch     | detach/reattach          | immediate repaint after churn               |
| Tab switch             | hide/reveal + restore    | reveal paints without Enter                 |
| Minimize / expand      | detachForViewSwitch      | unminimize paints immediately               |
| Drawer expand/collapse | drawer restore/reattach | drawer terminals remain visible             |
| Undo / restore         | undoClose + restoreView  | restored pane paints immediately            |
| Launch restore         | restoreAllViews          | no placeholder-only first paint             |
| Hidden -> visible      | attach / occlusion       | no Enter required to recover                |
+------------------------+--------------------------+--------------------------------------------+
```

## Data Flow Diagrams

### Split insertion

```text
User presses split button
  ->
PaneCoordinator creates new pane + surface metadata
  ->
WorkspaceStore mutates layout
  ->
ViewRegistry ensures stable `TerminalPaneHostView` reuse for visible terminal panes
  ->
SwiftUI/AppKit lays out hosts
  ->
TerminalPaneHostView.layout()
  measures actual mounted bounds
  ->
Ghostty size applied from measured bounds
  ->
structure-mutation reconciliation
  - focus sync
  - occlusion sync
  - redraw sync
  ->
all visible panes stay painted
```

### C callback routing

```text
Ghostty renderer / I/O thread
  ->
ghostty_runtime_config_s callback
  ->
GhosttyCallbackRouter (nonisolated)
  ->
if UI/runtime work required:
  Task { @MainActor ... }
  ->
GhosttyActionRouter / GhosttyFocusSynchronizer
```

### Visible resize ownership

```text
resolved model frame
  -> recorded for diagnostics only

actual post-layout host bounds
  -> authoritative visible size
  -> Ghostty size update
  -> redraw if required
```

## Task 1: Split Ghostty Runtime Responsibilities By Isolation Contract

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyCallbackRouter.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyFocusSynchronizer.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyCallbackRouterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyFocusSynchronizerTests.swift`

- [ ] **Step 1: Write failing tests for threading/isolation contracts**

```swift
@Test
func ghosttyCallbackRouter_isolation_doesNotRequireMainActor() {
    #expect(GhosttyCallbackRouter.isMainActorIsolatedForTesting == false)
}

@Test
@MainActor
func ghosttyActionRouter_routesOnMainActor() {
    let router = GhosttyActionRouter(...)
    #expect(router.isRunningOnMainActorForTesting == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAppHandleTests|GhosttyCallbackRouterTests|GhosttyActionRouterTests|GhosttyFocusSynchronizerTests"
```

Expected: FAIL with missing-type errors.

- [ ] **Step 3: Implement `GhosttyAppHandle`**

Required behavior:

- own `ghostty_app_t`
- own init/deinit
- own `tick()`
- be `@unchecked Sendable`
- own userdata lifetime bridge for callback router access

- [ ] **Step 4: Implement `GhosttyCallbackRouter`**

Required behavior:

- own callback statics currently living in `Ghostty.App`
- remain nonisolated
- reconstruct `SurfaceView` and runtime wrapper references from userdata
- only hop to `@MainActor` when domain work requires it

- [ ] **Step 5: Implement `GhosttyActionRouter` and `GhosttyFocusSynchronizer`**

Required behavior:

- `GhosttyActionRouter` owns `@MainActor` action routing into `SurfaceManager`, `RuntimeRegistry`, and terminal runtime code
- `GhosttyFocusSynchronizer` owns app/window lifecycle focus sync and calls into `ghostty_app_set_focus`

- [ ] **Step 6: Rewire `Ghostty.swift` composition**

Required behavior:

- `Ghostty.swift` becomes a composition root for the four runtime pieces
- no mixed type remains that combines C callback statics and main-actor lifecycle logic

- [ ] **Step 7: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAppHandleTests|GhosttyCallbackRouterTests|GhosttyActionRouterTests|GhosttyFocusSynchronizerTests|GhosttyAdapterTests"
```

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty \
        Tests/AgentStudioTests/Features/Terminal/Ghostty
git commit -m "refactor: split ghostty runtime by isolation contract"
```

## Task 2: Add Thin Proof Types For Later Host Reconciliation

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalHostMetrics.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalStructureMutationContext.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceTypes.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalStructureMutationContextTests.swift`

- [ ] **Step 1: Write failing tests for host metrics and generation typing**

```swift
@Test
func terminalStructureMutationGeneration_incrementsMonotonically() {
    let first = TerminalStructureMutationGeneration(rawValue: 1)
    let second = first.next()
    #expect(second.rawValue == 2)
}

@Test
func terminalHostMetrics_separatesResolvedAndMeasuredGeometry() {
    let metrics = TerminalHostMetrics(
        paneId: UUIDv7.generate(),
        surfaceId: UUID(),
        resolvedFrame: CGRect(x: 0, y: 0, width: 500, height: 300),
        measuredBounds: CGRect(x: 0, y: 0, width: 498, height: 300),
        lastAppliedSize: CGSize(width: 498, height: 300),
        redrawGeneration: 1,
        focusGeneration: 1,
        occlusionGeneration: 1,
        hostParentDebugID: "host-1"
    )
    #expect(metrics.resolvedFrame?.width == 500)
    #expect(metrics.measuredBounds?.width == 498)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalStructureMutationContextTests"
```

Expected: FAIL

- [ ] **Step 3: Implement the metrics and mutation types**

Required behavior:

- typed generation ids for tree churn
- metrics snapshot for host/layout/redraw/focus/occlusion proof state
- keep the types intentionally thin and proof-oriented; they exist now because later tasks need shared vocabulary for tests and reconciliation rather than reintroducing ad hoc dictionaries
- no UI mutation here; this task is diagnostics and coordination typing only

- [ ] **Step 4: Add typed surface inspection accessors**

Required behavior in `SurfaceManager`:

- expose surface id for pane
- expose active/hidden status
- expose process-alive status
- do not add new mutation surface yet

- [ ] **Step 5: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalStructureMutationContextTests|SurfaceTypesTests"
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Hosting/TerminalHostMetrics.swift \
        Sources/AgentStudio/Features/Terminal/Hosting/TerminalStructureMutationContext.swift \
        Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceTypes.swift \
        Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
        Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalStructureMutationContextTests.swift
git commit -m "feat: add terminal host diagnostics contract"
```

## Task 3: Refactor `AgentStudioTerminalView` Into `TerminalPaneHostView` And Add `GhosttyMountView`

**Files:**
- Move: `Sources/AgentStudio/Features/Terminal/Views/AgentStudioTerminalView.swift` -> `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift`
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneHostViewTests.swift`
- Test Helper: `Tests/AgentStudioTests/Helpers/MockGhosttySurfaceFactory.swift`

- [ ] **Step 0: Prove whether parent churn is real in the current code**

Before introducing `GhosttyMountView`, add temporary diagnostics to the current path and record whether `Ghostty.SurfaceView.superview` changes during:

- rapid split insert
- arrangement switch
- tab reveal

If parent churn is not observed, keep `GhosttyMountView` only if it still earns its place as a clearer mount boundary; do not present it as if the root cause has already been proven.

- [ ] **Step 1: Write failing tests for stable mount parentage**

```swift
@Test
@MainActor
func ghosttyMountView_isOnlyAppLocalParentOfGhosttySurface() {
    let host = TerminalPaneHostView(paneId: UUIDv7.generate())
    let mount = host.ghosttyMountViewForTesting
    let surfaceView = MockGhosttySurfaceFactory.makeSurfaceView()

    host.bindGhosttySurfaceForTesting(surfaceView)

    #expect(surfaceView.superview === mount)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyMountViewTests|TerminalPaneHostViewTests"
```

Expected: FAIL

- [ ] **Step 3: Implement `GhosttyMountView`**

Required behavior:

- be the dedicated mount/unmount site for `Ghostty.SurfaceView`
- no overlays
- no pane semantics
- mount and constraint the Ghostty view safely

- [ ] **Step 4: Add a test-only Ghostty surface factory**

Required behavior:

- use a concrete, explicit strategy rather than hand-waving:
  - either initialize a real test harness Ghostty surface, or
  - introduce a tiny mount-target protocol / adapter boundary so mount-view tests can use a plain `NSView`-backed double

Do not leave this ambiguous for the implementer.

- [ ] **Step 5: Rename and refactor `AgentStudioTerminalView`**

Required behavior:

- rename type and file to `TerminalPaneHostView`
- keep `PaneView` inheritance
- own overlays, host metrics, health behavior
- delegate direct Ghostty parenting to `GhosttyMountView`
- stop directly adding/removing `Ghostty.SurfaceView`

- [ ] **Step 6: Update terminal view references**

Replace all `AgentStudioTerminalView` usage in:

- `ViewRegistry`
- `PaneCoordinator+ViewLifecycle`
- `PaneCoordinator+ActionExecution`
- `PaneLeafContainer`

with `TerminalPaneHostView`

- [ ] **Step 7: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyMountViewTests|TerminalPaneHostViewTests|PaneContentWiringTests"
```

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift \
        Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift \
        Sources/AgentStudio/App/Panes/ViewRegistry.swift \
        Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift \
        Tests/AgentStudioTests/Helpers/MockGhosttySurfaceFactory.swift \
        Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift \
        Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneHostViewTests.swift
git commit -m "refactor: introduce stable terminal pane host and mount view"
```

## Task 4: Add Stable Terminal Host Reuse To `ViewRegistry`

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift`

- [ ] **Step 1: Write failing tests for one host per terminal pane**

```swift
@Test
@MainActor
func samePaneId_returnsSameTerminalPaneHost() {
    let registry = ViewRegistry()
    let paneId = UUIDv7.generate()

    let first = registry.ensureTerminalHost(for: paneId)
    let second = registry.ensureTerminalHost(for: paneId)

    #expect(first === second)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalHostReconciliationTests"
```

Expected: FAIL

- [ ] **Step 3: Add stable terminal-host reuse behavior to `ViewRegistry`**

Required behavior:

- one stable terminal host per terminal `paneId`
- no second app-global registry
- support deferred host configuration after lookup

- [ ] **Step 4: Route terminal host creation through `ViewRegistry`**

Required behavior in `PaneCoordinator+ViewLifecycle`:

- fetch terminal host through `ViewRegistry.ensureTerminalHost(...)`
- configure host with pane/worktree/repo/title context
- bind or rebind surface id and mount
- support both worktree-bound and floating-terminal paths

- [ ] **Step 5: Add explicit rationale comments**

Document in code that stable terminal-host reuse inside `ViewRegistry` exists to stabilize host identity across:

- split insert
- arrangement switch
- tab reveal
- minimize/expand
- undo/restore

not just to paper over one `displaySurface(...)` call

- [ ] **Step 6: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalHostReconciliationTests|PaneCoordinatorTests|PaneCoordinatorHardeningTests"
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/App/Panes/ViewRegistry.swift \
        Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
        Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift
git commit -m "feat: add stable terminal host reuse to view registry"
```

## Task 5: Reclassify All Visible Resize Paths And Make Host Layout Authoritative

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneHostViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalPaneGeometryResolverTests.swift`

- [ ] **Step 1: Write failing tests for measured-bounds-driven visible resize**

```swift
@Test
@MainActor
func hostLayout_appliesMeasuredBoundsAsVisibleSizeAuthority() {
    let paneId = UUIDv7.generate()
    let host = TerminalPaneHostView(paneId: paneId)

    host.recordResolvedFrameForTesting(CGRect(x: 0, y: 0, width: 500, height: 300))
    host.applyMeasuredBoundsForTesting(CGRect(x: 0, y: 0, width: 498, height: 300))

    #expect(host.metricsForTesting?.lastAppliedSize == CGSize(width: 498, height: 300))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalPaneHostViewTests|TerminalPaneGeometryResolverTests"
```

Expected: FAIL

- [ ] **Step 3: Write an ownership table for current size paths**

In code comments and plan notes, classify each current size path as:

- deleted
- retained for startup/restore only
- retained for scale-factor changes only
- authoritative visible resize path

This step must explicitly cover:

- `GhosttySurfaceView.setFrameSize(...)`
- `GhosttySurfaceView.viewDidMoveToWindow()` async resend
- `GhosttySurfaceView.viewDidChangeBackingProperties()`
- `TerminalPaneHostView.layout()`
- `TerminalPaneHostView.forceGeometrySync(...)`
- `PaneTabViewController.syncVisibleTerminalGeometry(...)`

- [ ] **Step 4: Move visible resize authority into `TerminalPaneHostView.layout()`**

Required behavior:

- host stores resolved frame for diagnostics only
- host measures actual mounted `ghosttyMountView.bounds`
- if measured size changed, host sends visible size to Ghostty
- size sends are de-duped by value/generation

- [ ] **Step 5: Re-scope the current geometry-sync path**

Required behavior:

- visible panes: `forceGeometrySync(...)` records/compares geometry and triggers host reconciliation, but does not act as the final visible size authority
- startup/offscreen creation: still allowed to use initial frame sizing
- code comments must explain how startup sizing and steady-state visible sizing coexist
- launch/restore visible geometry should be read from `WindowLifecycleStore.terminalContainerBounds` from the prerequisite plan rather than preserving a parallel closure chain

- [ ] **Step 6: Preserve scale-factor handling**

Ensure `viewDidChangeBackingProperties()` still:

- updates content scale
- resends size for scale-factor changes
- does not reintroduce a second visible steady-state size authority

- [ ] **Step 7: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalPaneHostViewTests|TerminalPaneGeometryResolverTests|PaneTabViewControllerLaunchRestoreTests"
```

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift \
        Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
        Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
        Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift \
        Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneHostViewTests.swift \
        Tests/AgentStudioTests/Features/Terminal/Restore/TerminalPaneGeometryResolverTests.swift
git commit -m "refactor: make host layout the visible ghostty resize authority"
```

## Task 6: Add Structure-Mutation Reconciliation For Focus, Occlusion, And Redraw

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Test: `Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift`

- [ ] **Step 1: Write failing tests for structure mutation without selection change**

```swift
@Test
@MainActor
func structureMutation_triggersFocusReconciliation_evenIfActivePaneUnchanged() {
    let coordinator = TestPaneCoordinatorFactory.make()
    coordinator.recordStructureMutationForTesting()
    #expect(coordinator.focusReconciliationCountForTesting == 1)
}

@Test
@MainActor
func structureMutation_triggersRedrawForAffectedVisibleHosts() {
    let host = TerminalPaneHostView(paneId: UUIDv7.generate())
    host.markStructureMutationForTesting()
    host.performPostLayoutReconciliationForTesting()
    #expect(host.metricsForTesting?.redrawGeneration == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalHostReconciliationTests"
```

Expected: FAIL

- [ ] **Step 3: Introduce explicit structure-mutation generations**

Required behavior:

- tree mutation gets a generation id and reason
- `PaneCoordinator` owns the generation and the sweep trigger
- reconciliation runs after layout settles
- this path is independent from `selectionChanged`

- [ ] **Step 4: Add focus reconciliation**

Required behavior:

- after structural mutation, run `syncFocus(activeSurfaceId:)` even if `activePaneId` is unchanged
- if active host moved/remounted, defer focus sync until the next runloop after layout settles

- [ ] **Step 5: Add occlusion reconciliation**

Required behavior:

- affected visible/hidden panes reconcile `ghostty_surface_set_occlusion`
- hidden panes stop rendering
- revealed panes resume correctly

- [ ] **Step 6: Add redraw reconciliation**

Required behavior:

- visible affected hosts request redraw after layout settles
- start with `ghostty_surface_refresh`
- treat refresh-first as a proof checkpoint, not a guaranteed final answer
- escalate to `ghostty_surface_draw` only if proof shows refresh is insufficient

- [ ] **Step 6a: Reuse existing `SurfaceManager.syncFocus(...)`**

Do not invent a second focus fanout path. The reconciliation sweep should reuse `SurfaceManager.syncFocus(activeSurfaceId:)` unless implementation evidence shows it is insufficient.

- [ ] **Step 7: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalHostReconciliationTests|PaneCoordinatorTests|PaneTabViewControllerLaunchRestoreTests"
```

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
        Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
        Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneHostView.swift \
        Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
        Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift
git commit -m "feat: reconcile focus occlusion and redraw after terminal tree churn"
```

## Task 7: Hard-Cut Existing Hot Paths To The New Host Contract

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`

- [ ] **Step 1: Write failing tests for lifecycle matrix rows**

Cover these exact rows:

- split insert
- arrangement switch
- tab reveal
- minimize / expand
- drawer expand / collapse
- undo / restore
- launch restore

Each test should assert no duplicate host creation and no missing repaint trigger.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorHardeningTests"
```

Expected: FAIL

- [ ] **Step 3: Replace or tighten existing hot paths**

Explicitly rewrite:

- `displaySurface(...)`
- `reattachForViewSwitch(...)`
- `SurfaceManager.attach(...)`
- `SurfaceManager.detach(...)`
- `restoreViewsForActiveTabIfNeeded()`
- `restoreAllViews(...)`

For each method, include one sentence in code comments or the implementation note describing the exact change:

- `displaySurface(...)` — route surface parenting only through `GhosttyMountView.mount(...)`
- `reattachForViewSwitch(...)` — reuse existing host identity rather than creating or swapping terminal hosts
- `SurfaceManager.attach(...)` — lifecycle state only, not arbitrary parent transport
- `SurfaceManager.detach(...)` — lifecycle state only, no hidden ownership of view hierarchy
- `restoreViewsForActiveTabIfNeeded()` — ensure stable host reuse and lifecycle-matrix reconciliation
- `restoreAllViews(...)` — ensure launch-restore path consumes prerequisite geometry store and the same host contract

Required behavior:

- each path must use stable hosts
- each path must feed the lifecycle matrix correctly
- no ad hoc renderer parent movement remains outside `GhosttyMountView`

- [ ] **Step 4: Run focused tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorHardeningTests|PaneCoordinatorTests|PaneContentWiringTests"
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
        Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
        Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
        Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift
git commit -m "refactor: cut terminal hot paths over to stable host contract"
```

## Task 8: Update Architecture Docs And Agent Guidance

**Files:**
- Modify: `docs/architecture/ghostty_surface_architecture.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/directory_structure.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Document the current vs target host tree**

Add the exact current and target ASCII diagrams.

- [ ] **Step 2: Document app-local rules vs Ghostty-backed behavior**

Required examples:

- `GhosttyMountView` parentage rule = app-local
- `ghostty_surface_refresh` after resize = app-local choice to validate
- `ghostty_surface_set_size`, focus, occlusion callbacks = vendor-backed Ghostty behavior

- [ ] **Step 3: Document the lifecycle matrix and resize-ownership table**

Required:

- matrix rows from Task 7
- current size-path ownership classification from Task 5

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/ghostty_surface_architecture.md \
        docs/architecture/component_architecture.md \
        docs/architecture/directory_structure.md \
        AGENTS.md
git commit -m "docs: describe stable terminal host and ghostty runtime boundaries"
```

## Task 9: Full Verification And Manual Proof Run

**Files:**
- Test: full suite

- [ ] **Step 1: Run focused host/runtime tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAppHandleTests|GhosttyCallbackRouterTests|GhosttyActionRouterTests|GhosttyFocusSynchronizerTests|GhosttyMountViewTests|TerminalPaneHostViewTests|TerminalHostReconciliationTests|PaneCoordinatorHardeningTests"
```

Expected: PASS

- [ ] **Step 2: Run full project tests**

Run:

```bash
AGENT_RUN_ID=stable-terminal-host mise run test
```

Expected: PASS, zero failures.

- [ ] **Step 3: Run lint**

Run:

```bash
AGENT_RUN_ID=stable-terminal-host mise run lint
```

Expected: PASS, zero errors.

- [ ] **Step 4: Manual repaint proof run**

Launch:

```bash
AGENTSTUDIO_RESTORE_TRACE=1 .build/debug/AgentStudio
```

Manual verification script:

1. Open one visible terminal pane.
2. Create two or three panes rapidly from the same visible tab.
3. Switch arrangements if available.
4. Minimize and expand a terminal pane.
5. Switch away and back to the tab.
6. Expand/collapse a drawer terminal if present.
7. Confirm no pane requires Enter to recover.
8. If anything looks blank, inspect `/tmp/agentstudio_debug.log` for:
   - host measured bounds
   - last applied Ghostty size
   - redraw generation
   - focus generation
   - occlusion generation
   - mount parent identity
   - lifecycle-matrix row under test

Expected: no visible pane goes blank during churn; no repaint depends on fresh PTY output.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: stabilize ghostty terminal hosting and runtime boundaries"
```

## Notes For The Implementer

- Use `@superpowers:subagent-driven-development` for execution.
- Do not parallelize Swift builds/tests.
- Do not leave multiple visible resize authorities in place.
- Do not leave C callback statics in a type that also owns main-actor lifecycle logic.
- Keep `ViewRegistry` as the app-canonical pane view map.
- Treat `ghostty_surface_refresh` as the first redraw strategy to prove, not the final answer by assumption.
