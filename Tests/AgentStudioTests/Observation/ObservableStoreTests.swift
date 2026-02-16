import XCTest
import Observation
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
/// TabBarAdapter, and TTVC's observeForAppKitState() all rely on this.
@MainActor
final class ObservableStoreTests: XCTestCase {

    private var store: WorkspaceStore!

    override func setUp() {
        super.setUp()
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory
                .appending(path: "obs-tests-\(UUID().uuidString)")
        )
        store = WorkspaceStore(persistor: persistor)
        store.restore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - withObservationTracking Fires on Store Mutations

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
        XCTAssertTrue(flag.fired, "withObservationTracking must fire when store.tabs mutates")
    }

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
        XCTAssertTrue(flag.fired, "withObservationTracking must fire when activeTabId changes")
    }

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
        XCTAssertTrue(flag.fired, "withObservationTracking must fire when panes dictionary mutates")
    }

    // MARK: - Drawer Mutation Observability (The Original Bug)

    /// This test verifies the exact scenario that motivated the migration.
    /// Previously, drawer state changes on Pane (a struct in the panes dictionary)
    /// did NOT propagate through ObservableObject because panes was @Published
    /// as a dictionary — struct-in-dictionary mutations don't trigger objectWillChange.
    /// With @Observable, mutating panes[id]?.drawer fires observation correctly.
    func test_observationTracking_firesOnDrawerMutation() {
        // Arrange — create a pane with a drawer
        let parentPane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        _ = store.addDrawerPane(
            to: parentPane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Drawer")
        )
        XCTAssertTrue(store.pane(parentPane.id)!.drawer!.isExpanded, "Precondition: drawer starts expanded")

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.panes
        } onChange: {
            flag.fired = true
        }

        // Act — toggle drawer (struct-in-dictionary mutation)
        store.toggleDrawer(for: parentPane.id)

        // Assert — this FAILED with ObservableObject, PASSES with @Observable
        XCTAssertTrue(flag.fired, "Drawer toggle must trigger observation (was broken before migration)")
        XCTAssertFalse(store.pane(parentPane.id)!.drawer!.isExpanded)
    }

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
        _ = store.addDrawerPane(
            to: parentPane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "D")
        )

        // Assert
        XCTAssertTrue(flag.fired, "Adding drawer pane must trigger observation")
    }

    // MARK: - Observation Re-registration Pattern

    /// Verifies that re-registering withObservationTracking after onChange
    /// correctly detects subsequent mutations. This is the pattern used by
    /// TabBarAdapter.observeStore() and TTVC.observeForAppKitState().
    func test_observationTracking_reregistration_detectsSubsequentChanges() {
        // Arrange — track only repos (single property, one fire per mutation)
        let flag = ObservationFlag()

        nonisolated func register(store: WorkspaceStore, flag: ObservationFlag) {
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
        XCTAssertGreaterThan(countAfterFirst, 0, "First mutation must trigger observation")

        // Act — second mutation (after re-registration)
        _ = store.addRepo(at: URL(fileURLWithPath: "/tmp/re-reg-test-2"))

        // Assert — re-registration worked: count increased beyond first mutation
        XCTAssertGreaterThan(flag.count, countAfterFirst, "Re-registration must detect subsequent mutations")
    }

    // MARK: - Observation Doesn't Fire for Untracked Properties

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
        XCTAssertFalse(flag.fired, "Observation should not fire for untracked property mutations")
    }

    // MARK: - TabBarAdapter Bridge Verification

    /// Verifies TabBarAdapter's withObservationTracking bridge automatically
    /// refreshes when the store changes, without manual objectWillChange.send().
    func test_tabBarAdapter_bridgeAutoRefreshes_onStoreTabChange() {
        // Arrange
        let adapter = TabBarAdapter(store: store)
        XCTAssertTrue(adapter.tabs.isEmpty)

        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "AutoRefresh"),
            title: "AutoRefresh"
        )
        let tab = Tab(paneId: pane.id)

        // Act — mutate store directly (no manual objectWillChange.send())
        store.appendTab(tab)

        // Wait for async bridge (Task { @MainActor } fires next runloop)
        let expectation = XCTestExpectation(description: "Adapter auto-refreshes from bridge")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert — adapter derived state updated
        XCTAssertEqual(adapter.tabs.count, 1, "TabBarAdapter must auto-refresh via observation bridge")
        XCTAssertEqual(adapter.tabs[0].title, "AutoRefresh")
        XCTAssertEqual(adapter.activeTabId, tab.id)
    }

    func test_tabBarAdapter_bridgeAutoRefreshes_onDrawerChange() {
        // Arrange
        let adapter = TabBarAdapter(store: store)
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "WithDrawer"),
            title: "WithDrawer"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Wait for initial sync
        let e1 = XCTestExpectation(description: "Initial sync")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)
        XCTAssertEqual(adapter.tabs.count, 1)

        // Act — add drawer (struct-in-dictionary mutation)
        _ = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Drawer")
        )

        // Wait for bridge
        let e2 = XCTestExpectation(description: "Drawer change triggers bridge")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { e2.fulfill() }
        wait(for: [e2], timeout: 1.0)

        // Assert — panes mutation triggered re-derive
        XCTAssertEqual(adapter.tabs.count, 1, "Adapter should still have 1 tab after drawer change")
    }

    // MARK: - ActiveTabContent Data Derivation

    /// Tests the exact data path ActiveTabContent.body uses:
    /// store.activeTabId → store.tab(id) → tab properties.
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
        XCTAssertEqual(activeTabId, tab1.id)
        XCTAssertNotNil(tab)
        XCTAssertEqual(tab?.activePaneId, p1.id)
        XCTAssertNil(tab?.zoomedPaneId)
        XCTAssertTrue(tab?.minimizedPaneIds.isEmpty ?? false)
    }

    func test_activeTabContent_dataPath_nilWhenNoTabs() {
        // Act — follow ActiveTabContent's body path with empty store
        let activeTabId = store.activeTabId
        let tab = activeTabId.flatMap { store.tab($0) }

        // Assert — ActiveTabContent renders nothing (empty state handled by AppKit)
        XCTAssertNil(activeTabId)
        XCTAssertNil(tab)
    }

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
        XCTAssertEqual(resolvedTab?.id, tab2.id)
        XCTAssertEqual(resolvedTab?.activePaneId, p2.id)
    }

    // MARK: - Observation Granularity: Pane Property Changes

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
        XCTAssertTrue(flag.fired, "Pane title update must trigger observation")
        XCTAssertEqual(store.pane(pane.id)?.title, "Updated")
    }

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
        XCTAssertTrue(flag.fired, "Active pane change must trigger observation on tabs")
    }

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
        XCTAssertTrue(flag.fired, "Zoom toggle must trigger observation on tabs")
        XCTAssertEqual(store.tab(tab.id)?.zoomedPaneId, p1.id)
    }
}
