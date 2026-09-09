import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioTerminal

@MainActor
private final class TerminalViewportReadSequence {
    private var results: [TerminalViewportTextReadResult]
    private(set) var readCount = 0

    init(_ results: [TerminalViewportTextReadResult]) {
        self.results = results
    }

    func read() -> TerminalViewportTextReadResult {
        readCount += 1
        return results.isEmpty ? .empty : results.removeFirst()
    }
}

@MainActor
struct TerminalActivityProjectorCommandFinishedTests {
    @Test("commandFinished publishes the literal trailing viewport line with zero scrollbar evidence")
    func commandFinishedPublishesLiteralTrailingLine() async {
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in .value("todo1-live-proof-071342\n$ ") },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        let settled = recorder.outcomes.compactMap { outcome -> TerminalSettledActivity? in
            guard case .unseenActivitySettled(let outcomeSurfaceID, let outcomePaneID, let activity) = outcome,
                outcomeSurfaceID == surfaceID, outcomePaneID == paneID
            else { return nil }
            return activity
        }.first
        #expect(settled?.lastOutputLine == "$")
        #expect(settled?.rowsAdded == 0)
        await projector.reset()
    }

    @Test("commandFinished with no viewport line and no accumulated window emits nothing")
    func commandFinishedWithNothingToShowEmitsNothing() async {
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in .empty },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        #expect(recorder.outcomes.isEmpty)
        await projector.reset()
    }

    @Test("prompt-only viewport publishes the prompt as literal terminal context")
    func promptOnlyViewportPublishesPrompt() async {
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in .value("⚡ ➜ agent-studio (main) ") },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        #expect(
            recorder.outcomes.contains { outcome in
                if case .unseenActivitySettled(_, let outcomePaneID, let activity) = outcome {
                    return outcomePaneID == paneID && activity.lastOutputLine == "⚡ ➜ agent-studio (main)"
                }
                return false
            }
        )
        await projector.reset()
    }

    @Test("unchanged literal trailing line suppresses a repeated settle")
    func unchangedLineSuppressionStillHolds() async {
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in .value("same output\n⚡ ➜ agent-studio (main) ") },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)
        let outcomeCountBeforeRepeat = recorder.outcomes.count
        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        #expect(outcomeCountBeforeRepeat == 1)
        #expect(recorder.outcomes.count == outcomeCountBeforeRepeat)
        await projector.reset()
    }

    @Test("commandFinished closes an accumulating unseen window without waiting the debounce")
    func commandFinishedClosesAccumulatingWindowImmediately() async throws {
        let clock = TestPushClock()
        let projector = TerminalActivityProjector(
            unseenQuietDuration: .milliseconds(750),
            clock: clock,
            nowMilliseconds: { 5000 }
        )
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in .value("final streamed line\n$ ") },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let context = TerminalActivityProjectionContext(
            isAttended: false,
            isAgentClassified: false,
            outputBurstThreshold: 30
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.ingest(
            surfaceID: surfaceID,
            paneID: paneID,
            aggregate: makeAggregate(firstTotal: 100, latestTotal: 140),
            latestState: ScrollbarState(top: 100, bottom: 140, total: 140),
            context: context
        )
        await clock.waitForPendingSleepCount(exactly: 1)
        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        let settled = recorder.outcomes.compactMap { outcome -> TerminalSettledActivity? in
            guard case .unseenActivitySettled(_, let outcomePaneID, let activity) = outcome,
                outcomePaneID == paneID
            else { return nil }
            return activity
        }.first
        #expect(settled?.rowsAdded == 40)
        #expect(settled?.lastOutputLine == "$")
        #expect(await projector.scheduledTimerCount == 0)
        await projector.reset()
    }

    @Test("ordered commandFinished reads once and emits one batch after preceding aggregate outcomes")
    func orderedCommandFinishedReadsOnceAndEmitsOneBatch() async {
        let projector = TerminalActivityProjector(clock: TestPushClock(), nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        let readSequence = TerminalViewportReadSequence([.value("final line")])
        await projector.configure(
            lastOutputLineReader: { _ in readSequence.read() },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.applyOrderedControl(
            surfaceID: surfaceID,
            paneID: paneID,
            precedingAggregate: TerminalActivityAggregateInput(
                aggregate: makeAggregate(firstTotal: 100, latestTotal: 140),
                latestState: ScrollbarState(top: 100, bottom: 140, total: 140),
                context: TerminalActivityProjectionContext(
                    isAttended: false,
                    isAgentClassified: false,
                    outputBurstThreshold: 30
                )
            ),
            control: .commandFinished
        )

        #expect(readSequence.readCount == 1)
        #expect(recorder.batches.count == 1)
        #expect(recorder.batches[0].count == 4)
        guard case .unseenActivitySettled(_, _, let activity) = recorder.batches[0].last else {
            Issue.record("Expected ordered settlement after preceding aggregate outcomes")
            return
        }
        #expect(activity.lastOutputLine == "final line")
        #expect(activity.rowsAdded == 40)
        #expect(await projector.scheduledTimerCount == 0)
        await projector.reset()
    }

    @Test("non-value viewport outcomes leave confirmed unchanged-line state intact")
    func nonValueViewportOutcomePreservesConfirmedLineState() async {
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        let readSequence = TerminalViewportReadSequence([
            .value("same line"),
            .readFailed,
            .value("same line"),
        ])
        await projector.configure(
            lastOutputLineReader: { _ in readSequence.read() },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)
        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)
        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        #expect(readSequence.readCount == 3)
        #expect(recorder.outcomes.count == 1)
        await projector.reset()
    }

    private func makeAggregate(firstTotal: Int, latestTotal: Int) -> TerminalScrollbarActivityAggregate {
        var aggregate = TerminalScrollbarActivityAggregate(
            state: ScrollbarState(top: max(0, firstTotal - 10), bottom: firstTotal, total: firstTotal),
            observedAtMilliseconds: 1000
        )
        aggregate.merge(
            state: ScrollbarState(top: max(0, latestTotal - 10), bottom: latestTotal, total: latestTotal),
            observedAtMilliseconds: 1100
        )
        return aggregate
    }
}
