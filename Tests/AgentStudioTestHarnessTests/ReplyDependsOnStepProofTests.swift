import AgentStudioTestHarness
import Synchronization
import Testing

@Suite("proveReplyDependsOnStep")
struct ReplyDependsOnStepProofTests {
    @Test("accepts work whose reply waits for the held step's outcome")
    func acceptsReplyThatWaitsForTheStep() async throws {
        // Arrange
        var scenariosBuilt = 0

        // Act
        try await proveReplyDependsOnStep(
            makeScenario: { () -> HeldReplyScenario<CommittedEffect, Void, StepReply> in
                scenariosBuilt += 1
                let step = HeldStep<Void>("commit")
                let effect = CommittedEffect()
                return HeldReplyScenario(context: effect, step: step) { () -> StepReply in
                    do {
                        try await step.arrive(())
                        effect.commit()
                        return .committed
                    } catch {
                        return .failed
                    }
                }
            },
            replyReportsFailure: { (reply: StepReply, _: CommittedEffect) -> Bool in reply == .failed },
            assertCommitted: { (_: StepReply, effect: CommittedEffect) in #expect(effect.isCommitted) }
        )

        // Assert
        #expect(scenariosBuilt == 2)
    }

    @Test("rejects work that replies before the held step finishes")
    func rejectsReplyThatPrecedesTheStep() async throws {
        // Arrange
        let stepName = "early-reply"

        // Act
        let violation = await #expect(throws: ReplyDependsOnStepViolation.self) {
            try await proveReplyDependsOnStep(
                makeScenario: { () -> HeldReplyScenario<CommittedEffect, Void, StepReply> in
                    let step = HeldStep<Void>(stepName)
                    let effect = CommittedEffect()
                    return HeldReplyScenario(context: effect, step: step) { () -> StepReply in
                        Task {
                            guard (try? await step.arrive(())) != nil else { return }
                            effect.commit()
                        }
                        return .committed
                    }
                },
                replyReportsFailure: { (reply: StepReply, _: CommittedEffect) -> Bool in reply == .failed },
                assertCommitted: { (_: StepReply, _: CommittedEffect) in }
            )
        }

        // Assert
        guard case .replySucceededAfterStepFailed(let violatingStep) = violation else {
            Issue.record("expected the fail branch to reject the early reply, got \(String(describing: violation))")
            return
        }
        #expect(violatingStep == stepName)
    }

    @Test("a failed wait for the step cancels and joins the reply task before returning")
    func failedWaitCancelsAndJoinsTheReplyTask() async throws {
        // Arrange: the work is held at an earlier, cancellation-aware prerequisite,
        // so it never reaches the step the proof waits for.
        let prerequisite = HeldStep<Void>("earlier prerequisite")
        let effect = CommittedEffect()
        let proof = Task {
            try await proveReplyDependsOnStep(
                makeScenario: { () -> HeldReplyScenario<CommittedEffect, Void, StepReply> in
                    let step = HeldStep<Void>("never reached")
                    return HeldReplyScenario(context: effect, step: step) { () -> StepReply in
                        defer { effect.commit() }  // marks the reply task as finished
                        do {
                            try await prerequisite.arrive(())
                            try await step.arrive(())
                            return .committed
                        } catch {
                            return .failed
                        }
                    }
                },
                replyReportsFailure: { (reply: StepReply, _: CommittedEffect) -> Bool in reply == .failed },
                assertCommitted: { (_: StepReply, _: CommittedEffect) in }
            )
        }
        try await prerequisite.firstArrival()

        // Act
        proof.cancel()
        let failure = await #expect(throws: HeldStepNeverReached.self) { try await proof.value }

        // Assert: the reply task observed the cancellation and finished before the proof returned.
        #expect(failure?.stepName == "never reached")
        #expect(prerequisite.hasObservedCancellation)
        #expect(effect.isCommitted)
    }
}

private enum StepReply: Sendable, Equatable {
    case committed
    case failed
}

private final class CommittedEffect: Sendable {
    private let committed = Mutex(false)

    var isCommitted: Bool {
        committed.withLock { $0 }
    }

    func commit() {
        committed.withLock { $0 = true }
    }
}
