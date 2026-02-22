import Foundation
import Observation

@MainActor
@Observable
final class TerminalRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    private(set) var lifecycle: PaneRuntimeLifecycle
    let capabilities: Set<PaneCapability>

    private let envelopeClock: ContinuousClock
    private let replayBuffer: EventReplayBuffer
    private var sequence: UInt64 = 0
    private let eventStream: AsyncStream<PaneEventEnvelope>
    private let eventContinuation: AsyncStream<PaneEventEnvelope>.Continuation

    init(
        paneId: PaneId,
        metadata: PaneMetadata,
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer? = nil
    ) {
        self.paneId = paneId
        self.metadata = metadata
        self.lifecycle = .created
        self.capabilities = [.input, .resize, .search]
        self.envelopeClock = clock
        self.replayBuffer = replayBuffer ?? EventReplayBuffer()

        var continuation: AsyncStream<PaneEventEnvelope>.Continuation?
        self.eventStream = AsyncStream<PaneEventEnvelope> { streamContinuation in
            continuation = streamContinuation
        }
        self.eventContinuation = continuation!
    }

    func transitionToReady() {
        guard lifecycle == .created else { return }
        lifecycle = .ready
    }

    func handleCommand(_ envelope: PaneCommandEnvelope) async -> ActionResult {
        guard lifecycle == .ready else {
            return .failure(.runtimeNotReady(lifecycle: lifecycle))
        }

        switch envelope.command {
        case .activate:
            return .success(commandId: envelope.commandId)
        case .deactivate:
            return .success(commandId: envelope.commandId)
        case .prepareForClose:
            lifecycle = .draining
            return .success(commandId: envelope.commandId)
        case .requestSnapshot:
            return .success(commandId: envelope.commandId)
        case .terminal:
            return .success(commandId: envelope.commandId)
        case .browser, .diff, .editor, .plugin:
            return .failure(.unsupportedCommand(command: String(describing: envelope.command), required: .input))
        }
    }

    func subscribe() -> AsyncStream<PaneEventEnvelope> {
        eventStream
    }

    func snapshot() -> PaneRuntimeSnapshot {
        PaneRuntimeSnapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities,
            lastSeq: sequence,
            timestamp: Date()
        )
    }

    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        replayBuffer.eventsSince(seq: seq)
    }

    func shutdown(timeout _: Duration) async -> [UUID] {
        if lifecycle == .terminated {
            return []
        }
        lifecycle = .draining
        lifecycle = .terminated
        eventContinuation.finish()
        return []
    }

    func handleGhosttyEvent(
        _ event: GhosttyEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        guard lifecycle != .terminated else { return }

        switch event {
        case .titleChanged(let title):
            metadata.title = title
        case .cwdChanged(let cwdPath):
            metadata.cwd = URL(fileURLWithPath: cwdPath)
        case .commandFinished, .bellRang, .scrollbarChanged, .unhandled:
            break
        }

        sequence += 1
        let envelope = PaneEventEnvelope(
            source: .pane(paneId),
            paneKind: .terminal,
            seq: sequence,
            commandId: commandId,
            correlationId: correlationId,
            timestamp: envelopeClock.now,
            epoch: 0,
            event: .terminal(event)
        )
        replayBuffer.append(envelope)
        eventContinuation.yield(envelope)
    }
}
