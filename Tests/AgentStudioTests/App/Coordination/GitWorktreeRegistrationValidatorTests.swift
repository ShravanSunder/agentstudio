import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite
struct GitWorktreeRegistrationValidatorTests {
    @Test(
        "a probe that cannot confirm the repository registers provisionally instead of stalling",
        arguments: [
            GitRepositoryDiscoveryOutcome.timeout,
            .cancelled,
            .failure(.serviceFailed(detail: "boom")),
        ]
    )
    func nonCertainProbeOutcomesRegisterProvisionally(outcome: GitRepositoryDiscoveryOutcome) async {
        await assertDecision(outcome, is: .validated)
    }

    @Test(
        "worktree metadata drift reasons register provisionally rather than reject",
        arguments: [
            GitRepositoryAuthoritativeNegativeReason.canonicalPathMismatch,
            .mainWorktreeMismatch,
            .submoduleWorktree,
        ]
    )
    func metadataDriftReasonsRegisterProvisionally(
        reason: GitRepositoryAuthoritativeNegativeReason
    ) async {
        await assertDecision(.authoritativeNegative(reason), is: .validated)
    }

    @Test(
        "certain non-repository evidence still rejects registration",
        arguments: [
            GitRepositoryAuthoritativeNegativeReason.exactCandidateIsNotRepository,
            .invalidRepository,
            .invalidWorktreeRegistration,
            .bareRepository,
        ]
    )
    func certainNonRepositoryReasonsReject(
        reason: GitRepositoryAuthoritativeNegativeReason
    ) async {
        await assertDecision(.authoritativeNegative(reason), is: .authoritativeNegative)
    }

    @Test("validated discovery evidence registers")
    func validatedOutcomeRegisters() async {
        let entry = RepoScanner.ResolvedGitEntry(
            path: URL(fileURLWithPath: "/tmp/registration-validator-validated"),
            kind: .cloneRoot,
            repositoryKey: "test:validated"
        )
        await assertDecision(.validated(entry), is: .validated)
    }

    @Test("registration performs a single probe with no retry")
    func registrationPerformsSingleProbeWithoutRetry() async {
        // Arrange
        let discoveryProvider = RecordingRegistrationDiscoveryProvider(outcome: .timeout)
        let validator = GitWorktreeRegistrationValidator(discoveryProvider: discoveryProvider)
        let context = WorktreeFilesystemContext(
            repoId: UUIDv7.generate(),
            rootPath: URL(fileURLWithPath: "/tmp/registration-validator-single-probe")
        )

        // Act
        _ = await validator.registrationDecision(context: context)

        // Assert
        #expect(await discoveryProvider.callCount == 1)
    }

    private func assertDecision(
        _ outcome: GitRepositoryDiscoveryOutcome,
        is expectedDecision: GitWorktreeRegistrationDecision
    ) async {
        // Arrange
        let discoveryProvider = RecordingRegistrationDiscoveryProvider(outcome: outcome)
        let validator = GitWorktreeRegistrationValidator(discoveryProvider: discoveryProvider)
        let context = WorktreeFilesystemContext(
            repoId: UUIDv7.generate(),
            rootPath: URL(fileURLWithPath: "/tmp/registration-validator-\(UUID().uuidString)")
        )

        // Act
        let decision = await validator.registrationDecision(context: context)

        // Assert
        #expect(decision == expectedDecision)
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
