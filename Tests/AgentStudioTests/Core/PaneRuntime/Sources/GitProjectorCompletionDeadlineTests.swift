import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("GitWorkingDirectoryProjector completion deadline")
struct GitProjectorCompletionDeadlineTests {
    @Test("completed read replaces a visibility deadline based on the previous sample")
    func completionReplacesDeadlineFromPreviousSample() async throws {
        let clock = TestPushClock()
        let policy = AppPolicies.GitRefresh.Policy(
            activePaneCadence: .milliseconds(120), visibleSidebarCadence: .milliseconds(240)
        )
        let projector = GitWorkingDirectoryProjector(
            bus: EventBus<RuntimeEnvelope>(),
            gitWorkingTreeProvider: StubGitWorkingTreeStatusProvider { _ in nil },
            coalescingWindow: .zero,
            sleepClock: clock,
            refreshPolicy: policy
        )

        try await assertCompletionReplacesPreviousDeadline(projector, clock: clock, policy: policy)
        await projector.shutdown()
        #expect(clock.pendingSleepCount == 0)
    }

    private func assertCompletionReplacesPreviousDeadline(
        _ projector: isolated GitWorkingDirectoryProjector,
        clock: TestPushClock,
        policy: AppPolicies.GitRefresh.Policy
    ) throws {
        let worktreeID = UUIDv7.generate()
        projector.repoIdByWorktreeId[worktreeID] = worktreeID
        projector.rootPathByWorktreeId[worktreeID] = URL(fileURLWithPath: "/tmp/completion-deadline-\(worktreeID)")
        projector.sidebarVisibleWorktreeIds = [worktreeID]
        projector.lastAcceptedStatusAtByWorktreeId[worktreeID] = .zero
        projector.lastAcceptedLineDetailAtByWorktreeId[worktreeID] = .zero
        projector.lastAutomaticCompletionAtByWorktreeId[worktreeID] = .zero
        projector.lastAutomaticDutyByWorktreeId[worktreeID] = .milliseconds(1)

        clock.advance(by: policy.visibleSidebarCadence)
        projector.recordAutomaticAdmission(worktreeId: worktreeID, isExplicit: false)

        // Visibility can be processed while the new read is suspended, before its duty is known.
        projector.scheduleAutomaticRefresh(worktreeId: worktreeID)
        #expect(projector.automaticRefreshDeadlineByWorktreeId[worktreeID] == .milliseconds(480))

        let completedDuty = Duration.seconds(1)
        projector.recordAutomaticCompletion(worktreeId: worktreeID, duty: completedDuty)

        let completion = try #require(projector.lastAutomaticCompletionAtByWorktreeId[worktreeID])
        #expect(
            projector.automaticRefreshDeadlineByWorktreeId[worktreeID]
                == completion + policy.automaticDutyGap(for: completedDuty)
        )
    }
}
