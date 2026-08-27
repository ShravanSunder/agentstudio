import Foundation

private struct BridgeWorktreeAnnotationSubscriptionOpenRequest {
    let activeStream: BridgePaneProductMetadataCoordinator.ActiveStream
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    let productAdmission: BridgeProductAdmissionContext
    let subscription: BridgeProductSubscriptionSnapshot
    let surface: BridgeProductSurface
}

private struct BridgeReviewMetadataDeliveryContext {
    let activeStream: BridgePaneProductMetadataCoordinator.ActiveStream
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    let productAdmission: BridgeProductAdmissionContext
    let subscription: BridgeProductSubscriptionSnapshot
    let traceContext: BridgeTraceContext?
}

struct BridgePaneProductMetadataNativeAdapter: Sendable {
    typealias Operation =
        @Sendable (
            isolated BridgePaneProductMetadataCoordinator,
            BridgeProductSubscriptionSnapshot,
            BridgePaneProductMetadataCoordinator.ActiveStream,
            BridgeProductAdmissionContext,
            BridgePaneRefreshWorkAdmission,
            BridgeTraceContext?,
            BridgeProductSurface
        ) async throws -> Void
    typealias Cancellation =
        @Sendable (
            isolated BridgePaneProductMetadataCoordinator,
            String
        ) async -> Void

    let open: Operation
    let update: Operation
    let cancel: Cancellation
}

struct BridgePaneProductMetadataNativeApplication: Sendable {
    let registration: AnyBridgeProductMetadataApplicationProtocol
    let adapter: BridgePaneProductMetadataNativeAdapter
}

struct BridgePaneProductMetadataNativeApplicationRegistry: Sendable {
    static let product: Self = {
        do {
            return try Self(applications: [
                .init(
                    registration: AnyBridgeProductMetadataApplicationProtocol(
                        BridgeProductFileAnnotationsMetadataApplication.self
                    ),
                    adapter: BridgePaneProductMetadataCoordinator.annotationNativeAdapter
                ),
                .init(
                    registration: AnyBridgeProductMetadataApplicationProtocol(
                        BridgeProductFileMetadataApplication.self
                    ),
                    adapter: BridgePaneProductMetadataCoordinator.fileMetadataNativeAdapter
                ),
                .init(
                    registration: AnyBridgeProductMetadataApplicationProtocol(
                        BridgeProductReviewAnnotationsMetadataApplication.self
                    ),
                    adapter: BridgePaneProductMetadataCoordinator.annotationNativeAdapter
                ),
                .init(
                    registration: AnyBridgeProductMetadataApplicationProtocol(
                        BridgeProductReviewMetadataApplication.self
                    ),
                    adapter: BridgePaneProductMetadataCoordinator.reviewMetadataNativeAdapter
                ),
            ])
        } catch {
            preconditionFailure("Invalid static Bridge metadata native application registry: \(error)")
        }
    }()

    let schemaRegistry: BridgeProductMetadataApplicationRegistry
    private let applicationByKind: [BridgeProductSubscriptionKind: BridgePaneProductMetadataNativeApplication]

    init(applications: [BridgePaneProductMetadataNativeApplication]) throws {
        self.schemaRegistry = try BridgeProductMetadataApplicationRegistry(
            registrations: applications.map(\.registration)
        )
        self.applicationByKind = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.registration.kind, $0) }
        )
    }

    func application(
        for kind: BridgeProductSubscriptionKind
    ) throws -> BridgePaneProductMetadataNativeApplication {
        guard let application = applicationByKind[kind] else {
            throw BridgeProductMetadataApplicationRegistryError.unknownKind(kind)
        }
        return application
    }
}

extension BridgeProductMetadataApplicationRegistry {
    static var product: Self {
        BridgePaneProductMetadataNativeApplicationRegistry.product.schemaRegistry
    }
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
                let application = try self.nativeApplicationRegistry.application(
                    for: subscription.subscriptionKind
                )
                try await application.adapter.open(
                    self,
                    subscription,
                    activeStream,
                    productAdmission,
                    foregroundWorkAdmission,
                    traceContext,
                    application.registration.surface
                )
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
            surface: request.surface
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

    private func openFileMetadataSubscription(
        _ subscription: BridgeProductSubscriptionSnapshot,
        activeStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async throws {
        try await fileMetadataSource.open(
            subscription: subscription,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        ) { event in
            try await self.enqueueFileMetadataEvent(
                event,
                subscription: subscription,
                activeStream: activeStream,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                traceContext: traceContext
            )
        }
    }

    private func updateFileMetadataSubscription(
        _ subscription: BridgeProductSubscriptionSnapshot,
        activeStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async throws {
        try await fileMetadataSource.update(
            subscription: subscription,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        ) { event in
            try await self.enqueueFileMetadataEvent(
                event,
                subscription: subscription,
                activeStream: activeStream,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                traceContext: traceContext
            )
        }
    }

    private func enqueueFileMetadataEvent(
        _ event: BridgeProductFileMetadataEvent,
        subscription: BridgeProductSubscriptionSnapshot,
        activeStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async throws {
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
        await recordEnqueued(event, traceContext: traceContext)
    }

    private func openReviewMetadataSubscription(
        _ subscription: BridgeProductSubscriptionSnapshot,
        activeStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async throws {
        try await reviewMetadataSource.open(
            subscription: subscription,
            productAdmission: productAdmission
        ) { event, emittedAdmission in
            try await self.enqueueReviewMetadataEvent(
                event,
                emittedAdmission: emittedAdmission,
                context: .init(
                    activeStream: activeStream,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    productAdmission: productAdmission,
                    subscription: subscription,
                    traceContext: traceContext
                )
            )
        }
        await replayCommittedReviewPublicationIfPresent(
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            traceContext: traceContext
        )
    }

    private func updateReviewMetadataSubscription(
        _ subscription: BridgeProductSubscriptionSnapshot,
        activeStream: ActiveStream,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async throws {
        try await reviewMetadataSource.update(
            subscription: subscription,
            productAdmission: productAdmission
        ) { event, emittedAdmission in
            try await self.enqueueReviewMetadataEvent(
                event,
                emittedAdmission: emittedAdmission,
                context: .init(
                    activeStream: activeStream,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    productAdmission: productAdmission,
                    subscription: subscription,
                    traceContext: traceContext
                )
            )
        }
    }

    private func enqueueReviewMetadataEvent(
        _ event: BridgeProductReviewMetadataEvent,
        emittedAdmission: BridgeProductAdmissionContext,
        context: BridgeReviewMetadataDeliveryContext
    ) async throws -> BridgeProductProducerEnqueueResult {
        guard context.foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
        }
        guard emittedAdmission.matches(context.productAdmission),
            await isReviewPublicationCurrent(event.publicationId, emittedAdmission)
        else {
            throw CancellationError()
        }
        let result = try await Self.enqueue(
            event: event,
            subscriptionId: context.subscription.subscriptionId,
            productAdmission: emittedAdmission,
            foregroundWorkAdmission: context.foregroundWorkAdmission,
            session: context.activeStream.session
        )
        guard context.foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
        }
        await recordEnqueued(event, traceContext: context.traceContext)
        return result
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
                let application = try self.nativeApplicationRegistry.application(
                    for: subscription.subscriptionKind
                )
                try await application.adapter.update(
                    self,
                    subscription,
                    activeStream,
                    productAdmission,
                    foregroundWorkAdmission,
                    traceContext,
                    application.registration.surface
                )
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

    func cancelRegisteredSource(
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind
    ) async {
        guard let application = try? nativeApplicationRegistry.application(for: subscriptionKind) else { return }
        await application.adapter.cancel(self, subscriptionId)
    }

    static let annotationNativeAdapter = BridgePaneProductMetadataNativeAdapter(
        open: { coordinator, subscription, activeStream, productAdmission, foregroundAdmission, _, surface in
            try await coordinator.openWorktreeAnnotationSubscription(
                .init(
                    activeStream: activeStream,
                    foregroundWorkAdmission: foregroundAdmission,
                    productAdmission: productAdmission,
                    subscription: subscription,
                    surface: surface
                )
            )
        },
        update: { coordinator, subscription, _, _, _, _, _ in
            try await coordinator.annotationSource.update(subscription: subscription)
        },
        cancel: { coordinator, subscriptionId in
            await coordinator.annotationSource.cancel(subscriptionID: subscriptionId)
        }
    )

    static let fileMetadataNativeAdapter = BridgePaneProductMetadataNativeAdapter(
        open: { coordinator, subscription, activeStream, productAdmission, foregroundAdmission, traceContext, _ in
            try await coordinator.openFileMetadataSubscription(
                subscription,
                activeStream: activeStream,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundAdmission,
                traceContext: traceContext
            )
        },
        update: { coordinator, subscription, activeStream, productAdmission, foregroundAdmission, traceContext, _ in
            try await coordinator.updateFileMetadataSubscription(
                subscription,
                activeStream: activeStream,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundAdmission,
                traceContext: traceContext
            )
        },
        cancel: { coordinator, subscriptionId in
            await coordinator.fileMetadataSource.cancel(subscriptionId: subscriptionId)
        }
    )

    static let reviewMetadataNativeAdapter = BridgePaneProductMetadataNativeAdapter(
        open: { coordinator, subscription, activeStream, productAdmission, foregroundAdmission, traceContext, _ in
            try await coordinator.openReviewMetadataSubscription(
                subscription,
                activeStream: activeStream,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundAdmission,
                traceContext: traceContext
            )
        },
        update: { coordinator, subscription, activeStream, productAdmission, foregroundAdmission, traceContext, _ in
            try await coordinator.updateReviewMetadataSubscription(
                subscription,
                activeStream: activeStream,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundAdmission,
                traceContext: traceContext
            )
        },
        cancel: { coordinator, subscriptionId in
            await coordinator.reviewMetadataSource.cancel(subscriptionId: subscriptionId)
        }
    )
}
