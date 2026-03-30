# Persistent Tab Hosting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep every tab's pane hierarchy alive in memory so tab switching and ordinary within-tab state changes never detach terminal or webview panes from the window hierarchy.

**Architecture:** Move tab retention to AppKit by giving `PaneTabViewController` one persistent content host per tab. Replace the single active-tab SwiftUI root with a tab-scoped SwiftUI root (`SingleTabContent`) rendered inside per-tab hosts, and switch tabs by showing/hiding hosts rather than replacing a shared subtree. Also remove closure-based subtree identity churn by routing pane actions, split persistence, and drop handling through a stable AppKit-owned dispatcher reference all the way down the visible tab view tree.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, NSHostingView, Swift Testing (`Testing`), GhosttyKit, `@Observable`

---

## File Structure

**Files:**
- Create: `Sources/AgentStudio/App/Panes/PersistentTabHostView.swift`
  Responsibility: AppKit-owned persistent host for one tab, containing one pinned `NSHostingView<SingleTabContent>`.
- Create: `Sources/AgentStudio/App/Panes/PaneTabActionDispatcher.swift`
  Responsibility: stable `@MainActor` reference type that exposes pane action dispatch, split-resize finalization, and drop-routing methods without closure recreation.
- Create: `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift`
  Responsibility: SwiftUI root for exactly one tab ID; renders one visible tab subtree without reading `store.activeTabId`.
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  Responsibility: own per-tab host lifecycle, visibility switching, geometry sync targeting, focus routing, and test-only dismantle counters.
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
  Responsibility: replace `action`, `shouldAcceptDrop`, `onDrop`, and `onPersist` closures with a stable dispatcher reference.
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
  Responsibility: replace action/persist closures with the stable dispatcher and keep pane/divider children closure-free.
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
  Responsibility: route pane controls through the stable dispatcher reference rather than per-render closures.
- Modify: `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`
  Responsibility: route collapsed-pane actions through the stable dispatcher reference.
- Modify: `Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift`
  Responsibility: route drop-acceptance and drop-commit through the stable dispatcher reference.
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
  Responsibility: route drawer-level pane actions through the stable dispatcher reference.
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
  Responsibility: retire or reduce to compatibility shim; remove active-tab main-content ownership from the controller path.
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
  Responsibility: unchanged pane mapping, but comments/docs may need to clarify the added tab-host retention layer.
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
  Responsibility: add launch and visibility tests for tab-host persistence.
- Create: `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`
  Responsibility: verify tab switching and within-tab state changes preserve hosts and do not dismantle representables.
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
  Responsibility: assert the tab-retention boundary moved from active-tab SwiftUI selection plus closures to AppKit host ownership plus dispatcher references.
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
  Responsibility: document per-tab persistent hosting as the main content pattern.
- Modify: `docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md`
  Responsibility: capture the final diagnosis and the chosen architectural fix.

### Task 1: Lock The Cross-Tab And Within-Tab No-Dismantle Regressions

**Files:**
- Create: `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`

- [ ] **Step 1: Write the failing tab-retention test file**

Create `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`:

```swift
import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneTabViewControllerTabRetentionTests {
    private struct Harness {
        let store: WorkspaceStore
        let controller: PaneTabViewController
        let window: NSWindow
        let tempDir: URL
    }

    private func makeHarness() -> Harness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-tab-retention-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let appLifecycleStore = AppLifecycleStore()
        let windowLifecycleStore = WindowLifecycleStore()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let coordinator = makeTestPaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: MockPersistentTabSurfaceManager(),
            runtimeRegistry: RuntimeRegistry()
        )
        let controller = PaneTabViewController(
            store: store,
            repoCache: WorkspaceRepoCache(),
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: ActionExecutor(coordinator: coordinator, store: store),
            tabBarAdapter: TabBarAdapter(store: store, repoCache: WorkspaceRepoCache()),
            viewRegistry: viewRegistry
        )
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        return Harness(store: store, controller: controller, window: window, tempDir: tempDir)
    }

    @Test
    func switchingTabs_reusesPersistentHosts() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "First"),
            provider: .zmx
        )
        let secondPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Second"),
            provider: .zmx
        )
        let firstTab = Tab(paneId: firstPane.id, name: "First")
        let secondTab = Tab(paneId: secondPane.id, name: "Second")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.setActiveTab(firstTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let firstHost = try #require(harness.controller.tabHostViewForTesting(tabId: firstTab.id))

        harness.store.setActiveTab(secondTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()
        let secondHost = try #require(harness.controller.tabHostViewForTesting(tabId: secondTab.id))

        harness.store.setActiveTab(firstTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()
        let firstHostAfterRoundTrip = try #require(
            harness.controller.tabHostViewForTesting(tabId: firstTab.id)
        )

        #expect(firstHostAfterRoundTrip === firstHost)
        #expect(secondHost !== firstHost)
    }

    @Test
    func activeTabChanges_doNotDismantleStillExistingTabHosts() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "First"),
            provider: .zmx
        )
        let secondPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Second"),
            provider: .zmx
        )
        let firstTab = Tab(paneId: firstPane.id, name: "First")
        let secondTab = Tab(paneId: secondPane.id, name: "Second")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.setActiveTab(firstTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let dismantleCountBeforeSwitch = harness.controller.paneRepresentableDismantleCountForTesting

        harness.store.setActiveTab(secondTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        #expect(
            harness.controller.paneRepresentableDismantleCountForTesting == dismantleCountBeforeSwitch
        )
    }

    @Test
    func withinTabStateChanges_doNotDismantleRepresentables() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let pane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Focused"),
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Focused")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let dismantleCountBeforeMutation = harness.controller.paneRepresentableDismantleCountForTesting

        harness.store.bumpViewRevision()
        harness.controller.view.layoutSubtreeIfNeeded()

        #expect(
            harness.controller.paneRepresentableDismantleCountForTesting == dismantleCountBeforeMutation
        )
    }
}
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerTabRetentionTests"
```

Expected: FAIL to compile because `tabHostViewForTesting`, `paneRepresentableDismantleCountForTesting`, and `MockPersistentTabSurfaceManager` do not exist yet.

- [ ] **Step 3: Add the minimal DEBUG accessors and test stub needed to express the regressions**

Update `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`:

```swift
#if DEBUG
    extension PaneTabViewController {
        func tabHostViewForTesting(tabId: UUID) -> NSView? {
            tabContentHosts[tabId]?.containerView
        }

        var paneRepresentableDismantleCountForTesting: Int {
            paneRepresentableDismantleCount
        }
    }
#endif
```

Add a minimal test double in the new test file:

```swift
@MainActor
private final class MockPersistentTabSurfaceManager: PaneCoordinatorSurfaceManaging {
    private let cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
        continuation.finish()
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> { .failure(.operationFailed("test")) }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        _ = surfaceId
        _ = paneId
        return nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {
        _ = surfaceId
        _ = reason
    }

    func undoClose() -> ManagedSurface? { nil }
    func requeueUndo(_ surfaceId: UUID) { _ = surfaceId }
    func destroy(_ surfaceId: UUID) { _ = surfaceId }
}
```

- [ ] **Step 4: Run the targeted test again to verify the current architecture still fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerTabRetentionTests"
```

Expected: FAIL because `PaneTabViewController` still has only one `splitHostingView`, so there is no per-tab host identity to preserve and no no-dismantle invariant.

- [ ] **Step 5: Commit the regression-test checkpoint**

```bash
git add Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift
git commit -m "test: lock persistent tab and no-dismantle regressions"
```

### Task 2: Introduce Per-Tab Persistent AppKit Hosts

**Files:**
- Create: `Sources/AgentStudio/App/Panes/PersistentTabHostView.swift`
- Create: `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`

- [ ] **Step 1: Add the failing host references to the controller**

Update `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`:

```swift
    private var tabContentHosts: [UUID: PersistentTabHostView] = [:]
    private(set) var paneRepresentableDismantleCount = 0

    private func buildTabContentHost(for tabId: UUID) -> PersistentTabHostView {
        let rootView = SingleTabContent(
            tabId: tabId,
            store: store,
            repoCache: repoCache,
            viewRegistry: viewRegistry,
            appLifecycleStore: appLifecycleStore,
            closeTransitionCoordinator: closeTransitionCoordinator,
            actionDispatcher: actionDispatcher
        )
        return PersistentTabHostView(tabId: tabId, rootView: rootView)
    }
```

- [ ] **Step 2: Run the targeted test to verify it fails before implementation**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerTabRetentionTests/switchingTabs_reusesPersistentHosts"
```

Expected: FAIL to compile because `PersistentTabHostView` and `SingleTabContent` do not exist.

- [ ] **Step 3: Create the persistent host and tab-scoped SwiftUI root**

Create `Sources/AgentStudio/App/Panes/PersistentTabHostView.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class PersistentTabHostView: NSView {
    let tabId: UUID
    let hostingView: NSHostingView<SingleTabContent>
    var containerView: NSView { self }

    init(tabId: UUID, rootView: SingleTabContent) {
        self.tabId = tabId
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}
```

Create `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift`:

```swift
import SwiftUI

struct SingleTabContent: View {
    let tabId: UUID
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleStore
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneTabActionDispatching

    var body: some View {
        if let tab = store.tab(tabId) {
            FlatTabStripContainer(
                layout: tab.layout,
                tabId: tabId,
                activePaneId: tab.activePaneId,
                zoomedPaneId: tab.zoomedPaneId,
                minimizedPaneIds: tab.minimizedPaneIds,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                appLifecycleStore: appLifecycleStore
            )
            .background(AppStyle.chromeBackground)
        }
    }
}
```

- [ ] **Step 4: Replace the single active-tab host path in the controller**

Update `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`:

```swift
    override func viewDidLoad() {
        super.viewDidLoad()
        CommandDispatcher.shared.handler = self
        syncTabContentHosts()
        updateVisibleTabHost()
        updateEmptyState()
        observeForAppKitState()
        ...
    }

    private func syncTabContentHosts() {
        let liveTabIds = Set(store.tabs.map(\.id))

        for tab in store.tabs where tabContentHosts[tab.id] == nil {
            let host = buildTabContentHost(for: tab.id)
            terminalContainer.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                host.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
                host.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
            ])
            tabContentHosts[tab.id] = host
        }

        for (tabId, host) in tabContentHosts where !liveTabIds.contains(tabId) {
            host.removeFromSuperview()
            tabContentHosts.removeValue(forKey: tabId)
        }
    }

    private func updateVisibleTabHost() {
        let activeTabId = store.activeTabId
        for (tabId, host) in tabContentHosts {
            host.isHidden = tabId != activeTabId
        }
    }
```

Remove the single-host path:

```swift
    private var splitHostingView: NSHostingView<ActiveTabContent>?
    ...
    setupSplitContentView()
```

Stop using `ActiveTabContent` from `PaneTabViewController`.

- [ ] **Step 5: Run the retention suite to verify the host layer works**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerTabRetentionTests"
```

Expected: still FAIL on the within-tab no-dismantle test because the closure-heavy visible subtree has not been fixed yet.

### Task 3: Replace Closure Props Through The Full Visible Tab Tree

**Files:**
- Create: `Sources/AgentStudio/App/Panes/PaneTabActionDispatcher.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`

- [ ] **Step 1: Add the failing dispatcher references**

Introduce these API shape changes before implementation:

In `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`:

```swift
struct FlatTabStripContainer: View {
    ...
    let actionDispatcher: PaneTabActionDispatching
    ...
}
```

In `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`:

```swift
struct FlatPaneStripContent: View {
    ...
    let actionDispatcher: PaneTabActionDispatching
}
```

In `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`:

```swift
struct PaneLeafContainer: View {
    ...
    let actionDispatcher: PaneTabActionDispatching
}
```

- [ ] **Step 2: Run the targeted test to verify it fails before implementation**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerTabRetentionTests/withinTabStateChanges_doNotDismantleRepresentables"
```

Expected: FAIL to compile because the dispatcher type and propagated API do not exist.

- [ ] **Step 3: Implement the stable dispatcher and propagate it to every hot-path child**

Create `Sources/AgentStudio/App/Panes/PaneTabActionDispatcher.swift`:

```swift
import Foundation

@MainActor
protocol PaneTabActionDispatching: AnyObject {
    func dispatch(_ action: PaneActionCommand)
    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    ) -> Bool
    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    )
    func finishSplitResize(tabId: UUID, dividerId: UUID)
}

@MainActor
final class PaneTabActionDispatcher: PaneTabActionDispatching {
    private let dispatchImpl: (PaneActionCommand) -> Void
    private let shouldAcceptDropImpl: (SplitDropPayload, UUID, DropZone) -> Bool
    private let handleDropImpl: (SplitDropPayload, UUID, DropZone) -> Void
    private let finishSplitResizeImpl: (UUID, UUID) -> Void

    init(
        dispatch: @escaping (PaneActionCommand) -> Void,
        shouldAcceptDrop: @escaping (SplitDropPayload, UUID, DropZone) -> Bool,
        handleDrop: @escaping (SplitDropPayload, UUID, DropZone) -> Void,
        finishSplitResize: @escaping (UUID, UUID) -> Void
    ) {
        self.dispatchImpl = dispatch
        self.shouldAcceptDropImpl = shouldAcceptDrop
        self.handleDropImpl = handleDrop
        self.finishSplitResizeImpl = finishSplitResize
    }

    func dispatch(_ action: PaneActionCommand) {
        dispatchImpl(action)
    }

    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    ) -> Bool {
        shouldAcceptDropImpl(payload, destinationPaneId, zone)
    }

    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZone
    ) {
        handleDropImpl(payload, destinationPaneId, zone)
    }

    func finishSplitResize(tabId: UUID, dividerId: UUID) {
        finishSplitResizeImpl(tabId, dividerId)
    }
}
```

Then propagate the dispatcher through the full visible tree:

`Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`

```swift
CollapsedPaneBar(..., actionDispatcher: actionDispatcher, ...)
FlatPaneStripContent(..., actionDispatcher: actionDispatcher, ...)
DrawerPanelOverlay(..., actionDispatcher: actionDispatcher)
SplitContainerDropCaptureOverlay(..., actionDispatcher: actionDispatcher)
```

`Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`

```swift
CollapsedPaneBar(..., actionDispatcher: actionDispatcher, ...)
PaneLeafContainer(..., actionDispatcher: actionDispatcher, ...)
FlatPaneDivider(..., actionDispatcher: actionDispatcher)
```

`Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`

```swift
actionDispatcher.dispatch(.minimizePane(tabId: tabId, paneId: paneHost.id))
actionDispatcher.dispatch(.closePane(tabId: tabId, paneId: paneHost.id))
```

`Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`

```swift
actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
```

`Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift`

```swift
actionDispatcher.shouldAcceptDrop(payload, destinationPaneId: paneId, zone: zone)
actionDispatcher.handleDrop(payload, destinationPaneId: paneId, zone: zone)
```

`Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`

```swift
actionDispatcher.dispatch(.toggleDrawer(paneId: info.paneId))
```

Update `FlatPaneDivider` in `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift` to remove the `onPersist` closure:

```swift
actionDispatcher.finishSplitResize(tabId: tabId, dividerId: dividerId)
```

and update `PaneTabViewController` to construct the dispatcher once in `init`:

```swift
        self.actionDispatcher = PaneTabActionDispatcher(
            dispatch: { [weak self] action in self?.dispatchAction(action) },
            shouldAcceptDrop: { [weak self] payload, destPaneId, zone in
                self?.evaluateDropAcceptance(payload: payload, destPaneId: destPaneId, zone: zone) ?? false
            },
            handleDrop: { [weak self] payload, destPaneId, zone in
                self?.handleSplitDrop(payload: payload, destPaneId: destPaneId, zone: zone)
            },
            finishSplitResize: { [weak self] tabId, dividerId in
                self?.persistAfterSplitResize(tabId: tabId, dividerId: dividerId)
            }
        )
```

and add the concrete helper in `PaneTabViewController`:

```swift
    private func persistAfterSplitResize(tabId: UUID, dividerId: UUID) {
        _ = dividerId
        guard store.tab(tabId) != nil else { return }
        store.persistNow()
    }
```

- [ ] **Step 4: Run the retention suite again**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerTabRetentionTests"
```

Expected: PASS. Both cross-tab and within-tab no-dismantle tests should pass.

- [ ] **Step 5: Commit the dispatcher propagation**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabActionDispatcher.swift Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift
git commit -m "refactor: remove closure churn from visible tab subtree"
```

### Task 4: Update Controller Semantics Around Focus, Geometry, And Restore

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`

- [ ] **Step 1: Write the failing launch/visibility test for inactive-host persistence**

Add to `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`:

```swift
    @Test
    func activeTabChanges_doNotReplaceInactiveTabHosts() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }

        let firstPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "One"),
            provider: .zmx
        )
        let secondPane = harness.store.createPane(
            source: .floating(workingDirectory: harness.tempDir, title: "Two"),
            provider: .zmx
        )
        let firstTab = Tab(paneId: firstPane.id, name: "One")
        let secondTab = Tab(paneId: secondPane.id, name: "Two")
        harness.store.appendTab(firstTab)
        harness.store.appendTab(secondTab)
        harness.store.setActiveTab(firstTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let firstHost = try #require(harness.controller.tabHostViewForTesting(tabId: firstTab.id))

        harness.store.setActiveTab(secondTab.id)
        harness.controller.view.layoutSubtreeIfNeeded()

        let firstHostAfterSwitch = try #require(harness.controller.tabHostViewForTesting(tabId: firstTab.id))
        #expect(firstHostAfterSwitch === firstHost)
        #expect(firstHostAfterSwitch.isHidden)
        #expect(harness.controller.paneRepresentableDismantleCountForTesting == 0)
    }
```

- [ ] **Step 2: Run the focused launch-restore test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests/activeTabChanges_doNotReplaceInactiveTabHosts"
```

Expected: FAIL until `PaneTabViewController` exposes the host accessors and keeps inactive hosts attached without dismantling.

- [ ] **Step 3: Update focus and geometry paths to target only the active host**

Adjust `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`:

```swift
    private func handleAppKitStateChange() {
        syncTabContentHosts()
        updateVisibleTabHost()
        updateEmptyState()
        ...
    }

    func syncVisibleTerminalGeometry(reason: StaticString) {
        guard let activeTabId = store.activeTabId else { return }
        let visiblePaneIds = store.tab(activeTabId)?.paneIds ?? []
        let visibleTerminalViews = visiblePaneIds.compactMap { viewRegistry.terminalView(for: $0) }
            .filter { $0.window != nil && !$0.isHidden }
        guard !visibleTerminalViews.isEmpty else { return }
        for terminalView in visibleTerminalViews {
            terminalView.forceGeometrySync(reason: reason)
        }
    }
```

Keep `updateEmptyState()` tab-level only:

```swift
    private func updateEmptyState() {
        let hasTabs = !store.tabs.isEmpty
        tabBarHostingView.isHidden = !hasTabs
        terminalContainer.isHidden = !hasTabs
        emptyStateView?.isHidden = hasTabs
    }
```

- [ ] **Step 4: Run the focused launch and retention tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests"
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerTabRetentionTests"
```

Expected: PASS. Startup remains healthy and the new tab-retention behavior is stable.

- [ ] **Step 5: Commit the controller semantics update**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift
git commit -m "fix: keep inactive tab hosts attached and stable"
```

### Task 5: Lock The Architecture Boundary And Document The Why

**Files:**
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md`
- Test: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Update the architecture test to ban the single-host and closure-heavy active-tab model**

Add these expectations to `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`:

```swift
        let singleTabContentPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift"
        )
        #expect(paneTabViewControllerSource.contains("tabContentHosts"))
        #expect(paneTabViewControllerSource.contains("PaneTabActionDispatcher"))
        #expect(paneTabViewControllerSource.contains("updateVisibleTabHost"))
        #expect(paneTabViewControllerSource.contains("syncTabContentHosts"))
        #expect(!paneTabViewControllerSource.contains("private var splitHostingView: NSHostingView<ActiveTabContent>?"))
        #expect(!activeTabContentSource.contains("let activeTabId = store.activeTabId"))
        let singleTabContentSource = try String(contentsOf: singleTabContentPath, encoding: .utf8)
        #expect(!flatTabStripContainerSource.contains("let action: (PaneActionCommand) -> Void"))
        #expect(!flatPaneStripContentSource.contains("let action: (PaneActionCommand) -> Void"))
        #expect(!paneLeafContainerSource.contains("let action: (PaneActionCommand) -> Void"))
        #expect(singleTabContentSource.contains("let actionDispatcher: PaneTabActionDispatching"))
```

- [ ] **Step 2: Run the architecture test to verify it fails before alignment**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CoordinationPlaneArchitectureTests"
```

Expected: FAIL until the source and architecture assertions match the new design.

- [ ] **Step 3: Document the chosen architecture and the old failure mode**

Append this section to `docs/architecture/appkit_swiftui_architecture.md`:

```markdown
### Per-Tab Persistent Hosting

The main pane area keeps one persistent AppKit content host per tab.

- `PaneTabViewController` owns the tab-host lifecycle
- each tab host contains one `NSHostingView<SingleTabContent>`
- inactive tabs are hidden at the AppKit level, not removed from the SwiftUI tree
- pane actions, split persistence, and drop routing flow through a stable dispatcher reference instead of fresh closures

This replaces the older single-host `ActiveTabContent` pattern, which rendered only the active tab and caused `NSViewRepresentable` teardown on tab switch and on some within-tab state changes.
```

Append this section to `docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md`:

```markdown
## Debugging Epoch (2026-03-29): Tab Switch Churn Is The Single-Host Active-Tab Architecture

Startup relaunch and new-pane insertion can be clean while tab switch still churns.

The remaining issue is architectural:

```text
one NSHostingView<ActiveTabContent>
  -> one active tab subtree at a time
  -> tab switch removes leaving-tab pane representables
  -> closure-heavy parent views can also churn within the visible tab
```

The chosen fix is per-tab persistent AppKit hosting plus stable dispatcher references:

```text
PaneTabViewController
  -> one persistent host per tab
  -> show/hide on selection change
  -> no tab-switch detach for still-existing tabs
  -> no within-tab representable teardown from closure churn
```
```

- [ ] **Step 4: Run the architecture test again**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CoordinationPlaneArchitectureTests"
```

Expected: PASS. The architecture test should reflect the new boundary and reject a return to the single-host active-tab design.

- [ ] **Step 5: Commit the architecture/docs checkpoint**

```bash
git add Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift docs/architecture/appkit_swiftui_architecture.md docs/debugging/2026-03-29-terminal-startup-ratio-drift-and-redraw.md
git commit -m "docs: adopt persistent tab hosting and stable dispatch"
```

### Task 6: Full Verification And Runtime Confirmation

**Files:**
- Modify: none
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
- Test: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Run the full project test suite**

Run:

```bash
AGENT_RUN_ID=persistent-tab-hosting mise run test
```

Expected: PASS, exit code `0`.

- [ ] **Step 2: Run lint**

Run:

```bash
mise run lint
```

Expected: PASS, exit code `0`.

- [ ] **Step 3: Build and launch the standard debug app**

Run:

```bash
SWIFT_BUILD_DIR=.build AGENT_RUN_ID=persistent-tab-hosting mise run build
pkill -9 -f "/AgentStudio"
truncate -s 0 /tmp/agentstudio_debug.log
./.build/debug/AgentStudio
```

Expected: app launches normally with restored tabs.

- [ ] **Step 4: Verify tab switching and within-tab updates no longer churn**

Run after switching tabs and mutating visible-tab state:

```bash
rg -n "PaneViewRepresentable\\.dismantleNSView|reparent=true|window=false" /tmp/agentstudio_debug.log
```

Expected:

```text
startup may include initial unattached creation logs before first mount
tab switch should not emit leaving-tab window=false or reparent=true for still-existing tabs
ordinary within-tab state changes should not emit PaneViewRepresentable.dismantleNSView
```

- [ ] **Step 5: Commit the verification checkpoint**

```bash
git add -A
git commit -m "test: verify tabs stay alive without subtree teardown"
```

## Self-Review

### Spec coverage

- Why the current single-host architecture fails: covered in the design doc and Tasks 2-5.
- Why per-tab hosts alone are insufficient: covered in Task 3 and the updated design.
- What files must stop taking closures: explicitly covered in File Structure and Task 3.
- Requirement that all tabs remain alive in memory: covered by per-tab persistent hosts and no-dismantle tests.

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain.
- Every code-changing step includes concrete code snippets.
- Every verification step includes exact commands and expected outcomes.

### Type consistency

- `PersistentTabHostView`, `PaneTabActionDispatcher`, and `SingleTabContent` are used consistently throughout.
- `PaneTabActionDispatching` is the stable reference protocol at every layer.
- Test accessor names are consistent: `tabHostViewForTesting(tabId:)` and `paneRepresentableDismantleCountForTesting`.

Plan complete and saved to `docs/superpowers/plans/2026-03-29-persistent-tab-hosting-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
