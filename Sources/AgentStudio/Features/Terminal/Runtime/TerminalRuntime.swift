import Foundation
import Observation
import os.log

@MainActor
@Observable
final class TerminalRuntime: PaneRuntime {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "TerminalRuntime")

    let paneId: PaneId
    private(set) var metadata: PaneMetadata
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
        guard lifecycle != .terminated else {
            Self.logger.debug(
                "Dropped terminal event after termination for pane \(self.paneId.uuid.uuidString, privacy: .public): \(String(describing: event), privacy: .public)"
            )
            return
        }

        switch event {
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom:
            break
        case .titleChanged(let title):
            metadata.updateTitle(title)
        case .cwdChanged(let cwdPath):
            metadata.updateCWD(URL(fileURLWithPath: cwdPath))
        case .commandFinished, .bellRang, .scrollbarChanged, .unhandled:
            break
        }

        sequence += 1
        let envelope = PaneEventEnvelope(
            source: .pane(paneId),
            sourceFacets: metadata.facets,
            paneKind: .terminal,
            seq: sequence,
            commandId: commandId,
            correlationId: correlationId,
            timestamp: envelopeClock.now,
            epoch: 0,
            event: .terminal(event)
        )
        if shouldPersistForReplay(event) {
            replayBuffer.append(envelope)
        }
        eventContinuation.yield(envelope)
    }

    private func shouldPersistForReplay(_ event: GhosttyEvent) -> Bool {
        switch event {
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom:
            return false
        case .titleChanged, .cwdChanged, .commandFinished, .bellRang, .scrollbarChanged, .unhandled:
            return true
        }
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
