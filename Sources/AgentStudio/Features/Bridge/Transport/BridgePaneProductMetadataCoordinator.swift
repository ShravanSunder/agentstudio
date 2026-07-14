import Foundation

enum BridgePaneProductMetadataCoordinatorError: Error, Equatable {
    case producerQueueReset
    case producerRejected(BridgeProductProducerEnqueueRejection)
}

actor BridgePaneProductMetadataCoordinator {
    private enum ProducerTaskKind: Sendable {
        case bootstrap
        case interest
    }

    private struct ActiveStream: Sendable {
        let correlation: BridgeProductMetadataStreamCorrelation
        let lease: BridgeProductProducerLease
        let session: BridgeProductSession
    }

    private struct BootstrapProducerTask: Sendable {
        let taskId: UUID
        let task: Task<Void, Never>
    }

    private let contentDemandAuthority: BridgePaneProductContentDemandAuthority
    private let fileMetadataSource: any BridgePaneProductFileMetadataProducing
    private let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?
    private let reviewContentSource: any BridgePaneProductReviewContentProducing
    private let reviewMetadataSource: any BridgePaneProductReviewMetadataProducing
    private var activeStream: ActiveStream?
    private var bootstrapTaskBySubscriptionId: [String: BootstrapProducerTask] = [:]
    private var interestTasksBySubscriptionId: [String: [UUID: Task<Void, Never>]] = [:]
    private var streamTransitionGeneration = 0
    private var subscriptionKindById: [String: BridgeProductSubscriptionKind] = [:]

    init(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewMetadataSource: any BridgePaneProductReviewMetadataProducing,
        reviewContentSource: any BridgePaneProductReviewContentProducing =
            BridgeUnavailablePaneProductReviewContentSource(),
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil
    ) {
        self.contentDemandAuthority = BridgePaneProductContentDemandAuthority(
            fileMetadataSource: fileMetadataSource,
            reviewContentSource: reviewContentSource
        )
        self.fileMetadataSource = fileMetadataSource
        self.lifecycleTraceRecorder = lifecycleTraceRecorder
        self.reviewContentSource = reviewContentSource
        self.reviewMetadataSource = reviewMetadataSource
    }

    var hasActiveStream: Bool { activeStream != nil }

    func install(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        streamTransitionGeneration += 1
        let transitionGeneration = streamTransitionGeneration
        cancelEveryProducerTask()
        await cancelEverySubscription()
        guard streamTransitionGeneration == transitionGeneration else { return }
        activeStream = ActiveStream(
            correlation: request.correlation,
            lease: lease,
            session: session
        )
    }

    func uninstall(lease: BridgeProductProducerLease) async {
        guard activeStream?.lease == lease else { return }
        streamTransitionGeneration += 1
        let transitionGeneration = streamTransitionGeneration
        cancelEveryProducerTask()
        await cancelEverySubscription()
        guard streamTransitionGeneration == transitionGeneration,
            activeStream?.lease == lease
        else { return }
        activeStream = nil
    }

    func apply(_ effect: BridgeProductSessionCompletionEffect) async {
        await contentDemandAuthority.apply(effect)
        guard let activeStream else { return }
        switch effect {
        case .subscriptionOpened(let subscription):
            subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
            startProducerTask(
                kind: .bootstrap,
                subscriptionId: subscription.subscriptionId,
                subscriptionKind: subscription.subscriptionKind,
                session: activeStream.session
            ) { traceContext in
                switch subscription.subscriptionKind {
                case .fileMetadata:
                    try await self.fileMetadataSource.open(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
                        await self.recordEnqueued(event, traceContext: traceContext)
                    }
                case .reviewMetadata:
                    try await self.reviewMetadataSource.open(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
                        await self.recordEnqueued(event, traceContext: traceContext)
                    }
                }
            }
        case .subscriptionInterestsCommitted(_, let subscription):
            subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
            cancelInterestTasks(subscriptionId: subscription.subscriptionId)
            startProducerTask(
                kind: .interest,
                subscriptionId: subscription.subscriptionId,
                subscriptionKind: subscription.subscriptionKind,
                session: activeStream.session
            ) { traceContext in
                switch subscription.subscriptionKind {
                case .fileMetadata:
                    try await self.fileMetadataSource.update(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
                        await self.recordEnqueued(event, traceContext: traceContext)
                    }
                case .reviewMetadata:
                    try await self.reviewMetadataSource.update(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
                        await self.recordEnqueued(event, traceContext: traceContext)
                    }
                }
            }
        case .subscriptionCancelled(let subscription):
            cancelProducerTasks(subscriptionId: subscription.subscriptionId)
            await cancelSource(
                subscriptionId: subscription.subscriptionId,
                subscriptionKind: subscription.subscriptionKind
            )
            subscriptionKindById.removeValue(forKey: subscription.subscriptionId)
        case .resynced(let result):
            for outcome in result.reconciliation {
                switch outcome {
                case .cancelled, .reopenRequired:
                    cancelProducerTasks(subscriptionId: outcome.subscriptionId)
                    await cancelSource(
                        subscriptionId: outcome.subscriptionId,
                        subscriptionKind: outcome.subscriptionKind
                    )
                    subscriptionKindById.removeValue(forKey: outcome.subscriptionId)
                case .retained, .reset:
                    break
                }
            }
            for subscriptionId in result.revokedNativeOnlySubscriptionIds {
                cancelProducerTasks(subscriptionId: subscriptionId)
                if let subscriptionKind = subscriptionKindById.removeValue(forKey: subscriptionId) {
                    await cancelSource(
                        subscriptionId: subscriptionId,
                        subscriptionKind: subscriptionKind
                    )
                }
            }
        case .noEffect, .productCall:
            break
        }
    }

    func publish(status: GitWorkingTreeStatus) async {
        guard let activeStream else { return }
        for emission in await fileMetadataSource.publish(status: status) {
            try? await Self.enqueue(
                event: emission.event,
                subscriptionId: emission.subscriptionId,
                session: activeStream.session
            )
        }
    }

    func publish(changeset: FileChangeset) async {
        guard let activeStream,
            let emissions = try? await fileMetadataSource.publish(changeset: changeset)
        else { return }
        for emission in emissions {
            try? await Self.enqueue(
                event: emission.event,
                subscriptionId: emission.subscriptionId,
                session: activeStream.session
            )
        }
    }

    func publish(
        availability: BridgePaneProductReviewMetadataAvailability,
        traceContext: BridgeTraceContext? = nil
    ) async {
        let publishingStream = activeStream
        let retainedSubscriptionCount = reviewSubscriptionIds.count
        if case .ready = availability {
            await lifecycleTraceRecorder?.record(
                .started(
                    retainedSubscriptions: retainedSubscriptionCount,
                    traceContext: traceContext
                )
            )
        }
        do {
            try await reviewContentSource.replaceAuthority(with: availability)
            let outcome = try await reviewMetadataSource.publish(availability: availability)
            guard case .ready = availability else { return }
            switch outcome {
            case .ready(let receipt):
                await lifecycleTraceRecorder?.record(
                    .completed(receipt: receipt, traceContext: traceContext)
                )
            case .loading, .failed:
                await recordReviewPublicationFailure(
                    .unexpected,
                    retainedSubscriptions: retainedSubscriptionCount,
                    traceContext: traceContext
                )
            }
        } catch {
            try? await reviewContentSource.replaceAuthority(with: .failed)
            guard case .ready = availability else { return }
            await recordReviewPublicationFailure(
                Self.reviewPublicationFailure(for: error),
                retainedSubscriptions: retainedSubscriptionCount,
                traceContext: traceContext
            )
            guard let publishingStream,
                activeStream?.lease == publishingStream.lease
            else { return }
            for subscriptionId in reviewSubscriptionIds {
                do {
                    let resetResult = try await publishingStream.session.enqueueSubscriptionReset(
                        subscriptionId: subscriptionId,
                        reason: .staleSource
                    )
                    guard case .enqueued = resetResult else {
                        await recordReviewPublicationFailure(
                            .resetEnqueueFailure,
                            retainedSubscriptions: retainedSubscriptionCount,
                            traceContext: traceContext
                        )
                        continue
                    }
                } catch {
                    await recordReviewPublicationFailure(
                        .resetEnqueueFailure,
                        retainedSubscriptions: retainedSubscriptionCount,
                        traceContext: traceContext
                    )
                }
            }
        }
    }

    func contentBody(
        for request: BridgeProductFileContentRequest
    ) async -> BridgePaneProductFileContentBody? {
        await fileMetadataSource.contentBody(for: request)
    }

    func contentDemandInterest(
        for request: BridgeProductContentRequest
    ) async -> BridgeContentDemandInterest {
        await contentDemandAuthority.interest(for: request)
    }

    private func startProducerTask(
        kind: ProducerTaskKind,
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind,
        session: BridgeProductSession,
        operation: @escaping @Sendable (BridgeTraceContext?) async throws -> Void
    ) {
        let taskId = UUID()
        let bootstrapPredecessor =
            kind == .interest ? bootstrapTaskBySubscriptionId[subscriptionId]?.task : nil
        let task = Task { [weak self, lifecycleTraceRecorder] in
            let traceContext = BridgeTraceContextFactory.live.makeRootContext()
            var terminalResult = BridgeProductMetadataLifecycleTraceEvent.Result.success
            await lifecycleTraceRecorder?.record(
                .init(
                    stage: .bootstrapStarted,
                    subscriptionKind: subscriptionKind,
                    result: .success,
                    traceContext: traceContext
                )
            )
            do {
                if let bootstrapPredecessor {
                    await bootstrapPredecessor.value
                    try Task.checkCancellation()
                }
                try await operation(traceContext)
            } catch {
                terminalResult = .failure
                if Task.isCancelled {
                    await lifecycleTraceRecorder?.record(
                        .init(
                            stage: .producerCancelled,
                            subscriptionKind: subscriptionKind,
                            result: .failure,
                            failureReason: .taskCancellation,
                            traceContext: traceContext
                        )
                    )
                } else {
                    await lifecycleTraceRecorder?.record(
                        .init(
                            stage: .producerFailed,
                            subscriptionKind: subscriptionKind,
                            result: .failure,
                            failureReason: Self.producerFailureReason(for: error),
                            traceContext: traceContext
                        )
                    )
                    let resetResult = try? await session.enqueueSubscriptionReset(
                        subscriptionId: subscriptionId,
                        reason: .staleSource
                    )
                    if case .enqueued? = resetResult {
                        await lifecycleTraceRecorder?.record(
                            .init(
                                stage: .subscriptionResetEnqueued,
                                subscriptionKind: subscriptionKind,
                                result: .queued,
                                traceContext: traceContext
                            )
                        )
                    }
                }
            }
            await self?.producerTaskFinished(
                kind: kind,
                subscriptionId: subscriptionId,
                taskId: taskId
            )
            await lifecycleTraceRecorder?.record(
                .init(
                    stage: .bootstrapFinished,
                    subscriptionKind: subscriptionKind,
                    result: terminalResult,
                    traceContext: traceContext
                )
            )
        }
        switch kind {
        case .bootstrap:
            bootstrapTaskBySubscriptionId[subscriptionId]?.task.cancel()
            bootstrapTaskBySubscriptionId[subscriptionId] = .init(
                taskId: taskId,
                task: task
            )
        case .interest:
            interestTasksBySubscriptionId[subscriptionId, default: [:]][taskId] = task
        }
    }

    private func recordEnqueued(
        _ event: BridgeProductFileMetadataEvent,
        traceContext: BridgeTraceContext?
    ) async {
        let traceEvent: BridgeProductMetadataLifecycleTraceEvent
        switch event {
        case .sourceAccepted:
            traceEvent = .init(
                stage: .sourceAcceptedEnqueued,
                subscriptionKind: .fileMetadata,
                result: .queued,
                traceContext: traceContext,
                sourceGeneration: event.sourceGeneration
            )
        case .treeWindow(let window):
            traceEvent = .init(
                stage: .windowEnqueued,
                subscriptionKind: .fileMetadata,
                result: .queued,
                traceContext: traceContext,
                sourceGeneration: event.sourceGeneration,
                rowCount: window.rows.count,
                isFinalWindow: window.finalWindow
            )
        case .treeDelta, .statusPatch, .descriptorReady, .invalidated:
            return
        }
        await lifecycleTraceRecorder?.record(traceEvent)
    }

    private func recordEnqueued(
        _ event: BridgeProductReviewMetadataEvent,
        traceContext: BridgeTraceContext?
    ) async {
        let stage: BridgeProductMetadataLifecycleTraceEvent.Stage
        switch event {
        case .sourceAccepted:
            stage = .sourceAcceptedEnqueued
        case .snapshot, .window:
            stage = .windowEnqueued
        case .delta, .invalidated, .reset:
            return
        }
        await lifecycleTraceRecorder?.record(
            .init(
                stage: stage,
                subscriptionKind: .reviewMetadata,
                result: .queued,
                traceContext: traceContext,
                sourceGeneration: event.generation
            )
        )
    }

    private func producerTaskFinished(
        kind: ProducerTaskKind,
        subscriptionId: String,
        taskId: UUID
    ) {
        switch kind {
        case .bootstrap:
            guard bootstrapTaskBySubscriptionId[subscriptionId]?.taskId == taskId else { return }
            bootstrapTaskBySubscriptionId.removeValue(forKey: subscriptionId)
        case .interest:
            interestTasksBySubscriptionId[subscriptionId]?.removeValue(forKey: taskId)
            if interestTasksBySubscriptionId[subscriptionId]?.isEmpty == true {
                interestTasksBySubscriptionId.removeValue(forKey: subscriptionId)
            }
        }
    }

    private func cancelProducerTasks(subscriptionId: String) {
        bootstrapTaskBySubscriptionId.removeValue(forKey: subscriptionId)?.task.cancel()
        cancelInterestTasks(subscriptionId: subscriptionId)
    }

    private func cancelInterestTasks(subscriptionId: String) {
        let tasks = interestTasksBySubscriptionId.removeValue(forKey: subscriptionId) ?? [:]
        for task in tasks.values { task.cancel() }
    }

    private func cancelEveryProducerTask() {
        let bootstrapTasks = bootstrapTaskBySubscriptionId.values.map(\.task)
        let interestTasks = interestTasksBySubscriptionId.values.flatMap(\.values)
        bootstrapTaskBySubscriptionId.removeAll(keepingCapacity: false)
        interestTasksBySubscriptionId.removeAll(keepingCapacity: false)
        for task in bootstrapTasks { task.cancel() }
        for task in interestTasks { task.cancel() }
    }

    private func cancelEverySubscription() async {
        let subscriptions = subscriptionKindById
        subscriptionKindById.removeAll(keepingCapacity: false)
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

    private static func reviewPublicationFailure(
        for error: any Error
    ) -> BridgeProductReviewMetadataPublicationFailure {
        if error is CancellationError { return .cancellation }
        if error is BridgePaneProductReviewMetadataSourceError { return .eventConstruction }
        guard let coordinatorError = error as? BridgePaneProductMetadataCoordinatorError else {
            return .unexpected
        }
        switch coordinatorError {
        case .producerQueueReset:
            return .producerQueueReset
        case .producerRejected:
            return .producerRejection
        }
    }

    private static func producerFailureReason(
        for error: any Error
    ) -> BridgeProductMetadataProducerFailureReason {
        if error is CancellationError { return .cancellation }
        if let reviewSourceError = error as? BridgePaneProductReviewMetadataSourceError {
            switch reviewSourceError {
            case .integerOutOfRange, .metadataEventExceedsByteLimit:
                return .reviewEventConstruction
            case .unavailablePackage:
                return .reviewSourceUnavailable
            case .unknownSubscription:
                return .reviewSubscriptionMissing
            }
        }
        if error is BridgePaneProductFileMetadataSourceError {
            return .fileSourceUnavailable
        }
        if let coordinatorError = error as? BridgePaneProductMetadataCoordinatorError {
            switch coordinatorError {
            case .producerQueueReset:
                return .producerQueueReset
            case .producerRejected(let rejection):
                return .producerRejection(rejection)
            }
        }
        if error is BridgeProductSessionError {
            return .sessionEnqueueFailure
        }
        return .unexpected
    }

    private static func enqueue(
        event: BridgeProductFileMetadataEvent,
        subscriptionId: String,
        session: BridgeProductSession
    ) async throws {
        let result = try await session.enqueueSubscriptionData(
            subscriptionId: subscriptionId,
            data: .fileMetadata(event)
        )
        switch result {
        case .enqueued:
            return
        case .queueReset:
            throw BridgePaneProductMetadataCoordinatorError.producerQueueReset
        case .rejected(let rejection):
            throw BridgePaneProductMetadataCoordinatorError.producerRejected(rejection)
        }
    }

    private static func enqueue(
        event: BridgeProductReviewMetadataEvent,
        subscriptionId: String,
        session: BridgeProductSession
    ) async throws {
        let result = try await session.enqueueSubscriptionData(
            subscriptionId: subscriptionId,
            data: .reviewMetadata(event)
        )
        switch result {
        case .enqueued:
            return
        case .queueReset:
            throw BridgePaneProductMetadataCoordinatorError.producerQueueReset
        case .rejected(let rejection):
            throw BridgePaneProductMetadataCoordinatorError.producerRejected(rejection)
        }
    }
}
