import Foundation

@testable import AgentStudio

@MainActor
func waitForRecordedCommands(
    on runtime: RecordingCommandPaneRuntime,
    count: Int,
    maxTurns: Int = 50
) async {
    for _ in 0..<maxTurns where runtime.receivedCommands.count < count {
        await Task.yield()
    }
}

@MainActor
final class RecordingCommandPaneRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle = .ready
    var capabilities: Set<PaneCapability> = [.input]

    private let stream: AsyncStream<RuntimeEnvelope>
    private let continuation: AsyncStream<RuntimeEnvelope>.Continuation
    private(set) var receivedCommands: [RuntimeCommandEnvelope] = []

    init(paneId: PaneId) {
        self.paneId = paneId
        self.metadata = PaneMetadata(
            paneId: paneId,
            contentType: .terminal,
            source: .floating(launchDirectory: nil, title: "Fake"),
            title: "Fake"
        )
        let (stream, continuation) = AsyncStream.makeStream(of: RuntimeEnvelope.self)
        self.stream = stream
        self.continuation = continuation
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
        receivedCommands.append(envelope)
        return .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<RuntimeEnvelope> {
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

    func shutdown(timeout _: Duration) async -> [UUID] {
        continuation.finish()
        return []
    }
}
