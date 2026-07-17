import Foundation

enum BridgePaneProductFileRefreshPublicationDisposition: Equatable, Sendable {
    case applied
    case notRequired
    case failed
    case stale
}

extension BridgePaneProductMetadataCoordinator {
    static func reviewPublicationFailure(
        for error: any Error
    ) -> BridgeProductReviewMetadataPublicationFailure {
        if error is CancellationError { return .cancellation }
        if error is BridgePaneProductReviewMetadataSourceError { return .eventConstruction }
        guard let coordinatorError = error as? BridgePaneProductMetadataCoordinatorError else {
            return .unexpected
        }
        switch coordinatorError {
        case .foregroundWorkInvalidated:
            return .cancellation
        case .producerQueueReset:
            return .producerQueueReset
        case .producerRejected:
            return .producerRejection
        }
    }

    static func isRetryableReviewDeliveryFailure(_ error: any Error) -> Bool {
        guard let coordinatorError = error as? BridgePaneProductMetadataCoordinatorError else {
            return false
        }
        switch coordinatorError {
        case .producerQueueReset:
            return true
        case .foregroundWorkInvalidated, .producerRejected:
            return false
        }
    }

    static func producerFailureReason(
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
            case .foregroundWorkInvalidated:
                return .cancellation
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

    static func isForegroundWorkInvalidation(_ error: any Error) -> Bool {
        guard let coordinatorError = error as? BridgePaneProductMetadataCoordinatorError else {
            return false
        }
        return coordinatorError == .foregroundWorkInvalidated
    }

    static func enqueue(
        event: BridgeProductFileMetadataEvent,
        subscriptionId: String,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        let result = try await session.enqueueSubscriptionData(
            subscriptionId: subscriptionId,
            data: .fileMetadata(event),
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        switch result {
        case .enqueued:
            return
        case .queueReset:
            throw BridgePaneProductMetadataCoordinatorError.producerQueueReset
        case .rejected(let rejection):
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
            }
            throw BridgePaneProductMetadataCoordinatorError.producerRejected(rejection)
        }
    }

    static func enqueue(
        event: BridgeProductReviewMetadataEvent,
        subscriptionId: String,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws -> BridgeProductProducerEnqueueResult {
        let result = try await session.enqueueSubscriptionData(
            subscriptionId: subscriptionId,
            data: .reviewMetadata(event),
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        switch result {
        case .enqueued:
            return result
        case .queueReset:
            throw BridgePaneProductMetadataCoordinatorError.producerQueueReset
        case .rejected(let rejection):
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true else {
                throw BridgePaneProductMetadataCoordinatorError.foregroundWorkInvalidated
            }
            throw BridgePaneProductMetadataCoordinatorError.producerRejected(rejection)
        }
    }
}
