import Foundation

extension BridgeProductSession {
    func enqueueSubscriptionReset(
        subscriptionId: String,
        reason: BridgeProductResetReason,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) throws -> BridgeProductProducerEnqueueResult {
        try foregroundWorkAdmission.withValidAdmission {
            try productAdmission.withValidAdmission {
                let target = try activeMetadataFrameTarget()
                guard producerAdmissionMatches(productAdmission, for: target.lease),
                    let delivery = protocolSubscriptionDeliveryById[subscriptionId]
                else {
                    return .rejected(.unknownLease)
                }
                settlePendingMetadataAdmissions(forSubscriptionId: subscriptionId)
                let result = try producerRegistry.enqueueNonterminalFrame(
                    for: target.lease,
                    build: { streamSequence in
                        .metadata(
                            try .subscriptionReset(
                                stream: target.stream,
                                streamSequence: streamSequence,
                                subscription: delivery.correlation,
                                subscriptionSequence: delivery.nextSequence,
                                reason: reason
                            )
                        )
                    },
                    overflowReset: metadataStreamOverflowReset(for: target)
                )
                switch result {
                case .enqueued:
                    terminateProtocolSubscription(subscriptionId: subscriptionId)
                    resumeProducerFrameWaiterIfPossible(for: target.lease)
                case .queueReset:
                    terminateAllProtocolSubscriptionsWithDeliveries()
                    resumeProducerFrameWaiterIfPossible(for: target.lease)
                case .rejected:
                    break
                }
                return result
            } ?? .rejected(.lifecycleClosed)
        } ?? .rejected(.lifecycleClosed)
    }

    func enqueueSubscriptionData(
        subscriptionId: String,
        data: BridgeProductSubscriptionData,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> BridgeProductProducerEnqueueResult {
        try await enqueueOrdinarySubscriptionData(
            subscriptionId: subscriptionId,
            data: data,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
    }

    private func terminateProtocolSubscription(subscriptionId: String) {
        settlePendingMetadataAdmissions(forSubscriptionId: subscriptionId)
        protocolSubscriptionDeliveryById.removeValue(forKey: subscriptionId)
        subscriptionState.terminate(subscriptionId: subscriptionId)
    }

    private func terminateAllProtocolSubscriptionsWithDeliveries() {
        settleEveryPendingMetadataAdmission()
        let subscriptionIds = protocolSubscriptionDeliveryById.keys
        for subscriptionId in subscriptionIds {
            subscriptionState.terminate(subscriptionId: subscriptionId)
        }
        protocolSubscriptionDeliveryById.removeAll(keepingCapacity: false)
    }

    func admitRequiredProtocolLifecycleFrame(
        for effect: BridgeProductSessionCompletionEffect
    ) throws {
        switch effect {
        case .noEffect, .productCall, .resynced:
            return
        case .subscriptionOpened(let snapshot):
            try admitSubscriptionOpenedFrame(snapshot)
        case .subscriptionInterestsCommitted(let barrier, let snapshot):
            try admitSubscriptionInterestsCommittedFrame(barrier: barrier, snapshot: snapshot)
        case .subscriptionCancelled(let snapshot):
            try admitSubscriptionCancelledFrame(snapshot)
        }
    }

    func reconcileProtocolSubscriptionDeliveries(
        _ result: BridgeProductSubscriptionResyncResult
    ) {
        for subscriptionId in result.revokedNativeOnlySubscriptionIds {
            settlePendingMetadataAdmissions(forSubscriptionId: subscriptionId)
            protocolSubscriptionDeliveryById.removeValue(forKey: subscriptionId)
        }
        for outcome in result.reconciliation {
            switch outcome {
            case .cancelled, .reopenRequired:
                settlePendingMetadataAdmissions(forSubscriptionId: outcome.subscriptionId)
                protocolSubscriptionDeliveryById.removeValue(forKey: outcome.subscriptionId)
            case .reset:
                settlePendingMetadataAdmissions(forSubscriptionId: outcome.subscriptionId)
                guard
                    let snapshot = subscriptionState.snapshot(
                        subscriptionId: outcome.subscriptionId
                    ),
                    let correlation = try? Self.subscriptionFrameCorrelation(for: snapshot),
                    var delivery = protocolSubscriptionDeliveryById[outcome.subscriptionId]
                else { continue }
                delivery.correlation = correlation
                protocolSubscriptionDeliveryById[outcome.subscriptionId] = delivery
            case .retained:
                guard
                    let snapshot = subscriptionState.snapshot(
                        subscriptionId: outcome.subscriptionId
                    ),
                    let correlation = try? Self.subscriptionFrameCorrelation(for: snapshot),
                    var delivery = protocolSubscriptionDeliveryById[outcome.subscriptionId]
                else { continue }
                delivery.correlation = correlation
                protocolSubscriptionDeliveryById[outcome.subscriptionId] = delivery
            }
        }
    }

    private func admitSubscriptionOpenedFrame(
        _ snapshot: BridgeProductSubscriptionSnapshot
    ) throws {
        let target = try activeMetadataFrameTarget()
        let correlation = try Self.subscriptionFrameCorrelation(for: snapshot)
        try enqueueRequiredProtocolLifecycleFrame(
            target: target,
            build: { streamSequence in
                .metadata(
                    try .subscriptionAccepted(
                        stream: target.stream,
                        streamSequence: streamSequence,
                        subscription: correlation
                    )
                )
            }
        )
        protocolSubscriptionDeliveryById[snapshot.subscriptionId] = .init(
            correlation: correlation,
            nextSequence: 1
        )
    }

    private func admitSubscriptionInterestsCommittedFrame(
        barrier: BridgeProductSubscriptionCommitBarrierIntent,
        snapshot: BridgeProductSubscriptionSnapshot
    ) throws {
        let target = try activeMetadataFrameTarget()
        guard var delivery = protocolSubscriptionDeliveryById[snapshot.subscriptionId] else {
            throw BridgeProductSessionError.lifecycleFrameAdmissionFailed
        }
        let correlation = try Self.subscriptionFrameCorrelation(for: snapshot)
        let subscriptionSequence = delivery.nextSequence
        try enqueueRequiredProtocolLifecycleFrame(
            target: target,
            build: { streamSequence in
                .metadata(
                    try .subscriptionInterestsCommitted(
                        stream: target.stream,
                        streamSequence: streamSequence,
                        subscription: correlation,
                        subscriptionSequence: subscriptionSequence,
                        updateId: barrier.updateId
                    )
                )
            }
        )
        delivery.correlation = correlation
        delivery.nextSequence += 1
        protocolSubscriptionDeliveryById[snapshot.subscriptionId] = delivery
    }

    private func admitSubscriptionCancelledFrame(
        _ snapshot: BridgeProductSubscriptionSnapshot
    ) throws {
        let target = try activeMetadataFrameTarget()
        guard let delivery = protocolSubscriptionDeliveryById[snapshot.subscriptionId] else {
            throw BridgeProductSessionError.lifecycleFrameAdmissionFailed
        }
        try enqueueRequiredProtocolLifecycleFrame(
            target: target,
            build: { streamSequence in
                .metadata(
                    try .subscriptionCancelled(
                        stream: target.stream,
                        streamSequence: streamSequence,
                        subscription: delivery.correlation,
                        subscriptionSequence: delivery.nextSequence
                    )
                )
            }
        )
        settlePendingMetadataAdmissions(forSubscriptionId: snapshot.subscriptionId)
        protocolSubscriptionDeliveryById.removeValue(forKey: snapshot.subscriptionId)
    }

    func activeMetadataFrameTarget() throws -> BridgeProductProtocolMetadataFrameTarget {
        for (leaseId, state) in producerRegistry.producersByLeaseId {
            guard case .metadata(let metadataKey) = state.key,
                state.openingFrameState != .required,
                state.lifecycle == .running
            else { continue }
            return .init(
                lease: .init(id: leaseId),
                stream: metadataKey.request.correlation
            )
        }
        throw BridgeProductSessionError.lifecycleFrameAdmissionFailed
    }

    private func enqueueRequiredProtocolLifecycleFrame(
        target: BridgeProductProtocolMetadataFrameTarget,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws {
        let result = try producerRegistry.enqueueNonterminalFrame(
            for: target.lease,
            build: build,
            overflowReset: metadataStreamOverflowReset(for: target)
        )
        guard case .enqueued = result else {
            throw BridgeProductSessionError.lifecycleFrameAdmissionFailed
        }
        resumeProducerFrameWaiterIfPossible(for: target.lease)
    }

    private func metadataStreamOverflowReset(
        for target: BridgeProductProtocolMetadataFrameTarget
    ) -> @Sendable (Int) throws -> BridgeProductProducerFrame {
        { streamSequence in
            .metadata(
                try .metadataStreamError(
                    stream: target.stream,
                    streamSequence: streamSequence,
                    code: .resyncRequired,
                    retryable: true,
                    safeMessage: nil
                )
            )
        }
    }

    private static func subscriptionFrameCorrelation(
        for snapshot: BridgeProductSubscriptionSnapshot
    ) throws -> BridgeProductSubscriptionFrameCorrelation {
        try .init(
            cursor: nil,
            interestRevision: snapshot.interestRevision,
            interestSha256: snapshot.interestSha256,
            sourceGeneration: 0,
            subscriptionId: snapshot.subscriptionId,
            subscriptionKind: snapshot.subscriptionKind,
            workerDerivationEpoch: snapshot.workerDerivationEpoch
        )
    }
}

struct BridgeProductProtocolMetadataFrameTarget: Sendable {
    let lease: BridgeProductProducerLease
    let stream: BridgeProductMetadataStreamCorrelation
}

struct BridgeProductProtocolSubscriptionDelivery: Sendable {
    var correlation: BridgeProductSubscriptionFrameCorrelation
    var nextSequence: Int
}
