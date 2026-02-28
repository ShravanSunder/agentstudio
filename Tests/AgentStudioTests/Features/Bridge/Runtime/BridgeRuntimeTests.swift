import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("BridgeRuntime lifecycle")
struct BridgeRuntimeTests {
    @Test("bridge runtime posts diff events to EventBus and replay")
    func bridgeRuntimePostsEvents() async {
        let paneEventBus = EventBus<PaneEventEnvelope>()
        let runtime = makeRuntime(
            paneEventBus: paneEventBus
        )
        runtime.transitionToReady()

        let busStream = await paneEventBus.subscribe()
        var busIterator = busStream.makeAsyncIterator()
        runtime.ingestBridgeEvent(
            .diff(.diffLoaded(stats: DiffStats(filesChanged: 1, insertions: 2, deletions: 0)))
        )

        let busEnvelope = await busIterator.next()
        let replay = await runtime.eventsSince(seq: 0)

        #expect(busEnvelope?.source == .pane(runtime.paneId))
        #expect(busEnvelope?.seq == 1)
        #expect(replay.events.count == 1)
        #expect(replay.nextSeq == 1)
        #expect(!replay.gapDetected)
    }

    @Test("handleCommand rejects when runtime is not ready")
    func handleCommandRejectsWhenNotReady() async {
        let runtime = makeRuntime()
        let envelope = makeEnvelope(command: .activate, paneId: runtime.paneId)

        let result = await runtime.handleCommand(envelope)

        #expect(result == .failure(.runtimeNotReady(lifecycle: .created)))
    }

    @Test("shutdown finishes subscriber streams")
    func shutdownFinishesSubscriberStreams() async {
        let runtime = makeRuntime()
        runtime.transitionToReady()
        var iterator = runtime.subscribe().makeAsyncIterator()

        _ = await runtime.shutdown(timeout: .seconds(1))
        let nextEvent = await iterator.next()

        #expect(runtime.lifecycle == .terminated)
        #expect(nextEvent == nil)
    }

    @Test("handleCommand forwards diff commands to bridge controller handler")
    func handleCommandForwardsDiffCommands() async {
        let handler = BridgeRuntimeCommandHandlerSpy()
        let runtime = makeRuntime(commandHandler: handler)
        runtime.transitionToReady()

        let commandId = UUID()
        let correlationId = UUID()
        let artifact = DiffArtifact(
            diffId: UUID(),
            worktreeId: UUID(),
            patchData: Data("diff --git a/file b/file\n+line\n-line\n".utf8)
        )
        let envelope = RuntimeCommandEnvelope(
            commandId: commandId,
            correlationId: correlationId,
            targetPaneId: runtime.paneId,
            command: .diff(.loadDiff(artifact)),
            timestamp: ContinuousClock().now
        )

        let result = await runtime.handleCommand(envelope)

        #expect(result == .success(commandId: commandId))
        #expect(handler.receivedCommandKinds == ["loadDiff"])
        #expect(handler.receivedCommandIds == [commandId])
        #expect(handler.receivedCorrelationIds == [correlationId])
    }

    private func makeRuntime(
        commandHandler: (any BridgeRuntimeCommandHandling)? = nil,
        paneEventBus: EventBus<PaneEventEnvelope> = PaneRuntimeEventBus.shared
    ) -> BridgeRuntime {
        let paneId = PaneId()
        let metadata = PaneMetadata(
            paneId: paneId,
            contentType: .diff,
            source: .floating(workingDirectory: nil, title: "Diff"),
            title: "Diff"
        )
        return BridgeRuntime(
            paneId: paneId,
            metadata: metadata,
            commandHandler: commandHandler,
            paneEventBus: paneEventBus
        )
    }

    private func makeEnvelope(command: RuntimeCommand, paneId: PaneId) -> RuntimeCommandEnvelope {
        RuntimeCommandEnvelope(
            commandId: UUID(),
            correlationId: nil,
            targetPaneId: paneId,
            command: command,
            timestamp: ContinuousClock().now
        )
    }
}

@MainActor
private final class BridgeRuntimeCommandHandlerSpy: BridgeRuntimeCommandHandling {
    private(set) var receivedCommandKinds: [String] = []
    private(set) var receivedCommandIds: [UUID] = []
    private(set) var receivedCorrelationIds: [UUID?] = []

    func handleDiffCommand(
        _ command: DiffCommand,
        commandId: UUID,
        correlationId: UUID?
    ) -> ActionResult {
        switch command {
        case .loadDiff:
            receivedCommandKinds.append("loadDiff")
        case .approveHunk:
            receivedCommandKinds.append("approveHunk")
        case .rejectHunk:
            receivedCommandKinds.append("rejectHunk")
        }
        receivedCommandIds.append(commandId)
        receivedCorrelationIds.append(correlationId)
        return .success(commandId: commandId)
    }
}
