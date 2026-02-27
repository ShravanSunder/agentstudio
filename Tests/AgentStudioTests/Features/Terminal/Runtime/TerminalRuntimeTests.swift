import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalRuntime lifecycle")
struct TerminalRuntimeTests {
    @Test("handleCommand rejects when lifecycle not ready")
    func rejectWhenNotReady() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        let commandEnvelope = makeEnvelope(command: .activate, paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        #expect(result == .failure(.runtimeNotReady(lifecycle: .created)))
    }

    @Test("handleCommand succeeds after ready transition")
    func succeedsWhenReady() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        let commandEnvelope = makeEnvelope(command: .activate, paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        switch result {
        case .success(let commandId):
            #expect(commandId == commandEnvelope.commandId)
        default:
            Issue.record("Expected success result for ready runtime")
        }
    }

    @Test("terminal commands fail when no surface is attached")
    func terminalCommandFailsWithoutSurface() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        let commandEnvelope = makeEnvelope(command: .terminal(.clearScrollback), paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        #expect(result == .failure(.backendUnavailable(backend: "SurfaceManager")))
    }

    @Test("terminal sendInput succeeds with injected surface dispatcher")
    func terminalSendInputUsesInjectedDispatcher() async {
        let dispatcher = MockTerminalSurfaceDispatcher()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime"),
            surfaceDispatch: dispatcher
        )
        runtime.transitionToReady()

        let commandEnvelope = makeEnvelope(command: .terminal(.sendInput("echo hi")), paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)

        #expect(result == .success(commandId: commandEnvelope.commandId))
        #expect(dispatcher.sentInputs == ["echo hi"])
        #expect(dispatcher.targetPaneIds == [runtime.paneId.uuid])
    }

    @Test("resize command is rejected as unsupported capability")
    func resizeCommandRejectedAsUnsupported() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        let commandEnvelope = makeEnvelope(command: .terminal(.resize(cols: 80, rows: 24)), paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)

        #expect(
            result
                == .failure(
                    .unsupportedCommand(
                        command: String(describing: commandEnvelope.command),
                        required: .resize
                    )
                )
        )
    }

    @Test("non-terminal command families are rejected as unsupported")
    func rejectsUnsupportedCommandFamilies() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        let browserCommand = makeEnvelope(
            command: .browser(.reload(hard: false)),
            paneId: runtime.paneId
        )
        let result = await runtime.handleCommand(browserCommand)

        switch result {
        case .failure(.unsupportedCommand(let command, let requiredCapability)):
            #expect(command.contains("browser"))
            #expect(requiredCapability == .input)
        default:
            Issue.record("Expected unsupported command failure for browser command")
        }
    }

    @Test("prepareForClose transitions runtime to draining and rejects follow-up command")
    func prepareForCloseTransitionsToDraining() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        let closeEnvelope = makeEnvelope(command: .prepareForClose, paneId: runtime.paneId)
        let closeResult = await runtime.handleCommand(closeEnvelope)
        #expect(closeResult == .success(commandId: closeEnvelope.commandId))
        #expect(runtime.lifecycle == .draining)

        let followupEnvelope = makeEnvelope(command: .terminal(.sendInput("echo hi")), paneId: runtime.paneId)
        let followupResult = await runtime.handleCommand(followupEnvelope)
        #expect(followupResult == .failure(.runtimeNotReady(lifecycle: .draining)))
    }

    @Test("eventsSince replays emitted events")
    func replaysEvents() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        runtime.handleGhosttyEvent(.bellRang)
        runtime.handleGhosttyEvent(.titleChanged("Build"))

        let replay = await runtime.eventsSince(seq: 0)

        #expect(!replay.gapDetected)
        #expect(replay.events.count == 2)
        #expect(replay.nextSeq == 2)
    }

    @Test("events are ignored before runtime ready transition")
    func eventsIgnoredBeforeReady() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )

        runtime.handleGhosttyEvent(.titleChanged("ShouldNotApply"))
        let replay = await runtime.eventsSince(seq: 0)

        #expect(runtime.metadata.title == "Runtime")
        #expect(replay.events.isEmpty)
        #expect(replay.nextSeq == 0)
    }

    @Test("handleGhosttyEvent updates metadata and preserves envelope identifiers")
    func ghosttyEventMetadataAndEnvelope() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        let commandId = UUID()
        let correlationId = UUID()
        runtime.handleGhosttyEvent(.titleChanged("Updated"), commandId: commandId, correlationId: correlationId)
        runtime.handleGhosttyEvent(.cwdChanged("/tmp"), commandId: commandId, correlationId: correlationId)

        #expect(runtime.metadata.title == "Updated")
        #expect(runtime.metadata.cwd == URL(fileURLWithPath: "/tmp"))

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.count == 2)
        #expect(replay.events.allSatisfy { $0.commandId == commandId })
        #expect(replay.events.allSatisfy { $0.correlationId == correlationId })
        #expect(replay.events.last?.sourceFacets.cwd == URL(fileURLWithPath: "/tmp"))
    }

    @Test("eventsSince reports gap after replay eviction")
    func replayGapAfterEviction() async {
        let replayBuffer = EventReplayBuffer(config: .init(maxEvents: 2, maxBytes: 10_000, ttl: .seconds(300)))
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime"),
            replayBuffer: replayBuffer
        )
        runtime.transitionToReady()
        runtime.handleGhosttyEvent(.bellRang)
        runtime.handleGhosttyEvent(.bellRang)
        runtime.handleGhosttyEvent(.bellRang)

        let replay = await runtime.eventsSince(seq: 0)

        #expect(replay.gapDetected)
        #expect(replay.events.count == 2)
        #expect(replay.events.first?.seq == 2)
    }

    @Test("action events emit to subscribers but are not persisted in replay")
    func actionEventsBypassReplayBuffer() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        var iterator = runtime.subscribe().makeAsyncIterator()

        runtime.handleGhosttyEvent(.newTab)
        let streamedEnvelope = await iterator.next()

        guard let streamedEnvelope else {
            Issue.record("Expected streamed envelope for action event")
            return
        }
        guard case .terminal(.newTab) = streamedEnvelope.event else {
            Issue.record("Expected streamed newTab runtime event")
            return
        }

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.isEmpty)
        #expect(replay.nextSeq == 0)
        #expect(!replay.gapDetected)
    }

    @Test("subscribe returns independent streams and broadcasts events to all subscribers")
    func subscribeBroadcastsToMultipleSubscribers() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        var firstIterator = runtime.subscribe().makeAsyncIterator()
        var secondIterator = runtime.subscribe().makeAsyncIterator()

        runtime.handleGhosttyEvent(.bellRang)

        let firstEvent = await firstIterator.next()
        let secondEvent = await secondIterator.next()

        #expect(firstEvent?.seq == 1)
        #expect(secondEvent?.seq == 1)

        guard let firstEvent, let secondEvent else {
            Issue.record("Expected both subscribers to receive runtime event")
            return
        }

        guard case .terminal(.bellRang) = firstEvent.event else {
            Issue.record("Expected bellRang terminal event for first subscriber")
            return
        }
        guard case .terminal(.bellRang) = secondEvent.event else {
            Issue.record("Expected bellRang terminal event for second subscriber")
            return
        }
    }

    @Test("shutdown finishes event stream")
    func shutdownFinishesEventStream() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        var iterator = runtime.subscribe().makeAsyncIterator()

        _ = await runtime.shutdown(timeout: .seconds(1))
        let nextEvent = await iterator.next()

        #expect(runtime.lifecycle == .terminated)
        #expect(nextEvent == nil)
    }

    @Test("commands are rejected after shutdown")
    func rejectCommandsAfterShutdown() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        _ = await runtime.shutdown(timeout: .seconds(1))

        let commandEnvelope = makeEnvelope(command: .activate, paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)

        #expect(result == .failure(.runtimeNotReady(lifecycle: .terminated)))
    }

    private func makeEnvelope(command: RuntimeCommand, paneId: PaneId) -> RuntimeCommandEnvelope {
        let clock = ContinuousClock()
        return RuntimeCommandEnvelope(
            commandId: UUID(),
            correlationId: nil,
            targetPaneId: paneId,
            command: command,
            timestamp: clock.now
        )
    }
}

@MainActor
private final class MockTerminalSurfaceDispatcher: TerminalSurfaceDispatching {
    private(set) var sentInputs: [String] = []
    private(set) var targetPaneIds: [UUID] = []

    func sendInput(_ input: String, toPaneId paneId: UUID) -> Result<Void, SurfaceError> {
        sentInputs.append(input)
        targetPaneIds.append(paneId)
        return .success(())
    }

    func clearScrollback(forPaneId paneId: UUID) -> Result<Void, SurfaceError> {
        targetPaneIds.append(paneId)
        return .success(())
    }
}
