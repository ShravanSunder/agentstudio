import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation notification source")
struct WorktreeAnnotationNotificationSourceTests {
    @Test("E3 Comment opening waits for accepted E4 scope before the first capture")
    func batchOpeningWaitsForFirstAcceptedScope() async throws {
        let harness = try makeNotificationSourceHarness()
        let handle = "comment-view-awaiting-scope"
        let (batches, continuation) = AsyncStream.makeStream(
            of: RecordedCommentBatchDelivery.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        let openTask = Task {
            defer { continuation.finish() }
            try await harness.source.openBatch(handle: handle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        await harness.source.waitUntilFirstBatchScopeIsNeeded(handle: handle)
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)

        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            sessionIDs: [],
            scopeRevision: 1
        )
        var iterator = batches.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.mode == .snapshot)
        #expect(initial.batch.scopeRevision == 1)
        #expect(initial.batch.puts.isEmpty)
        openTask.cancel()
        _ = try? await openTask.value
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("retiring a Comment handle releases E3 waiting on first E4 scope")
    func retiringHandleReleasesFirstScopeWaiter() async throws {
        let harness = try makeNotificationSourceHarness()
        let handle = "comment-view-retired-before-scope"
        let openTask = Task {
            try await harness.source.openBatch(handle: handle) { _, _ in
                Issue.record("A retired Comment handle must not capture a catalog")
            }
        }
        await harness.source.waitUntilFirstBatchScopeIsNeeded(handle: handle)
        await harness.source.retireBatchScope(handle: handle)
        await #expect(throws: CancellationError.self) {
            try await openTask.value
        }
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("cancelling E3 releases its first-scope waiter")
    func cancelledOpeningReleasesFirstScopeWaiter() async throws {
        let harness = try makeNotificationSourceHarness()
        let handle = "comment-view-cancelled-before-scope"
        let openTask = Task {
            try await harness.source.openBatch(handle: handle) { _, _ in
                Issue.record("A cancelled Comment opening must not capture a catalog")
            }
        }
        await harness.source.waitUntilFirstBatchScopeIsNeeded(handle: handle)
        openTask.cancel()
        await #expect(throws: CancellationError.self) {
            try await openTask.value
        }
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("three session ranges stay in one dirty union while Comment delivery is held")
    func heldCommentEmissionCoalescesThreeCurrentRanges() async throws {
        let sourceHarness = try makeNotificationSourceHarness()
        let drafts = [
            try await sourceHarness.service.createRootDraft(makeCreateRootDraftProps()),
            try await sourceHarness.service.createRootDraft(makeCreateRootDraftProps()),
            try await sourceHarness.service.createRootDraft(makeCreateRootDraftProps()),
        ]
        let nativeHarness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await nativeHarness.admitMetadataFrames(through: 0)
        var open = bridgeProductLifecycleFileSubscriptionOpenObject(requestSequence: 2, epoch: 2)
        open["subscription"] = ["subscriptionKind": "file.annotations"]
        open["subscriptionId"] = "comment-subscription-coalesced"
        try await nativeHarness.openSubscription(open)
        _ = try #require(
            await consumeNextBridgeProductProducerFrame(
                for: lease,
                from: nativeHarness.session,
                productAdmission: nativeHarness.productAdmission.context
            )
        )
        let view = try #require(
            try await nativeHarness.session.openNativeCommentView(
                subscriptionId: "comment-subscription-coalesced",
                worktreeID: "worktree-1",
                productAdmission: nativeHarness.productAdmission.context
            )
        )
        try await sourceHarness.source.acceptBatchScope(
            handle: view.handle,
            worktreeID: "worktree-1",
            sessionIDs: Set(drafts.map(\.session.id)),
            scopeRevision: 1
        )
        let session = nativeHarness.session
        let productAdmission = nativeHarness.productAdmission.context
        let initialSealed = HeldStep<Void>("initialCommentBatchSealed")
        let (batches, continuation) = AsyncStream.makeStream(
            of: BridgeProductCommentCatalogBatch.self,
            bufferingPolicy: .bufferingOldest(2)
        )
        let openTask = Task {
            defer { continuation.finish() }
            try await sourceHarness.source.openBatch(handle: view.handle) { batch, mode in
                guard
                    try await session.sealCommentCatalogBatch(
                        subscriptionId: "comment-subscription-coalesced",
                        catalogBatch: batch,
                        mode: mode,
                        productAdmission: productAdmission
                    )
                else { throw WorktreeAnnotationServiceError.staleSourceEpoch }
                continuation.yield(batch)
                if batch.baseRevision == 0 { try await initialSealed.arrive(()) }
                guard
                    await session.awaitViewEmissionCompletion(
                        for: view.viewDomain,
                        handle: view.handle
                    ) == .completed
                else { throw WorktreeAnnotationServiceError.staleSourceEpoch }
            }
        }
        var iterator = batches.makeAsyncIterator()
        #expect(try #require(await iterator.next()).baseRevision == 0)
        _ = try await initialSealed.firstArrival()

        for draft in drafts {
            let message = try #require(draft.threads.first?.messages.first)
            _ = try await sourceHarness.service.saveDraft(
                .init(
                    sessionID: draft.session.id,
                    messageID: message.id,
                    editToken: "editor-1",
                    expectedMessageRevision: message.semanticRevision,
                    expectedDraftRevision: try #require(message.draft?.draftRevision),
                    now: Date(timeIntervalSince1970: 3)
                )
            )
        }
        initialSealed.release()
        for _ in 0..<2 {
            _ = try #require(
                await consumeNextBridgeProductProducerFrame(
                    for: lease,
                    from: session,
                    productAdmission: productAdmission
                )
            )
        }

        let current = try #require(await iterator.next())
        #expect(current.baseRevision == 1)
        #expect(current.targetRevision == 2)
        #expect(current.puts.count == 9)
        #expect(current.deletes.isEmpty)
        openTask.cancel()
        _ = try? await openTask.value
        continuation.finish()
        try await nativeHarness.closeProducer(lease)
        #expect(await sourceHarness.service.catalogInvalidationObserverCount() == 0)
        #expect(await session.viewEmissionWaiterByDomain.isEmpty)
    }

    @Test("batch source observes committed ranges after its initial current-row snapshot")
    func batchSourceObservesCommittedRanges() async throws {
        let harness = try makeNotificationSourceHarness()
        let draft = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        try await harness.source.acceptBatchScope(
            handle: "comment-view-1",
            worktreeID: "worktree-1",
            sessionIDs: [draft.session.id],
            scopeRevision: 1
        )
        let (batches, continuation) = AsyncStream.makeStream(
            of: RecordedCommentBatchDelivery.self,
            bufferingPolicy: .bufferingOldest(2)
        )
        let openTask = Task {
            defer { continuation.finish() }
            try await harness.source.openBatch(handle: "comment-view-1") { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        var iterator = batches.makeAsyncIterator()
        guard let initial = await iterator.next() else {
            try await openTask.value
            Issue.record("The initial comment batch did not arrive")
            return
        }
        #expect(initial.mode == .snapshot)
        #expect(initial.batch.baseRevision == 0)
        #expect(initial.batch.targetRevision == 1)
        #expect(initial.batch.puts.count == 3)
        #expect(initial.batch.deletes.isEmpty)

        let message = try #require(draft.threads.first?.messages.first)
        _ = try await harness.service.saveDraft(
            .init(
                sessionID: draft.session.id,
                messageID: message.id,
                editToken: "editor-1",
                expectedMessageRevision: message.semanticRevision,
                expectedDraftRevision: try #require(message.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 3)
            )
        )
        let committed = try #require(await iterator.next())
        #expect(committed.mode == .change)
        #expect(committed.batch.baseRevision == 1)
        #expect(committed.batch.targetRevision == 2)
        #expect(committed.batch.puts.count == 3)
        #expect(committed.batch.deletes.isEmpty)

        await harness.source.requestBatchResnapshot(handle: "comment-view-1")
        let replacement = try #require(await iterator.next())
        #expect(replacement.mode == .snapshot)
        #expect(replacement.batch.baseRevision == 2)
        #expect(replacement.batch.targetRevision == 3)
        #expect(replacement.batch.puts.count == 3)

        openTask.cancel()
        _ = try? await openTask.value
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("an accepted subject change recaptures the same Comment view handle")
    func acceptedSubjectChangeRecapturesView() async throws {
        let harness = try makeNotificationSourceHarness()
        let firstDraft = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        let secondDraft = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        let handle = "comment-view-changing-subjects"
        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            sessionIDs: [firstDraft.session.id],
            scopeRevision: 1
        )
        let (batches, continuation) = AsyncStream.makeStream(
            of: RecordedCommentBatchDelivery.self,
            bufferingPolicy: .bufferingOldest(2)
        )
        let openTask = Task {
            defer { continuation.finish() }
            try await harness.source.openBatch(handle: handle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        var iterator = batches.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.mode == .snapshot)
        #expect(initial.batch.scopeRevision == 1)
        #expect(initial.batch.puts.count == 3)

        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            sessionIDs: [secondDraft.session.id],
            scopeRevision: 2
        )
        let replacement = try #require(await iterator.next())
        #expect(replacement.mode == .snapshot)
        #expect(replacement.batch.handle == handle)
        #expect(replacement.batch.scopeRevision == 2)
        #expect(replacement.batch.baseRevision == 1)
        #expect(replacement.batch.puts.count == 3)
        #expect(replacement.batch.deletes.count == 3)
        openTask.cancel()
        _ = try? await openTask.value
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("a resnapshot requested during held delivery recaptures current admitted rows")
    func heldDeliveryResnapshotRecapturesCurrentRows() async throws {
        let harness = try makeNotificationSourceHarness()
        let draft = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        let handle = "comment-view-lost-ack"
        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            sessionIDs: [draft.session.id],
            scopeRevision: 1
        )
        let initialDelivery = HeldStep<Void>("commentInitialDelivery")
        let (batches, continuation) = AsyncStream.makeStream(
            of: RecordedCommentBatchDelivery.self,
            bufferingPolicy: .bufferingOldest(2)
        )
        let openTask = Task {
            defer { continuation.finish() }
            try await harness.source.openBatch(handle: handle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
                if batch.baseRevision == 0 { try await initialDelivery.arrive(()) }
            }
        }
        var iterator = batches.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.mode == .snapshot)
        _ = try await initialDelivery.firstArrival()

        let message = try #require(draft.threads.first?.messages.first)
        _ = try await harness.service.saveDraft(
            .init(
                sessionID: draft.session.id,
                messageID: message.id,
                editToken: "editor-1",
                expectedMessageRevision: message.semanticRevision,
                expectedDraftRevision: try #require(message.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 3)
            )
        )
        await harness.source.requestBatchResnapshot(handle: handle)
        initialDelivery.release()

        let recaptured = try #require(await iterator.next())
        #expect(recaptured.mode == .snapshot)
        #expect(recaptured.batch.baseRevision == 1)
        #expect(recaptured.batch.targetRevision == 2)
        let currentRows = try await harness.service.captureCurrentCatalogRange(
            worktreeID: "worktree-1",
            range: .worktree
        )
        let recapturedRows = Dictionary(
            uniqueKeysWithValues: recaptured.batch.puts.map { record in
                (WorktreeAnnotationCatalogKey(entry: record.entry), record.entry)
            }
        )
        #expect(recapturedRows == currentRows)
        openTask.cancel()
        _ = try? await openTask.value
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("recovery control invalidation recaptures one current Comment range")
    func recoveryControlRecapturesCurrentRange() async throws {
        let harness = try makeNotificationSourceHarness()
        let draft = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        let handle = "comment-view-recovery-control"
        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            sessionIDs: [draft.session.id],
            scopeRevision: 1
        )
        let (deliveries, continuation) = AsyncStream.makeStream(
            of: RecordedCommentBatchDelivery.self,
            bufferingPolicy: .bufferingOldest(2)
        )
        let openTask = Task {
            defer { continuation.finish() }
            try await harness.source.openBatch(handle: handle) { batch, mode in
                continuation.yield(.init(batch: batch, mode: mode))
            }
        }
        var iterator = deliveries.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.mode == .snapshot)

        await harness.service.applyCommittedChange(
            .control(worktreeIDs: ["worktree-1"], reason: .recovery, sessionChanges: []),
            operationCorrelationID: String(repeating: "c", count: 64)
        )
        let recovered = try #require(await iterator.next())
        #expect(recovered.mode == .change)
        #expect(recovered.batch.baseRevision == initial.batch.targetRevision)
        #expect(recovered.batch.targetRevision == initial.batch.targetRevision + 1)
        let currentRows = try await harness.service.captureCurrentCatalogRange(
            worktreeID: "worktree-1",
            range: .worktree
        )
        #expect(
            Set(recovered.batch.puts.map(\.recordKey))
                == Set(currentRows.keys.map(\.recordKey))
        )
        openTask.cancel()
        _ = try? await openTask.value
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }

    @Test("failed Comment batch delivery terminates the source and removes its observer")
    func batchDeliveryFailureRemovesObserver() async throws {
        let harness = try makeNotificationSourceHarness()
        let draft = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        let handle = "comment-view-failed-delivery"
        try await harness.source.acceptBatchScope(
            handle: handle,
            worktreeID: "worktree-1",
            sessionIDs: [draft.session.id],
            scopeRevision: 1
        )
        let (initialDeliveries, continuation) = AsyncStream.makeStream(
            of: BridgeProductCommentCatalogBatch.self,
            bufferingPolicy: .bufferingOldest(1)
        )
        let openTask = Task {
            defer { continuation.finish() }
            try await harness.source.openBatch(handle: handle) { batch, _ in
                if batch.baseRevision > 0 { throw NotificationDeliveryFailure.injected }
                continuation.yield(batch)
            }
        }
        var iterator = initialDeliveries.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let message = try #require(draft.threads.first?.messages.first)
        _ = try await harness.service.saveDraft(
            .init(
                sessionID: draft.session.id,
                messageID: message.id,
                editToken: "editor-1",
                expectedMessageRevision: message.semanticRevision,
                expectedDraftRevision: try #require(message.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 3)
            )
        )
        await #expect(throws: NotificationDeliveryFailure.injected) {
            try await openTask.value
        }
        continuation.finish()
        #expect(await harness.service.catalogInvalidationObserverCount() == 0)
    }
}

private struct NotificationSourceHarness {
    let service: WorktreeAnnotationServiceActor
    let source: BridgePaneAnnotationNotificationSource
}

private func makeNotificationSourceHarness() throws -> NotificationSourceHarness {
    let repository = try makeAnnotationRepository()
    let service = WorktreeAnnotationServiceActor(
        repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
    )
    return .init(
        service: service,
        source: BridgePaneAnnotationNotificationSource(
            service: service,
            worktreeID: "worktree-1"
        )
    )
}

private struct RecordedCommentBatchDelivery: Sendable {
    let batch: BridgeProductCommentCatalogBatch
    let mode: BridgeProductBatchMode
}

private enum NotificationDeliveryFailure: Error {
    case injected
}
