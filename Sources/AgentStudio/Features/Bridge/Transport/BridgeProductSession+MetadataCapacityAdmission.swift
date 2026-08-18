import Foundation

enum BridgeProductPendingMetadataAdmissionSemantic: Sendable {
    case producerFrame(BridgeProductProducerRegistry.FrameBuilder)
    case subscriptionData(subscriptionId: String, data: BridgeProductSubscriptionData)

    var subscriptionId: String? {
        switch self {
        case .producerFrame:
            nil
        case .subscriptionData(let subscriptionId, _):
            subscriptionId
        }
    }
}

struct BridgeProductPendingMetadataAdmission {
    let continuation: CheckedContinuation<BridgeProductProducerEnqueueResult, any Error>
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission?
    let lease: BridgeProductProducerLease
    let productAdmission: BridgeProductAdmissionContext
    let semantic: BridgeProductPendingMetadataAdmissionSemantic
    let token: UUID
}

extension BridgeProductSession {
    func enqueueOrdinaryMetadataFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission? = nil,
        build: @escaping BridgeProductProducerRegistry.FrameBuilder
    ) async throws -> BridgeProductProducerEnqueueResult {
        try await enqueueOrdinaryMetadataAdmission(
            for: lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            semantic: .producerFrame(build)
        )
    }

    func enqueueOrdinarySubscriptionData(
        subscriptionId: String,
        data: BridgeProductSubscriptionData,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> BridgeProductProducerEnqueueResult {
        let target = try activeMetadataFrameTarget()
        return try await enqueueOrdinaryMetadataAdmission(
            for: target.lease,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            semantic: .subscriptionData(
                subscriptionId: subscriptionId,
                data: data
            )
        )
    }

    private func enqueueOrdinaryMetadataAdmission(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission?,
        semantic: BridgeProductPendingMetadataAdmissionSemantic
    ) async throws -> BridgeProductProducerEnqueueResult {
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let pendingAdmission = BridgeProductPendingMetadataAdmission(
                    continuation: continuation,
                    foregroundWorkAdmission: foregroundWorkAdmission,
                    lease: lease,
                    productAdmission: productAdmission,
                    semantic: semantic,
                    token: token
                )
                if pendingMetadataAdmissions.isEmpty {
                    do {
                        switch try attemptMetadataAdmission(pendingAdmission) {
                        case .enqueued(let frame):
                            resumeProducerFrameWaiterIfPossible(for: lease)
                            continuation.resume(returning: .enqueued(frame))
                            return
                        case .rejected(let rejection):
                            continuation.resume(returning: .rejected(rejection))
                            return
                        case .capacityUnavailable:
                            break
                        }
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                }
                pendingMetadataAdmissions.append(pendingAdmission)
            }
        } onCancel: {
            Task {
                await self.cancelPendingMetadataAdmission(token: token)
            }
        }
    }

    func drainPendingMetadataAdmissions() {
        while let pendingAdmission = pendingMetadataAdmissions.first {
            do {
                switch try attemptMetadataAdmission(pendingAdmission) {
                case .capacityUnavailable:
                    return
                case .enqueued(let frame):
                    pendingMetadataAdmissions.removeFirst()
                    resumeProducerFrameWaiterIfPossible(for: pendingAdmission.lease)
                    pendingAdmission.continuation.resume(returning: .enqueued(frame))
                case .rejected(let rejection):
                    pendingMetadataAdmissions.removeFirst()
                    pendingAdmission.continuation.resume(returning: .rejected(rejection))
                }
            } catch {
                pendingMetadataAdmissions.removeFirst()
                pendingAdmission.continuation.resume(throwing: error)
            }
        }
    }

    func settlePendingMetadataAdmissions(
        for lease: BridgeProductProducerLease
    ) {
        settlePendingMetadataAdmissions { $0.lease == lease }
    }

    func settlePendingMetadataAdmissions(
        forSubscriptionId subscriptionId: String
    ) {
        settlePendingMetadataAdmissions { $0.semantic.subscriptionId == subscriptionId }
    }

    func settleEveryPendingMetadataAdmission() {
        settlePendingMetadataAdmissions { _ in true }
    }

    private func attemptMetadataAdmission(
        _ pendingAdmission: BridgeProductPendingMetadataAdmission
    ) throws -> BridgeProductProducerNonterminalAdmissionResult {
        guard metadataAdmissionIsValid(pendingAdmission) else {
            return .rejected(.lifecycleClosed)
        }
        switch pendingAdmission.semantic {
        case .producerFrame(let build):
            return try producerRegistry.attemptNonterminalFrameAdmission(
                for: pendingAdmission.lease,
                build: build
            )
        case .subscriptionData(let subscriptionId, let data):
            guard var delivery = protocolSubscriptionDeliveryById[subscriptionId],
                delivery.correlation.subscriptionKind == data.subscriptionKind
            else {
                return .rejected(.unknownLease)
            }
            let dataCorrelation = try delivery.correlation.replacingSourceGeneration(
                with: data.sourceGeneration
            )
            let subscriptionSequence = delivery.nextSequence
            let target = try activeMetadataFrameTarget()
            guard target.lease == pendingAdmission.lease else {
                return .rejected(.unknownLease)
            }
            let result = try producerRegistry.attemptNonterminalFrameAdmission(
                for: pendingAdmission.lease,
                build: { streamSequence in
                    .metadata(
                        try .subscriptionData(
                            stream: target.stream,
                            streamSequence: streamSequence,
                            subscription: dataCorrelation,
                            subscriptionSequence: subscriptionSequence,
                            data: data
                        )
                    )
                }
            )
            guard case .enqueued = result else { return result }
            delivery.correlation = dataCorrelation
            delivery.nextSequence += 1
            protocolSubscriptionDeliveryById[subscriptionId] = delivery
            return result
        }
    }

    private func metadataAdmissionIsValid(
        _ pendingAdmission: BridgeProductPendingMetadataAdmission
    ) -> Bool {
        guard
            pendingAdmission.productAdmission.withValidAdmission({
                producerAdmissionMatches(
                    pendingAdmission.productAdmission,
                    for: pendingAdmission.lease
                )
            }) == true
        else {
            return false
        }
        guard let foregroundWorkAdmission = pendingAdmission.foregroundWorkAdmission else {
            return true
        }
        return foregroundWorkAdmission.withValidAdmission({ true }) == true
    }

    private func cancelPendingMetadataAdmission(token: UUID) {
        guard let index = pendingMetadataAdmissions.firstIndex(where: { $0.token == token }) else {
            return
        }
        let wasHead = index == pendingMetadataAdmissions.startIndex
        let pendingAdmission = pendingMetadataAdmissions.remove(at: index)
        pendingAdmission.continuation.resume(throwing: CancellationError())
        if wasHead {
            drainPendingMetadataAdmissions()
        }
    }

    private func settlePendingMetadataAdmissions(
        where shouldSettle: (BridgeProductPendingMetadataAdmission) -> Bool
    ) {
        var retainedAdmissions: [BridgeProductPendingMetadataAdmission] = []
        var settledAdmissions: [BridgeProductPendingMetadataAdmission] = []
        for pendingAdmission in pendingMetadataAdmissions {
            if shouldSettle(pendingAdmission) {
                settledAdmissions.append(pendingAdmission)
            } else {
                retainedAdmissions.append(pendingAdmission)
            }
        }
        pendingMetadataAdmissions = retainedAdmissions
        for settledAdmission in settledAdmissions {
            settledAdmission.continuation.resume(returning: .rejected(.lifecycleClosed))
        }
        if !settledAdmissions.isEmpty {
            drainPendingMetadataAdmissions()
        }
    }
}
