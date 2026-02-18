import XCTest
@testable import AgentStudio

@MainActor
final class PaneContentWiringTests: XCTestCase {

    private var store: WorkspaceStore!

    override func setUp() {
        super.setUp()
        store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - WorkspaceStore.createPane(content:)

    func test_createPane_webviewContent() {
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )

        XCTAssertEqual(pane.title, "Web")
        if case .webview(let state) = pane.content {
            XCTAssertEqual(state.url.absoluteString, "https://example.com")
            XCTAssertTrue(state.showNavigation)
        } else {
            XCTFail("Expected .webview content")
        }
        XCTAssertNotNil(store.pane(pane.id))
    }

    func test_createPane_codeViewerContent() {
        let filePath = URL(fileURLWithPath: "/tmp/test.swift")
        let pane = store.createPane(
            content: .codeViewer(CodeViewerState(filePath: filePath, scrollToLine: 42)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Code")
        )

        XCTAssertEqual(pane.title, "Code")
        if case .codeViewer(let state) = pane.content {
            XCTAssertEqual(state.filePath, filePath)
            XCTAssertEqual(state.scrollToLine, 42)
        } else {
            XCTFail("Expected .codeViewer content")
        }
    }

    func test_createPane_terminalContent_viaGenericOverload() {
        let pane = store.createPane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Term")
        )

        XCTAssertEqual(pane.provider, .ghostty)
        XCTAssertEqual(pane.title, "Term")
    }

    func test_createPane_marksDirty() {
        store.flush()
        _ = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://test.com")!, showNavigation: false)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )
        XCTAssertTrue(store.isDirty)
    }

    // MARK: - Mixed content types in a tab

    func test_mixedContentTab_layoutContainsAllPanes() {
        let terminalPane = store.createPane(
            source: .floating(workingDirectory: nil, title: nil),
            title: "Terminal",
            provider: .ghostty
        )
        let webPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://docs.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Docs")
        )

        let tab = Tab(paneId: terminalPane.id)
        store.appendTab(tab)
        store.insertPane(webPane.id, inTab: tab.id, at: terminalPane.id,
                         direction: .horizontal, position: .after)

        let updatedTab = store.tab(tab.id)!
        XCTAssertTrue(updatedTab.panes.contains(terminalPane.id))
        XCTAssertTrue(updatedTab.panes.contains(webPane.id))
        XCTAssertEqual(updatedTab.panes.count, 2)
    }

    // MARK: - Persistence round-trip

    func test_webviewPane_persistsAndRestores() {
        let persistDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let persistor = WorkspacePersistor(workspacesDir: persistDir)
        let store1 = WorkspaceStore(persistor: persistor)

        let pane = store1.createPane(
            content: .webview(WebviewState(url: URL(string: "https://round-trip.com")!, showNavigation: false)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Persist Web")
        )
        let tab = Tab(paneId: pane.id)
        store1.appendTab(tab)
        store1.flush()

        // Restore into new store
        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        let restored = store2.pane(pane.id)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.title, "Persist Web")
        if case .webview(let state) = restored?.content {
            XCTAssertEqual(state.url.absoluteString, "https://round-trip.com")
            XCTAssertFalse(state.showNavigation)
        } else {
            XCTFail("Expected .webview content after restore, got \(String(describing: restored?.content))")
        }
    }

    func test_codeViewerPane_persistsAndRestores() {
        let persistDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let persistor = WorkspacePersistor(workspacesDir: persistDir)
        let store1 = WorkspaceStore(persistor: persistor)

        let filePath = URL(fileURLWithPath: "/tmp/code.swift")
        let pane = store1.createPane(
            content: .codeViewer(CodeViewerState(filePath: filePath, scrollToLine: 99)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Persist Code")
        )
        let tab = Tab(paneId: pane.id)
        store1.appendTab(tab)
        store1.flush()

        let store2 = WorkspaceStore(persistor: persistor)
        store2.restore()

        let restored = store2.pane(pane.id)
        XCTAssertNotNil(restored)
        if case .codeViewer(let state) = restored?.content {
            XCTAssertEqual(state.filePath, filePath)
            XCTAssertEqual(state.scrollToLine, 99)
        } else {
            XCTFail("Expected .codeViewer content after restore")
        }
    }

    // MARK: - ViewRegistry generalization

    func test_viewRegistry_registersPaneView() {
        let registry = ViewRegistry()
        let view = PaneView(paneId: UUID())

        registry.register(view, for: view.paneId)

        XCTAssertNotNil(registry.view(for: view.paneId))
        XCTAssertTrue(registry.registeredPaneIds.contains(view.paneId))
    }

    func test_viewRegistry_terminalViewDowncast() {
        let registry = ViewRegistry()
        let paneId = UUID()

        // Non-terminal pane
        let webView = PaneView(paneId: paneId)
        registry.register(webView, for: paneId)

        XCTAssertNotNil(registry.view(for: paneId))
        XCTAssertNil(registry.terminalView(for: paneId))
    }

    func test_viewRegistry_epochBumpsOnRegister() {
        let registry = ViewRegistry()
        let initial = registry.epoch

        registry.register(PaneView(paneId: UUID()), for: UUID())

        XCTAssertEqual(registry.epoch, initial + 1)
    }

    // MARK: - PaneView base class

    func test_paneView_identifiable() {
        let id = UUID()
        let view = PaneView(paneId: id)

        XCTAssertEqual(view.id, id)
        XCTAssertEqual(view.paneId, id)
    }

    func test_paneView_swiftUIContainer() {
        let view = PaneView(paneId: UUID())
        let container = view.swiftUIContainer

        // Container wraps the view
        XCTAssertTrue(container.subviews.contains(view))
    }

    // MARK: - updatePaneWebviewState

    func test_updatePaneWebviewState_updatesContent() {
        // Arrange
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://old.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )
        let newState = WebviewState(
            url: URL(string: "https://new.com")!,
            title: "New",
            showNavigation: false
        )

        // Act
        store.updatePaneWebviewState(pane.id, state: newState)

        // Assert
        let updated = store.pane(pane.id)
        if case .webview(let state) = updated?.content {
            XCTAssertEqual(state.url.absoluteString, "https://new.com")
            XCTAssertEqual(state.title, "New")
            XCTAssertFalse(state.showNavigation)
        } else {
            XCTFail("Expected .webview content after update")
        }
    }

    func test_updatePaneWebviewState_marksDirty() {
        // Arrange
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )
        store.flush()
        XCTAssertFalse(store.isDirty)

        // Act
        store.updatePaneWebviewState(pane.id, state: WebviewState(url: URL(string: "https://updated.com")!))

        // Assert
        XCTAssertTrue(store.isDirty)
    }

    func test_updatePaneWebviewState_missingPane_doesNotCrash() {
        // Act — should log warning but not crash
        store.updatePaneWebviewState(UUID(), state: WebviewState(url: URL(string: "https://ghost.com")!))

        // Assert — store still functional
        XCTAssertTrue(store.panes.isEmpty)
    }

    // MARK: - ViewRegistry webview accessors

    func test_viewRegistry_webviewView_returnsNilForNonWebview() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let view = PaneView(paneId: paneId)
        registry.register(view, for: paneId)

        XCTAssertNil(registry.webviewView(for: paneId))
    }

    func test_viewRegistry_allWebviewViews_filtersCorrectly() {
        let registry = ViewRegistry()
        let paneId1 = UUID()
        let paneId2 = UUID()

        // Register a generic PaneView (not a webview)
        registry.register(PaneView(paneId: paneId1), for: paneId1)
        // Register another generic PaneView
        registry.register(PaneView(paneId: paneId2), for: paneId2)

        // allWebviewViews should be empty since neither is a WebviewPaneView
        XCTAssertTrue(registry.allWebviewViews.isEmpty)
    }
}
