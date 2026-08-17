import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioTerminal

/// RC2 + learned-prompt-signature coverage for `TerminalActivityProjector.commandFinished(...)`,
/// split from `TerminalActivityProjectorTests` (general aggregate/window behavior) purely to keep
/// both files under the repo's file-length lint cap.
@MainActor
struct TerminalActivityProjectorCommandFinishedTests {
    @Test("commandFinished settles immediately with zero scrollbar evidence")
    func commandFinishedSettlesWithZeroScrollbarEvidence() async throws {
        // RC2: attended panes never accumulate a scrollbar unseen-window at all (see the
        // `context.isAttended` branch in `consumeAggregateState`), and scrollbar evidence can be
        // silent for short bursts even when unattended. commandFinished is a contracted semantic
        // settle boundary that must still surface real content through the settle path with no
        // scrollbar activity whatsoever.
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            // Realistic raw viewport text: the real output line followed by the
            // shell's freshly-printed (bare) prompt as the trailing line.
            lastOutputLineReader: { _ in "todo1-live-proof-071342\n$ " },
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
        #expect(settled?.lastOutputLine == "todo1-live-proof-071342")
        #expect(settled?.rowsAdded == 0)
        await projector.reset()
    }

    @Test("commandFinished with no resolved last output line and no accumulated window emits nothing")
    func commandFinishedWithNothingToShowEmitsNothing() async {
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in nil },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        #expect(recorder.outcomes.isEmpty)
        await projector.reset()
    }

    @Test("commandFinished on a pane's first-ever settle never publishes a prompt-only viewport")
    func commandFinishedFirstSettlePromptOnlyViewportNeverPublishes() async {
        // The pane's very first commandFinished settle can genuinely be a prompt-only viewport
        // (nothing has run in this pane yet, or the shell just started). Learn-then-contract must
        // self-heal even this first settle: the trailing line becomes the signature and is
        // excluded in the same pass, so it is never mistaken for real output.
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in "➜  agent-studio (⑂ main) " },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        #expect(recorder.outcomes.isEmpty)
        await projector.reset()
    }

    @Test("the learned prompt signature updates every commandFinished settle as the prompt text changes")
    func learnedPromptSignatureUpdatesAsPromptTextChanges() async {
        // A `cd` or branch switch changes the prompt's exact text between commands. The signature
        // must track that change every settle (not just once), so a later real output line that
        // happens to match the OLD prompt text is still surfaced, and the NEW prompt is still
        // correctly excluded.
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        let rawText = MutableRawViewportTextBox("first output\n➜  repo-one (⑂ main) ")
        await projector.configure(
            lastOutputLineReader: { _ in rawText.read() },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)
        let firstSettled = try? await recorder.firstSnapshot { outcomes in
            outcomes.contains {
                if case .unseenActivitySettled(_, let outcomePaneID, let activity) = $0,
                    outcomePaneID == paneID
                {
                    return activity.lastOutputLine == "first output"
                }
                return false
            }
        }
        #expect(firstSettled != nil)

        // `cd` into a different worktree, then run a command whose only output line happens to be
        // the OLD prompt's exact text — the OLD signature must not still be excluding it.
        rawText.set("➜  repo-one (⑂ main) \n➜  repo-two (⑂ feature) ")
        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)
        let secondSettled = try? await recorder.firstSnapshot { outcomes in
            outcomes.contains {
                if case .unseenActivitySettled(_, let outcomePaneID, let activity) = $0,
                    outcomePaneID == paneID
                {
                    return activity.lastOutputLine == "➜  repo-one (⑂ main)"
                }
                return false
            }
        }
        #expect(secondSettled != nil)
        await projector.reset()
    }

    @Test("unchanged-line suppression still holds for genuinely repeated real output")
    func unchangedLineSuppressionStillHoldsForRepeatedRealOutput() async {
        // The signature exclusion must not interfere with the existing unchanged-line suppression:
        // two settles with the identical real output line (and an identical prompt) must still
        // suppress the repeat.
        let projector = TerminalActivityProjector(nowMilliseconds: { 5000 })
        let recorder = OutcomeRecorder()
        await projector.configure(
            lastOutputLineReader: { _ in "same real output\n➜  agent-studio (⑂ main) " },
            outcomeSink: { outcomes in recorder.record(outcomes) }
        )
        let paneID = UUIDv7.generate()
        let surfaceID = UUIDv7.generate()

        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)
        let firstSettled = try? await recorder.firstSnapshot { outcomes in
            outcomes.contains {
                if case .unseenActivitySettled(_, let outcomePaneID, let activity) = $0,
                    outcomePaneID == paneID
                {
                    return activity.lastOutputLine == "same real output"
                }
                return false
            }
        }
        #expect(firstSettled != nil)

        // The repeat settle has an unchanged candidate and no accumulated scrollbar window, so
        // `commandFinished`'s own emit guard (`closedWindow != nil || lastOutputLine != nil`)
        // suppresses the entire outcome batch — nothing new gets recorded.
        let outcomeCountBeforeRepeat = recorder.outcomes.count
        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        #expect(recorder.outcomes.count == outcomeCountBeforeRepeat)
        await projector.reset()
    }

    @Test("commandFinished closes an already-accumulating unseen window immediately, without waiting the debounce")
    func commandFinishedClosesAccumulatingWindowImmediately() async throws {
        let clock = TestPushClock()
        let projector = TerminalActivityProjector(
            unseenQuietDuration: .milliseconds(750),
            clock: clock,
            nowMilliseconds: { 5000 }
        )
        let recorder = OutcomeRecorder()
        await projector.configure(
            // Realistic raw viewport text: the real output line followed by the
            // shell's freshly-printed (bare) prompt as the trailing line.
            lastOutputLineReader: { _ in "final streamed line\n$ " },
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

        // No clock advance: commandFinished must settle without waiting out the pending debounce.
        await projector.commandFinished(surfaceID: surfaceID, paneID: paneID)

        let settled = recorder.outcomes.compactMap { outcome -> TerminalSettledActivity? in
            guard case .unseenActivitySettled(let outcomeSurfaceID, let outcomePaneID, let activity) = outcome,
                outcomeSurfaceID == surfaceID, outcomePaneID == paneID
            else { return nil }
            return activity
        }.first
        #expect(settled?.rowsAdded == 40)
        #expect(settled?.lastOutputLine == "final streamed line")
        // The closed window's debounce timer must be cancelled, not left pending.
        #expect(await projector.scheduledTimerCount == 0)
        await projector.reset()
    }

    private func makeAggregate(
        firstTotal: Int,
        latestTotal: Int,
        firstObservedAtMilliseconds: Int64 = 1000,
        latestObservedAtMilliseconds: Int64 = 1100
    ) -> TerminalScrollbarActivityAggregate {
        var aggregate = TerminalScrollbarActivityAggregate(
            state: ScrollbarState(top: max(0, firstTotal - 10), bottom: firstTotal, total: firstTotal),
            observedAtMilliseconds: firstObservedAtMilliseconds
        )
        aggregate.merge(
            state: ScrollbarState(top: max(0, latestTotal - 10), bottom: latestTotal, total: latestTotal),
            observedAtMilliseconds: latestObservedAtMilliseconds
        )
        return aggregate
    }
}
