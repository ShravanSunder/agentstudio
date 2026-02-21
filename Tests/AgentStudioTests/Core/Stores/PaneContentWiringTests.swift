import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PaneContentWiringTests {

    private var store: WorkspaceStore!

        init() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }

    // MARK: - WorkspaceStore.createPane(content:)

    @Test

    func test_createPane_webviewContent() {
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!, showNavigation: true)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )

        #expect(pane.title == "Web")
        if case .webview(let state) = pane.content {
            #expect(state.url.absoluteString == "https://example.com")
            #expect(state.showNavigation)
        } else {
            Issue.record("Expected .webview content")
        }
        #expect((store.pane(pane.id)) != nil)
    }

    @Test

    func test_createPane_codeViewerContent() {
        let filePath = URL(fileURLWithPath: "/tmp/test.swift")
        let pane = store.createPane(
            content: .codeViewer(CodeViewerState(filePath: filePath, scrollToLine: 42)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Code")
        )

        #expect(pane.title == "Code")
        if case .codeViewer(let state) = pane.content {
            #expect(state.filePath == filePath)
            #expect(state.scrollToLine == 42)
        } else {
            Issue.record("Expected .codeViewer content")
        }
    }

    @Test

    func test_createPane_terminalContent_viaGenericOverload() {
        let pane = store.createPane(
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .persistent)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Term")
        )

        #expect(pane.provider == .ghostty)
        #expect(pane.title == "Term")
    }

    @Test

    func test_createPane_marksDirty() {
        store.flush()
        _ = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://test.com")!, showNavigation: false)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )
        #expect(store.isDirty)
    }

    // MARK: - Mixed content types in a tab

    @Test

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
        store.insertPane(
            webPane.id, inTab: tab.id, at: terminalPane.id,
            direction: .horizontal, position: .after)

        let updatedTab = store.tab(tab.id)!
        #expect(updatedTab.panes.contains(terminalPane.id))
        #expect(updatedTab.panes.contains(webPane.id))
        #expect(updatedTab.panes.count == 2)
    }

    // MARK: - Persistence round-trip

    @Test

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
        #expect((restored) != nil)
        #expect(restored?.title == "Persist Web")
        if case .webview(let state) = restored?.content {
            #expect(state.url.absoluteString == "https://round-trip.com")
            #expect(!(state.showNavigation))
        } else {
            Issue.record("Expected .webview content after restore, got \(String(describing: restored?.content))")
        }
    }

    @Test

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
        #expect((restored) != nil)
        if case .codeViewer(let state) = restored?.content {
            #expect(state.filePath == filePath)
            #expect(state.scrollToLine == 99)
        } else {
            Issue.record("Expected .codeViewer content after restore")
        }
    }

    // MARK: - ViewRegistry generalization

    @Test

    func test_viewRegistry_registersPaneView() {
        let registry = ViewRegistry()
        let view = PaneView(paneId: UUID())

        registry.register(view, for: view.paneId)

        #expect((registry.view(for: view.paneId)) != nil)
        #expect(registry.registeredPaneIds.contains(view.paneId))
    }

    @Test

    func test_viewRegistry_terminalViewDowncast() {
        let registry = ViewRegistry()
        let paneId = UUID()

        // Non-terminal pane
        let webView = PaneView(paneId: paneId)
        registry.register(webView, for: paneId)

        #expect((registry.view(for: paneId)) != nil)
        #expect((registry.terminalView(for: paneId)) == nil)
    }

    // MARK: - PaneView base class

    @Test

    func test_paneView_identifiable() {
        let id = UUID()
        let view = PaneView(paneId: id)

        #expect(view.id == id)
        #expect(view.paneId == id)
    }

    @Test

    func test_paneView_swiftUIContainer() {
        let view = PaneView(paneId: UUID())
        let container = view.swiftUIContainer

        // Container wraps the view
        #expect(container.subviews.contains(view))
    }

    // MARK: - updatePaneWebviewState

    @Test

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
            #expect(state.url.absoluteString == "https://new.com")
            #expect(state.title == "New")
            #expect(!(state.showNavigation))
        } else {
            Issue.record("Expected .webview content after update")
        }
    }

    @Test

    func test_updatePaneWebviewState_marksDirty() {
        // Arrange
        let pane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "Web")
        )
        store.flush()
        #expect(!(store.isDirty))

        // Act
        store.updatePaneWebviewState(pane.id, state: WebviewState(url: URL(string: "https://updated.com")!))

        // Assert
        #expect(store.isDirty)
    }

    @Test

    func test_updatePaneWebviewState_missingPane_doesNotCrash() {
        // Act — should log warning but not crash
        store.updatePaneWebviewState(UUID(), state: WebviewState(url: URL(string: "https://ghost.com")!))

        // Assert — store still functional
        #expect(store.panes.isEmpty)
    }

    // MARK: - ViewRegistry webview accessors

    @Test

    func test_viewRegistry_webviewView_returnsNilForNonWebview() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let view = PaneView(paneId: paneId)
        registry.register(view, for: paneId)

        #expect((registry.webviewView(for: paneId)) == nil)
    }

    @Test

    func test_viewRegistry_allWebviewViews_filtersCorrectly() {
        let registry = ViewRegistry()
        let paneId1 = UUID()
        let paneId2 = UUID()

        // Register a generic PaneView (not a webview)
        registry.register(PaneView(paneId: paneId1), for: paneId1)
        // Register another generic PaneView
        registry.register(PaneView(paneId: paneId2), for: paneId2)

        // allWebviewViews should be empty since neither is a WebviewPaneView
        #expect(registry.allWebviewViews.isEmpty)
    }
}
