import Foundation

enum BridgePaneProductFileRefreshFailureKind: String, Codable, CaseIterable, Sendable {
    case fileRefreshFailed
    case fileSourceUnavailable
    case producerRejected
    case missingRoot
    case unreadable
    case refused

    var retryable: Bool {
        switch self {
        case .fileSourceUnavailable, .missingRoot, .unreadable:
            true
        case .fileRefreshFailed, .producerRejected, .refused:
            false
        }
    }

    var safeMessage: String? {
        switch self {
        case .missingRoot:
            "The File root is unavailable. Restore it, then retry."
        case .unreadable:
            "The File root or range cannot be read. Check access, then retry."
        case .refused:
            "Choose an accessible directory as the File root."
        case .fileRefreshFailed, .fileSourceUnavailable, .producerRejected:
            nil
        }
    }
}

struct BridgePaneProductFileRefreshFailure: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case failureKind
        case retryable
        case safeMessage
    }

    let failureKind: BridgePaneProductFileRefreshFailureKind
    let retryable: Bool
    var safeMessage: String? { failureKind.safeMessage }

    init(failureKind: BridgePaneProductFileRefreshFailureKind) {
        self.failureKind = failureKind
        self.retryable = failureKind.retryable
    }

    init(rootAccessFailure: BridgeWorktreeFileRootAccessError) {
        let failureKind: BridgePaneProductFileRefreshFailureKind
        switch rootAccessFailure {
        case .missingRoot:
            failureKind = .missingRoot
        case .unreadable:
            failureKind = .unreadable
        case .refused:
            failureKind = .refused
        }
        self.init(failureKind: failureKind)
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
        let safeMessage: String?
        if container.contains(.safeMessage) {
            safeMessage = try container.decode(String.self, forKey: .safeMessage)
        } else {
            safeMessage = nil
        }
        guard safeMessage == failureKind.safeMessage else {
            throw BridgeProductContractDecoding.invalidValue(
                "File refresh safe copy must match its closed failure kind",
                codingPath: decoder.codingPath
            )
        }
        self.init(failureKind: failureKind)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(failureKind, forKey: .failureKind)
        try container.encode(retryable, forKey: .retryable)
        try container.encodeIfPresent(safeMessage, forKey: .safeMessage)
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
        if let rootAccessFailure = error as? BridgeWorktreeFileRootAccessError {
            return .failed(.init(rootAccessFailure: rootAccessFailure))
        }
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
        return .failed(
            BridgeFileSurfaceReconciler.failure(for: error, phase: .delivery).refreshFailure
        )
    }
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
        if error is BridgeWorktreeFileRootAccessError { return .fileSourceUnavailable }
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
        if let catalogWriterError = error as? BridgeProductMetadataCatalogWriterError {
            switch catalogWriterError {
            case .frameQueueReset:
                return .producerQueueReset
            case .frameRejected(let rejection):
                return .producerRejection(rejection)
            case .encodedEntryBytesExceeded, .entryCountExceeded,
                .entryDoesNotFitMetadataFrame, .frameObservationFailed:
                return .unexpected
            }
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

}
