import AgentStudioCore
import AgentStudioGit
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge Review Git refresh scope")
@MainActor
struct BridgeReviewGitRefreshScopeTests {
    @Test("Review refresh retains exact sorted paths")
    func retainsExactSortedPaths() throws {
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(
                paths: ["Sources/B.swift", "Sources/A.swift", "Sources/B.swift"],
                batchSequence: 1
            ),
            requiresReviewRefresh: true
        )
        let reservation = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        #expect(reservation.reviewRefreshScope == .exactPaths(["Sources/A.swift", "Sources/B.swift"]))
    }

    @Test(
        "Review refresh rejects non-exact filesystem evidence",
        arguments: [
            ([], false, 0, 0, BridgeReviewCompleteScopeReason.emptyPaths),
            (["."], false, 0, 0, .rootOrOverflowSummary),
            (["Sources/A.swift"], true, 0, 0, .gitInternalChange),
            (["Sources/A.swift"], false, 1, 0, .suppressedIgnoredPath),
            (["Sources/A.swift"], false, 0, 1, .suppressedGitInternalPath),
        ]
    )
    func rejectsNonExactFilesystemEvidence(
        paths: [String],
        containsGitInternalChanges: Bool,
        suppressedIgnoredPathCount: Int,
        suppressedGitInternalPathCount: Int,
        expectedReason: BridgeReviewCompleteScopeReason
    ) throws {
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(
                paths: paths,
                batchSequence: 2,
                containsGitInternalChanges: containsGitInternalChanges,
                suppressedIgnoredPathCount: suppressedIgnoredPathCount,
                suppressedGitInternalPathCount: suppressedGitInternalPathCount
            ),
            requiresReviewRefresh: true
        )
        let reservation = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        #expect(reservation.reviewRefreshScope == .complete(reason: expectedReason))
    }

    @Test("Review status-only invalidation requires complete refresh")
    func statusOnlyInvalidationRequiresCompleteRefresh() throws {
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        coordinator.recordInvalidation(
            fileChangeset: nil,
            latestFileStatus: GitWorkingTreeStatus(
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 0),
                branch: "feature/latest",
                origin: nil
            ),
            requiresReviewRefresh: true
        )
        let reservation = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        #expect(reservation.reviewRefreshScope == .complete(reason: .statusOnlyChange))
    }

    @Test("Review exact scopes union and mixed authority becomes complete")
    func exactScopesUnionAndMixedAuthorityBecomesComplete() throws {
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(paths: ["Sources/A.swift"], batchSequence: 3),
            requiresReviewRefresh: true
        )
        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(paths: ["Sources/B.swift"], batchSequence: 4),
            requiresReviewRefresh: true
        )
        let union = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        #expect(union.reviewRefreshScope == .exactPaths(["Sources/A.swift", "Sources/B.swift"]))
        coordinator.completeRefreshPass(union, outcome: .succeeded)

        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(paths: ["Sources/C.swift"], batchSequence: 5),
            requiresReviewRefresh: true
        )
        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(
                paths: ["Sources/D.swift"],
                batchSequence: 6,
                worktreeId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
            ),
            requiresReviewRefresh: true
        )
        let mixed = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        #expect(mixed.reviewRefreshScope == .complete(reason: .mixedAuthority))
    }

    @Test("Review exact scope overflow becomes complete")
    func exactScopeOverflowBecomesComplete() throws {
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        let paths = (0...AppPolicies.GitRefresh.defaultPolicy.maxScopedStatusPathspecCount)
            .map { "Sources/File-\($0).swift" }
        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(paths: paths, batchSequence: 7),
            requiresReviewRefresh: true
        )
        let reservation = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        #expect(reservation.reviewRefreshScope == .complete(reason: .rootOrOverflowSummary))
    }

    @Test("post-currentness seed commit survives later rejection and dirty-scope restoration")
    func seedCommitSurvivesLaterRejectionAndDirtyScopeRestoration() throws {
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        var seedHolder = BridgeReviewGitRefreshSeedHolder()
        coordinator.recordInvalidation(
            fileChangeset: makeScopeChangeset(paths: ["Sources/Changed.swift"], batchSequence: 8),
            requiresReviewRefresh: true
        )
        let reservation = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        seedHolder.commit(makeScopeSeed(oid: "candidate"))
        coordinator.completeRefreshPass(reservation, outcome: .failed)
        let retry = try #require(coordinator.reserveForegroundRefreshPass(for: .review))
        #expect(seedHolder.hasActiveSeed)
        #expect(seedHolder.commitCount == 1)
        #expect(retry.reviewRefreshScope == .exactPaths(["Sources/Changed.swift"]))
    }

}

private func makeScopeChangeset(
    paths: [String],
    batchSequence: UInt64,
    worktreeId: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    containsGitInternalChanges: Bool = false,
    suppressedIgnoredPathCount: Int = 0,
    suppressedGitInternalPathCount: Int = 0
) -> FileChangeset {
    FileChangeset(
        worktreeId: worktreeId,
        repoId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        rootPath: URL(fileURLWithPath: "/tmp/bridge-review-refresh-scope"),
        paths: paths,
        containsGitInternalChanges: containsGitInternalChanges,
        suppressedIgnoredPathCount: suppressedIgnoredPathCount,
        suppressedGitInternalPathCount: suppressedGitInternalPathCount,
        timestamp: .now,
        batchSeq: batchSequence
    )
}

private func makeScopeSeed(oid: String) -> GitReviewRefreshSeed {
    GitContributionDiffResult.clientFixture(
        snapshot: GitContributionDiffSnapshot(
            resolvedTarget: GitResolvedRevision(oid: "target-\(oid)", shortName: "target"),
            reviewedHead: GitResolvedRevision(oid: "head-\(oid)", shortName: "feature"),
            contributionBase: GitResolvedRevision(oid: "base-\(oid)", shortName: nil),
            diff: GitDiffSnapshot(files: [])
        )
    ).successorSeed
}
