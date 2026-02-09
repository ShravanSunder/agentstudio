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
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: "MyTerminal"),
            title: "MyTerminal"
        )
        let tab = Tab(sessionId: session.id)
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
        let s1 = store.createSession(
            source: .floating(workingDirectory: nil, title: "Left"),
            title: "Left"
        )
        let s2 = store.createSession(
            source: .floating(workingDirectory: nil, title: "Right"),
            title: "Right"
        )
        let layout = Layout(sessionId: s1.id)
            .inserting(sessionId: s2.id, at: s1.id, direction: .horizontal, position: .after)
        let tab = Tab(layout: layout, activeSessionId: s1.id)
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
        let s1 = store.createSession(
            source: .floating(workingDirectory: nil, title: "Tab1"),
            title: "Tab1"
        )
        let s2 = store.createSession(
            source: .floating(workingDirectory: nil, title: "Tab2"),
            title: "Tab2"
        )
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
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
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
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
        let s1 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createSession(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(sessionId: s1.id)
        let tab2 = Tab(sessionId: s2.id)
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

    func test_sessionWithNoTitle_defaultsToTerminal() {
        // Arrange
        let session = store.createSession(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(sessionId: session.id)
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
}
