import XCTest

@testable import AgentStudio

@MainActor
final class TabBarAdapterTests: XCTestCase {

    private var store: WorkspaceStore!
    private var adapter: TabBarAdapter!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "adapter-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        store = WorkspaceStore(persistor: persistor)
        store.restore()
        adapter = TabBarAdapter(store: store)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        adapter = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState_empty() {
        // Assert
        XCTAssertTrue(adapter.tabs.isEmpty)
        XCTAssertNil(adapter.activeTabId)
    }

    // MARK: - Derivation from Store

    func test_singleTab_derivesTabBarItem() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "MyTerminal"),
            title: "MyTerminal"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Act — trigger refresh
        adapter.objectWillChange.send()
        // The adapter observes store changes; we need to wait for the async task
        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs.count, 1)
        XCTAssertEqual(adapter.tabs[0].id, tab.id)
        XCTAssertEqual(adapter.tabs[0].title, "MyTerminal")
        XCTAssertEqual(adapter.tabs[0].displayTitle, "MyTerminal")
        XCTAssertFalse(adapter.tabs[0].isSplit)
        XCTAssertEqual(adapter.activeTabId, tab.id)
    }

    func test_splitTab_showsJoinedTitle() {
        // Arrange
        let s1 = store.createPane(
            source: .floating(workingDirectory: nil, title: "Left"),
            title: "Left"
        )
        let s2 = store.createPane(
            source: .floating(workingDirectory: nil, title: "Right"),
            title: "Right"
        )
        let tab = makeTab(paneIds: [s1.id, s2.id], activePaneId: s1.id)
        store.appendTab(tab)

        // Wait for async refresh
        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs.count, 1)
        XCTAssertTrue(adapter.tabs[0].isSplit)
        XCTAssertEqual(adapter.tabs[0].displayTitle, "Left | Right")
        XCTAssertEqual(adapter.tabs[0].title, "Left")
    }

    func test_multipleTabs_derivesAll() {
        // Arrange
        let s1 = store.createPane(
            source: .floating(workingDirectory: nil, title: "Tab1"),
            title: "Tab1"
        )
        let s2 = store.createPane(
            source: .floating(workingDirectory: nil, title: "Tab2"),
            title: "Tab2"
        )
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Wait for async refresh
        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs.count, 2)
        XCTAssertEqual(adapter.tabs[0].id, tab1.id)
        XCTAssertEqual(adapter.tabs[1].id, tab2.id)
    }

    func test_activeTabId_tracksStore() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Wait for async refresh
        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.activeTabId, tab1.id)
    }

    func test_tabRemoved_adapterUpdates() {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Wait for initial sync
        let expectation1 = XCTestExpectation(description: "Initial refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)
        XCTAssertEqual(adapter.tabs.count, 2)

        // Act
        store.removeTab(tab1.id)

        // Wait for update
        let expectation2 = XCTestExpectation(description: "Post-remove refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs.count, 1)
        XCTAssertEqual(adapter.tabs[0].id, tab2.id)
    }

    func test_paneWithNoTitle_defaultsToTerminal() {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Wait for refresh
        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs[0].displayTitle, "Terminal")
    }

    // MARK: - Transient State

    func test_transientState_draggingTabId() {
        // Act
        adapter.draggingTabId = UUID()

        // Assert
        XCTAssertNotNil(adapter.draggingTabId)
    }

    func test_transientState_dropTargetIndex() {
        // Act
        adapter.dropTargetIndex = 2

        // Assert
        XCTAssertEqual(adapter.dropTargetIndex, 2)
    }

    func test_transientState_tabFrames() {
        // Arrange
        let tabId = UUID()
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)

        // Act
        adapter.tabFrames[tabId] = frame

        // Assert
        XCTAssertEqual(adapter.tabFrames[tabId], frame)
    }

    // MARK: - Overflow Detection

    func test_noTabs_notOverflowing() {
        // Arrange
        adapter.availableWidth = 600

        // Assert
        XCTAssertFalse(adapter.isOverflowing)
    }

    func test_fewTabs_withinSpace_notOverflowing() {
        // Arrange — 2 tabs: 2×220 + 1×4 + 16 = 460px < 600px
        for _ in 0..<2 {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.appendTab(Tab(paneId: pane.id))
        }

        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // Act
        adapter.availableWidth = 600

        let expectation2 = XCTestExpectation(description: "Overflow updates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs.count, 2)
        XCTAssertFalse(adapter.isOverflowing)
    }

    func test_manyTabs_exceedingSpace_overflowing() {
        // Arrange — 8 tabs: 8×220 + 7×4 + 16 = 1804px > 600px
        for _ in 0..<8 {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.appendTab(Tab(paneId: pane.id))
        }

        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // Act
        adapter.availableWidth = 600

        let expectation2 = XCTestExpectation(description: "Overflow updates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs.count, 8)
        XCTAssertTrue(adapter.isOverflowing)
    }

    func test_zeroAvailableWidth_notOverflowing() {
        // Arrange — layout not ready (width = 0)
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))

        let expectation = XCTestExpectation(description: "Adapter refreshes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // Assert — availableWidth defaults to 0
        XCTAssertFalse(adapter.isOverflowing)
    }

    func test_viewportWidth_prefersOverAvailableWidth() {
        // Arrange — 1 tab, set both availableWidth and viewportWidth
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 800  // outer container
        adapter.viewportWidth = 600  // actual scroll viewport (smaller)
        adapter.contentWidth = 700  // content exceeds viewport but not available

        let e1 = XCTestExpectation(description: "Viewport overflow")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)

        // Assert — should overflow based on viewport (700 > 600), not available (700 < 800)
        XCTAssertTrue(adapter.isOverflowing)
    }

    func test_contentWidthOverflow_triggersWhenContentExceedsAvailable() {
        // Arrange — 1 tab so tabs.count > 0
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 600

        let e1 = XCTestExpectation(description: "Initial")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)
        XCTAssertFalse(adapter.isOverflowing)

        // Act — set content width wider than available
        adapter.contentWidth = 700

        let e2 = XCTestExpectation(description: "Content width update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e2.fulfill() }
        wait(for: [e2], timeout: 1.0)

        // Assert
        XCTAssertTrue(adapter.isOverflowing)
    }

    func test_contentWidthOverflow_hysteresisPreventsOscillation() {
        // Arrange — trigger overflow via content width
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 600
        adapter.contentWidth = 700

        let e1 = XCTestExpectation(description: "Initial overflow")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)
        XCTAssertTrue(adapter.isOverflowing)

        // Act — reduce content width slightly (simulates "+" button removed)
        // Still within hysteresis buffer (600 - 50 = 550, and 570 > 550)
        adapter.contentWidth = 570

        let e2 = XCTestExpectation(description: "Still overflowing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e2.fulfill() }
        wait(for: [e2], timeout: 1.0)

        // Assert — should remain overflowing due to hysteresis
        XCTAssertTrue(adapter.isOverflowing)
    }

    func test_contentWidthOverflow_turnsOffWhenWellUnderThreshold() {
        // Arrange — trigger overflow via content width
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 600
        adapter.contentWidth = 700

        let e1 = XCTestExpectation(description: "Initial overflow")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)
        XCTAssertTrue(adapter.isOverflowing)

        // Act — reduce well below hysteresis threshold (600 - 50 = 550)
        adapter.contentWidth = 500

        let e2 = XCTestExpectation(description: "No longer overflowing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e2.fulfill() }
        wait(for: [e2], timeout: 1.0)

        // Assert
        XCTAssertFalse(adapter.isOverflowing)
    }

    func test_overflowUpdates_whenTabsAddedOrRemoved() {
        // Arrange — start with 4 tabs in 600px: 4×220 + 3×4 + 16 = 908px > 600px → overflow
        var panes: [Pane] = []
        for _ in 0..<4 {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.appendTab(Tab(paneId: pane.id))
            panes.append(pane)
        }
        adapter.availableWidth = 600

        let e1 = XCTestExpectation(description: "Initial")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)
        XCTAssertTrue(adapter.isOverflowing)

        // Act — remove tabs until not overflowing: 2 tabs: 2×220 + 1×4 + 16 = 460px < 600px
        let tabsToRemove = store.tabs.prefix(2)
        for tab in tabsToRemove {
            store.removeTab(tab.id)
        }

        let e2 = XCTestExpectation(description: "After removal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { e2.fulfill() }
        wait(for: [e2], timeout: 1.0)

        // Assert
        XCTAssertEqual(adapter.tabs.count, 2)
        XCTAssertFalse(adapter.isOverflowing)
    }
}
