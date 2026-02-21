 import Observation
import Testing
import Foundation

@testable import AgentStudio

/// Thread-safe flag for use in @Sendable `withObservationTracking` onChange closures.
private final class ObservationFlag: @unchecked Sendable {
    var fired = false
    var count = 0
}

/// Tests for @Observable migration patterns.
///
/// These tests verify that WorkspaceStore's @Observable macro correctly
/// triggers `withObservationTracking` callbacks when properties mutate.
/// This is the core contract the migration depends on — ActiveTabContent,
/// TabBarAdapter, and PaneTabViewController's observeForAppKitState() all rely on this.
@MainActor
@Suite(.serialized)
final class ObservableStoreTests {

    private var store: WorkspaceStore!

        init() {
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory
                .appending(path: "obs-tests-\(UUID().uuidString)")
        )
        store = WorkspaceStore(persistor: persistor)
        store.restore()
    }

    deinit {
        store = nil
    }

    // MARK: - withObservationTracking Fires on Store Mutations

    @Test

    func test_observationTracking_firesOnTabsChange() {
        // Arrange
        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.tabs
        } onChange: {
            flag.fired = true
        }

        // Act
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))

        // Assert — onChange fires synchronously during willSet
        #expect(flag.fired)
    }

    @Test

    func test_observationTracking_firesOnActiveTabIdChange() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.activeTabId
        } onChange: {
            flag.fired = true
        }

        // Act
        store.setActiveTab(tab1.id)

        // Assert
        #expect(flag.fired)
    }

    @Test

    func test_observationTracking_firesOnPanesMutation() {
        // Arrange
        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.panes
        } onChange: {
            flag.fired = true
        }

        // Act
        _ = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        // Assert
        #expect(flag.fired)
    }

    // MARK: - Drawer Mutation Observability (The Original Bug)

    /// This test verifies the exact scenario that motivated the migration.
    /// Previously, drawer state changes on Pane (a struct in the panes dictionary)
    /// did NOT propagate through ObservableObject because panes was @Published
    /// as a dictionary — struct-in-dictionary mutations don't trigger objectWillChange.
    /// With @Observable, mutating panes[id]?.drawer fires observation correctly.
    @Test
    func test_observationTracking_firesOnDrawerMutation() {
        // Arrange — create a pane with a drawer
        let parentPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(to: parentPane.id)
        #expect(store.pane(parentPane.id)!.drawer!.isExpanded)

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.panes
        } onChange: {
            flag.fired = true
        }

        // Act — toggle drawer (struct-in-dictionary mutation)
        store.toggleDrawer(for: parentPane.id)

        // Assert — this FAILED with ObservableObject, PASSES with @Observable
        #expect(flag.fired)
        #expect(!(store.pane(parentPane.id)!.drawer!.isExpanded))
    }

    @Test

    func test_observationTracking_firesOnDrawerPaneAdded() {
        // Arrange
        let parentPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.panes
        } onChange: {
            flag.fired = true
        }

        // Act — add drawer pane (mutates panes dict entry)
        _ = store.addDrawerPane(to: parentPane.id)

        // Assert
        #expect(flag.fired)
    }

    // MARK: - Observation Re-registration Pattern

    /// Verifies that re-registering withObservationTracking after onChange
    /// correctly detects subsequent mutations. This is the pattern used by
    /// TabBarAdapter.observeStore() and PaneTabViewController.observeForAppKitState().
    @Test
    func test_observationTracking_reregistration_detectsSubsequentChanges() {
        // Arrange — track only repos (single property, one fire per mutation)
        let flag = ObservationFlag()

        @Sendable nonisolated func register(store: WorkspaceStore, flag: ObservationFlag) {
            withObservationTracking {
                _ = MainActor.assumeIsolated { store.repos }
            } onChange: {
                flag.count += 1
                register(store: store, flag: flag)
            }
        }
        register(store: store, flag: flag)

        // Act — first mutation
        _ = store.addRepo(at: URL(fileURLWithPath: "/tmp/re-reg-test-1"))

        // Assert — fires at least once (may fire multiple times due to internal mutations)
        let countAfterFirst = flag.count
        #expect(countAfterFirst > 0, "First mutation must trigger observation")

        // Act — second mutation (after re-registration)
        _ = store.addRepo(at: URL(fileURLWithPath: "/tmp/re-reg-test-2"))

        // Assert — re-registration worked: count increased beyond first mutation
        #expect(flag.count > countAfterFirst, "Re-registration must detect subsequent mutations")
    }

    // MARK: - Observation Doesn't Fire for Untracked Properties

    @Test

    func test_observationTracking_doesNotFireForUntrackedProperties() {
        // Arrange — only track activeTabId
        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.activeTabId
        } onChange: {
            flag.fired = true
        }

        // Act — mutate repos (not tracked)
        _ = store.addRepo(at: URL(fileURLWithPath: "/tmp/untracked-repo"))

        // Assert — should NOT fire
        #expect(!(flag.fired))
    }

    // MARK: - TabBarAdapter Bridge Verification

    /// Verifies TabBarAdapter's withObservationTracking bridge automatically
    /// refreshes when the store changes, without manual objectWillChange.send().
    @Test
    func test_tabBarAdapter_bridgeAutoRefreshes_onStoreTabChange() async throws {
        // Arrange
        let adapter = TabBarAdapter(store: store)
        #expect(adapter.tabs.isEmpty)

        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "AutoRefresh"),
            title: "AutoRefresh"
        )
        let tab = Tab(paneId: pane.id)

        // Act — mutate store directly (no manual objectWillChange.send())
        store.appendTab(tab)

        // Wait for async bridge (Task { @MainActor } fires on next runloop)
        await awaitTaskBoundary()

        // Assert — adapter derived state updated
        #expect(adapter.tabs.count == 1, "TabBarAdapter must auto-refresh via observation bridge")
        let firstTab = try #require(adapter.tabs.first, "Expected derived tab to exist")
        #expect(firstTab.title == "AutoRefresh")
        #expect(adapter.activeTabId == tab.id)
    }

    @Test

    func test_tabBarAdapter_bridgeAutoRefreshes_onDrawerChange() async {
        // Arrange
        let adapter = TabBarAdapter(store: store)
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "WithDrawer"),
            title: "WithDrawer"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Wait for initial sync
        await awaitTaskBoundary()
        #expect(adapter.tabs.count == 1)

        // Act — add drawer (struct-in-dictionary mutation)
        _ = store.addDrawerPane(to: pane.id)

        // Wait for bridge
        await awaitTaskBoundary()

        // Assert — panes mutation triggered re-derive
        #expect(adapter.tabs.count == 1, "Adapter should still have 1 tab after drawer change")
    }

    // MARK: - ActiveTabContent Data Derivation

    /// Tests the exact data path ActiveTabContent.body uses:
    /// store.activeTabId → store.tab(id) → tab properties.

    @Test
    func test_activeTabContent_dataPath_resolvesCorrectly() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: "Pane1"))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: "Pane2"))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Act — follow ActiveTabContent's body path
        let activeTabId = store.activeTabId
        let tab = activeTabId.flatMap { store.tab($0) }

        // Assert
        #expect(activeTabId == tab1.id)
        #expect((tab) != nil)
        #expect(tab?.activePaneId == p1.id)
        #expect((tab?.zoomedPaneId) == nil)
        #expect(tab?.minimizedPaneIds.isEmpty ?? false)
    }

    @Test

    func test_activeTabContent_dataPath_nilWhenNoTabs() {
        // Act — follow ActiveTabContent's body path with empty store
        let activeTabId = store.activeTabId
        let tab = activeTabId.flatMap { store.tab($0) }

        // Assert — ActiveTabContent renders nothing (empty state handled by AppKit)
        #expect((activeTabId) == nil)
        #expect((tab) == nil)
    }

    @Test

    func test_activeTabContent_dataPath_updatesOnTabSwitch() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: p1.id)
        let tab2 = Tab(paneId: p2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Act — switch tabs
        store.setActiveTab(tab2.id)

        // Assert — same path ActiveTabContent uses
        let resolvedTab = store.activeTabId.flatMap { store.tab($0) }
        #expect(resolvedTab?.id == tab2.id)
        #expect(resolvedTab?.activePaneId == p2.id)
    }

    // MARK: - Observation Granularity: Pane Property Changes

    @Test

    func test_observationTracking_firesOnPaneTitleUpdate() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "Original"),
            title: "Original"
        )

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.panes
        } onChange: {
            flag.fired = true
        }

        // Act
        store.updatePaneTitle(pane.id, title: "Updated")

        // Assert
        #expect(flag.fired)
        #expect(store.pane(pane.id)?.title == "Updated")
    }

    @Test

    func test_observationTracking_firesOnActivePaneChange() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id], activePaneId: p1.id)
        store.appendTab(tab)

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.tabs
        } onChange: {
            flag.fired = true
        }

        // Act — change active pane within a tab
        store.setActivePane(p2.id, inTab: tab.id)

        // Assert
        #expect(flag.fired)
    }

    @Test

    func test_observationTracking_firesOnZoomToggle() {
        // Arrange
        let p1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let p2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = makeTab(paneIds: [p1.id, p2.id])
        store.appendTab(tab)

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.tabs
        } onChange: {
            flag.fired = true
        }

        // Act
        store.toggleZoom(paneId: p1.id, inTab: tab.id)

        // Assert
        #expect(flag.fired)
        #expect(store.tab(tab.id)?.zoomedPaneId == p1.id)
    }

    func awaitTaskBoundary() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
        await Task.yield()
    }
}
