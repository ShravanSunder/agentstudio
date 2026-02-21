import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class TabBarAdapterTests {

    private var store: WorkspaceStore!
    private var adapter: TabBarAdapter!
    private var tempDir: URL!

        init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "adapter-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        store = WorkspaceStore(persistor: persistor)
        store.restore()
        adapter = TabBarAdapter(store: store)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
        adapter = nil
        store = nil
    }

    // MARK: - Initial State

    @Test

    func test_initialState_empty() {
        // Assert
        #expect(adapter.tabs.isEmpty)
        #expect((adapter.activeTabId) == nil)
    }

    // MARK: - Derivation from Store

    @Test

    func test_singleTab_derivesTabBarItem() async {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: "MyTerminal"),
            title: "MyTerminal"
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Act — wait for the async observation pipeline to process
        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.tabs.count == 1)
        if let derivedTab = adapter.tabs.first {
            #expect(derivedTab.id == tab.id)
            #expect(derivedTab.title == "MyTerminal")
            #expect(derivedTab.displayTitle == "MyTerminal")
            #expect(!(derivedTab.isSplit))
        } else {
            #expect(Bool(false), "Expected derived tab to exist")
        }
        #expect(adapter.activeTabId == tab.id)
    }

    @Test

    func test_splitTab_showsJoinedTitle() async {
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
        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.tabs.count == 1)
        if let derivedTab = adapter.tabs.first {
            #expect(derivedTab.isSplit)
            #expect(derivedTab.displayTitle == "Left | Right")
            #expect(derivedTab.title == "Left")
        } else {
            #expect(Bool(false), "Expected derived tab to exist")
        }
    }

    @Test

    func test_multipleTabs_derivesAll() async {
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
        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.tabs.count == 2)
        if let firstTab = adapter.tabs[safe: 0], let secondTab = adapter.tabs[safe: 1] {
            #expect(firstTab.id == tab1.id)
            #expect(secondTab.id == tab2.id)
        } else {
            #expect(Bool(false), "Expected two derived tabs to exist")
        }
    }

    @Test

    func test_activeTabId_tracksStore() async {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)
        store.setActiveTab(tab1.id)

        // Wait for async refresh
        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.activeTabId == tab1.id)
    }

    @Test

    func test_tabRemoved_adapterUpdates() async {
        // Arrange
        let s1 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let s2 = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab1 = Tab(paneId: s1.id)
        let tab2 = Tab(paneId: s2.id)
        store.appendTab(tab1)
        store.appendTab(tab2)

        // Wait for initial sync
        await waitForAdapterRefresh()
        #expect(adapter.tabs.count == 2)

        // Act
        store.removeTab(tab1.id)

        // Wait for update
        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.tabs.count == 1)
        if let remainingTab = adapter.tabs[safe: 0] {
            #expect(remainingTab.id == tab2.id)
        } else {
            #expect(Bool(false), "Expected remaining tab to exist")
        }
    }

    @Test

    func test_paneWithNoTitle_defaultsToTerminal() async {
        // Arrange
        let pane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil)
        )
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)

        // Wait for refresh
        await waitForAdapterRefresh()

        // Assert
        if let tabItem = adapter.tabs[safe: 0] {
            #expect(tabItem.displayTitle == "Terminal")
        } else {
            #expect(Bool(false), "Expected derived tab to exist")
        }
    }

    // MARK: - Transient State

    @Test

    func test_transientState_draggingTabId() {
        // Act
        adapter.draggingTabId = UUID()

        // Assert
        #expect((adapter.draggingTabId) != nil)
    }

    @Test

    func test_transientState_dropTargetIndex() {
        // Act
        adapter.dropTargetIndex = 2

        // Assert
        #expect(adapter.dropTargetIndex == 2)
    }

    @Test

    func test_transientState_tabFrames() {
        // Arrange
        let tabId = UUID()
        let frame = CGRect(x: 10, y: 20, width: 100, height: 30)

        // Act
        adapter.tabFrames[tabId] = frame

        // Assert
        #expect(adapter.tabFrames[tabId] == frame)
    }

    // MARK: - Overflow Detection

    @Test

    func test_noTabs_notOverflowing() {
        // Arrange
        adapter.availableWidth = 600

        // Assert
        #expect(!(adapter.isOverflowing))
    }

    @Test

    func test_fewTabs_withinSpace_notOverflowing() async {
        // Arrange — 2 tabs: 2×220 + 1×4 + 16 = 460px < 600px
        for _ in 0..<2 {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.appendTab(Tab(paneId: pane.id))
        }

        await waitForAdapterRefresh()

        // Act
        adapter.availableWidth = 600

        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.tabs.count == 2)
        #expect(!(adapter.isOverflowing))
    }

    @Test

    func test_manyTabs_exceedingSpace_overflowing() async {
        // Arrange — 8 tabs: 8×220 + 7×4 + 16 = 1804px > 600px
        for _ in 0..<8 {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.appendTab(Tab(paneId: pane.id))
        }

        await waitForAdapterRefresh()

        // Act
        adapter.availableWidth = 600

        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.tabs.count == 8)
        #expect(adapter.isOverflowing)
    }

    @Test

    func test_zeroAvailableWidth_notOverflowing() {
        // Arrange — layout not ready (width = 0)
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))

        Thread.sleep(forTimeInterval: 0.1)

        // Assert — availableWidth defaults to 0
        #expect(!(adapter.isOverflowing))
    }

    @Test

    func test_viewportWidth_prefersOverAvailableWidth() async {
        // Arrange — 1 tab, set both availableWidth and viewportWidth
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 800  // outer container
        adapter.viewportWidth = 600  // actual scroll viewport (smaller)
        adapter.contentWidth = 700  // content exceeds viewport but not available

        await waitForAdapterRefresh()

        // Assert — should overflow based on viewport (700 > 600), not available (700 < 800)
        #expect(adapter.isOverflowing)
    }

    @Test

    func test_contentWidthOverflow_triggersWhenContentExceedsAvailable() async {
        // Arrange — 1 tab so tabs.count > 0
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 600

        await waitForAdapterRefresh()
        #expect(!(adapter.isOverflowing))

        // Act — set content width wider than available
        adapter.contentWidth = 700

        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.isOverflowing)
    }

    @Test

    func test_contentWidthOverflow_hysteresisPreventsOscillation() async {
        // Arrange — trigger overflow via content width
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 600
        adapter.contentWidth = 700

        await waitForAdapterRefresh()
        #expect(adapter.isOverflowing)

        // Act — reduce content width slightly (simulates "+" button removed)
        // Still within hysteresis buffer (600 - 50 = 550, and 570 > 550)
        adapter.contentWidth = 570

        await waitForAdapterRefresh()

        // Assert — should remain overflowing due to hysteresis
        #expect(adapter.isOverflowing)
    }

    @Test

    func test_contentWidthOverflow_turnsOffWhenWellUnderThreshold() async {
        // Arrange — trigger overflow via content width
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        store.appendTab(Tab(paneId: pane.id))
        adapter.availableWidth = 600
        adapter.contentWidth = 700

        await waitForAdapterRefresh()
        #expect(adapter.isOverflowing)

        // Act — reduce well below hysteresis threshold (600 - 50 = 550)
        adapter.contentWidth = 500

        await waitForAdapterRefresh()

        // Assert
        #expect(!(adapter.isOverflowing))
    }

    @Test

    func test_overflowUpdates_whenTabsAddedOrRemoved() async {
        // Arrange — start with 4 tabs in 600px: 4×220 + 3×4 + 16 = 908px > 600px → overflow
        var panes: [Pane] = []
        for _ in 0..<4 {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.appendTab(Tab(paneId: pane.id))
            panes.append(pane)
        }
        adapter.availableWidth = 600

        await waitForAdapterRefresh()
        #expect(adapter.isOverflowing)

        // Act — remove tabs until not overflowing: 2 tabs: 2×220 + 1×4 + 16 = 460px < 600px
        let tabsToRemove = store.tabs.prefix(2)
        for tab in tabsToRemove {
            store.removeTab(tab.id)
        }

        await waitForAdapterRefresh()

        // Assert
        #expect(adapter.tabs.count == 2)
        #expect(!(adapter.isOverflowing))
    }
    private func waitForAdapterRefresh() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
        await Task.yield()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
