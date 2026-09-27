import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation notification source")
struct WorktreeAnnotationNotificationSourceTests {
    @Test("two committed edits while a Comment batch is held converge through one current range")
    func heldCommentEmissionCoalescesCurrentRange() async throws {
        let sourceHarness = try makeNotificationSourceHarness()
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

        let draft = try await sourceHarness.service.createRootDraft(makeCreateRootDraftProps())
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
        #expect(current.puts.count == 3)
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
        #expect(initial.batch.puts.isEmpty)
        #expect(initial.batch.deletes.isEmpty)

        _ = try await harness.service.createRootDraft(makeCreateRootDraftProps())
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

    @Test("bootstrap emits an empty catalog and awaits observation of every phase")
    func bootstrapEmitsEmptyCatalogAndAwaitsEveryPhaseObservation() async throws {
        let harness = try makeNotificationSourceHarness(automaticallyObserve: false)
        let openTask = Task {
            try await harness.source.open(
                subscription: harness.subscription,
                surface: .file,
                delivery: makeNotificationDelivery(
                    recorder: harness.recorder,
                    subscription: harness.subscription
                )
            )
        }

        guard
            await waitUntilNotificationState(
                "catalog begin should enqueue",
                condition: {
                    await harness.recorder.eventCount == 1
                })
        else {
            openTask.cancel()
            return
        }
        let begin = try #require(await harness.recorder.events.first)
        guard case .catalog(let beginEvent) = begin.event,
            case .begin(let beginTransfer) = beginEvent.transfer
        else {
            Issue.record("Expected empty catalog begin")
            openTask.cancel()
            return
        }
        #expect(beginEvent.authority.worktreeID == "worktree-1")
        #expect(beginEvent.authority.applicationSourceGeneration == 0)
        #expect(beginTransfer.expectedEntryCount == 0)
        guard
            await waitUntilNotificationState(
                "catalog begin observation waiter should register",
                condition: {
                    await harness.recorder.pendingObservationSequences == [begin.sequence]
                })
        else {
            openTask.cancel()
            return
        }
        #expect(await harness.recorder.pendingObservationSequences == [begin.sequence])
        #expect(await harness.recorder.eventCount == 1)

        await harness.recorder.acknowledge(sequence: begin.sequence)
        guard
            await waitUntilNotificationState(
                "catalog commit should enqueue after begin observation",
                condition: { await harness.recorder.eventCount == 2 }
            )
        else {
            openTask.cancel()
            return
        }
        let commit = try #require(await harness.recorder.events.last)
        guard case .catalog(let commitEvent) = commit.event,
            case .commit(let commitTransfer) = commitEvent.transfer
        else {
            Issue.record("Expected empty catalog commit")
            openTask.cancel()
            return
        }
        #expect(commitEvent.authority == beginEvent.authority)
        #expect(commitTransfer.windowCount == 0)
        #expect(commitTransfer.entryCount == 0)
        #expect(commit.operationCorrelationID == begin.operationCorrelationID)
        #expect(commit.operationCorrelationID.count == 64)
        guard
            await waitUntilNotificationState(
                "catalog commit observation waiter should register",
                condition: {
                    await harness.recorder.pendingObservationSequences == [commit.sequence]
                })
        else {
            openTask.cancel()
            return
        }
        #expect(await harness.recorder.pendingObservationSequences == [commit.sequence])

        await harness.recorder.acknowledge(sequence: commit.sequence)
        #expect(
            await waitUntilNotificationState(
                "source should enter its observation loop",
                condition: {
                    await harness.service.changeObserverCount() == 1
                })
        )
        #expect(await harness.recorder.observedSequences == [begin.sequence, commit.sequence])
        openTask.cancel()
        _ = try? await openTask.value
        #expect(await harness.service.changeObserverCount() == 0)
    }

    @Test("topology mutation replaces the catalog")
    func topologyMutationReplacesCatalog() async throws {
        let harness = try makeNotificationSourceHarness()
        let openTask = Task {
            try await harness.source.open(
                subscription: harness.subscription,
                surface: .file,
                delivery: makeNotificationDelivery(
                    recorder: harness.recorder,
                    subscription: harness.subscription
                )
            )
        }
        guard
            await waitUntilNotificationState(
                "bootstrap catalog should finish",
                condition: {
                    await harness.recorder.eventCount == 2
                })
        else {
            openTask.cancel()
            return
        }

        _ = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        guard
            await waitUntilNotificationState(
                "replacement catalog should finish",
                condition: {
                    await harness.recorder.eventCount == 5
                })
        else {
            openTask.cancel()
            return
        }

        let replacement = Array(await harness.recorder.events.suffix(3))
        let replacementCatalogs = try replacement.map { recorded in
            guard case .catalog(let event) = recorded.event else {
                throw NotificationSourceTestFailure.unexpectedEvent
            }
            return event
        }
        #expect(replacementCatalogs.map(\.authority.applicationSourceGeneration) == [1, 1, 1])
        #expect(
            replacement.map(\.operationCorrelationID)
                .allSatisfy { $0 == replacement[0].operationCorrelationID }
        )
        guard case .begin(let begin) = replacementCatalogs[0].transfer,
            case .window(let window) = replacementCatalogs[1].transfer,
            case .commit(let commit) = replacementCatalogs[2].transfer
        else {
            Issue.record("Expected begin, window, commit replacement")
            openTask.cancel()
            return
        }
        #expect(begin.expectedEntryCount == 3)
        #expect(window.windowOrdinal == 0)
        #expect(window.entries.count == 3)
        #expect(commit.windowCount == 1)
        #expect(commit.entryCount == 3)

        openTask.cancel()
        _ = try? await openTask.value
        #expect(await harness.service.changeObserverCount() == 0)
    }

    @Test("rich content mutation emits session-changed without a catalog")
    func contentMutationEmitsSessionChangedWithoutCatalog() async throws {
        let harness = try makeNotificationSourceHarness()
        let openTask = Task {
            try await harness.source.open(
                subscription: harness.subscription,
                surface: .file,
                delivery: makeNotificationDelivery(
                    recorder: harness.recorder,
                    subscription: harness.subscription
                )
            )
        }
        guard
            await waitUntilNotificationState(
                "bootstrap catalog should finish",
                condition: {
                    await harness.recorder.eventCount == 2
                })
        else {
            openTask.cancel()
            return
        }

        let draftDetail = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        guard
            await waitUntilNotificationState(
                "topology catalog should finish",
                condition: {
                    await harness.recorder.eventCount == 5
                })
        else {
            openTask.cancel()
            return
        }
        let draftMessage = try #require(draftDetail.threads.first?.messages.first)
        let savedDetail = try await harness.service.saveDraft(
            .init(
                sessionID: draftDetail.session.id,
                messageID: draftMessage.id,
                editToken: "editor-1",
                expectedMessageRevision: draftMessage.semanticRevision,
                expectedDraftRevision: try #require(draftMessage.draft?.draftRevision),
                now: Date(timeIntervalSince1970: 3)
            )
        )
        guard
            await waitUntilNotificationState(
                "session change should enqueue",
                condition: {
                    await harness.recorder.eventCount == 6
                })
        else {
            openTask.cancel()
            return
        }

        let recorded = try #require(await harness.recorder.events.last)
        guard case .sessionChanged(let event) = recorded.event else {
            Issue.record("Expected session-changed after content-only mutation")
            openTask.cancel()
            return
        }
        #expect(event.authority.worktreeID == "worktree-1")
        #expect(event.authority.applicationSourceGeneration == 2)
        #expect(event.sessionID == savedDetail.session.id)
        #expect(event.semanticRevision == savedDetail.session.semanticRevision)
        #expect(recorded.operationCorrelationID.count == 64)
        #expect(await harness.recorder.eventCount == 6)

        openTask.cancel()
        _ = try? await openTask.value
        #expect(await harness.service.changeObserverCount() == 0)
    }

    @Test("recovery control mutation emits one control-changed event")
    func recoveryControlMutationEmitsOneControlChangedEvent() async throws {
        let harness = try makeNotificationSourceHarness()
        let openTask = Task {
            try await harness.source.open(
                subscription: harness.subscription,
                surface: .file,
                delivery: makeNotificationDelivery(
                    recorder: harness.recorder,
                    subscription: harness.subscription
                )
            )
        }
        guard
            await waitUntilNotificationState(
                "bootstrap catalog should finish",
                condition: {
                    await harness.recorder.eventCount == 2
                })
        else {
            openTask.cancel()
            return
        }

        let operationCorrelationID = String(repeating: "c", count: 64)
        await harness.service.applyCommittedChange(
            .control(
                worktreeIDs: ["worktree-1"],
                reason: .recovery,
                sessionChanges: []
            ),
            operationCorrelationID: operationCorrelationID
        )
        guard
            await waitUntilNotificationState(
                "recovery control change should enqueue",
                condition: {
                    await harness.recorder.eventCount == 3
                })
        else {
            openTask.cancel()
            return
        }

        let recorded = try #require(await harness.recorder.events.last)
        guard case .controlChanged(let event) = recorded.event else {
            Issue.record("Expected control-changed after recovery mutation")
            openTask.cancel()
            return
        }
        #expect(event.authority.worktreeID == "worktree-1")
        #expect(event.authority.applicationSourceGeneration == 1)
        #expect(event.reason == .recovery)
        #expect(recorded.operationCorrelationID == operationCorrelationID)
        #expect(await harness.recorder.eventCount == 3)

        openTask.cancel()
        _ = try? await openTask.value
        #expect(await harness.service.changeObserverCount() == 0)
    }

    @Test("delivery failure terminates the supervised source and removes its observer")
    func deliveryFailureTerminatesSourceAndRemovesObserver() async throws {
        let harness = try makeNotificationSourceHarness(failingSequence: 3)
        let openTask = Task {
            try await harness.source.open(
                subscription: harness.subscription,
                surface: .file,
                delivery: makeNotificationDelivery(
                    recorder: harness.recorder,
                    subscription: harness.subscription
                )
            )
        }
        guard
            await waitUntilNotificationState(
                "bootstrap catalog should finish",
                condition: {
                    await harness.recorder.eventCount == 2
                })
        else {
            openTask.cancel()
            return
        }

        _ = try await harness.service.createRootDraft(makeCreateRootDraftProps())
        await #expect(throws: NotificationDeliveryFailure.injected) {
            try await openTask.value
        }
        #expect(
            await waitUntilNotificationState(
                "delivery failure should remove observer",
                condition: {
                    await harness.service.changeObserverCount() == 0
                })
        )
    }
}

private struct NotificationSourceHarness {
    let recorder: NotificationDeliveryRecorder
    let service: WorktreeAnnotationServiceActor
    let source: BridgePaneAnnotationNotificationSource
    let subscription: BridgeProductSubscriptionSnapshot
}

private func makeNotificationSourceHarness(
    automaticallyObserve: Bool = true,
    failingSequence: Int? = nil
) throws -> NotificationSourceHarness {
    let repository = try makeAnnotationRepository()
    let service = WorktreeAnnotationServiceActor(
        repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
    )
    let interestState = BridgeProductSubscriptionInterestState.fileAnnotations
    let subscription = BridgeProductSubscriptionSnapshot(
        subscription: .fileAnnotations,
        subscriptionId: "pane-a",
        subscriptionKind: .fileAnnotations,
        workerDerivationEpoch: 0,
        interestRevision: 0,
        interestSha256: try interestState.sha256Hex(),
        interestState: interestState,
        hasStagedUpdate: false
    )
    return .init(
        recorder: NotificationDeliveryRecorder(
            automaticallyObserve: automaticallyObserve,
            failingSequence: failingSequence
        ),
        service: service,
        source: BridgePaneAnnotationNotificationSource(
            service: service,
            worktreeID: "worktree-1"
        ),
        subscription: subscription
    )
}

private func makeNotificationDelivery(
    recorder: NotificationDeliveryRecorder,
    subscription: BridgeProductSubscriptionSnapshot
) -> BridgePaneAnnotationNotificationDelivery {
    .init(
        enqueue: { event, operationCorrelationID in
            try await recorder.enqueue(event, operationCorrelationID: operationCorrelationID)
        },
        makeProspectiveMetadataFrame: { event, operationCorrelationID in
            try BridgePaneProductMetadataCoordinator.makeProspectiveMetadataFrame(
                event: event,
                operationCorrelationID: operationCorrelationID,
                stream: .init(
                    metadataStreamId: "metadata-stream-a",
                    paneSessionId: "pane-session-a",
                    wireVersion: BridgeProductWireContract.version,
                    workerInstanceId: "worker-a"
                ),
                subscription: subscription
            )
        },
        waitUntilObserved: { sequence in
            await recorder.waitUntilObserved(sequence)
        }
    )
}

private actor NotificationDeliveryRecorder {
    struct RecordedEvent: Sendable {
        let event: BridgeProductWorktreeAnnotationEvent
        let operationCorrelationID: String
        let sequence: Int
    }

    private let automaticallyObserve: Bool
    private let failingSequence: Int?
    private var nextSequence = 1
    private var observationWaiterBySequence: [Int: CheckedContinuation<Bool, Never>] = [:]
    private(set) var events: [RecordedEvent] = []
    private(set) var observedSequences: [Int] = []

    init(automaticallyObserve: Bool, failingSequence: Int?) {
        self.automaticallyObserve = automaticallyObserve
        self.failingSequence = failingSequence
    }

    var eventCount: Int { events.count }

    var pendingObservationSequences: [Int] {
        observationWaiterBySequence.keys.sorted()
    }

    func enqueue(
        _ event: BridgeProductWorktreeAnnotationEvent,
        operationCorrelationID: String
    ) throws -> BridgeProductProducerEnqueueResult {
        let sequence = nextSequence
        if sequence == failingSequence {
            throw NotificationDeliveryFailure.injected
        }
        nextSequence += 1
        events.append(
            .init(
                event: event,
                operationCorrelationID: operationCorrelationID,
                sequence: sequence
            )
        )
        return .enqueued(
            .init(
                data: Data([UInt8(sequence)]),
                sequence: sequence,
                terminal: false,
                requiredOpening: false
            )
        )
    }

    func waitUntilObserved(_ sequence: Int) async -> Bool {
        if automaticallyObserve {
            observedSequences.append(sequence)
            return true
        }
        return await withCheckedContinuation { continuation in
            observationWaiterBySequence[sequence] = continuation
        }
    }

    func acknowledge(sequence: Int) {
        observedSequences.append(sequence)
        observationWaiterBySequence.removeValue(forKey: sequence)?.resume(returning: true)
    }
}

private struct RecordedCommentBatchDelivery: Sendable {
    let batch: BridgeProductCommentCatalogBatch
    let mode: BridgeProductBatchMode
}

private func waitUntilNotificationState(
    _ description: String,
    maximumTurns: Int = 20_000,
    condition: () async -> Bool
) async -> Bool {
    for _ in 0..<maximumTurns {
        if await condition() { return true }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(description)")
    return false
}

private enum NotificationDeliveryFailure: Error {
    case injected
}

private enum NotificationSourceTestFailure: Error {
    case unexpectedEvent
}
