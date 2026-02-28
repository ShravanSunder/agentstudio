import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RuntimeRegistry")
struct RuntimeRegistryTests {
    @Test("register and lookup by pane id")
    func registerAndLookup() {
        let registry = RuntimeRegistry()
        let runtime = TestPaneRuntime(paneId: PaneId())
        registry.register(runtime)
        #expect(registry.runtime(for: runtime.paneId) != nil)
    }

    @Test("unregister removes runtime")
    func unregisterRemoves() {
        let registry = RuntimeRegistry()
        let runtime = TestPaneRuntime(paneId: PaneId())
        registry.register(runtime)

        let removed = registry.unregister(runtime.paneId)

        #expect(removed?.paneId == runtime.paneId)
        #expect(registry.runtime(for: runtime.paneId) == nil)
    }

    @Test("duplicate registration is rejected and existing runtime is preserved")
    func duplicateRegistrationRejected() {
        let registry = RuntimeRegistry()
        let paneId = PaneId()
        let first = TestPaneRuntime(paneId: paneId, contentType: .terminal)
        let second = TestPaneRuntime(paneId: paneId, contentType: .browser)

        let firstResult = registry.register(first)
        let secondResult = registry.register(second)

        #expect(firstResult == .inserted)
        #expect(secondResult == .duplicateRejected)
        #expect(registry.count == 1)
        #expect(registry.runtime(for: paneId)?.metadata.contentType == .terminal)
        #expect(registry.runtimes(ofType: .terminal).count == 1)
        #expect(registry.runtimes(ofType: .browser).isEmpty)
    }

    @Test("findPaneWithWorktree returns paneId when worktree is registered")
    func findPaneWithWorktreeFindsExisting() {
        let registry = RuntimeRegistry()
        let paneId = PaneId()
        let worktreeId = UUID()
        let runtime = TestPaneRuntime(
            paneId: paneId,
            source: .worktree(worktreeId: worktreeId, repoId: UUID())
        )
        registry.register(runtime)

        let found = registry.findPaneWithWorktree(worktreeId: worktreeId)

        #expect(found == paneId)
    }

    @Test("findPaneWithWorktree returns nil for unknown worktree")
    func findPaneWithWorktreeReturnsNilForUnknown() {
        let registry = RuntimeRegistry()

        #expect(registry.findPaneWithWorktree(worktreeId: UUID()) == nil)
    }

    @Test("findPaneWithWorktree ignores floating panes")
    func findPaneWithWorktreeIgnoresFloating() {
        let registry = RuntimeRegistry()
        let runtime = TestPaneRuntime(paneId: PaneId())
        registry.register(runtime)

        #expect(registry.findPaneWithWorktree(worktreeId: UUID()) == nil)
    }

    @Test("runtimes(ofType:) tracks non-terminal runtime kinds")
    func runtimesByNonTerminalKinds() {
        let registry = RuntimeRegistry()
        let webviewRuntime = TestPaneRuntime(paneId: PaneId(), contentType: .browser)
        let bridgeRuntime = TestPaneRuntime(paneId: PaneId(), contentType: .diff)
        let codeViewerRuntime = TestPaneRuntime(paneId: PaneId(), contentType: .codeViewer)
        registry.register(webviewRuntime)
        registry.register(bridgeRuntime)
        registry.register(codeViewerRuntime)

        let browserPaneIds = Set(registry.runtimes(ofType: .browser).map(\.paneId))
        let diffPaneIds = Set(registry.runtimes(ofType: .diff).map(\.paneId))
        let codeViewerPaneIds = Set(registry.runtimes(ofType: .codeViewer).map(\.paneId))

        #expect(browserPaneIds == [webviewRuntime.paneId])
        #expect(diffPaneIds == [bridgeRuntime.paneId])
        #expect(codeViewerPaneIds == [codeViewerRuntime.paneId])
        #expect(registry.runtimes(ofType: .terminal).isEmpty)
    }
}

@MainActor
private final class TestPaneRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle
    var capabilities: Set<PaneCapability>

    private let stream: AsyncStream<PaneEventEnvelope>

    init(
        paneId: PaneId,
        contentType: PaneContentType = .terminal,
        source: PaneMetadata.PaneMetadataSource = .floating(workingDirectory: nil, title: "Test")
    ) {
        self.paneId = paneId
        self.metadata = PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            source: source,
            title: "Test"
        )
        self.lifecycle = .ready
        self.capabilities = []
        self.stream = AsyncStream<PaneEventEnvelope> { continuation in
            continuation.finish()
        }
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
        .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<PaneEventEnvelope> {
        stream
    }

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

    func shutdown(timeout: Duration) async -> [UUID] {
        lifecycle = .terminated
        return []
    }
}
