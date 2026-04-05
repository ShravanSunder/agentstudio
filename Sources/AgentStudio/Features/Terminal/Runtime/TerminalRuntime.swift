import AppKit
import Foundation
import Observation
import os.log

@MainActor
@Observable
final class TerminalRuntime: BusPostingPaneRuntime {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "TerminalRuntime")

    let paneId: PaneId
    private(set) var metadata: PaneMetadata
    private(set) var lifecycle: PaneRuntimeLifecycle
    private(set) var commandProgress: ProgressState?
    private(set) var isReadOnly: Bool = false
    private(set) var isSecureInput: Bool = false
    private(set) var rendererHealthy: Bool = true
    private(set) var cellSize: NSSize = .zero
    private(set) var sizeConstraints: TerminalSizeConstraints?
    let capabilities: Set<PaneCapability>

    private let eventChannel: PaneRuntimeEventChannel

    init(
        paneId: PaneId,
        metadata: PaneMetadata,
        clock: ContinuousClock = ContinuousClock(),
        replayBuffer: EventReplayBuffer? = nil,
        paneEventBus: EventBus<RuntimeEnvelope> = PaneRuntimeEventBus.shared
    ) {
        self.paneId = paneId
        self.metadata = metadata
        self.lifecycle = .created
        self.commandProgress = nil
        self.capabilities = [.input, .resize, .search]
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
        case .terminal(let terminalCommand):
            if let requiredCapability = requiredCapability(for: terminalCommand),
                !capabilities.contains(requiredCapability)
            {
                return .failure(
                    .unsupportedCommand(
                        command: String(describing: envelope.command),
                        required: requiredCapability
                    )
                )
            }

            return dispatchTerminalCommand(terminalCommand, commandId: envelope.commandId)
        case .browser, .diff, .editor, .plugin:
            return .failure(
                .unsupportedCommand(
                    command: String(describing: envelope.command),
                    required: envelope.command.requiredCapability
                )
            )
        }
    }

    func subscribe() -> AsyncStream<RuntimeEnvelope> {
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

    func handleGhosttyEvent(
        _ event: GhosttyEvent,
        commandId: UUID? = nil,
        correlationId: UUID? = nil
    ) {
        guard lifecycle != .terminated else {
            Self.logger.debug(
                "Dropped terminal event after termination for pane \(self.paneId.uuid.uuidString, privacy: .public): \(String(describing: event), privacy: .public)"
            )
            return
        }

        switch event {
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
        case .titleChanged(let title):
            metadata.updateTitle(title)
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
        case .cwdChanged(let cwdPath):
            metadata.updateCWD(URL(fileURLWithPath: cwdPath))
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
        case .commandFinished, .bellRang, .scrollbarChanged, .unhandled:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
        case .progressReportUpdated(let progressState):
            commandProgress = progressState
        case .readOnlyChanged(let isReadOnly):
            self.isReadOnly = isReadOnly
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
        case .secureInputRequested(let mode):
            let resolvedValue = resolvedSecureInputValue(for: mode)
            isSecureInput = resolvedValue
            emit(
                .secureInputChanged(resolvedValue),
                commandId: commandId,
                correlationId: correlationId,
                persistForReplay: true
            )
        case .secureInputChanged:
            break
        case .rendererHealthChanged(let healthy):
            rendererHealthy = healthy
        case .cellSizeChanged(let size):
            cellSize = size
        case .initialSizeChanged:
            break
        case .sizeLimitChanged(let constraints):
            sizeConstraints = constraints
        case .promptTitleRequested, .desktopNotificationRequested:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
        case .openURLRequested, .undoRequested, .redoRequested, .copyTitleToClipboardRequested, .deferred:
            break
        }
    }

    private func resolvedSecureInputValue(for mode: SecureInputMode) -> Bool {
        switch mode {
        case .on:
            return true
        case .off:
            return false
        case .toggle:
            return !isSecureInput
        }
    }

    private func emit(
        _ event: GhosttyEvent,
        commandId: UUID?,
        correlationId: UUID?,
        persistForReplay: Bool
    ) {
        eventChannel.emit(
            paneId: paneId,
            metadata: metadata,
            paneKind: .terminal,
            commandId: commandId,
            correlationId: correlationId,
            event: .terminal(event),
            persistForReplay: persistForReplay
        )
    }

    private func requiredCapability(for command: TerminalCommand) -> PaneCapability? {
        switch command {
        case .sendInput, .clearScrollback:
            return .input
        case .resize:
            return .resize
        }
    }

    private func dispatchTerminalCommand(_ command: TerminalCommand, commandId: UUID) -> ActionResult {
        switch command {
        case .sendInput(let input):
            let dispatchResult = SurfaceManager.shared.sendInput(input, toPaneId: paneId.uuid)
            return mapSurfaceDispatchResult(dispatchResult, commandId: commandId, command: command)
        case .clearScrollback:
            let dispatchResult = SurfaceManager.shared.clearScrollback(forPaneId: paneId.uuid)
            return mapSurfaceDispatchResult(dispatchResult, commandId: commandId, command: command)
        case .resize(let cols, let rows):
            Self.logger.warning(
                "Rejected terminal resize command for pane \(self.paneId.uuid.uuidString, privacy: .public): cols=\(cols, privacy: .public) rows=\(rows, privacy: .public). Programmatic col/row resizing is not supported by embedded Ghostty surface API."
            )
            return .failure(
                .invalidPayload(
                    description: "Programmatic terminal resize by columns/rows is not supported by embedded Ghostty"
                )
            )
        }
    }

    private func mapSurfaceDispatchResult(
        _ result: Result<Void, SurfaceError>,
        commandId: UUID,
        command: TerminalCommand
    ) -> ActionResult {
        switch result {
        case .success:
            return .success(commandId: commandId)
        case .failure(let error):
            Self.logger.warning(
                "Terminal command dispatch failed for pane \(self.paneId.uuid.uuidString, privacy: .public) command=\(String(describing: command), privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return .failure(.backendUnavailable(backend: "SurfaceManager"))
        }
    }
}
