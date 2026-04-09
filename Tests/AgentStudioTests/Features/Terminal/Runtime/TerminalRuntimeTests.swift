import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalRuntime lifecycle")
struct TerminalRuntimeTests {
    @Test("handleCommand rejects when lifecycle not ready")
    func rejectWhenNotReady() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        let commandEnvelope = makeEnvelope(command: .activate, paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        #expect(result == .failure(.runtimeNotReady(lifecycle: .created)))
    }

    @Test("handleCommand succeeds after ready transition")
    func succeedsWhenReady() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
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
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        let commandEnvelope = makeEnvelope(command: .terminal(.clearScrollback), paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        #expect(result == .failure(.backendUnavailable(backend: "SurfaceManager")))
    }

    @Test("non-terminal command families are rejected as unsupported")
    func rejectsUnsupportedCommandFamilies() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
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
            #expect(requiredCapability == browserCommand.command.requiredCapability)
        default:
            Issue.record("Expected unsupported command failure for browser command")
        }
    }

    @Test("prepareForClose transitions runtime to draining and rejects follow-up command")
    func prepareForCloseTransitionsToDraining() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
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
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        runtime.handleGhosttyEvent(.bellRang)
        runtime.handleGhosttyEvent(.titleChanged("Build"))

        let replay = await runtime.eventsSince(seq: 0)

        #expect(!replay.gapDetected)
        #expect(replay.events.count == 2)
        #expect(replay.nextSeq == 2)
    }

    @Test("handleGhosttyEvent updates metadata and preserves envelope identifiers")
    func ghosttyEventMetadataAndEnvelope() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
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
        guard
            let lastEvent = replay.events.last,
            case .pane(let paneEnvelope) = lastEvent,
            case .terminal(.cwdChanged(let cwdPath)) = paneEnvelope.event
        else {
            Issue.record("Expected replay to include terminal cwdChanged event")
            return
        }
        #expect(URL(fileURLWithPath: cwdPath) == URL(fileURLWithPath: "/tmp"))
    }

    @Test("eventsSince reports gap after replay eviction")
    func replayGapAfterEviction() async {
        let replayBuffer = EventReplayBuffer(config: .init(maxEvents: 2, maxBytes: 10_000, ttl: .seconds(300)))
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
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
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        var iterator = runtime.subscribe().makeAsyncIterator()

        runtime.handleGhosttyEvent(.newTab)
        let streamedEnvelope = await iterator.next()

        guard let streamedEnvelope else {
            Issue.record("Expected streamed envelope for action event")
            return
        }
        guard
            case .pane(let paneEnvelope) = streamedEnvelope,
            case .terminal(.newTab) = paneEnvelope.event
        else {
            Issue.record("Expected streamed newTab runtime event")
            return
        }

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.isEmpty)
        #expect(replay.nextSeq == 0)
        #expect(!replay.gapDetected)
    }

    @Test("stateful terminal metadata events update observable state and post replayable bus events")
    func statefulTerminalMetadataEvents_postReplayableBusEvents() async {
        let harness = EventBusHarness<RuntimeEnvelope>()
        let subscriber = await harness.makeSubscriber()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
            paneEventBus: harness.bus
        )
        runtime.transitionToReady()

        let expectedProgress = ProgressState(kind: .set, percent: 50)
        let expectedCellSize = NSSize(width: 8, height: 16)
        let expectedSizeConstraints = TerminalSizeConstraints(
            minWidth: 640,
            minHeight: 480,
            maxWidth: 1440,
            maxHeight: 900
        )

        runtime.handleGhosttyEvent(.progressReportUpdated(expectedProgress))
        runtime.handleGhosttyEvent(.rendererHealthChanged(healthy: false))
        runtime.handleGhosttyEvent(.cellSizeChanged(expectedCellSize))
        runtime.handleGhosttyEvent(.sizeLimitChanged(expectedSizeConstraints))

        #expect(runtime.commandProgress == expectedProgress)
        #expect(!runtime.rendererHealthy)
        #expect(runtime.cellSize == expectedCellSize)
        #expect(runtime.sizeConstraints == expectedSizeConstraints)

        await assertEventuallyAsync(
            "subscriber should receive replayable state events",
            maxTurns: 5000
        ) {
            await subscriber.snapshot().count == 4
        }

        let streamedEvents = RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot())
        #expect(streamedEvents.map(\.seq) == [1, 2, 3, 4])
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.progressReportUpdated(let progress)) = record.event else { return false }
                return progress == expectedProgress
            }))
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.rendererHealthChanged(let healthy)) = record.event else { return false }
                return healthy == false
            }))
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.cellSizeChanged(let size)) = record.event else { return false }
                return size == expectedCellSize
            }))
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.sizeLimitChanged(let constraints)) = record.event else { return false }
                return constraints == expectedSizeConstraints
            }))

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.count == 4)

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("readOnly updates observable state and posts replayable event")
    func readOnly_postsReplayableBusEvent() async {
        let paneEventBus = EventBus<RuntimeEnvelope>()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
            paneEventBus: paneEventBus
        )
        runtime.transitionToReady()
        let stream = await paneEventBus.subscribe()
        var iterator = stream.makeAsyncIterator()

        runtime.handleGhosttyEvent(.readOnlyChanged(true))

        #expect(runtime.isReadOnly)
        guard
            let busEnvelope = await iterator.next(),
            case .pane(let paneEnvelope) = busEnvelope,
            case .terminal(.readOnlyChanged(let isReadOnly)) = paneEnvelope.event
        else {
            Issue.record("Expected readOnlyChanged event on pane bus")
            return
        }
        #expect(isReadOnly)

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.count == 1)
    }

    @Test("promptTitle posts to bus but is not replayed")
    func promptTitle_postsNonReplayableBusEvent() async {
        let paneEventBus = EventBus<RuntimeEnvelope>()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
            paneEventBus: paneEventBus
        )
        runtime.transitionToReady()
        let stream = await paneEventBus.subscribe()
        var iterator = stream.makeAsyncIterator()

        runtime.handleGhosttyEvent(.promptTitleRequested(scope: .surface))
        guard
            let busEnvelope = await iterator.next(),
            case .pane(let paneEnvelope) = busEnvelope,
            case .terminal(.promptTitleRequested(let scope)) = paneEnvelope.event
        else {
            Issue.record("Expected promptTitleRequested event on pane bus")
            return
        }
        #expect(scope == .surface)

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.isEmpty)
    }

    @Test("non-replayable terminal request events still post to the bus")
    func nonReplayableTerminalRequestEvents_postWithoutReplay() async {
        let harness = EventBusHarness<RuntimeEnvelope>()
        let subscriber = await harness.makeSubscriber()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
            paneEventBus: harness.bus
        )
        runtime.transitionToReady()

        let initialSize = NSSize(width: 80, height: 25)
        runtime.handleGhosttyEvent(.openURLRequested(url: "https://example.com", kind: .text))
        runtime.handleGhosttyEvent(.undoRequested)
        runtime.handleGhosttyEvent(.redoRequested)
        runtime.handleGhosttyEvent(.copyTitleToClipboardRequested)
        runtime.handleGhosttyEvent(.initialSizeChanged(initialSize))

        await assertEventuallyAsync(
            "subscriber should receive non-replayable request events",
            maxTurns: 5000
        ) {
            await subscriber.snapshot().count == 5
        }

        let streamedEvents = RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot())
        #expect(streamedEvents.map(\.seq) == [1, 2, 3, 4, 5])
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.openURLRequested(let url, let kind)) = record.event else { return false }
                return url == "https://example.com" && kind == .text
            }))
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.undoRequested) = record.event else { return false }
                return true
            }))
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.redoRequested) = record.event else { return false }
                return true
            }))
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.copyTitleToClipboardRequested) = record.event else { return false }
                return true
            }))
        #expect(
            streamedEvents.contains(where: { record in
                guard case .terminal(.initialSizeChanged(let size)) = record.event else { return false }
                return size == initialSize
            }))

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.isEmpty)

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("promoted deferred state events update runtime state and remain replayable")
    func promotedDeferredStateEvents_postReplayableBusEvents() async {
        let harness = EventBusHarness<RuntimeEnvelope>()
        let subscriber = await harness.makeSubscriber()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
            paneEventBus: harness.bus
        )
        runtime.transitionToReady()

        let scrollbar = ScrollbarState(top: 5, bottom: 15, total: 100)
        let colorChange = TerminalColorChange(kind: .foreground, red: 1, green: 2, blue: 3)

        runtime.handleGhosttyEvent(.tabTitleChanged("Build"))
        runtime.handleGhosttyEvent(.scrollbarChanged(scrollbar))
        runtime.handleGhosttyEvent(.searchStarted(query: "needle"))
        runtime.handleGhosttyEvent(.searchMatchesUpdated(totalMatches: 4))
        runtime.handleGhosttyEvent(.searchSelectionChanged(selectedMatchIndex: 2))
        runtime.handleGhosttyEvent(.colorChanged(colorChange))
        runtime.handleGhosttyEvent(.configChanged)

        #expect(runtime.metadata.title == "Build")
        #expect(runtime.scrollbarState == scrollbar)
        #expect(runtime.searchState == TerminalSearchState(query: "needle", totalMatches: 4, selectedMatchIndex: 2))

        await assertEventuallyAsync(
            "subscriber should receive promoted deferred replayable events",
            maxTurns: 5000
        ) {
            await subscriber.snapshot().count == 7
        }

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.count == 7)

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("searchEnded clears state and remains replayable")
    func searchEnded_clearsStateAndReplays() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()

        runtime.handleGhosttyEvent(.searchStarted(query: "needle"))
        runtime.handleGhosttyEvent(.searchEnded)

        #expect(runtime.searchState == nil)

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.count == 2)
        guard
            let lastEvent = replay.events.last,
            case .pane(let envelope) = lastEvent,
            case .terminal(.searchEnded) = envelope.event
        else {
            Issue.record("Expected searchEnded in replay")
            return
        }
    }

    @Test("promoted deferred transient events post to bus without replay")
    func promotedDeferredTransientEvents_postWithoutReplay() async {
        let harness = EventBusHarness<RuntimeEnvelope>()
        let subscriber = await harness.makeSubscriber()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
            paneEventBus: harness.bus
        )
        runtime.transitionToReady()

        runtime.handleGhosttyEvent(.mouseShapeChanged(shapeRawValue: 1))
        runtime.handleGhosttyEvent(.mouseVisibilityChanged(isVisible: false))
        runtime.handleGhosttyEvent(.mouseLinkHovered(url: "https://example.com"))
        runtime.handleGhosttyEvent(
            .keySequenceChanged(
                active: true,
                trigger: GhosttyInputTrigger(tag: .unicode, key: 97, modifiers: 0)
            )
        )
        runtime.handleGhosttyEvent(.keyTableChanged(.activate(name: "copy-mode")))
        runtime.handleGhosttyEvent(.configReloadRequested(soft: true))

        await assertEventuallyAsync(
            "subscriber should receive promoted deferred transient events",
            maxTurns: 5000
        ) {
            await subscriber.snapshot().count == 6
        }

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.isEmpty)

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }

    @Test("deferred events stay out of bus and replay")
    func deferredEvent_doesNotPostOrReplay() async {
        let paneEventBus = EventBus<RuntimeEnvelope>()
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime"),
            paneEventBus: paneEventBus
        )
        runtime.transitionToReady()

        runtime.handleGhosttyEvent(.deferred(tag: UInt32(GHOSTTY_ACTION_RENDER.rawValue)))

        let replay = await runtime.eventsSince(seq: 0)
        #expect(replay.events.isEmpty)

        let busEvent = await paneEventBus.waitForFirst(timeout: .milliseconds(100)) { envelope in
            envelope
        }
        #expect(busEvent == nil)
    }

    @Test("subscribe returns independent streams and broadcasts events to all subscribers")
    func subscribeBroadcastsToMultipleSubscribers() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
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

        guard
            case .pane(let firstPaneEnvelope) = firstEvent,
            case .terminal(.bellRang) = firstPaneEnvelope.event
        else {
            Issue.record("Expected bellRang terminal event for first subscriber")
            return
        }
        guard
            case .pane(let secondPaneEnvelope) = secondEvent,
            case .terminal(.bellRang) = secondPaneEnvelope.event
        else {
            Issue.record("Expected bellRang terminal event for second subscriber")
            return
        }
    }

    @Test("shutdown finishes event stream")
    func shutdownFinishesEventStream() async {
        let runtime = TerminalRuntime(
            paneId: PaneId(),
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
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
            metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
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
