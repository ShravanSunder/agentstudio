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
    private(set) var scrollbarState: ScrollbarState?
    private(set) var searchState: TerminalSearchState?
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
        self.scrollbarState = nil
        self.searchState = nil
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

        if handleGhosttyStructuralEvent(event, commandId: commandId, correlationId: correlationId) { return }
        if handleGhosttyStateEvent(event, commandId: commandId, correlationId: correlationId) { return }
        if handleGhosttyConfigurationEvent(event, commandId: commandId, correlationId: correlationId) { return }
        if handleGhosttySearchEvent(event, commandId: commandId, correlationId: correlationId) { return }
        if handleGhosttyRequestEvent(event, commandId: commandId, correlationId: correlationId) { return }
    }

    private func handleGhosttyStructuralEvent(
        _ event: GhosttyEvent,
        commandId: UUID?,
        correlationId: UUID?
    ) -> Bool {
        switch event {
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .titleChanged(let title), .tabTitleChanged(let title):
            metadata.updateTitle(title)
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .cwdChanged(let cwdPath):
            metadata.updateCWD(URL(fileURLWithPath: cwdPath))
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .commandFinished, .bellRang, .unhandled:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        default:
            return false
        }
    }

    private func handleGhosttyStateEvent(
        _ event: GhosttyEvent,
        commandId: UUID?,
        correlationId: UUID?
    ) -> Bool {
        switch event {
        case .scrollbarChanged(let scrollbarState):
            self.scrollbarState = scrollbarState
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .progressReportUpdated(let progressState):
            commandProgress = progressState
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .readOnlyChanged(let isReadOnly):
            self.isReadOnly = isReadOnly
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .secureInputRequested(let mode):
            let resolvedValue = resolvedSecureInputValue(for: mode)
            isSecureInput = resolvedValue
            emit(
                .secureInputChanged(resolvedValue),
                commandId: commandId,
                correlationId: correlationId,
                persistForReplay: true
            )
            return true
        case .secureInputChanged:
            return true
        case .rendererHealthChanged(let healthy):
            rendererHealthy = healthy
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .cellSizeChanged(let size):
            cellSize = size
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .initialSizeChanged:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .sizeLimitChanged(let constraints):
            sizeConstraints = constraints
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        default:
            return false
        }
    }

    private func handleGhosttyConfigurationEvent(
        _ event: GhosttyEvent,
        commandId: UUID?,
        correlationId: UUID?
    ) -> Bool {
        switch event {
        case .mouseShapeChanged, .mouseVisibilityChanged, .mouseLinkHovered, .keySequenceChanged,
            .keyTableChanged:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .colorChanged, .configChanged:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .configReloadRequested:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        default:
            return false
        }
    }

    private func handleGhosttySearchEvent(
        _ event: GhosttyEvent,
        commandId: UUID?,
        correlationId: UUID?
    ) -> Bool {
        switch event {
        case .searchStarted(let query):
            searchState = TerminalSearchState(query: query ?? "", totalMatches: nil, selectedMatchIndex: nil)
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .searchEnded:
            searchState = nil
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .searchMatchesUpdated(let totalMatches):
            if searchState == nil {
                searchState = TerminalSearchState(query: "", totalMatches: totalMatches, selectedMatchIndex: nil)
            } else {
                searchState?.totalMatches = totalMatches
            }
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .searchSelectionChanged(let selectedMatchIndex):
            if searchState == nil {
                searchState = TerminalSearchState(
                    query: "",
                    totalMatches: nil,
                    selectedMatchIndex: selectedMatchIndex
                )
            } else {
                searchState?.selectedMatchIndex = selectedMatchIndex
            }
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        default:
            return false
        }
    }

    private func handleGhosttyRequestEvent(
        _ event: GhosttyEvent,
        commandId: UUID?,
        correlationId: UUID?
    ) -> Bool {
        switch event {
        case .promptTitleRequested, .desktopNotificationRequested:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .openURLRequested, .undoRequested, .redoRequested, .copyTitleToClipboardRequested:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .deferred:
            return true
        default:
            return false
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
