import Foundation
import Observation
import os.log

@MainActor
protocol BridgeRuntimeCommandHandling: AnyObject {
    func handleDiffCommand(
        _ command: DiffCommand,
        commandId: UUID,
        correlationId: UUID?
    ) -> ActionResult
}

@MainActor
@Observable
final class BridgeRuntime: BusPostingPaneRuntime {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "BridgeRuntime")

    let paneId: PaneId
    private(set) var metadata: PaneMetadata
    private(set) var lifecycle: PaneRuntimeLifecycle
    let capabilities: Set<PaneCapability>
    let paneState = PaneDomainState()
    weak var commandHandler: (any BridgeRuntimeCommandHandling)?

    private let envelopeClock: ContinuousClock
    private let replayBuffer: EventReplayBuffer
    private let paneEventBus: EventBus<PaneEventEnvelope>
    private var sequence: UInt64 = 0
    private var nextSubscriberId: UInt64 = 0
    private var subscribers: [UInt64: AsyncStream<PaneEventEnvelope>.Continuation] = [:]

    init(
        paneId: PaneId,
        metadata: PaneMetadata,
        commandHandler: (any BridgeRuntimeCommandHandling)? = nil,
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer? = nil,
        paneEventBus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared
    ) {
        self.paneId = paneId
        self.metadata = metadata
        self.lifecycle = .created
        self.capabilities = Self.capabilities(for: metadata.contentType)
        self.commandHandler = commandHandler
        self.envelopeClock = clock
        self.replayBuffer = replayBuffer ?? EventReplayBuffer()
        self.paneEventBus = paneEventBus
    }

    func transitionToReady() {
        guard lifecycle == .created else {
            Self.logger.warning(
                "Rejected transitionToReady for pane \(self.paneId.uuid.uuidString, privacy: .public): lifecycle=\(String(describing: self.lifecycle), privacy: .public)"
            )
            return
        }
        lifecycle = .ready
    }

    func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
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
        case .diff(let diffCommand):
            guard capabilities.contains(.diffReview) else {
                return .failure(
                    .unsupportedCommand(
                        command: String(describing: envelope.command),
                        required: .diffReview
                    )
                )
            }
            guard let commandHandler else {
                return .failure(.backendUnavailable(backend: "BridgePaneController"))
            }
            return commandHandler.handleDiffCommand(
                diffCommand,
                commandId: envelope.commandId,
                correlationId: envelope.correlationId
            )
        case .terminal, .browser, .editor, .plugin:
            return .failure(
                .unsupportedCommand(
                    command: String(describing: envelope.command),
                    required: requiredCapability(for: envelope.command)
                )
            )
        }
    }

    func subscribe() -> AsyncStream<PaneEventEnvelope> {
        let (stream, continuation) = AsyncStream.makeStream(of: PaneEventEnvelope.self)
        guard lifecycle != .terminated else {
            continuation.finish()
            return stream
        }

        let subscriberId = nextSubscriberId
        nextSubscriberId += 1
        subscribers[subscriberId] = continuation

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.subscribers.removeValue(forKey: subscriberId)
            }
        }

        return stream
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
        let activeSubscribers = Array(subscribers.values)
        subscribers.removeAll(keepingCapacity: true)
        for continuation in activeSubscribers {
            continuation.finish()
        }
        return []
    }

    func ingestBridgeEvent(
        _ event: PaneRuntimeEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        guard lifecycle != .terminated else {
            Self.logger.debug(
                "Dropped bridge event after termination for pane \(self.paneId.uuid.uuidString, privacy: .public): \(String(describing: event), privacy: .public)"
            )
            return
        }

        sequence += 1
        let envelope = PaneEventEnvelope(
            source: .pane(paneId),
            sourceFacets: metadata.facets,
            paneKind: metadata.contentType,
            seq: sequence,
            commandId: commandId,
            correlationId: correlationId,
            timestamp: envelopeClock.now,
            epoch: 0,
            event: event
        )
        replayBuffer.append(envelope)
        broadcast(envelope)
        Task { [paneEventBus] in
            await paneEventBus.post(envelope)
        }
    }

    func recordCommandAck(_ ack: CommandAck) {
        paneState.recordAck(ack)
    }

    func clearCommandAcks() {
        paneState.clearAcks()
    }

    func resetForControllerTeardown() {
        guard lifecycle != .terminated else { return }
        let activeSubscribers = Array(subscribers.values)
        subscribers.removeAll(keepingCapacity: true)
        for continuation in activeSubscribers {
            continuation.finish()
        }
        sequence = 0
        nextSubscriberId = 0
        lifecycle = .created
        clearCommandAcks()
    }

    private func broadcast(_ envelope: PaneEventEnvelope) {
        for continuation in subscribers.values {
            continuation.yield(envelope)
        }
    }

    private static func capabilities(for contentType: PaneContentType) -> Set<PaneCapability> {
        switch contentType {
        case .diff, .review:
            return [.diffReview]
        case .editor, .codeViewer:
            return [.editorActions]
        case .browser:
            return [.navigation]
        case .agent:
            return [.input]
        case .plugin(let kind):
            return [.plugin(kind)]
        case .terminal:
            return [.input]
        }
    }

    private func requiredCapability(for command: RuntimeCommand) -> PaneCapability {
        switch command {
        case .terminal:
            return .input
        case .browser:
            return .navigation
        case .diff:
            return .diffReview
        case .editor:
            return .editorActions
        case .plugin(let pluginCommand):
            return .plugin(String(describing: type(of: pluginCommand)))
        case .activate, .deactivate, .prepareForClose, .requestSnapshot:
            return .input
        }
    }
}
