import Foundation

private struct BridgeWorktreeAnnotationSubscriptionOpenRequest {
    let activeStream: BridgePaneProductMetadataCoordinator.ActiveStream
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    let productAdmission: BridgeProductAdmissionContext
    let subscription: BridgeProductSubscriptionSnapshot
}

extension BridgePaneProductMetadataCoordinator {
    func startSubscriptionOpen(
        _ subscription: BridgeProductSubscriptionSnapshot,
        activeStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) {
        producerTaskLifecycle.startBootstrapTask(
            subscriptionId: subscription.subscriptionId,
            subscriptionKind: subscription.subscriptionKind,
            executionContext: .init(
                foregroundWorkAdmission: foregroundWorkAdmission,
                productAdmission: productAdmission,
                session: activeStream.session
            ),
            taskFinished: { [weak self] subscriptionId, taskId, shouldRetireSubscription in
                await self?.bootstrapProducerTaskFinished(
                    subscriptionId: subscriptionId,
                    taskId: taskId,
                    shouldRetireSubscription: shouldRetireSubscription
                )
            },
            operation: { traceContext in
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                }
                switch subscription.subscriptionKind {
                case .fileAnnotations, .reviewAnnotations:
                    try await self.openWorktreeAnnotationSubscription(
                        .init(
                            activeStream: activeStream,
                            foregroundWorkAdmission: foregroundWorkAdmission,
                            productAdmission: productAdmission,
                            subscription: subscription
                        )
                    )
                case .fileMetadata:
                    try await self.fileMetadataSource.open(
                        subscription: subscription,
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission
                    ) { event in
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            productAdmission: productAdmission,
                            foregroundWorkAdmission: foregroundWorkAdmission,
                            session: activeStream.session
                        )
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        await self.recordEnqueued(event, traceContext: traceContext)
                    }
                case .reviewMetadata:
                    try await self.reviewMetadataSource.open(
                        subscription: subscription,
                        productAdmission: productAdmission
                    ) { event, emittedAdmission in
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        guard emittedAdmission.matches(productAdmission),
                            await self.isReviewPublicationCurrent(
                                event.publicationId,
                                emittedAdmission
                            )
                        else {
                            throw CancellationError()
                        }
                        let enqueueResult = try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            productAdmission: emittedAdmission,
                            foregroundWorkAdmission: foregroundWorkAdmission,
                            session: activeStream.session
                        )
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        await self.recordEnqueued(event, traceContext: traceContext)
                        return enqueueResult
                    }
                    await self.replayCommittedReviewPublicationIfPresent(
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission,
                        traceContext: traceContext
                    )
                }
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                }
                await self.recordSourceOpened(
                    subscriptionId: subscription.subscriptionId,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            }
        )
    }

    private func openWorktreeAnnotationSubscription(
        _ request: BridgeWorktreeAnnotationSubscriptionOpenRequest
    ) async throws {
        try await annotationSource.open(
            subscription: request.subscription,
            surface: request.subscription.subscriptionKind.surface
        ) { event in
            guard request.foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
            }
            try await Self.enqueue(
                event: event,
                subscriptionKind: request.subscription.subscriptionKind,
                subscriptionId: request.subscription.subscriptionId,
                productAdmission: request.productAdmission,
                foregroundWorkAdmission: request.foregroundWorkAdmission,
                session: request.activeStream.session
            )
        }
    }

    func startSubscriptionUpdate(
        _ subscription: BridgeProductSubscriptionSnapshot,
        activeStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) {
        producerTaskLifecycle.startInterestTask(
            subscriptionId: subscription.subscriptionId,
            subscriptionKind: subscription.subscriptionKind,
            executionContext: .init(
                foregroundWorkAdmission: foregroundWorkAdmission,
                productAdmission: productAdmission,
                session: activeStream.session
            ),
            taskFinished: { [weak self] subscriptionId, taskId, shouldRetireSubscription in
                await self?.interestProducerTaskFinished(
                    subscriptionId: subscriptionId,
                    taskId: taskId,
                    shouldRetireSubscription: shouldRetireSubscription
                )
            },
            operation: { traceContext in
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                }
                switch subscription.subscriptionKind {
                case .fileAnnotations, .reviewAnnotations:
                    try await self.annotationSource.update(subscription: subscription)
                case .fileMetadata:
                    try await self.fileMetadataSource.update(
                        subscription: subscription,
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission
                    ) { event in
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            productAdmission: productAdmission,
                            foregroundWorkAdmission: foregroundWorkAdmission,
                            session: activeStream.session
                        )
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        await self.recordEnqueued(event, traceContext: traceContext)
                    }
                case .reviewMetadata:
                    try await self.reviewMetadataSource.update(
                        subscription: subscription,
                        productAdmission: productAdmission
                    ) { event, emittedAdmission in
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        guard emittedAdmission.matches(productAdmission),
                            await self.isReviewPublicationCurrent(
                                event.publicationId,
                                emittedAdmission
                            )
                        else {
                            throw CancellationError()
                        }
                        let enqueueResult = try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            productAdmission: emittedAdmission,
                            foregroundWorkAdmission: foregroundWorkAdmission,
                            session: activeStream.session
                        )
                        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                        }
                        await self.recordEnqueued(event, traceContext: traceContext)
                        return enqueueResult
                    }
                }
            }
        )
    }

    private func bootstrapProducerTaskFinished(
        subscriptionId: String,
        taskId: UUID,
        shouldRetireSubscription: Bool
    ) async {
        producerTaskLifecycle.bootstrapTaskFinished(
            subscriptionId: subscriptionId,
            taskId: taskId
        )
        if shouldRetireSubscription {
            await retireSubscriptionAfterReset(subscriptionId: subscriptionId)
        }
    }

    private func interestProducerTaskFinished(
        subscriptionId: String,
        taskId: UUID,
        shouldRetireSubscription: Bool
    ) async {
        producerTaskLifecycle.interestTaskFinished(
            subscriptionId: subscriptionId,
            taskId: taskId
        )
        if shouldRetireSubscription {
            await retireSubscriptionAfterReset(subscriptionId: subscriptionId)
        }
    }

    private func recordEnqueued(
        _ event: BridgeProductFileMetadataEvent,
        traceContext: BridgeTraceContext?
    ) async {
        await producerTaskLifecycle.recordEnqueued(event, traceContext: traceContext)
    }

    private func recordEnqueued(
        _ event: BridgeProductReviewMetadataEvent,
        traceContext: BridgeTraceContext?
    ) async {
        await producerTaskLifecycle.recordEnqueued(event, traceContext: traceContext)
    }

    private func recordSourceOpened(
        subscriptionId: String,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
            subscriptionKindById[subscriptionId] != nil
        else { return }
        openedSourceSubscriptionIds.insert(subscriptionId)
        deferredOpenSubscriptionIds.remove(subscriptionId)
    }
}
