import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Darwin shared exact-item real FSEvents integration", .serialized)
struct DarwinSharedExactItemRealStreamIntegrationTests {
    @Test("native shared stream delivers sibling and excludes-file callbacks to dependents")
    func nativeSharedStreamDeliversSiblingAndExcludesCallbacks() async throws {
        let fixture = try await SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        let baselineReadCounts = fixture.readRecorder.snapshot

        #expect(fixture.nativeStreamRecorder.startCount(forParentPath: fixture.externalParentPath) == 1)
        let siblingPath = DarwinFSEventPathCanonicalizer.canonicalURL(
            fixture.unrelatedSiblingPath
        ).path
        let siblingCallback = fixture.nativeStreamRecorder.armCallbackEvent(at: siblingPath)
        try "unrelated\n".write(
            to: fixture.unrelatedSiblingPath,
            atomically: false,
            encoding: .utf8
        )
        _ = try #require(
            await fixture.nativeStreamRecorder.awaitCallbackEvent(siblingCallback),
            "native sibling callback never arrived"
        )
        #expect(fixture.readRecorder.snapshot == baselineReadCounts)

        let fullGitBatchTask = fixture.collectFullGitRefreshBatches(
            expectedWorktreeIds: [fixture.firstWorktreeId, fixture.secondWorktreeId]
        )
        let exactPath = DarwinFSEventPathCanonicalizer.canonicalURL(fixture.excludesFilePath).path
        let exactCallback = fixture.nativeStreamRecorder.armCallbackEvent(at: exactPath)
        try "ignored.txt\nanother-ignored.txt\n".write(
            to: fixture.excludesFilePath,
            atomically: false,
            encoding: .utf8
        )
        _ = try #require(
            await fixture.nativeStreamRecorder.awaitCallbackEvent(exactCallback),
            "native excludes-file callback never arrived"
        )
        let fullGitBatches = await fullGitBatchTask.value

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

    @Test("native watched-parent replacement delivers RootChanged and refresh batches")
    func nativeWatchedParentReplacementDeliversRootChanged() async throws {
        let fixture = try await SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        let fullGitBatchTask = fixture.collectFullGitRefreshBatches(
            expectedWorktreeIds: [fixture.firstWorktreeId, fixture.secondWorktreeId]
        )
        let rootChangedCallback = fixture.nativeStreamRecorder.armRootChangedCallback()
        _ = try fixture.replaceExternalParent()
        _ = try #require(
            await fixture.nativeStreamRecorder.awaitCallbackEvent(rootChangedCallback),
            "native RootChanged callback never arrived"
        )
        let fullGitBatches = await fullGitBatchTask.value
        #expect(Set(fullGitBatches.keys) == [fixture.firstWorktreeId, fixture.secondWorktreeId])
        #expect(fullGitBatches.values.allSatisfy { $0.requiresFullGitRefresh })
        #expect(fullGitBatches.values.allSatisfy { $0.paths.isEmpty })
    }
}

enum SharedExactItemReplacementMutation: CaseIterable, Sendable {
    case delete
    case rename
    case atomicReplacement
}
