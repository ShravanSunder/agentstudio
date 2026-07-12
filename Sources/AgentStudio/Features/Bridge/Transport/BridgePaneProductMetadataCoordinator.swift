import Foundation

enum BridgePaneProductMetadataCoordinatorError: Error, Equatable {
    case producerQueueReset
    case producerRejected(BridgeProductProducerEnqueueRejection)
}

actor BridgePaneProductMetadataCoordinator {
    private struct ActiveStream: Sendable {
        let correlation: BridgeProductMetadataStreamCorrelation
        let lease: BridgeProductProducerLease
        let session: BridgeProductSession
    }

    private let fileMetadataSource: any BridgePaneProductFileMetadataProducing
    private let reviewMetadataSource: any BridgePaneProductReviewMetadataProducing
    private var activeStream: ActiveStream?
    private var producerTasksBySubscriptionId: [String: [UUID: Task<Void, Never>]] = [:]
    private var subscriptionKindById: [String: BridgeProductSubscriptionKind] = [:]

    init(
        fileMetadataSource: any BridgePaneProductFileMetadataProducing,
        reviewMetadataSource: any BridgePaneProductReviewMetadataProducing
    ) {
        self.fileMetadataSource = fileMetadataSource
        self.reviewMetadataSource = reviewMetadataSource
    }

    var hasActiveStream: Bool { activeStream != nil }

    func install(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async {
        cancelEveryProducerTask()
        await cancelEverySubscription()
        activeStream = ActiveStream(
            correlation: request.correlation,
            lease: lease,
            session: session
        )
    }

    func uninstall(lease: BridgeProductProducerLease) async {
        guard activeStream?.lease == lease else { return }
        cancelEveryProducerTask()
        await cancelEverySubscription()
        activeStream = nil
    }

    func apply(_ effect: BridgeProductSessionCompletionEffect) async {
        guard let activeStream else { return }
        switch effect {
        case .subscriptionOpened(let subscription):
            subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
            startProducerTask(
                subscriptionId: subscription.subscriptionId,
                session: activeStream.session
            ) {
                switch subscription.subscriptionKind {
                case .fileMetadata:
                    try await self.fileMetadataSource.open(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
                    }
                case .reviewMetadata:
                    try await self.reviewMetadataSource.open(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
                    }
                }
            }
        case .subscriptionInterestsCommitted(_, let subscription):
            subscriptionKindById[subscription.subscriptionId] = subscription.subscriptionKind
            cancelProducerTasks(subscriptionId: subscription.subscriptionId)
            startProducerTask(
                subscriptionId: subscription.subscriptionId,
                session: activeStream.session
            ) {
                switch subscription.subscriptionKind {
                case .fileMetadata:
                    try await self.fileMetadataSource.update(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
                    }
                case .reviewMetadata:
                    try await self.reviewMetadataSource.update(subscription: subscription) { event in
                        try await Self.enqueue(
                            event: event,
                            subscriptionId: subscription.subscriptionId,
                            session: activeStream.session
                        )
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

    func contentBody(
        for request: BridgeProductFileContentRequest
    ) async -> BridgePaneProductFileContentBody? {
        await fileMetadataSource.contentBody(for: request)
    }

    private func startProducerTask(
        subscriptionId: String,
        session: BridgeProductSession,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        let taskId = UUID()
        let task = Task { [weak self] in
            do {
                try await operation()
            } catch is CancellationError {
                // Subscription cancellation owns its lifecycle frame.
            } catch {
                if !Task.isCancelled {
                    _ = try? await session.enqueueSubscriptionReset(
                        subscriptionId: subscriptionId,
                        reason: .staleSource
                    )
                }
            }
            await self?.producerTaskFinished(
                subscriptionId: subscriptionId,
                taskId: taskId
            )
        }
        producerTasksBySubscriptionId[subscriptionId, default: [:]][taskId] = task
    }

    private func producerTaskFinished(subscriptionId: String, taskId: UUID) {
        producerTasksBySubscriptionId[subscriptionId]?.removeValue(forKey: taskId)
        if producerTasksBySubscriptionId[subscriptionId]?.isEmpty == true {
            producerTasksBySubscriptionId.removeValue(forKey: subscriptionId)
        }
    }

    private func cancelProducerTasks(subscriptionId: String) {
        let tasks = producerTasksBySubscriptionId.removeValue(forKey: subscriptionId) ?? [:]
        for task in tasks.values { task.cancel() }
    }

    private func cancelEveryProducerTask() {
        let tasks = producerTasksBySubscriptionId.values.flatMap(\.values)
        producerTasksBySubscriptionId.removeAll(keepingCapacity: false)
        for task in tasks { task.cancel() }
    }

    private func cancelEverySubscription() async {
        let subscriptions = subscriptionKindById
        subscriptionKindById.removeAll(keepingCapacity: false)
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
