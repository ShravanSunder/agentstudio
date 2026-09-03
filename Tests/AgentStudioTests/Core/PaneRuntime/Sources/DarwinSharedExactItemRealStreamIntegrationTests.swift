import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Darwin shared exact-item real FSEvents integration", .serialized)
struct DarwinSharedExactItemRealStreamIntegrationTests {
    @Test("native shared stream routes sibling misses and exact hits to every dependent")
    func nativeSharedStreamRoutesSiblingMissesAndExactHits() async throws {
        let fixture = try SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        try #require(await fixture.awaitLocalStreamSentinelBarrier())

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
        try "[core]\n\tfilemode = true\n".write(
            to: fixture.includedConfigurationPath,
            atomically: false,
            encoding: .utf8
        )
        #expect(await fixture.waitForNativeCallback(at: fixture.includedConfigurationPath))
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
        let fixture = try SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        try #require(await fixture.awaitLocalStreamSentinelBarrier())
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
        #expect(
            await fixture.provider.renewExactCleanAuthority(firstAuthority)
                == .renewed(firstAuthority)
        )
        #expect(
            await fixture.provider.renewExactCleanAuthority(secondAuthority)
                == .renewed(secondAuthority)
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
        let fixture = try SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        try #require(await fixture.awaitLocalStreamSentinelBarrier())
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

        try fixture.pointRepositoriesToExternalParent(replacementParent)
        fixture.rebindWorktreeRegistrations()
        try #require(await fixture.awaitLocalStreamSentinelBarrier())
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
