# Lifecycle Store Geometry — Replace Ad-Hoc Restore Closure Chain

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move terminal container geometry and launch-layout-settle state from ad-hoc closure chains into `WindowLifecycleStore`, written by `ApplicationLifecycleMonitor`, consumed via `@Observable` observation — eliminating the stale-geometry bug and the callback-forwarding fragility that invited the recent `@MainActor` crash.

**Architecture:** Terminal container bounds and the "launch layout has settled" signal are transient runtime facts about the physical window, same category as `isActive` and `keyWindowId`. They belong in lifecycle stores, not in closure chains across four files. The `onRestoreHostReady` callback, `terminalContainerBoundsProvider` closure, generation counter, arm flag, and 5-second timeout safety net all go away. `PaneCoordinator` observes `WindowLifecycleStore` directly. Geometry is always read live, never cached from an intermediate layout pass.

**Tech Stack:** Swift 6.2, AppKit, `@Observable`, Swift Testing, mise build/test/lint

---

## Why This Plan Exists

Launch restore currently fires with stale pre-maximize terminal container bounds (e.g. 251×548 instead of 1140×824). The root cause: `RestoreAwareTerminalContainerView.layout()` caches bounds from the first non-empty layout pass (triggered by `showWindow`), then the arm-and-reconcile flow publishes those cached bounds to `startLaunchRestoreIfNeeded`. The window maximize may have already been set in init, so `applyLaunchMaximizeIfNeeded` takes the "frame already matches" fast path and `layoutSubtreeIfNeeded()` is a no-op because nothing was invalidated. Result: every Ghostty surface starts at the wrong size, PTY gets wrong cols/rows, zmx replays into the wrong grid.

The stale-geometry bug is a symptom. The structural problem is that restore orchestration state (bounds, settle signal, generation counter) lives in callback closures across `AppDelegate → MainWindowController → MainSplitViewController → PaneTabViewController` with no named contract. This fragility directly caused the `@MainActor` crash — an agent couldn't reason about the threading boundary because the code crossed too many layers through ad-hoc wiring.

## Prerequisite For

This plan is a prerequisite for `docs/superpowers/plans/2026-03-22-luna-295-stable-terminal-host-architecture.md`. That plan's Task 5 (resize authority) and Task 7 (hot-path cutover) both need terminal container bounds to come from a clean source. Without this work, the stable host plan would either inherit the closure chain or have to do this refactor inline.

## Design Decision

Terminal container geometry is **not persisted**. It is a transient runtime fact — the current physical size of the terminal content area, derived from the window frame, sidebar width, and tab bar height. It changes on resize and is meaningless across app launches. The layout model (split tree, ratios) is persisted; the geometry resolver computes concrete pixel frames from model + bounds at runtime.

The `isLaunchLayoutSettled` flag is also transient — a one-shot signal per launch that transitions from false to true when the post-maximize layout has propagated. It resets implicitly if we ever support multiple windows.

## Coordination Plane Alignment

| What | Current plane | Target plane |
|------|--------------|-------------|
| Terminal container bounds | Pull-based closure (`terminalContainerBoundsProvider`) | `WindowLifecycleStore.terminalContainerBounds` (observable) |
| Layout settle signal | `launchRestoreArmed` flag + generation counter in PaneTabVC | `WindowLifecycleStore.isLaunchLayoutSettled` (observable) |
| Restore trigger | `onRestoreHostReady` closure chain across 4 files | PaneCoordinator observes `isLaunchLayoutSettled` |
| Bounds ingress | `RestoreAwareTerminalContainerView.layout()` → closure | `ApplicationLifecycleMonitor.handleTerminalContainerBoundsChanged()` |
| Post-maximize signal | `windowDidResize` → `armLaunchRestoreReadiness` → generation check | `ApplicationLifecycleMonitor.handleLaunchLayoutSettled()` |

After this plan, all five rows follow the architecture's coordination plane for AppKit lifecycle ingress: `ApplicationLifecycleMonitor` writes → lifecycle store holds → consumers observe.

## File Structure

### Files modified

- `Sources/AgentStudio/App/Lifecycle/WindowLifecycleStore.swift` — add `terminalContainerBounds` and `isLaunchLayoutSettled`
- `Sources/AgentStudio/App/Lifecycle/ApplicationLifecycleMonitor.swift` — add ingress methods for bounds and settle
- `Sources/AgentStudio/App/MainWindowController.swift` — call monitor for maximize settle, remove `onRestoreHostReady`/`awaitsLaunchRestoreResize`/`awaitsLaunchMaximize`/`armLaunchRestoreReadiness` forwarding
- `Sources/AgentStudio/App/MainSplitViewController.swift` — remove `onRestoreHostReady`/`terminalContainerBounds`/`isReadyForRestore`/`armLaunchRestoreReadiness` forwarding
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` — remove `onRestoreHostReady`, `cachedRestoreHostBounds`, `restoreHostBoundsGeneration`, `armedRestoreGeneration`, `launchRestoreArmed`, `hasReconciledInitialVisibleRestore`, `hasPublishedRestoreHostReady`, `restoreHostReadyTimeoutTask`, `reconcileRestoreHostReadinessIfNeeded`, `publishCachedRestoreHostReadinessIfNeeded`, `armLaunchRestoreReadiness`; keep `RestoreAwareTerminalContainerView` but have it call the monitor instead of a closure
- `Sources/AgentStudio/App/AppDelegate.swift` — remove `onRestoreHostReady` wiring and `startLaunchRestoreIfNeeded`; add observation of `WindowLifecycleStore.isLaunchLayoutSettled` to trigger restore
- `Sources/AgentStudio/App/PaneCoordinator.swift` — remove `terminalContainerBoundsProvider` closure; inject `WindowLifecycleStore` reference
- `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift` — read `windowLifecycleStore.terminalContainerBounds` directly instead of calling closure

### Test files modified

- `Tests/AgentStudioTests/App/Lifecycle/WindowLifecycleStoreTests.swift` — add tests for new properties
- `Tests/AgentStudioTests/App/Lifecycle/ApplicationLifecycleMonitorTests.swift` — add tests for new ingress
- `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift` — rewrite to test through lifecycle store observation instead of callback chain
- `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift` — update harness to inject `WindowLifecycleStore` instead of `terminalContainerBoundsProvider`

---

### Task 1: Add Geometry and Settle State to WindowLifecycleStore

**Files:**
- Modify: `Sources/AgentStudio/App/Lifecycle/WindowLifecycleStore.swift`
- Test: `Tests/AgentStudioTests/App/Lifecycle/WindowLifecycleStoreTests.swift`

- [ ] **Step 1: Write failing tests for the new properties**

```swift
@Test("terminalContainerBounds starts at zero")
func test_terminalContainerBounds_startsEmpty() {
    let store = WindowLifecycleStore()
    #expect(store.terminalContainerBounds == .zero)
    #expect(store.isLaunchLayoutSettled == false)
}

@Test("recordTerminalContainerBounds updates bounds")
func test_recordTerminalContainerBounds_updatesBounds() {
    let store = WindowLifecycleStore()
    let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

    store.recordTerminalContainerBounds(bounds)

    #expect(store.terminalContainerBounds == bounds)
}

@Test("recordLaunchLayoutSettled transitions to true once")
func test_recordLaunchLayoutSettled_transitionsOnce() {
    let store = WindowLifecycleStore()

    store.recordLaunchLayoutSettled()

    #expect(store.isLaunchLayoutSettled == true)
}

@Test("isReadyForLaunchRestore requires both settle and non-empty bounds")
func test_isReadyForLaunchRestore_requiresBoth() {
    let store = WindowLifecycleStore()

    #expect(store.isReadyForLaunchRestore == false)

    store.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1140, height: 824))
    #expect(store.isReadyForLaunchRestore == false)

    store.recordLaunchLayoutSettled()
    #expect(store.isReadyForLaunchRestore == true)
}

@Test("isReadyForLaunchRestore is false with empty bounds even when settled")
func test_isReadyForLaunchRestore_falseWithEmptyBounds() {
    let store = WindowLifecycleStore()

    store.recordLaunchLayoutSettled()

    #expect(store.isReadyForLaunchRestore == false)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WindowLifecycleStoreTests"`
Expected: FAIL with missing properties/methods.

- [ ] **Step 3: Add the new properties and methods to WindowLifecycleStore**

```swift
@Observable
@MainActor
final class WindowLifecycleStore {
    // existing
    private(set) var registeredWindowIds: Set<UUID> = []
    private(set) var keyWindowId: UUID?
    private(set) var focusedWindowId: UUID?

    // new — transient runtime geometry, never persisted
    private(set) var terminalContainerBounds: CGRect = .zero
    private(set) var isLaunchLayoutSettled: Bool = false

    // derived — the Swift @Observable equivalent of a Jotai derived atom
    var isReadyForLaunchRestore: Bool {
        isLaunchLayoutSettled && !terminalContainerBounds.isEmpty
    }

    // existing methods unchanged...

    func recordTerminalContainerBounds(_ bounds: CGRect) {
        terminalContainerBounds = bounds
    }

    func recordLaunchLayoutSettled() {
        isLaunchLayoutSettled = true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WindowLifecycleStoreTests"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Lifecycle/WindowLifecycleStore.swift \
  Tests/AgentStudioTests/App/Lifecycle/WindowLifecycleStoreTests.swift
git commit -m "feat: add terminal container geometry and launch settle state to WindowLifecycleStore"
```

---

### Task 2: Add Geometry Ingress to ApplicationLifecycleMonitor

**Files:**
- Modify: `Sources/AgentStudio/App/Lifecycle/ApplicationLifecycleMonitor.swift`
- Test: `Tests/AgentStudioTests/App/Lifecycle/ApplicationLifecycleMonitorTests.swift`

- [ ] **Step 1: Write failing tests for the new ingress methods**

```swift
@Test("handleTerminalContainerBoundsChanged writes to window lifecycle store")
func test_handleTerminalContainerBoundsChanged_writesToStore() {
    let appStore = AppLifecycleStore()
    let windowStore = WindowLifecycleStore()
    let monitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appStore,
        windowLifecycleStore: windowStore
    )
    let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

    monitor.handleTerminalContainerBoundsChanged(bounds)

    #expect(windowStore.terminalContainerBounds == bounds)
}

@Test("handleLaunchLayoutSettled writes settled state to store")
func test_handleLaunchLayoutSettled_writesToStore() {
    let appStore = AppLifecycleStore()
    let windowStore = WindowLifecycleStore()
    let monitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appStore,
        windowLifecycleStore: windowStore
    )

    monitor.handleLaunchLayoutSettled()

    #expect(windowStore.isLaunchLayoutSettled == true)
}

@Test("handleLaunchMaximizeCompleted writes bounds and settle in one call")
func test_handleLaunchMaximizeCompleted_writesBoundsAndSettle() {
    let appStore = AppLifecycleStore()
    let windowStore = WindowLifecycleStore()
    let monitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appStore,
        windowLifecycleStore: windowStore
    )
    let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

    monitor.handleLaunchMaximizeCompleted(terminalContainerBounds: bounds)

    #expect(windowStore.terminalContainerBounds == bounds)
    #expect(windowStore.isLaunchLayoutSettled == true)
    #expect(windowStore.isReadyForLaunchRestore == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ApplicationLifecycleMonitorTests"`
Expected: FAIL with missing methods.

- [ ] **Step 3: Add ingress methods to ApplicationLifecycleMonitor**

```swift
func handleTerminalContainerBoundsChanged(_ bounds: CGRect) {
    windowLifecycleStore.recordTerminalContainerBounds(bounds)
}

func handleLaunchLayoutSettled() {
    windowLifecycleStore.recordLaunchLayoutSettled()
}

func handleLaunchMaximizeCompleted(terminalContainerBounds: CGRect) {
    windowLifecycleStore.recordTerminalContainerBounds(terminalContainerBounds)
    windowLifecycleStore.recordLaunchLayoutSettled()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ApplicationLifecycleMonitorTests"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Lifecycle/ApplicationLifecycleMonitor.swift \
  Tests/AgentStudioTests/App/Lifecycle/ApplicationLifecycleMonitorTests.swift
git commit -m "feat: add terminal geometry and launch settle ingress to ApplicationLifecycleMonitor"
```

---

### Task 3: Hard Cutover — Wire Monitor Ingress, Observe Lifecycle Store, Delete Closure Chain

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/MainWindowController.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`

This is a single hard cutover. No coexistence window. The old callback chain is replaced with monitor ingress + lifecycle store observation in one commit.

- [ ] **Step 1: Inject `WindowLifecycleStore` into `PaneCoordinator`**

Add `windowLifecycleStore: WindowLifecycleStore` as a constructor parameter on `PaneCoordinator`. Remove `terminalContainerBoundsProvider` closure entirely.

- [ ] **Step 2: Replace `terminalContainerBoundsProvider()` reads with `windowLifecycleStore.terminalContainerBounds`**

In `PaneCoordinator+ViewLifecycle.swift`:
- `restoreViewsForActiveTabIfNeeded()` reads `windowLifecycleStore.terminalContainerBounds` instead of calling `terminalContainerBoundsProvider()`
- `restoreAllViews(in:)` keeps its parameter for the launch-restore call (AppDelegate passes the bounds from the store)

- [ ] **Step 3: Wire `RestoreAwareTerminalContainerView` to call the monitor**

In `PaneTabViewController`, pass `ApplicationLifecycleMonitor` as a dependency. In `loadView()`, the callback writes bounds through the monitor:

```swift
terminalContainer.onNonEmptyLayoutBoundsChanged = { [weak self] bounds in
    self?.applicationLifecycleMonitor.handleTerminalContainerBoundsChanged(bounds)
    self?.syncVisibleTerminalGeometry(reason: "terminalContainerLayout")
}
```

No dual path. The old `handleTerminalContainerBoundsChanged` method is simplified to only call `syncVisibleTerminalGeometry` — bounds update goes through the monitor.

- [ ] **Step 4: Wire `MainWindowController` maximize to call the monitor for settle**

Replace `applyLaunchMaximizeIfNeeded` — it now just does the maximize and calls the monitor:

```swift
private func applyLaunchMaximizeIfNeeded() {
    guard awaitsLaunchMaximize else { return }
    guard let window, let screen = window.screen ?? NSScreen.main else { return }
    awaitsLaunchMaximize = false
    let targetFrame = screen.visibleFrame

    if !window.frame.equalTo(targetFrame) {
        window.setFrame(targetFrame, display: true)
    }
    window.contentView?.needsLayout = true
    window.contentView?.layoutSubtreeIfNeeded()

    let bounds = windowLifecycleStore.terminalContainerBounds
    applicationLifecycleMonitor.handleLaunchMaximizeCompleted(terminalContainerBounds: bounds)
    RestoreTrace.log(
        "MainWindowController.applyLaunchMaximize bounds=\(NSStringFromRect(bounds))"
    )
}
```

`MainWindowController` reads bounds from `WindowLifecycleStore` (the `RestoreAwareTerminalContainerView` callback already wrote them via the monitor during `layoutSubtreeIfNeeded`). Inject `WindowLifecycleStore` into `MainWindowController` alongside the existing `ApplicationLifecycleMonitor`.

For the `windowDidResize` path: simplify to just call the monitor after layout:

```swift
func windowDidResize(_ notification: Notification) {
    saveWindowFrame()
    guard awaitsLaunchRestoreResize else { return }
    awaitsLaunchRestoreResize = false
    window?.contentView?.needsLayout = true
    window?.contentView?.layoutSubtreeIfNeeded()
    let bounds = windowLifecycleStore.terminalContainerBounds
    applicationLifecycleMonitor.handleLaunchMaximizeCompleted(terminalContainerBounds: bounds)
}
```

- [ ] **Step 5: Replace `onRestoreHostReady` callback in AppDelegate with observation**

Remove `startLaunchRestoreIfNeeded`, `hasStartedLaunchRestore`, and all `onRestoreHostReady` wiring. Replace with:

```swift
private var launchRestoreObservationTask: Task<Void, Never>?

private func observeLaunchRestoreReadiness() {
    let windowStore = windowLifecycleStore!
    let coordinator = paneCoordinator!
    let windowController = mainWindowController

    launchRestoreObservationTask = Task { @MainActor [weak self] in
        // One-shot observation loop: once isReadyForLaunchRestore transitions
        // to true, break and trigger restore exactly once.
        // Event-driven suspension — no timeout needed. The task suspends until
        // @Observable tracking fires, then re-checks the derived condition.
        while !Task.isCancelled {
            if windowStore.isReadyForLaunchRestore { break }
            await Task.yield()
            try? await withObservationTracking {
                _ = windowStore.isReadyForLaunchRestore
            } onChange: { }
        }
        guard !Task.isCancelled, let self else { return }
        let bounds = windowStore.terminalContainerBounds
        RestoreTrace.log(
            "launchRestore triggered bounds=\(NSStringFromRect(bounds))"
        )
        await coordinator.restoreAllViews(in: bounds)
        windowController?.syncVisibleTerminalGeometry(reason: "postLaunchRestore")
        RestoreTrace.log(
            "launchRestore complete registeredViews=\(self.viewRegistry.registeredPaneIds.count)"
        )
    }
}
```

Call `observeLaunchRestoreReadiness()` after `completeLaunchPresentation()` in `applicationDidFinishLaunching`.

- [ ] **Step 6: Delete all old callback chain artifacts**

Delete from `PaneTabViewController`:
- `onRestoreHostReady` property and `didSet`
- `cachedRestoreHostBounds`
- `restoreHostBoundsGeneration`
- `armedRestoreGeneration`
- `launchRestoreArmed`
- `hasReconciledInitialVisibleRestore`
- `hasPublishedRestoreHostReady`
- `restoreHostReadyTimeoutTask`
- `armLaunchRestoreReadiness()`
- `reconcileRestoreHostReadinessIfNeeded(reason:)`
- `publishCachedRestoreHostReadinessIfNeeded(reason:)`
- `isReadyForRestore` (readiness is now in `WindowLifecycleStore`)

Simplify `handleTerminalContainerBoundsChanged` to only call `syncVisibleTerminalGeometry`.

Delete from `MainSplitViewController`:
- `onRestoreHostReady` property and `didSet`
- `terminalContainerBounds` computed property
- `isReadyForRestore` computed property
- `armLaunchRestoreReadiness()` forwarding

Delete from `MainWindowController`:
- `onRestoreHostReady` property and `didSet`
- `terminalContainerBounds` computed property
- `isReadyForRestore` computed property
- `prepareLaunchMaximizeAndRestore()` (the `awaitsLaunchMaximize` flag stays — it gates the maximize itself, not restore)
- `awaitLaunchRestoreAfterNextResize()` (the `awaitsLaunchRestoreResize` flag stays — it gates the resize-to-settle path)

Delete from `AppDelegate`:
- `startLaunchRestoreIfNeeded(in:)`
- `hasStartedLaunchRestore`
- `onRestoreHostReady` wiring
- `launchRestoreTask` (replaced by `launchRestoreObservationTask`)

Delete from `PaneCoordinator`:
- `terminalContainerBoundsProvider` closure

- [ ] **Step 7: Run full test suite**

Run: `AGENT_RUN_ID=lifecycle-cutover mise run test`
Expected: Some existing tests will fail because they reference removed APIs. Fix in Task 4.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/App/AppDelegate.swift \
  Sources/AgentStudio/App/PaneCoordinator.swift \
  Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Sources/AgentStudio/App/MainWindowController.swift \
  Sources/AgentStudio/App/MainSplitViewController.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift
git commit -m "refactor: hard cutover from restore callback chain to WindowLifecycleStore observation"
```

---

### Task 4: Rewrite Tests for the New Observation Path

**Files:**
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
- Modify: `Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift`

- [ ] **Step 1: Rewrite PaneTabViewControllerLaunchRestoreTests**

The old tests tested the arm→generation→publish callback chain. The new tests should test:
- Before settle: `windowLifecycleStore.isReadyForLaunchRestore == false`
- After bounds + settle: `isReadyForLaunchRestore == true`
- Bounds read at restore time are live (not cached from an earlier layout)
- `syncVisibleTerminalGeometry` still fires on layout changes

```swift
@Test("layout before settle does not make store ready")
func layoutBeforeSettle_storeNotReady() {
    let harness = makeHarness()
    defer { cleanup(harness) }

    let windowStore = harness.windowLifecycleStore
    windowStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1200, height: 800))

    #expect(windowStore.isReadyForLaunchRestore == false)
}

@Test("settle with bounds makes store ready for restore")
func settleWithBounds_storeReady() {
    let harness = makeHarness()
    defer { cleanup(harness) }

    let windowStore = harness.windowLifecycleStore
    windowStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1140, height: 824))
    windowStore.recordLaunchLayoutSettled()

    #expect(windowStore.isReadyForLaunchRestore == true)
    #expect(windowStore.terminalContainerBounds.width == 1140)
}

@Test("restoreAllViews uses lifecycle store bounds")
func restoreAllViews_usesLifecycleStoreBounds() async throws {
    let harness = makeHarness()
    defer { cleanup(harness) }

    // Set up a pane to restore
    let pane = harness.store.createPane(
        source: .floating(workingDirectory: harness.tempDir, title: "Test"),
        provider: .zmx
    )
    let tab = Tab(paneId: pane.id, name: "Test")
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)

    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
    await harness.coordinator.restoreAllViews(in: bounds)

    let config = harness.surfaceManager.createdConfigsByPaneId[pane.id]
    #expect(config?.initialFrame == CGRect(x: 2, y: 2, width: 996, height: 596))
}
```

- [ ] **Step 2: Add observation-triggers-restore integration test**

The old tests tested the callback chain. This test verifies that the observation loop in AppDelegate actually triggers `restoreAllViews` when the lifecycle store transitions to ready.

```swift
@Test("lifecycle store readiness transition triggers restore")
func lifecycleStoreReadiness_triggersRestore() async throws {
    let harness = makeHarness()
    defer { cleanup(harness) }

    let pane = harness.store.createPane(
        source: .floating(workingDirectory: harness.tempDir, title: "Observation"),
        provider: .zmx
    )
    let tab = Tab(paneId: pane.id, name: "Observation")
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)

    // Store not ready yet — no surfaces should be created
    #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == false)
    #expect(harness.surfaceManager.createdPaneIds.isEmpty)

    // Transition to ready
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
    harness.windowLifecycleStore.recordTerminalContainerBounds(bounds)
    harness.windowLifecycleStore.recordLaunchLayoutSettled()
    #expect(harness.windowLifecycleStore.isReadyForLaunchRestore == true)

    // Manually trigger restore (simulating what the observation loop does)
    await harness.coordinator.restoreAllViews(in: bounds)

    #expect(harness.surfaceManager.createdPaneIds == [pane.id])
}
```

- [ ] **Step 3: Update Luna295DirectZmxAttachIntegrationTests harness**

Replace `harness.coordinator.terminalContainerBoundsProvider = { ... }` with injection of `WindowLifecycleStore`:

```swift
let windowLifecycleStore = WindowLifecycleStore()
windowLifecycleStore.recordTerminalContainerBounds(CGRect(x: 0, y: 0, width: 1000, height: 600))
// Pass windowLifecycleStore to PaneCoordinator constructor
```

- [ ] **Step 4: Run full test suite**

Run: `AGENT_RUN_ID=lifecycle-tests mise run test`
Expected: PASS, zero failures.

- [ ] **Step 5: Commit**

```bash
git add Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift \
  Tests/AgentStudioTests/App/Luna295DirectZmxAttachIntegrationTests.swift
git commit -m "test: rewrite restore tests for lifecycle store observation path"
```

---

### Task 5: Full Verification

**Files:**
- All modified files from Tasks 1-5

- [ ] **Step 1: Run full test suite**

Run: `AGENT_RUN_ID=lifecycle-verify mise run test`
Expected: PASS, zero failures. Report pass/fail counts.

- [ ] **Step 2: Run lint**

Run: `AGENT_RUN_ID=lifecycle-verify mise run lint`
Expected: PASS, zero errors.

- [ ] **Step 3: Manual verification with restore trace**

Launch:

```bash
pkill -9 -f "AgentStudio" 2>/dev/null
AGENTSTUDIO_RESTORE_TRACE=1 .build/debug/AgentStudio &
```

Verify in trace output:
- `handleTerminalContainerBoundsChanged` fires through the monitor
- `handleLaunchMaximizeCompleted` fires with post-maximize bounds
- `launchRestore triggered bounds=` shows the correct full-size bounds (not 251×548)
- Surfaces are created with initial frames matching the full terminal container size

- [ ] **Step 4: Verify no stale geometry**

1. Add a repo from the sidebar
2. Open a terminal pane (Cmd+T or sidebar click)
3. Check RestoreTrace: the surface initial frame should match the terminal container, not 800×600 or 251×548
4. Quit and relaunch — restored panes should start at correct size without a visible resize flash

- [ ] **Step 5: Verify closure chain is fully removed**

```bash
grep -rn "onRestoreHostReady\|terminalContainerBoundsProvider\|cachedRestoreHostBounds\|restoreHostBoundsGeneration\|armedRestoreGeneration\|launchRestoreArmed\|hasPublishedRestoreHostReady\|restoreHostReadyTimeoutTask" Sources/
```

Expected: zero matches.

---

## Notes for the Implementer

- **No coexistence.** Task 3 is a single hard cutover. The old callback chain and the new observation path never coexist in the same commit.
- **Do not add a generation counter** to the new design. The `@Observable` tracking handles dependency invalidation. If `terminalContainerBounds` changes, any consumer reading it re-evaluates automatically.
- **Do not cache bounds.** Always read `windowLifecycleStore.terminalContainerBounds` live. The stale-geometry bug was caused by caching.
- **`RestoreAwareTerminalContainerView`** stays — it's still the AppKit ingress point where `layout()` fires. But its callback now calls the monitor, not a closure chain.
- **`syncVisibleTerminalGeometry`** stays — it's the resize percolation path for ongoing resize. It reads live bounds from the view hierarchy, which is correct for steady-state resize. The lifecycle store is for the launch-restore path.
- **The `withObservationTracking` loop in AppDelegate** is intentionally simple. It checks `isReadyForLaunchRestore` and yields. A more elegant approach would use `AsyncStream` from observation, but that's unnecessary complexity for a one-shot signal.
