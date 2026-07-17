import Foundation

enum BridgeProductMetadataFrameFactoryError: Error, Equatable {
    case contentSessionMismatch
    case subscriptionDataMismatch
    case subscriptionDataSourceGenerationMismatch
}

struct BridgeProductMetadataStreamCorrelation: Equatable, Sendable {
    let metadataStreamId: String
    let paneSessionId: String
    let wireVersion: Int
    let workerInstanceId: String

    init(request: BridgeProductMetadataStreamRequest) {
        self.metadataStreamId = request.metadataStreamId
        self.paneSessionId = request.paneSessionId
        self.wireVersion = request.wireVersion
        self.workerInstanceId = request.workerInstanceId
    }
}

extension BridgeProductMetadataStreamRequest {
    var correlation: BridgeProductMetadataStreamCorrelation {
        .init(request: self)
    }
}

struct BridgeProductSubscriptionFrameCorrelation: Equatable, Sendable {
    let cursor: String?
    let interestRevision: Int
    let interestSha256: String
    let sourceGeneration: Int
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let workerDerivationEpoch: Int

    var surface: BridgeProductSurface { subscriptionKind.surface }

    init(
        cursor: String?,
        interestRevision: Int,
        interestSha256: String,
        sourceGeneration: Int,
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind,
        workerDerivationEpoch: Int
    ) throws {
        if let cursor {
            try BridgeProductContractDecoding.validateOpaqueReference(cursor, codingPath: [])
        }
        try BridgeProductContractDecoding.validateNonnegative(
            interestRevision,
            name: "interestRevision",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateSHA256(interestSha256, codingPath: [])
        try BridgeProductContractDecoding.validateNonnegative(
            sourceGeneration,
            name: "sourceGeneration",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: [])
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: []
        )
        self.cursor = cursor
        self.interestRevision = interestRevision
        self.interestSha256 = interestSha256
        self.sourceGeneration = sourceGeneration
        self.subscriptionId = subscriptionId
        self.subscriptionKind = subscriptionKind
        self.workerDerivationEpoch = workerDerivationEpoch
    }

    func replacingSourceGeneration(
        with sourceGeneration: Int
    ) throws -> Self {
        try .init(
            cursor: cursor,
            interestRevision: interestRevision,
            interestSha256: interestSha256,
            sourceGeneration: sourceGeneration,
            subscriptionId: subscriptionId,
            subscriptionKind: subscriptionKind,
            workerDerivationEpoch: workerDerivationEpoch
        )
    }
}

extension BridgeProductMetadataFrameIdentity {
    init(correlation: BridgeProductMetadataStreamCorrelation, streamSequence: Int) {
        self.metadataStreamId = correlation.metadataStreamId
        self.paneSessionId = correlation.paneSessionId
        self.streamSequence = streamSequence
        self.wireVersion = correlation.wireVersion
        self.workerInstanceId = correlation.workerInstanceId
    }
}

extension BridgeProductSubscriptionFrameIdentity {
    init(correlation: BridgeProductSubscriptionFrameCorrelation, subscriptionSequence: Int) {
        self.cursor = correlation.cursor
        self.interestRevision = correlation.interestRevision
        self.interestSha256 = correlation.interestSha256
        self.sourceGeneration = correlation.sourceGeneration
        self.subscriptionId = correlation.subscriptionId
        self.subscriptionKind = correlation.subscriptionKind
        self.subscriptionSequence = subscriptionSequence
        self.workerDerivationEpoch = correlation.workerDerivationEpoch
    }
}

extension BridgeProductSubscriptionProgressIdentity {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int
    ) throws {
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        try BridgeProductContractDecoding.validatePositive(
            subscriptionSequence,
            name: "subscriptionSequence",
            codingPath: []
        )
        self.frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        self.subscriptionIdentity = .init(
            correlation: subscription,
            subscriptionSequence: subscriptionSequence
        )
    }
}

extension BridgeProductSubscriptionInterestsCommittedFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int,
        updateId: String
    ) throws {
        try BridgeProductContractDecoding.validateIdentifier(updateId, codingPath: [])
        self.identity = try .init(
            stream: stream,
            streamSequence: streamSequence,
            subscription: subscription,
            subscriptionSequence: subscriptionSequence
        )
        self.updateId = updateId
    }
}

extension BridgeProductMetadataStreamAcceptedFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        resumeDisposition: BridgeProductMetadataStreamResumeDisposition
    ) throws {
        try BridgeProductContractDecoding.validateNonnegative(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        self.frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        self.resumeDisposition = resumeDisposition
    }
}

extension BridgeProductSubscriptionAcceptedFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation
    ) throws {
        guard subscription.interestRevision == 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "subscription.accepted interest revision must be zero",
                codingPath: []
            )
        }
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        self.frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        self.subscriptionIdentity = .init(correlation: subscription, subscriptionSequence: 0)
    }
}

extension BridgeProductSubscriptionDataFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int,
        data: BridgeProductSubscriptionData
    ) throws {
        guard subscription.subscriptionKind == data.subscriptionKind else {
            throw BridgeProductMetadataFrameFactoryError.subscriptionDataMismatch
        }
        guard subscription.sourceGeneration == data.sourceGeneration else {
            throw BridgeProductMetadataFrameFactoryError.subscriptionDataSourceGenerationMismatch
        }
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        try BridgeProductContractDecoding.validatePositive(
            subscriptionSequence,
            name: "subscriptionSequence",
            codingPath: []
        )
        self.frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        self.subscriptionIdentity = .init(
            correlation: subscription,
            subscriptionSequence: subscriptionSequence
        )
        self.data = data
    }
}

extension BridgeProductSubscriptionResetFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int,
        reason: BridgeProductResetReason
    ) throws {
        self.identity = try .init(
            stream: stream,
            streamSequence: streamSequence,
            subscription: subscription,
            subscriptionSequence: subscriptionSequence
        )
        self.reason = reason
    }
}

extension BridgeProductSubscriptionEndFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int
    ) throws {
        self.identity = try .init(
            stream: stream,
            streamSequence: streamSequence,
            subscription: subscription,
            subscriptionSequence: subscriptionSequence
        )
    }
}

extension BridgeProductSubscriptionCancelledFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int
    ) throws {
        self.identity = try .init(
            stream: stream,
            streamSequence: streamSequence,
            subscription: subscription,
            subscriptionSequence: subscriptionSequence
        )
    }
}

extension BridgeProductContentCancelledFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        admission: BridgeProductContentAdmission,
        disposition: BridgeProductContentCancellationDisposition
    ) throws {
        guard
            stream.paneSessionId == admission.paneSessionId,
            stream.wireVersion == admission.wireVersion,
            stream.workerInstanceId == admission.workerInstanceId
        else {
            throw BridgeProductMetadataFrameFactoryError.contentSessionMismatch
        }
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        self.frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        self.contentRequestId = admission.contentRequestId
        self.disposition = disposition
        self.identity = admission.identity
        self.leaseId = admission.leaseId
        self.workerDerivationEpoch = admission.workerDerivationEpoch
    }
}

extension BridgeProductMetadataStreamErrorFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        code: BridgeProductRequestErrorCode,
        retryable: Bool,
        safeMessage: String?
    ) throws {
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        if let safeMessage {
            try BridgeProductContractDecoding.validateSafeMessage(safeMessage, codingPath: [])
        }
        self.frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        self.code = code
        self.retryable = retryable
        self.safeMessage = safeMessage
    }
}

extension BridgeProductPanePresentationFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        snapshot: BridgePaneProductPresentationSnapshot
    ) throws {
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        try BridgeProductContractDecoding.validatePositive(
            snapshot.activityRevision,
            name: "activityRevision",
            codingPath: []
        )
        self.frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        self.activityRevision = snapshot.activityRevision
        self.nativeActivity = snapshot.nativeActivity
        self.refreshingLanes = snapshot.refreshingLanes.sorted { $0.rawValue < $1.rawValue }
    }
}

extension BridgeProductPaneSurfaceSelectionRequestedFrame {
    init(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        request: BridgePaneSurfaceSelectionRequest
    ) throws {
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: []
        )
        try BridgeProductContractDecoding.validatePositive(
            request.selectionRevision,
            name: "selectionRevision",
            codingPath: []
        )
        frameIdentity = .init(correlation: stream, streamSequence: streamSequence)
        requestId = request.requestId
        selectionRevision = request.selectionRevision
        surface = request.surface
    }
}

extension BridgeProductMetadataFrame {
    static func metadataStreamAccepted(
        for request: BridgeProductMetadataStreamRequest,
        resumeDisposition: BridgeProductMetadataStreamResumeDisposition
    ) throws -> Self {
        .metadataStreamAccepted(
            try .init(
                stream: request.correlation,
                streamSequence: request.resumeFromStreamSequence.map { $0 + 1 } ?? 0,
                resumeDisposition: resumeDisposition
            )
        )
    }

    static func panePresentation(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        snapshot: BridgePaneProductPresentationSnapshot
    ) throws -> Self {
        .panePresentation(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                snapshot: snapshot
            )
        )
    }

    static func paneSurfaceSelectionRequested(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        request: BridgePaneSurfaceSelectionRequest
    ) throws -> Self {
        .paneSurfaceSelectionRequested(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                request: request
            )
        )
    }

    static func subscriptionAccepted(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation
    ) throws -> Self {
        .subscriptionAccepted(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                subscription: subscription
            )
        )
    }

    static func subscriptionData(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int,
        data: BridgeProductSubscriptionData
    ) throws -> Self {
        .subscriptionData(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                subscription: subscription,
                subscriptionSequence: subscriptionSequence,
                data: data
            )
        )
    }

    static func subscriptionInterestsCommitted(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int,
        updateId: String
    ) throws -> Self {
        .subscriptionInterestsCommitted(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                subscription: subscription,
                subscriptionSequence: subscriptionSequence,
                updateId: updateId
            )
        )
    }

    static func subscriptionReset(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int,
        reason: BridgeProductResetReason
    ) throws -> Self {
        .subscriptionReset(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                subscription: subscription,
                subscriptionSequence: subscriptionSequence,
                reason: reason
            )
        )
    }

    static func subscriptionEnd(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int
    ) throws -> Self {
        .subscriptionEnd(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                subscription: subscription,
                subscriptionSequence: subscriptionSequence
            )
        )
    }

    static func subscriptionCancelled(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        subscription: BridgeProductSubscriptionFrameCorrelation,
        subscriptionSequence: Int
    ) throws -> Self {
        .subscriptionCancelled(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                subscription: subscription,
                subscriptionSequence: subscriptionSequence
            )
        )
    }

    static func contentCancelled(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        admission: BridgeProductContentAdmission,
        disposition: BridgeProductContentCancellationDisposition
    ) throws -> Self {
        .contentCancelled(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                admission: admission,
                disposition: disposition
            )
        )
    }

    static func metadataStreamError(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        code: BridgeProductRequestErrorCode,
        retryable: Bool,
        safeMessage: String?
    ) throws -> Self {
        .metadataStreamError(
            try .init(
                stream: stream,
                streamSequence: streamSequence,
                code: code,
                retryable: retryable,
                safeMessage: safeMessage
            )
        )
    }
}
