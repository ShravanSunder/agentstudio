import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneCoordinatorRuntimeDispatchNonTerminalTests {
    @Test("dispatchRuntimeCommand routes non-terminal commands to targeted runtimes")
    func dispatchRoutesNonTerminalRuntimeCommands() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-coordinator-runtime-non-terminal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()
        let coordinator = PaneCoordinator(
            store: store,
            viewRegistry: ViewRegistry(),
            runtime: SessionRuntime(store: store),
            surfaceManager: MockPaneCoordinatorSurfaceManagerNonTerminal(),
            runtimeRegistry: RuntimeRegistry()
        )

        let webviewPane = store.createPane(
            content: .webview(WebviewState(url: URL(string: "https://example.com/non-terminal-webview")!)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Webview"), title: "Webview")
        )
        let bridgePane = store.createPane(
            content: .bridgePanel(BridgePaneState(panelKind: .diffViewer, source: nil)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Bridge"), title: "Bridge")
        )
        let codePane = store.createPane(
            content: .codeViewer(
                CodeViewerState(filePath: URL(fileURLWithPath: "/tmp/non-terminal.swift"), scrollToLine: nil)
            ),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Code"), title: "Code")
        )

        store.appendTab(Tab(paneId: webviewPane.id))
        store.appendTab(Tab(paneId: bridgePane.id))
        store.appendTab(Tab(paneId: codePane.id))

        let webviewRuntime = FakePaneRuntimeNonTerminal(
            paneId: PaneId(uuid: webviewPane.id),
            contentType: .browser,
            capabilities: [.navigation]
        )
        let bridgeRuntime = FakePaneRuntimeNonTerminal(
            paneId: PaneId(uuid: bridgePane.id),
            contentType: .diff,
            capabilities: [.diffReview]
        )
        let codeViewerRuntime = FakePaneRuntimeNonTerminal(
            paneId: PaneId(uuid: codePane.id),
            contentType: .codeViewer,
            capabilities: [.editorActions]
        )
        coordinator.registerRuntime(webviewRuntime)
        coordinator.registerRuntime(bridgeRuntime)
        coordinator.registerRuntime(codeViewerRuntime)

        let webviewResult = await coordinator.dispatchRuntimeCommand(
            .browser(.reload(hard: false)),
            target: .pane(PaneId(uuid: webviewPane.id))
        )
        let bridgeResult = await coordinator.dispatchRuntimeCommand(
            .diff(.approveHunk(hunkId: "h1")),
            target: .pane(PaneId(uuid: bridgePane.id))
        )
        let codeViewerResult = await coordinator.dispatchRuntimeCommand(
            .editor(.save),
            target: .pane(PaneId(uuid: codePane.id))
        )

        #expect(webviewResult == .success(commandId: webviewRuntime.receivedCommandIds.first!))
        #expect(bridgeResult == .success(commandId: bridgeRuntime.receivedCommandIds.first!))
        #expect(codeViewerResult == .success(commandId: codeViewerRuntime.receivedCommandIds.first!))
        #expect(webviewRuntime.receivedCommands.count == 1)
        #expect(bridgeRuntime.receivedCommands.count == 1)
        #expect(codeViewerRuntime.receivedCommands.count == 1)
    }
}

@MainActor
private final class FakePaneRuntimeNonTerminal: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle = .ready
    var capabilities: Set<PaneCapability>
    private let stream: AsyncStream<PaneEventEnvelope>
    private let continuation: AsyncStream<PaneEventEnvelope>.Continuation

    private(set) var receivedCommands: [RuntimeCommandEnvelope] = []
    private(set) var receivedCommandIds: [UUID] = []

    init(
        paneId: PaneId,
        contentType: PaneContentType,
        capabilities: Set<PaneCapability>
    ) {
        self.paneId = paneId
        self.metadata = PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            source: .floating(workingDirectory: nil, title: "Fake"),
            title: "Fake"
        )
        self.capabilities = capabilities
        let (stream, continuation) = AsyncStream.makeStream(of: PaneEventEnvelope.self)
        self.stream = stream
        self.continuation = continuation
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
        receivedCommands.append(envelope)
        receivedCommandIds.append(envelope.commandId)
        return .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<PaneEventEnvelope> { stream }

    func snapshot() -> PaneRuntimeSnapshot {
        PaneRuntimeSnapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities,
            lastSeq: 0,
            timestamp: Date()
        )
    }

    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        EventReplayBuffer.ReplayResult(events: [], nextSeq: seq, gapDetected: false)
    }

    func shutdown(timeout _: Duration) async -> [UUID] {
        continuation.finish()
        return []
    }
}

@MainActor
private final class MockPaneCoordinatorSurfaceManagerNonTerminal: PaneCoordinatorSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        self.cwdStream = AsyncStream { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

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

    func requeueUndo(_ surfaceId: UUID) {
        _ = surfaceId
    }

    func destroy(_ surfaceId: UUID) {
        _ = surfaceId
    }
}
