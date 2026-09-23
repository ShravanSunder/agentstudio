/// A fresh system under test for one branch of ``proveReplyDependsOnStep``:
/// the step its work is held at, the work that produces the reply, and any
/// context the assertions read afterwards.
package struct HeldReplyScenario<Context: Sendable, Arrival: Sendable, Reply: Sendable>: Sendable {
    package let context: Context
    package let step: HeldStep<Arrival>
    package let produceReply: @Sendable () async -> Reply

    package init(context: Context, step: HeldStep<Arrival>, produceReply: @escaping @Sendable () async -> Reply) {
        self.context = context
        self.step = step
        self.produceReply = produceReply
    }
}

/// The step failure the helper injects in the fail branch. A reply that
/// reports failure there can only have come from observing this outcome.
package struct HeldStepInjectedFailure: Error, Equatable {
    package let stepName: String
}

/// Why ``proveReplyDependsOnStep`` rejected the work under test.
package enum ReplyDependsOnStepViolation: Error, CustomStringConvertible {
    /// The step failed, yet the reply reported success: the reply did not wait
    /// for the step's outcome.
    case replySucceededAfterStepFailed(stepName: String)
    /// The step was released, yet the reply reported failure.
    case replyFailedAfterStepReleased(stepName: String)

    package var description: String {
        switch self {
        case .replySucceededAfterStepFailed(let stepName):
            "reply reported success although held step '\(stepName)' failed; the reply does not depend on the step"
        case .replyFailedAfterStepReleased(let stepName):
            "reply reported failure although held step '\(stepName)' was released"
        }
    }
}

/// Proves that the work's reply is caused by the held step's outcome.
///
/// Runs two branches, each on a fresh scenario:
/// 1. hold the work at the step, fail the step, and require the reply to
///    report that failure;
/// 2. hold the work at the step, release it, and require the reply to report
///    success, then run `assertCommitted` on the effect.
///
/// A reply produced before the step completes cannot depend on the step's
/// outcome, so it reports success in branch 1 and the helper throws
/// ``ReplyDependsOnStepViolation`` — without any clock or quiescence wait.
/// The helper always ends the step in both branches.
package func proveReplyDependsOnStep<Context: Sendable, Arrival: Sendable, Reply: Sendable>(
    isolation: isolated (any Actor)? = #isolation,
    makeScenario: () async throws -> HeldReplyScenario<Context, Arrival, Reply>,
    replyReportsFailure: (Reply, Context) async throws -> Bool,
    assertCommitted: (Reply, Context) async throws -> Void
) async throws {
    let failBranch = try await makeScenario()
    let replyAfterFailure = try await replyAfterEndingHeldStep(of: failBranch) { step in
        step.fail(HeldStepInjectedFailure(stepName: step.name))
    }
    guard try await replyReportsFailure(replyAfterFailure, failBranch.context) else {
        throw ReplyDependsOnStepViolation.replySucceededAfterStepFailed(stepName: failBranch.step.name)
    }

    let releaseBranch = try await makeScenario()
    let replyAfterRelease = try await replyAfterEndingHeldStep(of: releaseBranch) { step in
        step.release()
    }
    guard try await !replyReportsFailure(replyAfterRelease, releaseBranch.context) else {
        throw ReplyDependsOnStepViolation.replyFailedAfterStepReleased(stepName: releaseBranch.step.name)
    }
    try await assertCommitted(replyAfterRelease, releaseBranch.context)
}

/// Starts the work, waits until it reaches the step, ends the step, and
/// returns the reply. The step is retired on every exit path, so a branch that
/// throws never leaves the work parked.
private func replyAfterEndingHeldStep<Context: Sendable, Arrival: Sendable, Reply: Sendable>(
    isolation: isolated (any Actor)? = #isolation,
    of scenario: HeldReplyScenario<Context, Arrival, Reply>,
    endStep: (HeldStep<Arrival>) -> Void
) async throws -> Reply {
    let step = scenario.step
    defer { step.retire() }
    let produceReply = scenario.produceReply
    let replyTask = Task { await produceReply() }
    _ = try await step.firstArrival()
    endStep(step)
    return await replyTask.value
}
