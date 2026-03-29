# Startup Pane Hosting Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate startup-time `PaneViewRepresentable.dismantleNSView -> makeNSView` cycles by ensuring the terminal split hosting tree is created once and never replaced during launch wiring.

**Architecture:** Push the real `AppLifecycleStore` from the AppDelegate composition root into `PaneTabViewController` before `loadView` builds `ActiveTabContent`. Remove the post-load `setAppLifecycleStore -> replaceSplitContentView()` path so startup lifecycle wiring updates state in place instead of tearing down the `NSHostingView` subtree. Lock the behavior with controller-level regression tests and architecture assertions, then update the debugging note with the corrected diagnosis.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Testing (`Testing`), GhosttyKit restore tracing

---

## File Structure

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  Responsibility: own a single, injected `AppLifecycleStore` for the lifetime of the controller and expose DEBUG-only identity hooks for tests.
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
  Responsibility: accept the shared `AppLifecycleStore` and pass it into `PaneTabViewController` at construction time.
- Modify: `Sources/AgentStudio/App/MainWindowController.swift`
  Responsibility: thread the shared `AppLifecycleStore` from window composition into `MainSplitViewController`.
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
  Responsibility: pass `appLifecycleStore` into `MainWindowController` in both launch and reopen code paths.
- Modify: `Sources/AgentStudio/App/AppDelegate+LifecycleRouting.swift`
  Responsibility: stop injecting lifecycle state into an already-loaded pane controller; keep Ghostty binding only.
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
  Responsibility: add a regression proving lifecycle changes do not replace `splitHostingView`.
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
  Responsibility: assert lifecycle composition stays at the App layer without `setAppLifecycleStore`.
- Modify: `docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md`
  Responsibility: record the cross-checked conclusion that late split-host replacement is a proven startup teardown trigger.

### Task 1: Lock The Controller-Level Regression

**Files:**
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`

- [ ] **Step 1: Write the failing test for stable split hosting identity**

Add a new harness field and regression test to `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`:

```swift
    private struct Harness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let executor: ActionExecutor
        let appLifecycleStore: AppLifecycleStore
        let windowLifecycleStore: WindowLifecycleStore
        let applicationLifecycleMonitor: ApplicationLifecycleMonitor
        let controller: PaneTabViewController
        let surfaceManager: LaunchCapturingSurfaceManager
        let window: NSWindow
        let tempDir: URL
    }

    @Test
    func appLifecycleChanges_doNotReplaceSplitHostingView() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let originalSplitHostingView = try #require(harness.controller.splitHostingViewForTesting)
        #expect(harness.controller.appLifecycleStoreForTesting === harness.appLifecycleStore)

        harness.appLifecycleStore.setActive(true)
        harness.controller.view.layoutSubtreeIfNeeded()

        let updatedSplitHostingView = try #require(harness.controller.splitHostingViewForTesting)
        #expect(updatedSplitHostingView === originalSplitHostingView)
    }
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests/appLifecycleChanges_doNotReplaceSplitHostingView"
```

Expected: FAIL to compile because `PaneTabViewController` does not yet expose `splitHostingViewForTesting` / `appLifecycleStoreForTesting`, and the harness cannot yet pass or retain the shared `AppLifecycleStore`.

- [ ] **Step 3: Add the minimal controller test hooks needed to express the regression**

Update `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` with DEBUG-only accessors:

```swift
#if DEBUG
    extension PaneTabViewController {
        var splitHostingViewForTesting: NSHostingView<ActiveTabContent>? { splitHostingView }
        var appLifecycleStoreForTesting: AppLifecycleStore { appLifecycleStore }
    }
#endif
```

Also update `makeHarness()` in `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift` so the shared lifecycle store is retained:

```swift
        let appLifecycleStore = AppLifecycleStore()
        let windowLifecycleStore = WindowLifecycleStore()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
```

- [ ] **Step 4: Run the targeted test again to verify it still fails for the real behavior gap**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests/appLifecycleChanges_doNotReplaceSplitHostingView"
```

Expected: FAIL because the controller still constructs its own `AppLifecycleStore` and/or replaces the split hosting tree after lifecycle injection, so the identity assertion does not hold yet.

- [ ] **Step 5: Commit the failing-test checkpoint**

```bash
git add Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift
git commit -m "test: lock split hosting stability during lifecycle updates"
```

### Task 2: Remove The Post-Load Split Hosting Replacement Path

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/App/MainWindowController.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate+LifecycleRouting.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`

- [ ] **Step 1: Update the failing test harness to use constructor injection**

Change the controller construction in `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`:

```swift
        let controller = PaneTabViewController(
            store: store,
            repoCache: WorkspaceRepoCache(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: executor,
            tabBarAdapter: TabBarAdapter(store: store, repoCache: WorkspaceRepoCache()),
            viewRegistry: viewRegistry
        )
```

- [ ] **Step 2: Run the targeted test to verify the constructor-injection change fails before implementation**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests/appLifecycleChanges_doNotReplaceSplitHostingView"
```

Expected: FAIL to compile with an error similar to `extra argument 'appLifecycleStore' in call`.

- [ ] **Step 3: Implement constructor injection and delete the late replacement path**

Apply these changes:

In `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`:

```swift
    private let appLifecycleStore: AppLifecycleStore

    init(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache = WorkspaceRepoCache(),
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleStore,
        executor: ActionExecutor,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator()
    ) {
        self.store = store
        self.repoCache = repoCache
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.executor = executor
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        self.closeTransitionCoordinator = closeTransitionCoordinator
        super.init(nibName: nil, bundle: nil)
        setupNotificationObservers()
    }
```

Delete these members entirely:

```swift
    private var appLifecycleStore = AppLifecycleStore()

    func setAppLifecycleStore(_ appLifecycleStore: AppLifecycleStore) {
        self.appLifecycleStore = appLifecycleStore

        guard isViewLoaded else { return }
        replaceSplitContentView()
    }

    private func replaceSplitContentView() {
        splitHostingView?.removeFromSuperview()
        splitHostingView = nil
        setupSplitContentView()
    }
```

In `Sources/AgentStudio/App/MainSplitViewController.swift`:

```swift
    private let appLifecycleStore: AppLifecycleStore

    init(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache,
        uiStore: WorkspaceUIStore,
        actionExecutor: ActionExecutor,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleStore,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry
    ) {
        self.store = store
        self.repoCache = repoCache
        self.uiStore = uiStore
        self.actionExecutor = actionExecutor
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        super.init(nibName: nil, bundle: nil)
    }
```

And when constructing `PaneTabViewController`:

```swift
        let paneTabVC = PaneTabViewController(
            store: store,
            repoCache: repoCache,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: actionExecutor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
```

In `Sources/AgentStudio/App/MainWindowController.swift`:

```swift
    convenience init(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache,
        uiStore: WorkspaceUIStore,
        actionExecutor: ActionExecutor,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleStore,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry
    ) {
```

and:

```swift
        let splitVC = MainSplitViewController(
            store: store,
            repoCache: repoCache,
            uiStore: uiStore,
            actionExecutor: actionExecutor,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
```

In `Sources/AgentStudio/App/AppDelegate.swift`, update both window creation sites:

```swift
        mainWindowController = MainWindowController(
            store: store,
            repoCache: workspaceRepoCache,
            uiStore: workspaceUIStore,
            actionExecutor: executor,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
```

In `Sources/AgentStudio/App/AppDelegate+LifecycleRouting.swift`, keep only Ghostty binding:

```swift
    func wireLifecycleConsumers() {
        Ghostty.bindApplicationLifecycleStore(appLifecycleStore)
    }
```

- [ ] **Step 4: Run the targeted regression and the launch-restore suite to verify the fix**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests"
```

Expected: PASS, including `appLifecycleChanges_doNotReplaceSplitHostingView`, with no compile errors from the constructor chain.

- [ ] **Step 5: Commit the lifecycle-wiring refactor**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift Sources/AgentStudio/App/MainSplitViewController.swift Sources/AgentStudio/App/MainWindowController.swift Sources/AgentStudio/App/AppDelegate.swift Sources/AgentStudio/App/AppDelegate+LifecycleRouting.swift Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift
git commit -m "refactor: inject app lifecycle store before split hosting setup"
```

### Task 3: Lock The Architecture Boundary And Record The Diagnosis

**Files:**
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
- Modify: `docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md`
- Test: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Update the architecture assertions to ban late lifecycle injection**

Change the lifecycle-composition test in `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`:

```swift
        #expect(
            !paneTabViewControllerSource.contains(
                "func setAppLifecycleStore(_ appLifecycleStore: AppLifecycleStore)"
            )
        )
        #expect(paneTabViewControllerSource.contains("private let appLifecycleStore: AppLifecycleStore"))
        #expect(mainWindowControllerSource.contains("appLifecycleStore: AppLifecycleStore"))
        #expect(splitViewControllerSource.contains("private let appLifecycleStore: AppLifecycleStore"))
        #expect(!appDelegateRoutingSource.contains("setAppLifecycleStore(appLifecycleStore)"))
        #expect(appDelegateRoutingSource.contains("Ghostty.bindApplicationLifecycleStore(appLifecycleStore)"))
```

- [ ] **Step 2: Run the architecture test to verify it fails before the assertion updates are implemented everywhere**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CoordinationPlaneArchitectureTests/lifecycleCompositionRoot_staysInAppDelegate"
```

Expected: FAIL if any source file still contains the removed setter path or is missing the new constructor-injection boundary.

- [ ] **Step 3: Record the corrected debugging conclusion in the shared note**

Append this section to `docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md`:

```markdown
## Debugging Epoch (2026-03-29): Late AppLifecycleStore Injection Is A Proven Startup Recreate Trigger

### Grounded evidence

- `AppDelegate.applicationDidFinishLaunching` calls `showWindow(nil)` and then `wireLifecycleConsumers()`
- `wireLifecycleConsumers()` calls `paneTabViewController()?.setAppLifecycleStore(appLifecycleStore)`
- `PaneTabViewController.setAppLifecycleStore` calls `replaceSplitContentView()` when the view is already loaded
- restore traces show `PaneViewRepresentable.dismantleNSView` after `mainWindow showWindow` / `appDidFinishLaunching: end`
- the same pane/container identities are recreated immediately afterward
- the same `Ghostty.SurfaceView`s then report `viewDidMoveToWindow ... reparent=true wasDetached=true`

### Conclusion

Startup recreate/dismantle is not only a generic SwiftUI diffing problem.

There is a direct app-level trigger:

```text
late lifecycle-store injection
  -> replaceSplitContentView()
  -> NSHostingView subtree removal
  -> PaneViewRepresentable dismantle/make cycle
  -> Ghostty surface detach/reattach
```

This path must be removed before pursuing broader SwiftUI diffing theories.
```

- [ ] **Step 4: Run the architecture test and the focused launch-restore suite again**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CoordinationPlaneArchitectureTests/lifecycleCompositionRoot_staysInAppDelegate"
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests"
```

Expected: PASS for both filters. The architecture test should confirm the old setter path is gone, and the launch-restore suite should confirm the controller keeps a stable hosting view.

- [ ] **Step 5: Commit the architecture guardrail and debugging note**

```bash
git add Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md
git commit -m "docs: record lifecycle injection as startup teardown trigger"
```

### Task 4: Full Verification Before Completion

**Files:**
- Modify: none
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
- Test: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Run the full targeted verification bundle**

Run:

```bash
mise run test
```

Expected: PASS, exit code `0`.

- [ ] **Step 2: Run lint and format validation**

Run:

```bash
mise run lint
```

Expected: PASS, exit code `0`.

- [ ] **Step 3: Run a manual startup trace verification on the debug build**

Run:

```bash
pkill -9 -f "AgentStudio"
.build/debug/AgentStudio
```

Expected manual result:

```text
startup restores panes
no PaneViewRepresentable.dismantleNSView burst after mainWindow showWindow
no Ghostty.SurfaceView.viewDidMoveToWindow ... reparent=true wasDetached=true burst caused by lifecycle wiring
```

- [ ] **Step 4: Verify the trace reflects the new invariant**

Run:

```bash
rg -n "PaneViewRepresentable\\.dismantleNSView|viewDidMoveToWindow .*reparent=true" /tmp/agentstudio_debug.log
```

Expected: no startup-time burst attributable to `wireLifecycleConsumers`; any remaining matches must be investigated before calling the work done.

- [ ] **Step 5: Commit the verification checkpoint**

```bash
git add -A
git commit -m "test: verify startup pane hosting remains stable"
```

## Self-Review

### Spec coverage

- Cross-check current evidence before planning: covered by Task 3 doc update and architecture assertions.
- Prevent startup recreate/dismantle behavior: covered by Task 2 constructor injection and setter removal.
- Keep the plan narrow and evidence-driven: covered by targeting the proven late lifecycle injection path instead of broad SwiftUI diffing rewrites.
- Verify with tests and runtime evidence: covered by Tasks 1, 3, and 4.

### Placeholder scan

- No `TODO`, `TBD`, or “similar to above” placeholders remain.
- Each code-changing step contains concrete code blocks.
- Each verification step contains explicit commands and expected outcomes.

### Type consistency

- `appLifecycleStore` is consistently modeled as `AppLifecycleStore`.
- The plan uses the same constructor name and controller type throughout: `PaneTabViewController`.
- The testing accessor names are consistent across the test and implementation steps: `splitHostingViewForTesting`, `appLifecycleStoreForTesting`.

Plan complete and saved to `docs/superpowers/plans/2026-03-29-startup-pane-hosting-stability.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
