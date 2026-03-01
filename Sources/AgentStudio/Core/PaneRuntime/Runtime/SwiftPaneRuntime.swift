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

    private let eventChannel: PaneRuntimeEventChannel

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
        case .editor(let editorCommand):
            return await handleEditorCommand(
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

    @discardableResult
    func preloadFile(path: String, correlationId: UUID? = nil) async -> Bool {
        guard lifecycle == .ready else {
            Self.logger.debug(
                "Ignored preloadFile for pane \(self.paneId.uuid.uuidString, privacy: .public): lifecycle=\(String(describing: self.lifecycle), privacy: .public)"
            )
            return false
        }
        do {
            try await loadFile(path: path)
            emitEditorEvent(
                .fileOpened(path: path, language: languageIdentifier(for: path)),
                commandId: nil,
                correlationId: correlationId
            )
            return true
        } catch {
            Self.logger.warning(
                "Failed preload open for pane \(self.paneId.uuid.uuidString, privacy: .public) path=\(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func handleEditorCommand(
        _ command: EditorCommand,
        commandId: UUID,
        correlationId: UUID?
    ) async -> ActionResult {
        switch command {
        case .openFile(let path, _, _):
            guard await preloadFile(path: path, correlationId: correlationId) else {
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
                try await loadFile(path: openedFilePath)
                emitEditorEvent(
                    .fileOpened(path: openedFilePath, language: languageIdentifier(for: openedFilePath)),
                    commandId: commandId,
                    correlationId: correlationId
                )
                return .success(commandId: commandId)
            } catch {
                return .failure(
                    .invalidPayload(
                        description:
                            "Failed to revert file at path: \(openedFilePath). Error: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    private func loadFile(path: String) async throws {
        let fileURL = URL(fileURLWithPath: path)
        let text = try await Self.readFileContents(path: path)
        displayedText = text
        openedFilePath = path
        metadata.updateTitle(fileURL.lastPathComponent)
        metadata.updateCWD(fileURL.deletingLastPathComponent())
    }

    // Swift 6.2: explicit off-actor file I/O boundary for large files.
    @concurrent
    nonisolated private static func readFileContents(path: String) async throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    private func emitEditorEvent(
        _ editorEvent: EditorEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        guard lifecycle != .terminated else {
            return
        }

        eventChannel.emit(
            paneId: paneId,
            metadata: metadata,
            paneKind: metadata.contentType,
            commandId: commandId,
            correlationId: correlationId,
            event: .editor(editorEvent)
        )
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
