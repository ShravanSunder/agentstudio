import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalRuntime lifecycle")
struct TerminalRuntimeTests {
    @Test("handleCommand rejects when lifecycle not ready")
    func rejectWhenNotReady() async {
        let runtime = TerminalRuntime(
            paneId: UUID(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        let commandEnvelope = makeEnvelope(command: .activate, paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        #expect(result == .failure(.runtimeNotReady(lifecycle: .created)))
    }

    @Test("handleCommand succeeds after ready transition")
    func succeedsWhenReady() async {
        let runtime = TerminalRuntime(
            paneId: UUID(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        let commandEnvelope = makeEnvelope(command: .terminal(.clearScrollback), paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)
        switch result {
        case .success(let commandId):
            #expect(commandId == commandEnvelope.commandId)
        default:
            Issue.record("Expected success result for ready runtime")
        }
    }

    @Test("eventsSince replays emitted events")
    func replaysEvents() async {
        let runtime = TerminalRuntime(
            paneId: UUID(),
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

    @Test("eventsSince reports gap after replay eviction")
    func replayGapAfterEviction() async {
        let replayBuffer = EventReplayBuffer(config: .init(maxEvents: 2, maxBytes: 10_000, ttl: .seconds(300)))
        let runtime = TerminalRuntime(
            paneId: UUID(),
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

    @Test("shutdown finishes event stream")
    func shutdownFinishesEventStream() async {
        let runtime = TerminalRuntime(
            paneId: UUID(),
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
            paneId: UUID(),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: "Runtime"), title: "Runtime")
        )
        runtime.transitionToReady()
        _ = await runtime.shutdown(timeout: .seconds(1))

        let commandEnvelope = makeEnvelope(command: .activate, paneId: runtime.paneId)
        let result = await runtime.handleCommand(commandEnvelope)

        #expect(result == .failure(.runtimeNotReady(lifecycle: .terminated)))
    }

    private func makeEnvelope(command: PaneCommand, paneId: UUID) -> PaneCommandEnvelope {
        let clock = ContinuousClock()
        return PaneCommandEnvelope(
            commandId: UUID(),
            correlationId: nil,
            targetPaneId: paneId,
            command: command,
            timestamp: clock.now
        )
    }
}
