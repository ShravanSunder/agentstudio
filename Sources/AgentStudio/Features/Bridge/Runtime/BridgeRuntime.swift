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

    private let eventChannel: PaneRuntimeEventChannel

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
        self.eventChannel = PaneRuntimeEventChannel(
            clock: clock,
            replayBuffer: replayBuffer ?? EventReplayBuffer(),
            paneEventBus: paneEventBus
        )
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
        eventChannel.subscribe(isTerminated: lifecycle == .terminated)
    }

    func snapshot() -> PaneRuntimeSnapshot {
        eventChannel.snapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities
        )
    }

    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        eventChannel.eventsSince(seq: seq)
    }

    func shutdown(timeout _: Duration) async -> [UUID] {
        if lifecycle == .terminated {
            return []
        }
        lifecycle = .draining
        lifecycle = .terminated
        eventChannel.finishSubscribers()
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

        eventChannel.emit(
            paneId: paneId,
            metadata: metadata,
            paneKind: metadata.contentType,
            commandId: commandId,
            correlationId: correlationId,
            event: event
        )
    }

    func recordCommandAck(_ ack: CommandAck) {
        paneState.recordAck(ack)
    }

    func clearCommandAcks() {
        paneState.clearAcks()
    }

    func resetForControllerTeardown() {
        guard lifecycle != .terminated else { return }
        eventChannel.finishSubscribers()
        clearCommandAcks()
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
