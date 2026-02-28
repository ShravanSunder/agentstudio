import Foundation
import Observation
import os.log

@MainActor
protocol WebviewRuntimeCommandHandling: AnyObject {
    func handleBrowserCommand(_ command: BrowserCommand) -> Bool
}

@MainActor
@Observable
final class WebviewRuntime: BusPostingPaneRuntime {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WebviewRuntime")

    let paneId: PaneId
    private(set) var metadata: PaneMetadata
    private(set) var lifecycle: PaneRuntimeLifecycle
    let capabilities: Set<PaneCapability>
    weak var commandHandler: (any WebviewRuntimeCommandHandling)?

    private let envelopeClock: ContinuousClock
    private let replayBuffer: EventReplayBuffer
    private let paneEventBus: EventBus<PaneEventEnvelope>
    private var sequence: UInt64 = 0
    private var nextSubscriberId: UInt64 = 0
    private var subscribers: [UInt64: AsyncStream<PaneEventEnvelope>.Continuation] = [:]

    init(
        paneId: PaneId,
        metadata: PaneMetadata,
        commandHandler: (any WebviewRuntimeCommandHandling)? = nil,
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer? = nil,
        paneEventBus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared
    ) {
        self.paneId = paneId
        self.metadata = metadata
        self.lifecycle = .created
        self.capabilities = [.navigation]
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
        case .browser(let browserCommand):
            guard capabilities.contains(.navigation) else {
                return .failure(
                    .unsupportedCommand(
                        command: String(describing: envelope.command),
                        required: .navigation
                    )
                )
            }
            guard let commandHandler else {
                return .failure(.backendUnavailable(backend: "WebviewPaneController"))
            }
            let handled = commandHandler.handleBrowserCommand(browserCommand)
            return handled
                ? .success(commandId: envelope.commandId)
                : .failure(.invalidPayload(description: "Webview browser command could not be handled"))
        case .terminal, .diff, .editor, .plugin:
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

    func ingestBrowserEvent(
        _ event: BrowserEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        guard lifecycle != .terminated else {
            Self.logger.debug(
                "Dropped browser event after termination for pane \(self.paneId.uuid.uuidString, privacy: .public): \(String(describing: event), privacy: .public)"
            )
            return
        }

        sequence += 1
        let envelope = PaneEventEnvelope(
            source: .pane(paneId),
            sourceFacets: metadata.facets,
            paneKind: .browser,
            seq: sequence,
            commandId: commandId,
            correlationId: correlationId,
            timestamp: envelopeClock.now,
            epoch: 0,
            event: .browser(event)
        )
        replayBuffer.append(envelope)
        broadcast(envelope)
        Task { [paneEventBus] in
            await paneEventBus.post(envelope)
        }
    }

    private func broadcast(_ envelope: PaneEventEnvelope) {
        for continuation in subscribers.values {
            continuation.yield(envelope)
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
            return .navigation
        }
    }
}
