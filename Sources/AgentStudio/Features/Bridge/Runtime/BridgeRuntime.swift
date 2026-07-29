import AgentStudioCore
import Foundation
import Observation
import os.log

@MainActor
protocol BridgeRuntimeCommandHandling: AnyObject {
    func handleDiffCommand(
        _ command: DiffCommand,
        commandId: UUID,
        correlationId: UUID?
    ) async -> ActionResult
}

@MainActor
@Observable
package final class BridgeRuntime: BusPostingPaneRuntime {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "BridgeRuntime")

    package let paneId: PaneId
    package private(set) var metadata: PaneMetadata
    package private(set) var lifecycle: PaneRuntimeLifecycle
    package let capabilities: Set<PaneCapability>
    let paneState = PaneDomainState()
    weak var commandHandler: (any BridgeRuntimeCommandHandling)?

    private let eventChannel: PaneRuntimeEventChannel

    init(
        paneId: PaneId,
        metadata: PaneMetadata,
        commandHandler: (any BridgeRuntimeCommandHandling)? = nil,
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer? = nil,
        paneEventBus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared
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

    @discardableResult
    func transitionToReady() -> Bool {
        guard lifecycle == .created else {
            Self.logger.warning(
                "Rejected transitionToReady for pane \(self.paneId.uuid.uuidString, privacy: .public): lifecycle=\(String(describing: self.lifecycle), privacy: .public)"
            )
            return false
        }
        lifecycle = .ready
        return true
    }

    package func handleCommand(_ envelope: RuntimeCommandEnvelope) async -> ActionResult {
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
            return await commandHandler.handleDiffCommand(
                diffCommand,
                commandId: envelope.commandId,
                correlationId: envelope.correlationId
            )
        case .terminal, .browser, .editor, .plugin:
            return .failure(
                .unsupportedCommand(
                    command: String(describing: envelope.command),
                    required: envelope.command.requiredCapability
                )
            )
        }
    }

    package func subscribe() -> AsyncStream<RuntimeEnvelope> {
        eventChannel.subscribe(isTerminated: lifecycle == .terminated)
    }

    package func snapshot() -> PaneRuntimeSnapshot {
        eventChannel.snapshot(
            paneId: paneId,
            metadata: metadata,
            lifecycle: lifecycle,
            capabilities: capabilities
        )
    }

    package func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult {
        eventChannel.eventsSince(seq: seq)
    }

    package func shutdown(timeout _: Duration) async -> [UUID] {
        if lifecycle == .terminated {
            return []
        }
        lifecycle = .draining
        lifecycle = .terminated
        eventChannel.finishSubscribers()
        return []
    }

    package func ingestBridgeEvent(
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

    func resetForControllerTeardown() {
        guard lifecycle != .terminated else { return }
        eventChannel.finishSubscribers()
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
}
