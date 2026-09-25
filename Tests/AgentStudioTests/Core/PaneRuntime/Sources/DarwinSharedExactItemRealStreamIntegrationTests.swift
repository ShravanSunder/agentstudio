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
        // The sentinel proves each local event path is live. The coverage barrier
        // then proves the local and shared bindings are current and quiescent
        // before the first exact read.
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
        _ = try await fixture.fenceSecondAuthorityWindow()
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

    @Test("native atomic replacement invalidates exact-item authority")
    func nativeAtomicReplacementInvalidatesAuthority() async throws {
        let fixture = try await SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        try #require(
            await fixture.awaitActivityBarrier(),
            "native local and shared bindings could not be captured"
        )
        let authority = try await fixture.establishAuthorityAfterOverlappingMutation(
            worktreeId: fixture.firstWorktreeId,
            repositoryPath: fixture.firstRepositoryPath
        )
        let baselineReadCounts = fixture.readRecorder.snapshot
        let fullGitBatchTask = fixture.collectFullGitRefreshBatches(
            expectedWorktreeIds: [fixture.firstWorktreeId, fixture.secondWorktreeId]
        )

        try fixture.perform(.atomicReplacement)
        let fullGitBatches = await fullGitBatchTask.value
        #expect(
            fixture.requiresExact(
                await fixture.provider.renewExactCleanAuthority(authority)
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
        // The sentinel proves each local event path is live. The coverage barrier
        // then proves the local and shared bindings are current and quiescent
        // before the first exact read.
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
        _ = try await fixture.fenceSecondAuthorityWindow()
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
        try await fixture.rebindWorktreeRegistrations()
        // Prove the replacement registrations' local event paths are live before
        // the coverage barrier verifies their current local and shared bindings.
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
        _ = try await fixture.fenceSecondAuthorityWindow()
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
