import Foundation
import Testing

@testable import AgentStudio

final class FakePaneRuntime: PaneRuntime {
    let paneId: PaneId
    var metadata: PaneMetadata
    var lifecycle: PaneRuntimeLifecycle = .ready
    var capabilities: Set<PaneCapability>
    private let stream: AsyncStream<RuntimeEnvelope>
    private let continuation: AsyncStream<RuntimeEnvelope>.Continuation

    private(set) var receivedCommands: [RuntimeCommandEnvelope] = []
    private(set) var receivedCommandIds: [UUID] = []

    init(
        paneId: PaneId,
        contentType: PaneContentType = .terminal,
        capabilities: Set<PaneCapability> = [.input]
    ) {
        self.paneId = paneId
        self.metadata = PaneMetadata(
            paneId: paneId,
            contentType: contentType,
            title: "Fake"
        )
        self.capabilities = capabilities
        let (stream, continuation) = AsyncStream.makeStream(of: RuntimeEnvelope.self)
        self.stream = stream
        self.continuation = continuation
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
        if let requiredCapability = requiredCapability(for: envelope.command),
            !capabilities.contains(requiredCapability)
        {
            return .failure(
                .unsupportedCommand(
                    command: String(describing: envelope.command),
                    required: requiredCapability
                )
            )
        }

        receivedCommands.append(envelope)
        receivedCommandIds.append(envelope.commandId)
        return .success(commandId: envelope.commandId)
    }

    func subscribe() -> AsyncStream<RuntimeEnvelope> {
        stream
    }

    func emit(_ envelope: RuntimeEnvelope) {
        continuation.yield(envelope)
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
        continuation.finish()
        return []
    }

    private func requiredCapability(for command: RuntimeCommand) -> PaneCapability? {
        switch command {
        case .activate, .deactivate, .prepareForClose, .requestSnapshot:
            return nil
        case .terminal(let terminalCommand):
            switch terminalCommand {
            case .sendInput, .clearScrollback:
                return .input
            case .scrollToBottom, .scrollPageUp, .jumpToPrompt:
                return nil
            case .resize:
                return .resize
            }
        case .browser:
            return .navigation
        case .diff:
            return .diffReview
        case .editor:
            return .editorActions
        case .plugin:
            return nil
        }
    }
}

@MainActor
// swiftlint:disable:next function_parameter_count
func makeRuntimeEnvelope(
    source: EventSource,
    paneKind: PaneContentType?,
    seq: UInt64,
    commandId: UUID?,
    correlationId: UUID?,
    timestamp: ContinuousClock.Instant,
    epoch _: UInt64,
    event: PaneRuntimeEvent
) -> RuntimeEnvelope {
    let paneId: PaneId
    switch source {
    case .pane(let resolvedPaneId):
        paneId = resolvedPaneId
    case .system, .worktree:
        paneId = PaneId()
    }

    return .pane(
        PaneEnvelope(
            source: source,
            seq: seq,
            timestamp: timestamp,
            correlationId: correlationId,
            commandId: commandId,
            paneId: paneId,
            paneKind: paneKind ?? .agent,
            event: event
        )
    )
}
