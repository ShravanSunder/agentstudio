import Foundation

struct BridgeProductSessionControlTransition: Sendable {
    let subscriptionState: BridgeProductSubscriptionState
    let effect: BridgeProductSessionCompletionEffect
}

enum BridgeProductSessionControlTransitionBuilder {
    static func validateResponseShape(
        request: BridgeProductControlRequest,
        response: BridgeProductControlResponse
    ) throws {
        if case .requestError(let errorResponse) = response {
            guard
                errorResponse.nextExpectedRequestSequence
                    == request.correlation.requestSequence + 1
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            return
        }

        switch (request, response) {
        case (.workerSessionOpen, .workerSessionAccepted):
            return
        case (.productCall(let callRequest), .callCompleted(let callResponse)):
            guard callResponse.call.method == callRequest.call.method else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
        case (.subscriptionOpen(let openRequest), .subscriptionOpenAccepted(let openResponse)):
            var emptySubscriptions = BridgeProductSubscriptionState()
            let receipt = try emptySubscriptions.open(openRequest)
            guard openResponse.subscriptionId == receipt.subscriptionId,
                openResponse.subscriptionKind == receipt.subscriptionKind,
                openResponse.interestRevision == receipt.interestRevision,
                openResponse.interestSha256 == receipt.interestSha256
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
        case (
            .subscriptionUpdateBatch(let updateRequest),
            .subscriptionUpdateBatchAccepted(let updateResponse)
        ):
            let expectedDisposition: BridgeProductSubscriptionUpdateBatchDisposition =
                updateRequest.batchIndex + 1 == updateRequest.batchCount ? .committed : .staged
            guard updateResponse.batchIndex == updateRequest.batchIndex,
                updateResponse.disposition == expectedDisposition,
                updateResponse.subscriptionId == updateRequest.subscriptionId,
                updateResponse.subscriptionKind == updateRequest.subscriptionKind,
                updateResponse.targetInterestRevision == updateRequest.targetInterestRevision,
                updateResponse.targetInterestSha256 == updateRequest.targetInterestSha256,
                updateResponse.updateId == updateRequest.updateId
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
        case (
            .subscriptionCancel(let cancelRequest),
            .subscriptionCancelAccepted(let cancelResponse)
        ):
            guard cancelResponse.subscriptionId == cancelRequest.subscriptionId,
                cancelResponse.subscriptionKind == cancelRequest.subscriptionKind
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
        case (.workerSessionResync(let resyncRequest), .resyncAccepted(let resyncResponse)):
            let reconciliationMatchesActiveSubscriptions = zip(
                resyncResponse.reconciliation,
                resyncRequest.activeSubscriptions
            ).allSatisfy { outcome, activeSubscription in
                outcome.subscriptionId == activeSubscription.subscriptionId
                    && outcome.subscriptionKind == activeSubscription.subscriptionKind
            }
            guard
                resyncResponse.nextExpectedRequestSequence
                    == resyncRequest.correlation.requestSequence + 1,
                resyncResponse.metadataStreamSequenceBarrier
                    >= resyncRequest.lastAcceptedStreamSequence,
                resyncResponse.reconciliation.count == resyncRequest.activeSubscriptions.count,
                reconciliationMatchesActiveSubscriptions
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
        default:
            throw BridgeProductSessionError.mismatchedControlResponse
        }
    }

    static func prepare(
        request: BridgeProductControlRequest,
        response: BridgeProductControlResponse,
        subscriptionState: BridgeProductSubscriptionState,
        resyncEpochs: [BridgeProductSurface: Int],
        currentEpochs: [BridgeProductSurface: Int]
    ) throws -> BridgeProductSessionControlTransition {
        try validateResponseShape(request: request, response: response)
        if case .requestError = response {
            return .init(subscriptionState: subscriptionState, effect: .noEffect)
        }

        var candidateSubscriptions = subscriptionState
        switch (request, response) {
        case (.workerSessionOpen, .workerSessionAccepted):
            return .init(subscriptionState: candidateSubscriptions, effect: .noEffect)

        case (.productCall(let callRequest), .callCompleted(let callResponse)):
            guard callResponse.call.method == callRequest.call.method else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            return .init(
                subscriptionState: candidateSubscriptions,
                effect: .productCall(callRequest.call)
            )

        case (.subscriptionOpen(let openRequest), .subscriptionOpenAccepted(let openResponse)):
            let receipt = try candidateSubscriptions.open(openRequest)
            guard openResponse.subscriptionId == receipt.subscriptionId,
                openResponse.subscriptionKind == receipt.subscriptionKind,
                openResponse.interestRevision == receipt.interestRevision,
                openResponse.interestSha256 == receipt.interestSha256
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            guard
                let openedSubscription = candidateSubscriptions.snapshot(
                    subscriptionId: receipt.subscriptionId
                )
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            return .init(
                subscriptionState: candidateSubscriptions,
                effect: .subscriptionOpened(openedSubscription)
            )

        case (
            .subscriptionUpdateBatch(let updateRequest),
            .subscriptionUpdateBatchAccepted(let updateResponse)
        ):
            return try prepareSubscriptionUpdate(
                request: updateRequest,
                response: updateResponse,
                subscriptionState: candidateSubscriptions
            )

        case (
            .subscriptionCancel(let cancelRequest),
            .subscriptionCancelAccepted(let cancelResponse)
        ):
            let cancelledSubscription = try candidateSubscriptions.cancel(cancelRequest)
            guard cancelResponse.subscriptionId == cancelRequest.subscriptionId,
                cancelResponse.subscriptionKind == cancelRequest.subscriptionKind
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            return .init(
                subscriptionState: candidateSubscriptions,
                effect: .subscriptionCancelled(cancelledSubscription)
            )

        case (.workerSessionResync(let resyncRequest), .resyncAccepted(let resyncResponse)):
            guard
                resyncResponse.nextExpectedRequestSequence
                    == resyncRequest.correlation.requestSequence + 1,
                resyncResponse.metadataStreamSequenceBarrier
                    >= resyncRequest.lastAcceptedStreamSequence
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            for (surface, epoch) in resyncEpochs
            where epoch > currentEpochs[surface, default: 0] {
                candidateSubscriptions.reset(surface: surface)
            }
            let resyncResult = try candidateSubscriptions.reconcile(
                activeSubscriptions: resyncRequest.activeSubscriptions
            )
            guard resyncResponse.reconciliation == resyncResult.reconciliation else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            return .init(
                subscriptionState: candidateSubscriptions,
                effect: .resynced(resyncResult)
            )

        default:
            throw BridgeProductSessionError.mismatchedControlResponse
        }
    }

    private static func prepareSubscriptionUpdate(
        request: BridgeProductSubscriptionUpdateBatchRequest,
        response: BridgeProductSubscriptionBatchAcceptedResponse,
        subscriptionState: BridgeProductSubscriptionState
    ) throws -> BridgeProductSessionControlTransition {
        var candidateSubscriptions = subscriptionState
        let updateResult = try candidateSubscriptions.apply(request)
        let expectedDisposition: BridgeProductSubscriptionUpdateBatchDisposition
        let effect: BridgeProductSessionCompletionEffect
        switch updateResult {
        case .staged:
            expectedDisposition = .staged
            effect = .noEffect
        case .committed(let barrierIntent):
            expectedDisposition = .committed
            guard candidateSubscriptions.drainCommitBarrierIntents() == [barrierIntent] else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            guard
                let committedSubscription = candidateSubscriptions.snapshot(
                    subscriptionId: barrierIntent.subscriptionId
                )
            else {
                throw BridgeProductSessionError.mismatchedControlResponse
            }
            effect = .subscriptionInterestsCommitted(
                barrier: barrierIntent,
                subscription: committedSubscription
            )
        }
        guard response.batchIndex == request.batchIndex,
            response.disposition == expectedDisposition,
            response.subscriptionId == request.subscriptionId,
            response.subscriptionKind == request.subscriptionKind,
            response.targetInterestRevision == request.targetInterestRevision,
            response.targetInterestSha256 == request.targetInterestSha256,
            response.updateId == request.updateId
        else {
            throw BridgeProductSessionError.mismatchedControlResponse
        }
        return .init(
            subscriptionState: candidateSubscriptions,
            effect: effect
        )
    }
}
