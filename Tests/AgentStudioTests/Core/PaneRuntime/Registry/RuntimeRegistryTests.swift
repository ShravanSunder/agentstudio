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

    @Test("duplicate registration replaces existing runtime without crashing")
    func duplicateRegistrationReplacesRuntime() {
        let registry = RuntimeRegistry()
        let paneId = PaneId()
        let first = TestPaneRuntime(paneId: paneId, contentType: .terminal)
        let second = TestPaneRuntime(paneId: paneId, contentType: .browser)

        let firstResult = registry.register(first)
        let secondResult = registry.register(second)

        #expect(firstResult == .inserted)
        #expect(secondResult == .replaced)
        #expect(registry.count == 1)
        #expect(registry.runtime(for: paneId)?.metadata.contentType == .browser)  // paneId is now PaneId
        #expect(registry.runtimes(ofType: .terminal).isEmpty)
        #expect(registry.runtimes(ofType: .browser).count == 1)
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

    func handleCommand(_ envelope: PaneCommandEnvelope) async -> ActionResult {
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
