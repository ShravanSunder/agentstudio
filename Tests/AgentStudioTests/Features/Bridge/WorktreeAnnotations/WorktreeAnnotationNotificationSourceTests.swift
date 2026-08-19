import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation notification source")
struct WorktreeAnnotationNotificationSourceTests {
    @Test("registration emits snapshot-required then broadcasts committed changes")
    func registrationAndCommittedChangeAreGapFree() async throws {
        let repository = try makeAnnotationRepository()
        let service = WorktreeAnnotationServiceActor(
            repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
        )
        let source = BridgePaneAnnotationNotificationSource(
            service: service,
            worktreeID: "worktree-1"
        )
        let (events, continuation) = AsyncStream<BridgeProductWorktreeAnnotationEvent>.makeStream()
        var iterator = events.makeAsyncIterator()
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

        let openTask = Task {
            try await source.open(subscription: subscription) { event in
                continuation.yield(event)
            }
        }
        #expect(await iterator.next()?.sourceGeneration == 0)
        _ = try await service.createRootDraft(
            makeCreateRootDraftProps(),
            ownerGeneration: "worker-a"
        )
        let committedEvent = try BridgeProductWorktreeAnnotationEvent(
            sourceGeneration: 1,
            worktreeID: "worktree-1"
        )
        #expect(await iterator.next() == committedEvent)

        openTask.cancel()
        _ = try? await openTask.value
        #expect(await service.changeObserverCount() == 0)
        continuation.finish()
    }

    @Test("delivery failure terminates the supervised source and removes its observer")
    func deliveryFailureTerminatesSourceAndRemovesObserver() async throws {
        let repository = try makeAnnotationRepository()
        let service = WorktreeAnnotationServiceActor(
            repositoryAccess: RepositoryBackedWorktreeAnnotationAccess(repository: repository)
        )
        let source = BridgePaneAnnotationNotificationSource(
            service: service,
            worktreeID: "worktree-1"
        )
        let (initialEvents, continuation) = AsyncStream<Int>.makeStream()
        var iterator = initialEvents.makeAsyncIterator()
        let interestState = BridgeProductSubscriptionInterestState.fileAnnotations
        let subscription = BridgeProductSubscriptionSnapshot(
            subscription: .fileAnnotations,
            subscriptionId: "pane-failing",
            subscriptionKind: .fileAnnotations,
            workerDerivationEpoch: 0,
            interestRevision: 0,
            interestSha256: try interestState.sha256Hex(),
            interestState: interestState,
            hasStagedUpdate: false
        )
        let openTask = Task {
            try await source.open(subscription: subscription) { event in
                guard event.sourceGeneration == 0 else {
                    throw NotificationDeliveryFailure.injected
                }
                continuation.yield(event.sourceGeneration)
            }
        }
        #expect(await iterator.next() == 0)

        _ = try await service.createRootDraft(
            makeCreateRootDraftProps(),
            ownerGeneration: "worker-a"
        )

        await #expect(throws: NotificationDeliveryFailure.injected) {
            try await openTask.value
        }
        #expect(await service.changeObserverCount() == 0)
        continuation.finish()
    }
}

private enum NotificationDeliveryFailure: Error {
    case injected
}
