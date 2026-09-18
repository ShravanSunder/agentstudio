import AgentStudioCore
import Foundation

enum BridgePaneProductMetadataCoordinatorError: Error, Equatable {
    case foregroundWorkInvalidated
    case producerQueueReset
    case producerRejected(BridgeProductProducerEnqueueRejection)
}

actor BridgePaneProductMetadataCoordinator {
    struct ActiveStream: Sendable {
        let correlation: BridgeProductMetadataStreamCorrelation
        let lease: BridgeProductProducerLease
        /// True when the client opened this stream WITHOUT a resume cursor.
        ///
        /// A fresh open is the client's statement that it holds no subscription ids:
        /// it poisoned its metadata session, or it is a new worker. A resume — with or
        /// without a sequence gap — means it still holds them and expects the replay.
        /// The registry's `.snapshotRequired` disposition does NOT discriminate the
        /// two, because a gapped resume is also `.snapshotRequired`.
        let opensFresh: Bool
        let productAdmission: BridgeProductAdmissionContext
        let session: BridgeProductSession
        /// The subscriptions this fresh stream replaces, captured at install.
        ///
        /// Empty for a resume. Captured in `performInstall` rather than read again at
        /// replay time because install is the last moment at which the set is provably
        /// the OLD client's: the new client has not been told the stream exists yet, so
        /// it cannot have opened anything. Reading the session again at replay time
        /// would retire a subscription the new client had opened in between and still
        /// holds — stuck pane, the same bug class this retirement exists to prevent.
        let staleSubscriptionIdsToRetire: [String]
    }

    private let contentDemandAuthority: BridgePaneProductContentDemandAuthority
    let annotationSource: BridgePaneAnnotationNotificationSource
    let fileMetadataSource: any BridgePaneProductFileMetadataProducing
    let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?
    let nativeApplicationRegistry: BridgePaneProductMetadataNativeApplicationRegistry
    private let refreshWorkAdmissionSource: BridgePaneRefreshWorkAdmissionSource
    let isReviewPublicationCurrent: @MainActor @Sendable (UUID, BridgeProductAdmissionContext) -> Bool
    let reviewPublicationReplay:
        @MainActor @Sendable (BridgeProductAdmissionContext) -> BridgeReviewCommittedPublication?
    let reviewMetadataSource: any BridgePaneProductReviewMetadataProducing
    private var latestPanePresentation: BridgePaneProductPresentationSnapshot?
    private var latestPaneSurfaceSelectionRequest: BridgePaneSurfaceSelectionRequest?
    private(set) var activeStream: ActiveStream?
    var producerTaskLifecycle: BridgePaneProductMetadataProducerTaskLifecycle
    private var isClosed = false
    private var lifecycleTransitionTail: Task<Void, Never>?
    private var streamTransitionGeneration = 0
    var subscriptionKindById: [String: BridgeProductSubscriptionKind] = [:]
    var deferredOpenSubscriptionIds: Set<String> = []
    var deferredUpdateSubscriptionIds: Set<String> = []
    var openedSourceSubscriptionIds: Set<String> = []

    init(
        annotationSource: BridgePaneAnnotationNotificationSource = .unavailable,
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
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil,
        nativeApplicationRegistry: BridgePaneProductMetadataNativeApplicationRegistry = .product
    ) {
        self.annotationSource = annotationSource
        self.contentDemandAuthority = BridgePaneProductContentDemandAuthority(
            fileMetadataSource: fileMetadataSource,
            reviewContentSource: reviewContentSource
        )
        self.fileMetadataSource = fileMetadataSource
        self.isReviewPublicationCurrent = isReviewPublicationCurrent
        self.latestPanePresentation = initialPanePresentation
        self.lifecycleTraceRecorder = lifecycleTraceRecorder
        self.nativeApplicationRegistry = nativeApplicationRegistry
        self.producerTaskLifecycle = BridgePaneProductMetadataProducerTaskLifecycle(
            lifecycleTraceRecorder: lifecycleTraceRecorder
        )
        self.refreshWorkAdmissionSource = refreshWorkAdmissionSource
        self.reviewMetadataSource = reviewMetadataSource
        self.reviewPublicationReplay = reviewPublicationReplay
    }

    var hasActiveStream: Bool { activeStream != nil }

    func recordOperationLifecycle(
        operationCorrelationID: String,
        result: BridgeOperationLifecycleTraceEvent.Result,
        stage: BridgeOperationLifecycleTraceEvent.Stage,
        stageAttempt: Int,
        surface: BridgeProductSurface
    ) async {
        await lifecycleTraceRecorder?.record(
            .init(
                operationCorrelationID: operationCorrelationID,
                result: result,
                stage: stage,
                stageAttempt: stageAttempt,
                surface: surface
            )
        )
    }

    func recordOperationLifecycle(_ event: BridgeOperationLifecycleTraceEvent) async {
        await lifecycleTraceRecorder?.record(event)
    }
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
        // Capture the outgoing client's subscriptions HERE, not at replay time. The
        // opening frame has not been enqueued yet, so the new client cannot know this
        // stream exists and cannot have opened anything on it; everything the session
        // holds right now therefore belongs to the client this stream replaces.
        let opensFresh = request.resumeFromStreamSequence == nil
        let staleSubscriptionIdsToRetire =
            opensFresh ? await session.subscriptionSnapshots().map(\.subscriptionId) : []
        guard streamTransitionGeneration == transitionGeneration else { return }
        _ = productAdmission.withValidAdmission {
            activeStream = ActiveStream(
                correlation: request.correlation,
                lease: lease,
                opensFresh: opensFresh,
                productAdmission: productAdmission,
                session: session,
                staleSubscriptionIdsToRetire: staleSubscriptionIdsToRetire
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
                case .retained:
                    guard subscriptionKindById[outcome.subscriptionId] == nil,
                        let retainedStream = activeStream,
                        let subscription = await retainedStream.session.subscriptionSnapshot(
                            subscriptionId: outcome.subscriptionId
                        ),
                        activeStream?.lease == retainedStream.lease,
                        subscriptionKindById[outcome.subscriptionId] == nil
                    else { continue }
                    applySubscriptionOpened(subscription, productAdmission: productAdmission)
                case .reset:
                    guard let resetStream = activeStream,
                        let subscription = await resetStream.session.subscriptionSnapshot(
                            subscriptionId: outcome.subscriptionId
                        ),
                        activeStream?.lease == resetStream.lease
                    else { continue }
                    applySubscriptionInterestsCommitted(subscription, productAdmission: productAdmission)
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
                    let application = try? nativeApplicationRegistry.application(
                        for: subscription.subscriptionKind
                    )
                    let bootstrapAdmission =
                        application?.adapter.interestBootstrapAdmission ?? .afterBootstrap
                    let sourceIsReady = openedSourceSubscriptionIds.contains(
                        subscription.subscriptionId
                    )
                    let bootstrapIsRunning = producerTaskLifecycle.hasBootstrapTask(
                        subscriptionId: subscription.subscriptionId
                    )
                    if sourceIsReady
                        || (bootstrapIsRunning && bootstrapAdmission == .afterBootstrap)
                    {
                        deferredUpdateSubscriptionIds.remove(subscription.subscriptionId)
                        startSubscriptionUpdate(
                            subscription,
                            activeStream: activeStream,
                            productAdmission: productAdmission,
                            foregroundWorkAdmission: foregroundWorkAdmission
                        )
                    } else if bootstrapIsRunning {
                        deferredUpdateSubscriptionIds.insert(subscription.subscriptionId)
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
            if subscriptionKindById[subscriptionId] == .reviewMetadata
                || producerTaskLifecycle.hasBootstrapTask(subscriptionId: subscriptionId)
            {
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

    func replaySubscriptionsForInstalledStream() async {
        guard let installedStream = activeStream else { return }
        if installedStream.opensFresh {
            // A fresh stream means the client holds no subscription ids: it poisoned its
            // session, or it is a new worker. Replaying the pane session's earlier
            // subscriptions under their old ids would reach a client that cannot know
            // them, and the client treats an unknown id as fatal for the whole stream.
            // Retire them instead; the client re-opens what it still needs with fresh ids.
            //
            // EXACTLY the set captured at install, never whatever the session holds now:
            // anything opened since belongs to the NEW client and must survive.
            let staleSubscriptionIds = installedStream.staleSubscriptionIdsToRetire
            await installedStream.session.retireSubscriptions(staleSubscriptionIds)
            guard activeStream?.lease == installedStream.lease else { return }
            await forgetSubscriptions(staleSubscriptionIds)
            await resumeForegroundWork()
            return
        }
        let subscriptions = await installedStream.session.subscriptionSnapshots()
        guard activeStream?.lease == installedStream.lease else { return }
        for subscription in subscriptions where subscriptionKindById[subscription.subscriptionId] == nil {
            deferSubscriptionOpen(subscription, productAdmission: installedStream.productAdmission)
        }
        await resumeForegroundWork()
    }

    func publishPanePresentation(
        _ snapshot: BridgePaneProductPresentationSnapshot,
        traceContext: BridgeTraceContext? = nil
    ) async {
        if let latestPanePresentation {
            guard snapshot.presentationRevision > latestPanePresentation.presentationRevision else {
                await recordPanePresentation(
                    snapshot,
                    stage: .notEnqueued,
                    result: .skipped,
                    resultReason: .deduplicated,
                    traceContext: traceContext
                )
                return
            }
        }
        latestPanePresentation = snapshot
        await enqueueLatestPanePresentationIfPossible(traceContext: traceContext)
    }

    func replayPanePresentation() async {
        await enqueueLatestPanePresentationIfPossible(traceContext: nil)
    }

    func publishPaneSurfaceSelectionRequest(
        _ request: BridgePaneSurfaceSelectionRequest,
        productAdmission: BridgeProductAdmissionContext,
        streamAbsenceDisposition: BridgePaneSurfaceSelectionStreamAbsenceDisposition
    ) async -> Bool {
        guard !isClosed,
            productAdmission.withValidAdmission({
                if let latestPaneSurfaceSelectionRequest,
                    request.bindingRevision <= latestPaneSurfaceSelectionRequest.bindingRevision
                {
                    return false
                }
                latestPaneSurfaceSelectionRequest = request
                return true
            }) == true
        else {
            return false
        }
        guard let activeStream else {
            if streamAbsenceDisposition == .reject {
                discardFailedExactPaneSurfaceSelectionRequest(request)
            }
            return false
        }
        do {
            let result = try await enqueuePaneSurfaceSelectionRequest(
                request,
                activeStream: activeStream
            )
            guard case .enqueued = result else {
                if case .queueReset = result {
                    return false
                }
                discardFailedExactPaneSurfaceSelectionRequest(request)
                return false
            }
            return true
        } catch {
            discardFailedExactPaneSurfaceSelectionRequest(request)
            return false
        }
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

    private func enqueueLatestPanePresentationIfPossible(
        traceContext: BridgeTraceContext?
    ) async {
        guard let snapshot = latestPanePresentation else { return }
        guard let activeStream else {
            await recordPanePresentation(
                snapshot,
                stage: .notEnqueued,
                result: .skipped,
                resultReason: .noActiveStream,
                traceContext: traceContext
            )
            return
        }
        do {
            let enqueueResult = try await activeStream.session.enqueueProducerFrame(
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
                        .metadataStreamError(
                            stream: activeStream.correlation,
                            streamSequence: streamSequence,
                            code: .resyncRequired,
                            retryable: true,
                            safeMessage: nil
                        )
                    )
                }
            )
            switch enqueueResult {
            case .enqueued:
                await recordPanePresentation(
                    snapshot,
                    stage: .enqueued,
                    result: .success,
                    resultReason: .noReason,
                    traceContext: traceContext
                )
            case .queueReset:
                await recordPanePresentation(
                    snapshot,
                    stage: .enqueued,
                    result: .success,
                    resultReason: .producerQueueReset,
                    traceContext: traceContext
                )
            case .rejected:
                await recordPanePresentation(
                    snapshot,
                    stage: .notEnqueued,
                    result: .failure,
                    resultReason: .producerRejected,
                    traceContext: traceContext
                )
            }
        } catch {
            await recordPanePresentation(
                snapshot,
                stage: .notEnqueued,
                result: .failure,
                resultReason: .unexpected,
                traceContext: traceContext
            )
        }
    }

    private func recordPanePresentation(
        _ snapshot: BridgePaneProductPresentationSnapshot,
        stage: BridgePanePresentationTraceEvent.Stage,
        result: BridgePanePresentationTraceEvent.Result,
        resultReason: BridgePanePresentationTraceEvent.ResultReason,
        traceContext: BridgeTraceContext?
    ) async {
        await lifecycleTraceRecorder?.record(
            BridgePanePresentationTraceEvent(
                snapshot: snapshot,
                stage: stage,
                result: result,
                resultReason: resultReason,
                hasActiveStream: activeStream != nil,
                traceContext: traceContext
            )
        )
    }

    private func enqueueLatestPaneSurfaceSelectionRequestIfPossible() async {
        guard let activeStream, let request = latestPaneSurfaceSelectionRequest else { return }
        do {
            let result = try await enqueuePaneSurfaceSelectionRequest(
                request,
                activeStream: activeStream
            )
            guard case .enqueued = result else {
                if case .queueReset = result {
                    return
                }
                discardFailedExactPaneSurfaceSelectionRequest(request)
                return
            }
        } catch {
            discardFailedExactPaneSurfaceSelectionRequest(request)
        }
    }

    private func enqueuePaneSurfaceSelectionRequest(
        _ request: BridgePaneSurfaceSelectionRequest,
        activeStream: ActiveStream
    ) async throws -> BridgeProductProducerEnqueueResult {
        try await activeStream.session.enqueueProducerFrame(
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
                    .metadataStreamError(
                        stream: activeStream.correlation,
                        streamSequence: streamSequence,
                        code: .resyncRequired,
                        retryable: true,
                        safeMessage: nil
                    )
                )
            }
        )
    }

    private func discardFailedExactPaneSurfaceSelectionRequest(
        _ request: BridgePaneSurfaceSelectionRequest
    ) {
        guard latestPaneSurfaceSelectionRequest?.requestId == request.requestId else { return }
        switch request.navigationCommand {
        case .activateContext:
            return
        case .activateFileTarget, .activateReviewTarget:
            latestPaneSurfaceSelectionRequest = nil
        }
    }

}

extension BridgePaneProductMetadataCoordinator {
    func publish(
        status: GitWorkingTreeStatus,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        operationCorrelationID: String
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
                    operationCorrelationID: operationCorrelationID,
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
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil
                ? .stale
                : Self.fileRefreshDisposition(for: error)
        }
    }

    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        operationCorrelationID: String
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
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil
                ? .stale
                : Self.fileRefreshDisposition(for: error)
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
                    operationCorrelationID: operationCorrelationID,
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
            return foregroundWorkAdmission.withValidAdmission({ true }) == nil
                ? .stale
                : Self.fileRefreshDisposition(for: error)
        }
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
        await cancelRegisteredSource(
            subscriptionId: subscriptionId,
            subscriptionKind: subscriptionKind
        )
    }

    private func removeSubscriptionLifecycleState(subscriptionId: String) {
        subscriptionKindById.removeValue(forKey: subscriptionId)
        deferredOpenSubscriptionIds.remove(subscriptionId)
        deferredUpdateSubscriptionIds.remove(subscriptionId)
        openedSourceSubscriptionIds.remove(subscriptionId)
    }
    var reviewSubscriptionIds: [String] {
        subscriptionKindById.compactMap { subscriptionId, kind in
            kind == .reviewMetadata ? subscriptionId : nil
        }.sorted()
    }

    /// Drops the coordinator's own tracking for subscriptions the session retired.
    ///
    /// Uses the same per-subscription retirement a reset takes, so a producer the
    /// coordinator still owns for one of these ids is cancelled and drained rather
    /// than left running against a client that no longer knows the id.
    private func forgetSubscriptions(_ subscriptionIds: [String]) async {
        for subscriptionId in subscriptionIds {
            await retireSubscriptionAfterReset(subscriptionId: subscriptionId)
        }
    }

    func retireSubscriptionAfterReset(subscriptionId: String) async {
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
}
