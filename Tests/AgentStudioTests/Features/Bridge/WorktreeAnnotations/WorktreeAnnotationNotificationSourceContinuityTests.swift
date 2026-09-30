import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation notification source continuity")
struct WorktreeAnnotationCommentContinuityTests {
    @Test("a restarted Comment producer continues revisions and deletion tombstones")
    func retainedViewContinuesRevisionsAndTombstonesAfterProducerRestart() async throws {
        let harness = try makeNotificationSourceHarness()
        let changedDraft = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        let deletedDraft = try await harness.service.createRootDraft(
            .init(
                admission: .selected(changedDraft.session.id),
                repositoryID: "repo-1",
                worktreeID: "worktree-1",
                sourceFingerprint: makeSourceFingerprint(identity: "source-1"),
                origin: .session,
                body: "Draft to delete",
                editToken: "editor-2",
                now: Date(timeIntervalSince1970: 2)
            )
        )
        #expect(deletedDraft.session.id == changedDraft.session.id)
        let handle = "retained-comment-view-with-catalog"
        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            scopeRevision: 1
        )
        let (batches, continuation) = AsyncStream.makeStream(
            of: RecordedCommentBatchDelivery.self,
            bufferingPolicy: .bufferingOldest(2)
        )
        let firstProducer = Task {
            try await harness.source.openBatch(handle: handle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        var iterator = batches.makeAsyncIterator()
        let installed = try #require(await iterator.next())
        #expect(installed.mode == .snapshot)
        let previousCursor = installed.batch.targetRevision
        #expect(previousCursor > 0)
        let changedSessionKey = WorktreeAnnotationCatalogKey.session(changedDraft.session.id)
        let previousSessionRevision = try sessionSemanticRevision(
            in: installed.batch,
            for: changedSessionKey
        )

        firstProducer.cancel()
        _ = try? await firstProducer.value
        await harness.source.releaseProducerBatchScope(handle: handle)

        let changedMessage = try #require(changedDraft.threads.first?.messages.first)
        let detailAfterSave = try await harness.service.saveDraft(
            .init(
                sessionID: changedDraft.session.id,
                messageID: changedMessage.id,
                editToken: "editor-1",
                expectedMessageRevision: changedMessage.semanticRevision,
                expectedDraftRevision: try #require(changedMessage.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 3)
            )
        )
        let originalThreadIDs = Set(changedDraft.threads.map(\.thread.id))
        let deletedThreadDetail = try #require(
            detailAfterSave.threads.first { !originalThreadIDs.contains($0.thread.id) }
        )
        let deletedMessage = try #require(deletedThreadDetail.messages.first)
        _ = try await harness.service.revertDraft(
            .init(
                sessionID: detailAfterSave.session.id,
                messageID: deletedMessage.id,
                editToken: "editor-2",
                expectedMessageRevision: deletedMessage.semanticRevision,
                expectedDraftRevision: try #require(deletedMessage.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 4)
            )
        )

        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            scopeRevision: 1
        )
        let successor = Task {
            try await harness.source.openBatch(handle: handle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        let resumed = try #require(await iterator.next())
        let deletedKeys: Set<WorktreeAnnotationCatalogKey> = [
            .thread(deletedThreadDetail.thread.id),
            .message(deletedMessage.id),
        ]
        try expectResumedBatchContinuesView(
            resumed,
            handle: handle,
            previousCursor: previousCursor,
            previousSessionRevision: previousSessionRevision,
            changedSessionKey: changedSessionKey,
            deletedKeys: deletedKeys
        )

        successor.cancel()
        _ = try? await successor.value
        await harness.source.retireBatchView(handle: handle)
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("a new Comment incarnation starts clean after the prior view retires")
    func newIncarnationStartsCleanAfterViewRetirement() async throws {
        let harness = try makeNotificationSourceHarness()
        _ = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        let handle = "ended-comment-view"
        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            scopeRevision: 1
        )
        let (batches, continuation) = AsyncStream.makeStream(
            of: RecordedCommentBatchDelivery.self,
            bufferingPolicy: .bufferingOldest(2)
        )
        let endedProducer = Task {
            try await harness.source.openBatch(handle: handle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        var iterator = batches.makeAsyncIterator()
        let priorIncarnation = try #require(await iterator.next())
        #expect(priorIncarnation.batch.targetRevision == 1)
        endedProducer.cancel()
        _ = try? await endedProducer.value
        await harness.source.retireBatchView(handle: handle)
        await #expect(throws: WorktreeAnnotationServiceError.unavailable) {
            try await harness.source.acceptBatchScope(
                handle: handle,
                worktreeID: "worktree-1",
                scopeRevision: 2
            )
        }

        let newHandle = "replacement-comment-view"
        try await harness.source.acceptBatchScope(
            handle: newHandle,
            worktreeID: "worktree-1",
            scopeRevision: 1
        )
        let replacementProducer = Task {
            try await harness.source.openBatch(handle: newHandle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        let newIncarnation = try #require(await iterator.next())
        #expect(newIncarnation.batch.handle == newHandle)
        #expect(newIncarnation.batch.baseRevision == 0)
        #expect(newIncarnation.batch.targetRevision == 1)
        #expect(newIncarnation.batch.deletes.isEmpty)
        replacementProducer.cancel()
        _ = try? await replacementProducer.value
        await harness.source.retireBatchView(handle: newHandle)
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }
}

private func sessionSemanticRevision(
    in batch: BridgeProductCommentCatalogBatch,
    for key: WorktreeAnnotationCatalogKey
) throws -> Int {
    let put = try #require(
        batch.puts.first { WorktreeAnnotationCatalogKey(entry: $0.entry) == key }
    )
    if case .session(let session) = put.entry {
        return session.semanticRevision
    }
    Issue.record("The catalog batch omitted the expected session entry")
    return -1
}

private func expectResumedBatchContinuesView(
    _ delivery: RecordedCommentBatchDelivery,
    handle: String,
    previousCursor: Int,
    previousSessionRevision: Int,
    changedSessionKey: WorktreeAnnotationCatalogKey,
    deletedKeys: Set<WorktreeAnnotationCatalogKey>
) throws {
    #expect(delivery.mode == .snapshot)
    #expect(delivery.batch.handle == handle)
    #expect(delivery.batch.baseRevision == previousCursor)
    #expect(delivery.batch.targetRevision > previousCursor)
    #expect(delivery.batch.puts.allSatisfy { $0.revision > previousCursor })

    let changedSessionPut = try #require(
        delivery.batch.puts.first {
            WorktreeAnnotationCatalogKey(entry: $0.entry) == changedSessionKey
        }
    )
    if case .session(let session) = changedSessionPut.entry {
        #expect(session.semanticRevision > previousSessionRevision)
    } else {
        Issue.record("The resumed catalog batch omitted the changed session")
    }

    #expect(Set(delivery.batch.deletes.map(\.key)) == deletedKeys)
    #expect(delivery.batch.deletes.allSatisfy { $0.revision > previousCursor })
}
