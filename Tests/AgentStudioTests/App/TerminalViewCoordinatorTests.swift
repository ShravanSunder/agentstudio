import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TerminalViewCoordinatorTests {
    private func makeHarness() -> (
        WorkspaceStore,
        ViewRegistry,
        SessionRuntime,
        TerminalViewCoordinator,
        URL
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-coordinator-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = TerminalViewCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime
        )
        return (store, viewRegistry, runtime, coordinator, tempDir)
    }

    @Test("createViewForContent registers a webview view in the registry")
    func createViewForContent_registersWebviewView() {
        let (_, viewRegistry, _, coordinator, tempDir) = makeHarness()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUID(),
            content: .webview(WebviewState(url: URL(string: "https://example.com")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Web"))
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        let registered = viewRegistry.view(for: pane.id)

        #expect(maybeView is WebviewPaneView)
        #expect(registered is WebviewPaneView)
        #expect(viewRegistry.allWebviewViews.count == 1)
        #expect(viewRegistry.allWebviewViews[pane.id] === registered as? WebviewPaneView)
    }

    @Test("createViewForContent registers a code viewer view in the registry")
    func createViewForContent_registersCodeViewerView() {
        let (_, viewRegistry, _, coordinator, tempDir) = makeHarness()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUID(),
            content: .codeViewer(
                CodeViewerState(filePath: URL(fileURLWithPath: "/tmp/example.swift"), scrollToLine: 42)
            ),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Code"))
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        let registered = viewRegistry.view(for: pane.id)

        #expect(maybeView is CodeViewerPaneView)
        #expect(registered is CodeViewerPaneView)
        #expect(viewRegistry.registeredPaneIds == Set([pane.id]))
    }

    @Test("createViewForContent builds bridge view and teardown clears bridge readiness")
    func createViewForContent_bridgeView_tearsDownCleanly() {
        let (_, viewRegistry, _, coordinator, tempDir) = makeHarness()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUID(),
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "abc123"))),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Diff"))
        )

        let maybeView = coordinator.createViewForContent(pane: pane)
        guard let bridgeView = maybeView as? BridgePaneView else {
            Issue.record("Expected a BridgePaneView")
            return
        }
        let bridgeController = bridgeView.controller
        #expect(bridgeController.isBridgeReady == false)

        bridgeController.handleBridgeReady()
        #expect(bridgeController.isBridgeReady == true)

        coordinator.teardownView(for: pane.id)

        #expect(bridgeController.isBridgeReady == false)
        #expect(viewRegistry.view(for: pane.id) == nil)
        #expect(viewRegistry.registeredPaneIds == Set<UUID>())
    }

    @Test("createViewForContent returns nil for unsupported pane content")
    func createViewForContent_unsupportedContentReturnsNil() {
        let (_, viewRegistry, _, coordinator, tempDir) = makeHarness()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUID(),
            content: .unsupported(UnsupportedContent(type: "legacy", version: 1, rawState: nil)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Legacy"))
        )

        let maybeView = coordinator.createViewForContent(pane: pane)

        #expect(maybeView == nil)
        #expect(viewRegistry.view(for: pane.id) == nil)
        #expect(viewRegistry.registeredPaneIds.isEmpty)
    }
}
