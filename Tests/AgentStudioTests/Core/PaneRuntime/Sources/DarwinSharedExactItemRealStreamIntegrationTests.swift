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

    @Test("native atomic replacement callback classifies as relevant exact-item activity")
    func nativeAtomicReplacementCallbackClassifiesAsRelevantExactItemActivity() async throws {
        let fixture = try await SharedExactItemRealStreamFixture(nativeSharedStreamIsEnabled: true)
        defer { fixture.remove() }
        try #require(
            await fixture.awaitActivityBarrier(),
            "native local and shared bindings could not be captured"
        )
        let baselineReadCounts = fixture.readRecorder.snapshot
        let fullGitBatchTask = fixture.collectFullGitRefreshBatches(
            expectedWorktreeIds: [fixture.firstWorktreeId]
        )
        let exactPath = DarwinFSEventPathCanonicalizer.canonicalURL(fixture.excludesFilePath).path
        let exactCallback = fixture.nativeStreamRecorder.armCallbackEvent(at: exactPath)

        try fixture.perform(.atomicReplacement)
        let callbackEventID = try #require(
            await fixture.nativeStreamRecorder.awaitCallbackEvent(exactCallback),
            "native exact-item replacement callback never arrived"
        )
        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: [(path: exactPath, eventId: callbackEventID, flags: 0)],
            ordinaryPaths: [],
            rootPath: DarwinFSEventPathCanonicalizer.canonicalURL(
                fixture.firstRepositoryPath
            ).path,
            observationScopes: [
                AgentStudioGit.GitStatusObservationScope(
                    kind: .item,
                    path: URL(fileURLWithPath: exactPath)
                )
            ]
        )
        #expect(classification.rawEvents.map(\.hasRelevantMutation) == [true])

        let fullGitBatches = await fullGitBatchTask.value
        #expect(Set(fullGitBatches.keys) == [fixture.firstWorktreeId])
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

        let sentinelPath = fixture.firstRepositoryPath
            .appending(path: ".git", directoryHint: .isDirectory)
            .appending(path: "agentstudio-real-stream-sentinel")
        let sentinelBatchTask = fixture.armLocalSentinelCallback(
            at: sentinelPath,
            for: fixture.firstWorktreeId
        )
        try "after RootChanged\n".write(
            to: sentinelPath,
            atomically: false,
            encoding: .utf8
        )
        let sentinelBatch = try #require(
            await sentinelBatchTask.value,
            "rebound local stream did not deliver the armed sentinel callback"
        )
        let canonicalSentinelPath = DarwinFSEventPathCanonicalizer.canonicalURL(sentinelPath).path
        #expect(sentinelBatch.worktreeId == fixture.firstWorktreeId)
        #expect(
            sentinelBatch.paths.contains {
                DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath($0)
                    == canonicalSentinelPath
            }
        )
    }
}

enum SharedExactItemReplacementMutation: CaseIterable, Sendable {
    case delete
    case rename
    case atomicReplacement
}
