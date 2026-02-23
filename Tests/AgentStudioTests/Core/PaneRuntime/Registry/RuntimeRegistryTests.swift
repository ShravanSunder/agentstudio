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
        contentType: PaneContentType = .terminal
    ) {
        self.paneId = paneId
        self.metadata = PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            source: .floating(workingDirectory: nil, title: "Test"),
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
