import Foundation
import Observation
import os.log

@MainActor
@Observable
final class SwiftPaneRuntime: BusPostingPaneRuntime {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "SwiftPaneRuntime")

    let paneId: PaneId
    private(set) var metadata: PaneMetadata
    private(set) var lifecycle: PaneRuntimeLifecycle
    let capabilities: Set<PaneCapability>

    private(set) var displayedText: String
    private(set) var openedFilePath: String?

    private let envelopeClock: ContinuousClock
    private let replayBuffer: EventReplayBuffer
    private let paneEventBus: EventBus<PaneEventEnvelope>
    private var sequence: UInt64 = 0
    private var nextSubscriberId: UInt64 = 0
    private var subscribers: [UInt64: AsyncStream<PaneEventEnvelope>.Continuation] = [:]

    init(
        paneId: PaneId,
        metadata: PaneMetadata,
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer? = nil,
        paneEventBus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared
    ) {
        self.paneId = paneId
        self.metadata = metadata
        self.lifecycle = .created
        self.capabilities = [.editorActions]
        self.displayedText = ""
        self.openedFilePath = nil
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
        case .editor(let editorCommand):
            return handleEditorCommand(
                editorCommand,
                commandId: envelope.commandId,
                correlationId: envelope.correlationId
            )
        case .terminal, .browser, .diff, .plugin:
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

    @discardableResult
    func preloadFile(path: String, correlationId: UUID? = nil) -> Bool {
        guard lifecycle != .terminated else { return false }
        do {
            try loadFile(path: path)
            emitEditorEvent(
                .fileOpened(path: path, language: languageIdentifier(for: path)),
                commandId: nil,
                correlationId: correlationId
            )
            return true
        } catch {
            Self.logger.warning(
                "Failed preload open for pane \(self.paneId.uuid.uuidString, privacy: .public) path=\(path, privacy: .public)"
            )
            return false
        }
    }

    private func handleEditorCommand(
        _ command: EditorCommand,
        commandId: UUID,
        correlationId: UUID?
    ) -> ActionResult {
        switch command {
        case .openFile(let path, _, _):
            guard preloadFile(path: path, correlationId: correlationId) else {
                return .failure(.invalidPayload(description: "Failed to open file at path: \(path)"))
            }
            return .success(commandId: commandId)
        case .save:
            guard let openedFilePath else {
                return .failure(.invalidPayload(description: "Cannot save before opening a file"))
            }
            emitEditorEvent(
                .contentSaved(path: openedFilePath),
                commandId: commandId,
                correlationId: correlationId
            )
            return .success(commandId: commandId)
        case .revert:
            guard let openedFilePath else {
                return .failure(.invalidPayload(description: "Cannot revert before opening a file"))
            }

            do {
                try loadFile(path: openedFilePath)
                emitEditorEvent(
                    .fileOpened(path: openedFilePath, language: languageIdentifier(for: openedFilePath)),
                    commandId: commandId,
                    correlationId: correlationId
                )
                return .success(commandId: commandId)
            } catch {
                return .failure(.invalidPayload(description: "Failed to revert file at path: \(openedFilePath)"))
            }
        }
    }

    private func loadFile(path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        displayedText = text
        openedFilePath = path
        metadata.updateTitle(fileURL.lastPathComponent)
        metadata.updateCWD(fileURL.deletingLastPathComponent())
    }

    private func emitEditorEvent(
        _ editorEvent: EditorEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        guard lifecycle != .terminated else {
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
            event: .editor(editorEvent)
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
            return .editorActions
        }
    }

    private func languageIdentifier(for path: String) -> String? {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return fileExtension.isEmpty ? nil : fileExtension
    }
}
