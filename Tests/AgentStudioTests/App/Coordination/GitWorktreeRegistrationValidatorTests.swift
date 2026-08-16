import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite
struct GitWorktreeRegistrationValidatorTests {
    @Test("uncertain discovery retries are bounded without wall-clock waits")
    func uncertainDiscoveryRetriesAreBoundedWithoutWallClockWaits() async {
        // Arrange
        let discoveryProvider = RecordingRegistrationDiscoveryProvider(outcome: .timeout)
        let delayRecorder = RegistrationValidationDelayRecorder()
        let validator = GitWorktreeRegistrationValidator(
            discoveryProvider: discoveryProvider,
            delay: AsyncDelay { duration in
                await delayRecorder.record(duration)
            }
        )
        let worktreeId = UUIDv7.generate()
        let context = WorktreeFilesystemContext(
            repoId: UUIDv7.generate(),
            rootPath: URL(fileURLWithPath: "/tmp/registration-validator-uncertain")
        )

        // Act
        let decision = await validator.registrationDecision(
            worktreeId: worktreeId,
            context: context
        )

        // Assert
        #expect(decision == .uncertain(previouslyAcceptedContext: nil))
        #expect(
            await discoveryProvider.callCount
                == AppPolicies.GitRefresh.registrationValidationMaximumAttempts
        )
        #expect(
            await delayRecorder.recordedDurations
                == Array(
                    repeating: AppPolicies.GitRefresh.registrationValidationRetryDelay,
                    count: AppPolicies.GitRefresh.registrationValidationMaximumAttempts - 1
                )
        )
    }
}

private actor RecordingRegistrationDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
    private let outcome: GitRepositoryDiscoveryOutcome
    private(set) var callCount = 0

    init(outcome: GitRepositoryDiscoveryOutcome) {
        self.outcome = outcome
    }

    func discoveryOutcome(for _: URL) async -> GitRepositoryDiscoveryOutcome {
        callCount += 1
        return outcome
    }
}

private actor RegistrationValidationDelayRecorder {
    private(set) var recordedDurations: [Duration] = []

    func record(_ duration: Duration) {
        recordedDurations.append(duration)
    }
}
