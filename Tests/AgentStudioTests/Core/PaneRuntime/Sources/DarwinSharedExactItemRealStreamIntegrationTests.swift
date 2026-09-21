import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Darwin shared exact-item real FSEvents integration", .serialized)
struct DarwinSharedExactItemRealStreamIntegrationTests {
    @Test("native shared stream routes sibling misses and exact hits to every dependent")
    func nativeSharedStreamRoutesSiblingMissesAndExactHits() async throws {
        let fixture = try await SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        // Two different facts, both required. The sentinel proves each stream is
        // LIVE — a stream that has never carried an event cannot mint an
        // exact-clean authority. The barrier then proves QUIESCENCE: nothing the
        // kernel had queued, including the sentinel's own siblings, is still in
        // flight to bump `mutationEpoch` behind the test's back.
        try #require(
            await fixture.awaitLocalStreamSentinelBarrier(),
            "fixture not live: sentinel batch never arrived"
        )
        try #require(
            await fixture.awaitActivityBarrier(),
            "fixture not quiescent: activity barrier could not be captured"
        )

        let firstAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.firstWorktreeId,
                repositoryPath: fixture.firstRepositoryPath
            )
        )
        let secondAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.secondWorktreeId,
                repositoryPath: fixture.secondRepositoryPath
            )
        )
        let baselineReadCounts = fixture.readRecorder.snapshot

        #expect(fixture.nativeStreamRecorder.startCount(forParentPath: fixture.externalParentPath) == 1)
        let firstStableRenewal = await fixture.provider.renewExactCleanAuthority(firstAuthority)
        let secondStableRenewal = await fixture.provider.renewExactCleanAuthority(secondAuthority)
        #expect(firstStableRenewal == .renewed(firstAuthority))
        #expect(secondStableRenewal == .renewed(secondAuthority))
        #expect(fixture.readRecorder.snapshot == baselineReadCounts)

        try "unrelated\n".write(
            to: fixture.unrelatedSiblingPath,
            atomically: false,
            encoding: .utf8
        )
        #expect(await fixture.waitForNativeCallback(at: fixture.unrelatedSiblingPath))

        let firstSiblingRenewal = await fixture.provider.renewExactCleanAuthority(firstAuthority)
        let secondSiblingRenewal = await fixture.provider.renewExactCleanAuthority(secondAuthority)
        #expect(firstSiblingRenewal == .renewed(firstAuthority))
        #expect(secondSiblingRenewal == .renewed(secondAuthority))
        #expect(fixture.readRecorder.snapshot == baselineReadCounts)

        let fullGitBatchTask = fixture.collectFullGitRefreshBatches(
            expectedWorktreeIds: [fixture.firstWorktreeId, fixture.secondWorktreeId]
        )
        try "ignored.txt\nanother-ignored.txt\n".write(
            to: fixture.excludesFilePath,
            atomically: false,
            encoding: .utf8
        )
        #expect(await fixture.waitForNativeCallback(at: fixture.excludesFilePath))
        let fullGitBatches = try #require(
            await fixture.firstCompletedValue(
                from: fullGitBatchTask,
                timeout: .seconds(5)
            )
        )

        #expect(
            fixture.requiresExact(
                await fixture.provider.renewExactCleanAuthority(firstAuthority)
            )
        )
        #expect(
            fixture.requiresExact(
                await fixture.provider.renewExactCleanAuthority(secondAuthority)
            )
        )

        #expect(Set(fullGitBatches.keys) == [fixture.firstWorktreeId, fixture.secondWorktreeId])
        for batch in fullGitBatches.values {
            #expect(batch.requiresFullGitRefresh)
            #expect(batch.paths.isEmpty)
        }
        #expect(fixture.readRecorder.snapshot == baselineReadCounts)
    }

    @Test(
        "native shared stream fails exact-item replacements closed",
        arguments: SharedExactItemReplacementMutation.allCases
    )
    func nativeSharedStreamFailsReplacementClosed(
        mutation: SharedExactItemReplacementMutation
    ) async throws {
        let fixture = try await SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        // Arrange. Everything down to `perform(mutation)` is setup, so it is
        // `#require`d: a failure here means the fixture never reached a quiescent
        // state, not that the product misbehaved.
        //
        // The barrier proves every event the kernel had queued from repository
        // creation has been delivered AND recorded. The old sentinel wait proved
        // only that ONE event arrived on one stream, so a setup event still in
        // flight could bump `mutationEpoch` from the raw callback and make the
        // renewals below fail closed — the product being right, reported as the
        // product being wrong.
        // Two different facts, both required. The sentinel proves each stream is
        // LIVE — a stream that has never carried an event cannot mint an
        // exact-clean authority. The barrier then proves QUIESCENCE: nothing the
        // kernel had queued, including the sentinel's own siblings, is still in
        // flight to bump `mutationEpoch` behind the test's back.
        try #require(
            await fixture.awaitLocalStreamSentinelBarrier(),
            "fixture not live: sentinel batch never arrived"
        )
        try #require(
            await fixture.awaitActivityBarrier(),
            "fixture not quiescent: activity barrier could not be captured"
        )
        let firstAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.firstWorktreeId,
                repositoryPath: fixture.firstRepositoryPath
            )
        )
        let secondAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.secondWorktreeId,
                repositoryPath: fixture.secondRepositoryPath
            )
        )
        let firstBaselineRenewal = await fixture.provider.renewExactCleanAuthority(firstAuthority)
        let secondBaselineRenewal = await fixture.provider.renewExactCleanAuthority(secondAuthority)
        try #require(
            firstBaselineRenewal == .renewed(firstAuthority),
            Comment(
                rawValue: "fixture not quiescent before mutation: first authority renewal "
                    + "returned \(firstBaselineRenewal) instead of .renewed"
            )
        )
        try #require(
            secondBaselineRenewal == .renewed(secondAuthority),
            Comment(
                rawValue: "fixture not quiescent before mutation: second authority renewal "
                    + "returned \(secondBaselineRenewal) instead of .renewed"
            )
        )
        let baselineReadCounts = fixture.readRecorder.snapshot
        let fullGitBatchTask = fixture.collectFullGitRefreshBatches(
            expectedWorktreeIds: [fixture.firstWorktreeId, fixture.secondWorktreeId]
        )

        try fixture.perform(mutation)
        #expect(await fixture.waitForNativeCallbackUnderExternalParent())
        let fullGitBatches = try #require(
            await fixture.firstCompletedValue(
                from: fullGitBatchTask,
                timeout: .seconds(5)
            )
        )
        #expect(
            fixture.requiresExact(
                await fixture.provider.renewExactCleanAuthority(firstAuthority)
            )
        )
        #expect(
            fixture.requiresExact(
                await fixture.provider.renewExactCleanAuthority(secondAuthority)
            )
        )
        #expect(Set(fullGitBatches.keys) == [fixture.firstWorktreeId, fixture.secondWorktreeId])
        #expect(fullGitBatches.values.allSatisfy { $0.requiresFullGitRefresh })
        #expect(fullGitBatches.values.allSatisfy { $0.paths.isEmpty })
        #expect(fixture.readRecorder.snapshot == baselineReadCounts)
    }

    @Test("native watched-parent replacement requires rebinding and a new exact scan")
    func nativeWatchedParentReplacementRequiresRebinding() async throws {
        let fixture = try await SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        // Two different facts, both required. The sentinel proves each stream is
        // LIVE — a stream that has never carried an event cannot mint an
        // exact-clean authority. The barrier then proves QUIESCENCE: nothing the
        // kernel had queued, including the sentinel's own siblings, is still in
        // flight to bump `mutationEpoch` behind the test's back.
        try #require(
            await fixture.awaitLocalStreamSentinelBarrier(),
            "fixture not live: sentinel batch never arrived"
        )
        try #require(
            await fixture.awaitActivityBarrier(),
            "fixture not quiescent: activity barrier could not be captured"
        )
        let firstAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.firstWorktreeId,
                repositoryPath: fixture.firstRepositoryPath
            )
        )
        let secondAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.secondWorktreeId,
                repositoryPath: fixture.secondRepositoryPath
            )
        )
        let fullGitBatchTask = fixture.collectFullGitRefreshBatches(
            expectedWorktreeIds: [fixture.firstWorktreeId, fixture.secondWorktreeId]
        )

        let replacementParent = try fixture.replaceExternalParent()
        #expect(await fixture.waitForNativeRootChangedCallback())
        let fullGitBatches = try #require(
            await fixture.firstCompletedValue(
                from: fullGitBatchTask,
                timeout: .seconds(5)
            )
        )
        #expect(
            fixture.requiresExact(
                await fixture.provider.renewExactCleanAuthority(firstAuthority)
            )
        )
        #expect(
            fixture.requiresExact(
                await fixture.provider.renewExactCleanAuthority(secondAuthority)
            )
        )
        #expect(Set(fullGitBatches.keys) == [fixture.firstWorktreeId, fixture.secondWorktreeId])

        try await fixture.pointRepositoriesToExternalParent(replacementParent)
        fixture.rebindWorktreeRegistrations()
        // A re-registered stream that has never carried an event cannot yet mint
        // an exact-clean authority, so quiescence alone is not enough here: this
        // site needs the sentinel's STIMULUS, not just the barrier.
        try #require(
            await fixture.awaitLocalStreamSentinelBarrier(),
            "fixture not live after rebinding: sentinel batch never arrived"
        )
        try #require(
            await fixture.awaitActivityBarrier(),
            "fixture not quiescent after rebinding: activity barrier could not be captured"
        )
        let replacementFirstAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.firstWorktreeId,
                repositoryPath: fixture.firstRepositoryPath
            )
        )
        let replacementSecondAuthority = try #require(
            await fixture.establishAuthority(
                worktreeId: fixture.secondWorktreeId,
                repositoryPath: fixture.secondRepositoryPath
            )
        )
        let replacementReadCounts = fixture.readRecorder.snapshot

        #expect(replacementFirstAuthority.registrationGeneration != firstAuthority.registrationGeneration)
        #expect(replacementSecondAuthority.registrationGeneration != secondAuthority.registrationGeneration)
        #expect(
            await fixture.provider.renewExactCleanAuthority(replacementFirstAuthority)
                == .renewed(replacementFirstAuthority)
        )
        #expect(
            await fixture.provider.renewExactCleanAuthority(replacementSecondAuthority)
                == .renewed(replacementSecondAuthority)
        )
        #expect(fixture.readRecorder.snapshot == replacementReadCounts)
        #expect(
            fixture.nativeStreamRecorder.startCount(
                forParentPath: DarwinFSEventPathCanonicalizer.canonicalURL(replacementParent).path
            ) == 1
        )
    }
}

enum SharedExactItemReplacementMutation: CaseIterable, Sendable {
    case delete
    case rename
    case atomicReplacement
}
