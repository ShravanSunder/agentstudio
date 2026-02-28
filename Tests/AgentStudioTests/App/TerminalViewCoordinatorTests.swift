import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorViewFactoryTests {
    private struct PaneCoordinatorHarness {
        let store: WorkspaceStore
        let viewRegistry: ViewRegistry
        let runtime: SessionRuntime
        let coordinator: PaneCoordinator
        let tempDir: URL
    }

    private func makeHarness() -> PaneCoordinatorHarness {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-coordinator-tests-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let viewRegistry = ViewRegistry()
        let runtime = SessionRuntime(store: store)
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime
        )
        return PaneCoordinatorHarness(
            store: store,
            viewRegistry: viewRegistry,
            runtime: runtime,
            coordinator: coordinator,
            tempDir: tempDir
        )
    }

    @Test("createViewForContent registers a webview view in the registry")
    func createViewForContent_registersWebviewView() {
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
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
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
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
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
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

    @Test("createViewForContent registers runtime for bridge, webview, and code viewer panes")
    func createViewForContent_registersNonTerminalRuntimes() {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let webviewPane = Pane(
            id: UUIDv7.generate(),
            content: .webview(WebviewState(url: URL(string: "https://example.com/runtime-web")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Web"))
        )
        let bridgePane = Pane(
            id: UUIDv7.generate(),
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: .commit(sha: "def456"))),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Diff"))
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "code-view-runtime-\(UUID().uuidString).swift")
        try? "struct Runtime {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let codeViewerPane = Pane(
            id: UUIDv7.generate(),
            content: .codeViewer(CodeViewerState(filePath: fileURL, scrollToLine: 1)),
            metadata: PaneMetadata(
                source: .floating(workingDirectory: fileURL.deletingLastPathComponent(), title: "Code"))
        )

        _ = coordinator.createViewForContent(pane: webviewPane)
        _ = coordinator.createViewForContent(pane: bridgePane)
        _ = coordinator.createViewForContent(pane: codeViewerPane)

        #expect(coordinator.runtimeForPane(PaneId(uuid: webviewPane.id)) is WebviewRuntime)
        #expect(coordinator.runtimeForPane(PaneId(uuid: bridgePane.id)) is BridgeRuntime)
        #expect(coordinator.runtimeForPane(PaneId(uuid: codeViewerPane.id)) is SwiftPaneRuntime)
    }

    @Test("createViewForContent returns nil for unsupported pane content")
    func createViewForContent_unsupportedContentReturnsNil() {
        let harness = makeHarness()
        let viewRegistry = harness.viewRegistry
        let coordinator = harness.coordinator
        let tempDir = harness.tempDir
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pane = Pane(
            id: UUIDv7.generate(),
            content: .unsupported(UnsupportedContent(type: "legacy", version: 1, rawState: nil)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Legacy"))
        )

        let maybeView = coordinator.createViewForContent(pane: pane)

        #expect(maybeView == nil)
        #expect(viewRegistry.view(for: pane.id) == nil)
        #expect(viewRegistry.registeredPaneIds.isEmpty)
    }
}
