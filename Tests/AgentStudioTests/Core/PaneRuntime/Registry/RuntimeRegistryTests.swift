import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RuntimeRegistry")
struct RuntimeRegistryTests {
    @Test("register and lookup by pane id")
    func registerAndLookup() {
        let registry = RuntimeRegistry()
        let runtime = TestPaneRuntime(paneId: UUID())
        registry.register(runtime)
        #expect(registry.runtime(for: runtime.paneId) != nil)
    }

    @Test("unregister removes runtime")
    func unregisterRemoves() {
        let registry = RuntimeRegistry()
        let runtime = TestPaneRuntime(paneId: UUID())
        registry.register(runtime)

        let removed = registry.unregister(runtime.paneId)

        #expect(removed?.paneId == runtime.paneId)
        #expect(registry.runtime(for: runtime.paneId) == nil)
    }
}

@MainActor
private final class TestPaneRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle
    var capabilities: Set<PaneCapability>

    private let stream: AsyncStream<PaneEventEnvelope>

    init(paneId: PaneId) {
        self.paneId = paneId
        self.metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "Test"), title: "Test")
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
        PaneRuntimeSnapshot(paneId: paneId, lifecycle: lifecycle)
    }

    func shutdown(timeout: Duration) async -> [UUID] {
        lifecycle = .terminated
        return []
    }
}
