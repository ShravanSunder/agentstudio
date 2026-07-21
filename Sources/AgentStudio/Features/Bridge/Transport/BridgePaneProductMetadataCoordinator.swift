import Foundation

enum BridgePaneProductMetadataCoordinatorError: Error, Equatable {
    case foregroundWorkInvalidated
    case producerQueueReset
    case producerRejected(BridgeProductProducerEnqueueRejection)
}

actor BridgePaneProductMetadataCoordinator {
    private struct ActiveStream: Sendable {
        let correlation: BridgeProductMetadataStreamCorrelation
        let lease: BridgeProductProducerLease
        let productAdmission: BridgeProductAdmissionContext
        let session: BridgeProductSession
    }

    private let contentDemandAuthority: BridgePaneProductContentDemandAuthority
    private let fileMetadataSource: any BridgePaneProductFileMetadataProducing
    private let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?
    private let refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
    private let isReviewPublicationCurrent: @MainActor @Sendable (UUID, BridgeProductAdmissionContext) -> Bool
    private let reviewPublicationReplay:
        @MainActor @Sendable (BridgeProductAdmissionContext) -> BridgeReviewCommittedPublication?
    private let reviewMetadataSource: any BridgePaneProductReviewMetadataProducing
    private var latestPanePresentation: BridgePaneProductPresentationSnapshot?
    private var latestPaneSurfaceSelectionRequest: BridgePaneSurfaceSelectionRequest?
    private var activeStream: ActiveStream?
    private var producerTaskLifecycle: BridgePaneProductMetadataProducerTaskLifecycle
    private var isClosed = false
    private var lifecycleTransitionTail: Task<Void, Never>?
    private var streamTransitionGeneration = 0
    private var subscriptionKindById: [String: BridgeProductSubscriptionKind] = [:]
    private var deferredOpenSubscriptionIds: Set<String> = []
    private var deferredUpdateSubscriptionIds: Set<String> = []
    private var openedSourceSubscriptionIds: Set<String> = []

    init(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewMetadataSource: any BridgePaneProductReviewMetadataProducing,
        reviewContentSource: any BridgePaneProductReviewContentProducing =
            BridgeUnavailablePaneProductReviewContentSource(),
        reviewPublicationReplay:
            @escaping @MainActor @Sendable (BridgeProductAdmissionContext) ->
            BridgeReviewCommittedPublication? = { _ in nil },
        isReviewPublicationCurrent:
            @escaping @MainActor @Sendable (UUID, BridgeProductAdmissionContext) -> Bool = { _, _ in true },
        initialPanePresentation: BridgePaneProductPresentationSnapshot? = nil,
        refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource,
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil
    ) {
        self.contentDemandAuthority = BridgePaneProductContentDemandAuthority(
            fileMetadataSource: fileMetadataSource,
            reviewContentSource: reviewContentSource
        )
        self.fileMetadataSource = fileMetadataSource
        self.isReviewPublicationCurrent = isReviewPublicationCurrent
        self.latestPanePresentation = initialPanePresentation
        self.lifecycleTraceRecorder = lifecycleTraceRecorder
        self.producerTaskLifecycle = BridgePaneProductMetadataProducerTaskLifecycle(
            lifecycleTraceRecorder: lifecycleTraceRecorder
        )
        self.refreshWorkAdmissionSource = refreshWorkAdmissionSource
        self.reviewMetadataSource = reviewMetadataSource
        self.reviewPublicationReplay = reviewPublicationReplay
    }

    var hasActiveStream: Bool { activeStream != nil }
    func install(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async {
        let precedingTransition = lifecycleTransitionTail
        let transition = Task { [self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            await performInstall(
                request: request,
                lease: lease,
                productAdmission: productAdmission,
                session: session
            )
        }
        lifecycleTransitionTail = Task {
            await transition.value
        }
        await transition.value
    }
    private func performInstall(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async {
        guard !isClosed else { return }
        streamTransitionGeneration += 1
        let transitionGeneration = streamTransitionGeneration
        let producerTasks = producerTaskLifecycle.takeAndCancelEveryProducerTask()
        await cancelEverySubscription()
        await BridgePaneProductMetadataProducerTaskLifecycle.drain(producerTasks)
        guard streamTransitionGeneration == transitionGeneration else { return }
        _ = productAdmission.withValidAdmission {
            activeStream = ActiveStream(
                correlation: request.correlation,
                lease: lease,
                productAdmission: productAdmission,
                session: session
            )
        }
    }

    func uninstall(lease: BridgeProductProducerLease) async {
        let precedingTransition = lifecycleTransitionTail
        let transition = Task { [self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            await performUninstall(lease: lease)
        }
        lifecycleTransitionTail = Task {
            await transition.value
        }
        await transition.value
    }

    private func performUninstall(lease: BridgeProductProducerLease) async {
        guard activeStream?.lease == lease else { return }
        streamTransitionGeneration += 1
        let transitionGeneration = streamTransitionGeneration
        let producerTasks = producerTaskLifecycle.takeAndCancelEveryProducerTask()
        await cancelEverySubscription()
        await BridgePaneProductMetadataProducerTaskLifecycle.drain(producerTasks)
        guard streamTransitionGeneration == transitionGeneration,
            activeStream?.lease == lease
        else { return }
        activeStream = nil
    }
    func closeAndDrain() async {
        let precedingTransition = lifecycleTransitionTail
        let transition = Task { [self] in
            if let precedingTransition {
                await precedingTransition.value
            }
            await performCloseAndDrain()
        }
        lifecycleTransitionTail = Task {
            await transition.value
        }
        await transition.value
    }

    private func performCloseAndDrain() async {
        guard !isClosed else { return }
        isClosed = true
        streamTransitionGeneration += 1
        let producerTasks = producerTaskLifecycle.takeAndCancelEveryProducerTask()
        await cancelEverySubscription()
        await BridgePaneProductMetadataProducerTaskLifecycle.drain(producerTasks)
        activeStream = nil
    }
    func apply(
        _ effect: BridgeProductSessionCompletionEffect,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        await contentDemandAuthority.apply(
            effect,
            productAdmission: productAdmission
        )
        switch effect {
        case .subscriptionOpened(let subscription):
            applySubscriptionOpened(subscription, productAdmission: productAdmission)
        case .subscriptionInterestsCommitted(_, let subscription):
            applySubscriptionInterestsCommitted(subscription, productAdmission: productAdmission)
        case .subscriptionCancelled(let subscription):
            let producerTasks = producerTaskLifecycle.takeAndCancelProducerTasks(
                subscriptionId: subscription.subscriptionId
            )
            await cancelSource(
                subscriptionId: subscription.subscriptionId,
                subscriptionKind: subscription.subscriptionKind
            )
            await BridgePaneProductMetadataProducerTaskLifecycle.drain(producerTasks)
            removeSubscriptionLifecycleState(subscriptionId: subscription.subscriptionId)
        case .resynced(let result):
            for outcome in result.reconciliation {
                switch outcome {
                case .cancelled, .reopenRequired:
                    let producerTasks = producerTaskLifecycle.takeAndCancelProducerTasks(
                        subscriptionId: outcome.subscriptionId
                    )
                    await cancelSource(
                        subscriptionId: outcome.subscriptionId,
                        subscriptionKind: outcome.subscriptionKind
                    )
                    await BridgePaneProductMetadataProducerTaskLifecycle.drain(producerTasks)
                    removeSubscriptionLifecycleState(subscriptionId: outcome.subscriptionId)
                case .retained, .reset:
                    break
                }
            }
            for subscriptionId in result.revokedNativeOnlySubscriptionIds {
                let producerTasks = producerTaskLifecycle.takeAndCancelProducerTasks(
                    subscriptionId: subscriptionId
                )
                if let subscriptionKind = subscriptionKindById[subscriptionId] {
                    await cancelSource(
                        subscriptionId: subscriptionId,
                        subscriptionKind: subscriptionKind
                    )
                }
                await BridgePaneProductMetadataProducerTaskLifecycle.drain(producerTasks)
                removeSubscriptionLifecycleState(subscriptionId: subscriptionId)
            }
        case .noEffect, .productCall:
            break
        }
    }

    private func applySubscriptionOpened(
        _ subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext
    ) {
        guard let activeStream,
            activeStream.productAdmission.matches(productAdmission)
        else { return }
        guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else {
            deferSubscriptionOpen(subscription, productAdmission: productAdmission)
            return
        }
        let didStart =
            foregroundWorkAdmission.withValidAdmission {
                productAdmission.withValidAdmission { () -> Bool in
                    subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
                    deferredOpenSubscriptionIds.remove(subscription.subscriptionId)
                    deferredUpdateSubscriptionIds.remove(subscription.subscriptionId)
                    startSubscriptionOpen(
                        subscription,
                        activeStream: activeStream,
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission
                    )
                    return true
                } ?? false
            } ?? false
        if !didStart {
            deferSubscriptionOpen(subscription, productAdmission: productAdmission)
        }
    }

    private func applySubscriptionInterestsCommitted(
        _ subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext
    ) {
        guard let activeStream,
            activeStream.productAdmission.matches(productAdmission)
        else { return }
        guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else {
            deferSubscriptionInterestsCommitted(subscription, productAdmission: productAdmission)
            return
        }
        let didStart =
            foregroundWorkAdmission.withValidAdmission {
                productAdmission.withValidAdmission { () -> Bool in
                    subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
                    producerTaskLifecycle.cancelInterestTasks(
                        subscriptionId: subscription.subscriptionId
                    )
                    if openedSourceSubscriptionIds.contains(subscription.subscriptionId)
                        || producerTaskLifecycle.hasBootstrapTask(
                            subscriptionId: subscription.subscriptionId
                        )
                    {
                        deferredUpdateSubscriptionIds.remove(subscription.subscriptionId)
                        startSubscriptionUpdate(
                            subscription,
                            activeStream: activeStream,
                            productAdmission: productAdmission,
                            foregroundWorkAdmission: foregroundWorkAdmission
                        )
                    } else {
                        deferredOpenSubscriptionIds.remove(subscription.subscriptionId)
                        startSubscriptionOpen(
                            subscription,
                            activeStream: activeStream,
                            productAdmission: productAdmission,
                            foregroundWorkAdmission: foregroundWorkAdmission
                        )
                    }
                    return true
                } ?? false
            } ?? false
        if !didStart {
            deferSubscriptionInterestsCommitted(subscription, productAdmission: productAdmission)
        }
    }

    private func deferSubscriptionOpen(
        _ subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext
    ) {
        _ = productAdmission.withValidAdmission {
            subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
            deferredOpenSubscriptionIds.insert(subscription.subscriptionId)
            deferredUpdateSubscriptionIds.remove(subscription.subscriptionId)
        }
    }

    private func deferSubscriptionInterestsCommitted(
        _ subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext
    ) {
        _ = productAdmission.withValidAdmission {
            subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
            producerTaskLifecycle.cancelInterestTasks(subscriptionId: subscription.subscriptionId)
            if openedSourceSubscriptionIds.contains(subscription.subscriptionId) {
                deferredUpdateSubscriptionIds.insert(subscription.subscriptionId)
            } else {
                deferredOpenSubscriptionIds.insert(subscription.subscriptionId)
            }
        }
    }

    func suspendForegroundWork() async {
        for subscriptionId in subscriptionKindById.keys {
            if subscriptionKindById[subscriptionId] == .reviewMetadata {
                deferredOpenSubscriptionIds.insert(subscriptionId)
                deferredUpdateSubscriptionIds.remove(subscriptionId)
            } else if openedSourceSubscriptionIds.contains(subscriptionId) {
                deferredUpdateSubscriptionIds.insert(subscriptionId)
            } else {
                deferredOpenSubscriptionIds.insert(subscriptionId)
            }
        }
        let producerTasks = producerTaskLifecycle.takeAndCancelEveryProducerTask()
        if let activeStream {
            await activeStream.session.resolveProducerObservationPacingCancellation(
                for: activeStream.lease
            )
        }
        await BridgePaneProductMetadataProducerTaskLifecycle.drain(producerTasks)
    }

    func resumeForegroundWork() async {
        guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire(),
            let activeStream
        else { return }
        let subscriptionIds = Set(deferredOpenSubscriptionIds)
            .union(deferredUpdateSubscriptionIds)
            .sorted()
        for subscriptionId in subscriptionIds {
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
                self.activeStream?.lease == activeStream.lease
            else { return }
            guard
                let subscription = await activeStream.session.subscriptionSnapshot(
                    subscriptionId: subscriptionId
                )
            else { continue }
            if openedSourceSubscriptionIds.contains(subscriptionId),
                !deferredOpenSubscriptionIds.contains(subscriptionId)
            {
                deferredUpdateSubscriptionIds.remove(subscriptionId)
                startSubscriptionUpdate(
                    subscription,
                    activeStream: activeStream,
                    productAdmission: activeStream.productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            } else {
                deferredOpenSubscriptionIds.remove(subscriptionId)
                deferredUpdateSubscriptionIds.remove(subscriptionId)
                startSubscriptionOpen(
                    subscription,
                    activeStream: activeStream,
                    productAdmission: activeStream.productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            }
        }
    }

    func publishPanePresentation(
        _ snapshot: BridgePaneProductPresentationSnapshot
    ) async {
        if let latestPanePresentation {
            guard snapshot.activityRevision > latestPanePresentation.activityRevision else { return }
        }
        latestPanePresentation = snapshot
        await enqueueLatestPanePresentationIfPossible()
    }

    func replayPanePresentation() async {
        await enqueueLatestPanePresentationIfPossible()
    }

    func publishPaneSurfaceSelectionRequest(
        _ request: BridgePaneSurfaceSelectionRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard !isClosed,
            productAdmission.withValidAdmission({
                if let latestPaneSurfaceSelectionRequest,
                    request.selectionRevision <= latestPaneSurfaceSelectionRequest.selectionRevision
                {
                    return false
                }
                latestPaneSurfaceSelectionRequest = request
                return true
            }) == true
        else {
            return
        }
        await enqueueLatestPaneSurfaceSelectionRequestIfPossible()
    }

    func replayPaneSurfaceSelectionRequest() async {
        await enqueueLatestPaneSurfaceSelectionRequestIfPossible()
    }

    func settlePaneSurfaceSelectionRequest(
        requestId: String,
        productAdmission: BridgeProductAdmissionContext
    ) {
        _ = productAdmission.withValidAdmission {
            guard latestPaneSurfaceSelectionRequest?.requestId == requestId else { return }
            latestPaneSurfaceSelectionRequest = nil
        }
    }

    private func enqueueLatestPanePresentationIfPossible() async {
        guard let activeStream, let snapshot = latestPanePresentation else { return }
        _ = try? await activeStream.session.enqueueProducerFrame(
            for: activeStream.lease,
            productAdmission: activeStream.productAdmission,
            build: { streamSequence in
                try .metadata(
                    .panePresentation(
                        stream: activeStream.correlation,
                        streamSequence: streamSequence,
                        snapshot: snapshot
                    )
                )
            },
            overflowReset: { streamSequence in
                try .metadata(
                    .panePresentation(
                        stream: activeStream.correlation,
                        streamSequence: streamSequence,
                        snapshot: snapshot
                    )
                )
            }
        )
    }

    private func enqueueLatestPaneSurfaceSelectionRequestIfPossible() async {
        guard let activeStream, let request = latestPaneSurfaceSelectionRequest else { return }
        _ = try? await activeStream.session.enqueueProducerFrame(
            for: activeStream.lease,
            productAdmission: activeStream.productAdmission,
            build: { streamSequence in
                try .metadata(
                    .paneSurfaceSelectionRequested(
                        stream: activeStream.correlation,
                        streamSequence: streamSequence,
                        request: request
                    )
                )
            },
            overflowReset: { streamSequence in
                try .metadata(
                    .paneSurfaceSelectionRequested(
                        stream: activeStream.correlation,
                        streamSequence: streamSequence,
                        request: request
                    )
                )
            }
        )
    }

    private func startSubscriptionOpen(
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
            taskFinished: { [weak self] subscriptionId, taskId in
                await self?.bootstrapProducerTaskFinished(
                    subscriptionId: subscriptionId,
                    taskId: taskId
                )
            },
            operation: { traceContext in
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                }
                switch subscription.subscriptionKind {
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

    private func startSubscriptionUpdate(
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
            taskFinished: { [weak self] subscriptionId, taskId in
                await self?.interestProducerTaskFinished(
                    subscriptionId: subscriptionId,
                    taskId: taskId
                )
            },
            operation: { traceContext in
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
                }
                switch subscription.subscriptionKind {
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

    private func bootstrapProducerTaskFinished(subscriptionId: String, taskId: UUID) {
        producerTaskLifecycle.bootstrapTaskFinished(
            subscriptionId: subscriptionId,
            taskId: taskId
        )
    }

    private func interestProducerTaskFinished(subscriptionId: String, taskId: UUID) {
        producerTaskLifecycle.interestTaskFinished(
            subscriptionId: subscriptionId,
            taskId: taskId
        )
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

    func publish(
        status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgePaneProductFileRefreshPublicationDisposition {
        guard let activeStream else { return .notRequired }
        guard activeStream.productAdmission.matches(productAdmission),
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return .stale }
        let emissions = await fileMetadataSource.publish(
            status: status,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return .stale }
        guard !emissions.isEmpty else { return .notRequired }
        do {
            for emission in emissions {
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    return .stale
                }
                try await Self.enqueue(
                    event: emission.event,
                    subscriptionId: emission.subscriptionId,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    session: activeStream.session
                )
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    return .stale
                }
            }
            return .applied
        } catch {
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil ? .stale : .failed
        }
    }

    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgePaneProductFileRefreshPublicationDisposition {
        guard let activeStream else { return .notRequired }
        guard activeStream.productAdmission.matches(productAdmission),
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return .stale }
        let emissions: [BridgePaneProductFileMetadataEmission]
        do {
            emissions = try await fileMetadataSource.publish(
                changeset: changeset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        } catch {
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil ? .stale : .failed
        }
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else { return .stale }
        guard !emissions.isEmpty else { return .notRequired }
        do {
            for emission in emissions {
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    return .stale
                }
                try await Self.enqueue(
                    event: emission.event,
                    subscriptionId: emission.subscriptionId,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    session: activeStream.session
                )
                guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                    return .stale
                }
            }
            return .applied
        } catch {
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil ? .stale : .failed
        }
    }
}

extension BridgePaneProductMetadataCoordinator {
    func reserveReviewPublication(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            throw CancellationError()
        }
        return try await reviewMetadataSource.reserve(
            package: package,
            publicationId: publicationId,
            productAdmission: productAdmission
        )
    }

    private func replayCommittedReviewPublicationIfPresent(
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext?
    ) async {
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let publication = await reviewPublicationReplay(productAdmission),
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            let reservation = try? await reviewMetadataSource.reserve(
                package: publication.package,
                publicationId: publication.publicationId,
                productAdmission: productAdmission
            )
        else { return }
        _ = await deliverReviewPublication(
            publication,
            reservation: reservation,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            traceContext: traceContext
        )
    }

    func deliverReviewPublication(
        _ publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        traceContext: BridgeTraceContext? = nil
    ) async -> BridgeReviewPublicationDeliveryDisposition {
        guard let publishingStream = activeStream,
            publishingStream.productAdmission.matches(productAdmission),
            reservation.publicationId == publication.publicationId,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return .deferred }
        let retainedSubscriptionCount = reviewSubscriptionIds.count
        await lifecycleTraceRecorder?.record(
            .started(
                retainedSubscriptions: retainedSubscriptionCount,
                traceContext: traceContext
            )
        )
        for attempt in 0...1 {
            guard activeStream?.lease == publishingStream.lease,
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                await isReviewPublicationCurrent(
                    publication.publicationId,
                    productAdmission
                ),
                (productAdmission.withValidAdmission { true }) == true
            else { return .deferred }
            do {
                let outcome = try await reviewMetadataSource.deliver(
                    package: publication.package,
                    reservation: reservation,
                    productAdmission: productAdmission
                )
                switch outcome {
                case .delivered(let receipt):
                    guard activeStream?.lease == publishingStream.lease,
                        foregroundWorkAdmission.withValidAdmission({ true }) == true,
                        await isReviewPublicationCurrent(
                            publication.publicationId,
                            productAdmission
                        )
                    else { return .deferred }
                    if let maximumFinalSequence = receipt.finalFrames.map(\.sequence).max() {
                        guard
                            await publishingStream.session.waitUntilProducerFrameSequenceObserved(
                                for: publishingStream.lease,
                                sequence: maximumFinalSequence,
                                productAdmission: productAdmission
                            )
                        else {
                            guard activeStream?.lease == publishingStream.lease,
                                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                                await isReviewPublicationCurrent(
                                    publication.publicationId,
                                    productAdmission
                                ),
                                (productAdmission.withValidAdmission { true }) == true
                            else { return .deferred }
                            return .failed
                        }
                    }
                    guard activeStream?.lease == publishingStream.lease,
                        foregroundWorkAdmission.withValidAdmission({ true }) == true,
                        await isReviewPublicationCurrent(
                            publication.publicationId,
                            productAdmission
                        )
                    else { return .deferred }
                    await lifecycleTraceRecorder?.record(
                        .completed(receipt: receipt, traceContext: traceContext)
                    )
                    return receipt.publishedSubscriptions > 0
                        ? .transportAcknowledged
                        : .deferred
                case .deferred:
                    return .deferred
                }
            } catch {
                guard activeStream?.lease == publishingStream.lease,
                    foregroundWorkAdmission.withValidAdmission({ true }) == true,
                    await isReviewPublicationCurrent(
                        publication.publicationId,
                        productAdmission
                    )
                else { return .deferred }
                await recordReviewPublicationFailure(
                    Self.reviewPublicationFailure(for: error),
                    retainedSubscriptions: retainedSubscriptionCount,
                    traceContext: traceContext
                )
                guard attempt == 0,
                    Self.isRetryableReviewDeliveryFailure(error),
                    activeStream?.lease == publishingStream.lease,
                    foregroundWorkAdmission.withValidAdmission({ true }) == true,
                    await isReviewPublicationCurrent(
                        publication.publicationId,
                        productAdmission
                    ),
                    (productAdmission.withValidAdmission { true }) == true
                else { return .failed }
            }
        }
        return .failed
    }
}

extension BridgePaneProductMetadataCoordinator {
    func contentReadPlan(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneProductFileContentReadPlan? {
        await fileMetadataSource.contentReadPlan(
            for: request,
            productAdmission: productAdmission
        )
    }

    func contentDemandInterest(
        for request: BridgeProductContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgeContentDemandInterest {
        await contentDemandAuthority.interest(
            for: request,
            productAdmission: productAdmission
        )
    }

    private func cancelEverySubscription() async {
        let subscriptions = subscriptionKindById
        subscriptionKindById.removeAll(keepingCapacity: false)
        deferredOpenSubscriptionIds.removeAll(keepingCapacity: false)
        deferredUpdateSubscriptionIds.removeAll(keepingCapacity: false)
        openedSourceSubscriptionIds.removeAll(keepingCapacity: false)
        await contentDemandAuthority.removeAll()
        for (subscriptionId, subscriptionKind) in subscriptions {
            await cancelSource(
                subscriptionId: subscriptionId,
                subscriptionKind: subscriptionKind
            )
        }
    }

    private func cancelSource(
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind
    ) async {
        switch subscriptionKind {
        case .fileMetadata:
            await fileMetadataSource.cancel(subscriptionId: subscriptionId)
        case .reviewMetadata:
            await reviewMetadataSource.cancel(subscriptionId: subscriptionId)
        }
    }

    private func removeSubscriptionLifecycleState(subscriptionId: String) {
        subscriptionKindById.removeValue(forKey: subscriptionId)
        deferredOpenSubscriptionIds.remove(subscriptionId)
        deferredUpdateSubscriptionIds.remove(subscriptionId)
        openedSourceSubscriptionIds.remove(subscriptionId)
    }
    private var reviewSubscriptionIds: [String] {
        subscriptionKindById.compactMap { subscriptionId, kind in
            kind == .reviewMetadata ? subscriptionId : nil
        }.sorted()
    }

    private func recordReviewPublicationFailure(
        _ failure: BridgeProductReviewMetadataPublicationFailure,
        retainedSubscriptions: Int,
        traceContext: BridgeTraceContext?
    ) async {
        await lifecycleTraceRecorder?.record(
            .failed(
                failure: failure,
                retainedSubscriptions: retainedSubscriptions,
                traceContext: traceContext
            )
        )
    }
}
