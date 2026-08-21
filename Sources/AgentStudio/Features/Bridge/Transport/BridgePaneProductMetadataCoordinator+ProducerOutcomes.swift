import Foundation

enum BridgePaneProductFileRefreshFailureKind: String, Codable, CaseIterable, Sendable {
    case fileRefreshFailed
    case fileSourceUnavailable
    case producerRejected

    var retryable: Bool {
        self == .fileSourceUnavailable
    }
}

struct BridgePaneProductFileRefreshFailure: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case failureKind
        case retryable
    }

    let failureKind: BridgePaneProductFileRefreshFailureKind
    let retryable: Bool

    init(failureKind: BridgePaneProductFileRefreshFailureKind) {
        self.failureKind = failureKind
        self.retryable = failureKind.retryable
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "File refresh failure"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let failureKind = try container.decode(
            BridgePaneProductFileRefreshFailureKind.self,
            forKey: .failureKind
        )
        let retryable = try container.decode(Bool.self, forKey: .retryable)
        guard retryable == failureKind.retryable else {
            throw BridgeProductContractDecoding.invalidValue(
                "File refresh retryability must match its failure kind",
                codingPath: decoder.codingPath
            )
        }
        self.init(failureKind: failureKind)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(failureKind, forKey: .failureKind)
        try container.encode(retryable, forKey: .retryable)
    }
}

enum BridgePaneProductFileRefreshPublicationDisposition: Equatable, Sendable {
    case applied
    case notRequired
    case failed(BridgePaneProductFileRefreshFailure)
    case stale
    case streamResetRequired
}

extension BridgePaneProductMetadataCoordinator {
    static func fileRefreshDisposition(
        for error: any Error
    ) -> BridgePaneProductFileRefreshPublicationDisposition {
        if error is BridgePaneProductFileMetadataSourceError {
            return .failed(.init(failureKind: .fileSourceUnavailable))
        }
        if let coordinatorError = error as? BridgePaneProductMetadataCoordinatorError {
            switch coordinatorError {
            case .producerQueueReset:
                return .streamResetRequired
            case .foregroundWorkInvalidated:
                return .stale
            case .producerRejected:
                return .failed(.init(failureKind: .producerRejected))
            }
        }
        return .failed(.init(failureKind: .fileRefreshFailed))
    }
}

extension BridgePaneProductMetadataCoordinator {
    static func enqueue(
        event: BridgeProductWorktreeAnnotationEvent,
        subscriptionKind: BridgeProductSubscriptionKind,
        subscriptionId: String,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        let data: BridgeProductSubscriptionData
        switch subscriptionKind {
        case .fileAnnotations:
            data = .fileAnnotations(event)
        case .reviewAnnotations:
            data = .reviewAnnotations(event)
        case .fileMetadata, .reviewMetadata:
            throw BridgePaneProductMetadataCoordinatorError.producerRejected(.unknownLease)
        }
        let result = try await session.enqueueSubscriptionData(
            subscriptionId: subscriptionId,
            data: data,
            operationCorrelationID: event.operationCorrelationID,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
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
        operationCorrelationID: String? = nil,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        session: BridgeProductSession
    ) async throws {
        let result = try await session.enqueueSubscriptionData(
            subscriptionId: subscriptionId,
            data: .fileMetadata(event),
            operationCorrelationID: operationCorrelationID,
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
            operationCorrelationID: event.operationCorrelationID,
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
