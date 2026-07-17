import Foundation

enum BridgeProductMetadataStreamResumeDisposition: String, Codable, Equatable, Sendable {
    case resumed
    case snapshotRequired = "snapshot_required"
}

enum BridgeProductContentCancellationDisposition: String, Codable, Equatable, Sendable {
    case stopped
    case alreadyTerminal = "already_terminal"
}

struct BridgeProductMetadataStreamRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case metadataStreamId
        case paneSessionId
        case resumeFromStreamSequence
        case wireVersion
        case workerInstanceId
    }

    let metadataStreamId: String
    let paneSessionId: String
    let resumeFromStreamSequence: Int?
    let wireVersion: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "metadataStream.open request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "metadataStream.open" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid metadataStream.open request kind",
                codingPath: decoder.codingPath
            )
        }
        self.metadataStreamId = try container.decode(String.self, forKey: .metadataStreamId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.resumeFromStreamSequence = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .resumeFromStreamSequence,
            from: container,
            codingPath: decoder.codingPath
        )
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(metadataStreamId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        if let resumeFromStreamSequence {
            try BridgeProductContractDecoding.validateNonnegative(
                resumeFromStreamSequence,
                name: "resumeFromStreamSequence",
                codingPath: decoder.codingPath
            )
            try BridgeProductContractDecoding.validateMaximum(
                resumeFromStreamSequence,
                maximum: BridgeProductWireContract.maximumResumableStreamSequence,
                name: "resumeFromStreamSequence",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("metadataStream.open", forKey: .kind)
        try container.encode(metadataStreamId, forKey: .metadataStreamId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(resumeFromStreamSequence, forKey: .resumeFromStreamSequence)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}

enum BridgeProductMetadataFrameIdentityCodingKeys: String, CodingKey, CaseIterable {
    case metadataStreamId
    case paneSessionId
    case streamSequence
    case wireVersion
    case workerInstanceId
}

struct BridgeProductMetadataFrameIdentity: Codable, Equatable, Sendable {
    static let codingKeyNames = Set(BridgeProductMetadataFrameIdentityCodingKeys.allCases.map(\.rawValue))

    let metadataStreamId: String
    let paneSessionId: String
    let streamSequence: Int
    let wireVersion: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BridgeProductMetadataFrameIdentityCodingKeys.self)
        self.metadataStreamId = try container.decode(String.self, forKey: .metadataStreamId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.streamSequence = try container.decode(Int.self, forKey: .streamSequence)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(metadataStreamId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            streamSequence,
            name: "streamSequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
    }

    func validateProgressSequence(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validatePositive(
            streamSequence,
            name: "streamSequence",
            codingPath: codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeProductMetadataFrameIdentityCodingKeys.self)
        try container.encode(metadataStreamId, forKey: .metadataStreamId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(streamSequence, forKey: .streamSequence)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}

enum BridgeProductSubscriptionFrameIdentityCodingKeys: String, CodingKey, CaseIterable {
    case cursor
    case interestRevision
    case interestSha256
    case sourceGeneration
    case subscriptionId
    case subscriptionKind
    case subscriptionSequence
    case workerDerivationEpoch
}

struct BridgeProductSubscriptionFrameIdentity: Codable, Equatable, Sendable {
    static let codingKeyNames = Set(BridgeProductSubscriptionFrameIdentityCodingKeys.allCases.map(\.rawValue))

    let cursor: String?
    let interestRevision: Int
    let interestSha256: String
    let sourceGeneration: Int
    let subscriptionId: String
    let subscriptionKind: BridgeProductSubscriptionKind
    let subscriptionSequence: Int
    let workerDerivationEpoch: Int

    var surface: BridgeProductSurface { subscriptionKind.surface }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BridgeProductSubscriptionFrameIdentityCodingKeys.self)
        self.cursor = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .cursor,
            from: container,
            codingPath: decoder.codingPath
        )
        self.interestRevision = try container.decode(Int.self, forKey: .interestRevision)
        self.interestSha256 = try container.decode(String.self, forKey: .interestSha256)
        self.sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        self.subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        self.subscriptionKind = try container.decode(BridgeProductSubscriptionKind.self, forKey: .subscriptionKind)
        self.subscriptionSequence = try container.decode(Int.self, forKey: .subscriptionSequence)
        self.workerDerivationEpoch = try container.decode(
            Int.self,
            forKey: .workerDerivationEpoch
        )
        if let cursor {
            try BridgeProductContractDecoding.validateOpaqueReference(cursor, codingPath: decoder.codingPath)
        }
        try BridgeProductContractDecoding.validateNonnegative(
            interestRevision,
            name: "interestRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateSHA256(interestSha256, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            sourceGeneration,
            name: "sourceGeneration",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(subscriptionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            subscriptionSequence,
            name: "subscriptionSequence",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: decoder.codingPath
        )
    }

    func validateAcceptedSequence(codingPath: [any CodingKey]) throws {
        guard subscriptionSequence == 0, interestRevision == 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge subscription.accepted sequence and interest revision must be zero",
                codingPath: codingPath
            )
        }
    }

    func validateProgressSequence(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validatePositive(
            subscriptionSequence,
            name: "subscriptionSequence",
            codingPath: codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: BridgeProductSubscriptionFrameIdentityCodingKeys.self)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(interestRevision, forKey: .interestRevision)
        try container.encode(interestSha256, forKey: .interestSha256)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(subscriptionKind, forKey: .subscriptionKind)
        try container.encode(subscriptionSequence, forKey: .subscriptionSequence)
        try container.encode(workerDerivationEpoch, forKey: .workerDerivationEpoch)
    }
}

enum BridgeProductMetadataFrame: Codable, Equatable, Sendable {
    case metadataStreamAccepted(BridgeProductMetadataStreamAcceptedFrame)
    case panePresentation(BridgeProductPanePresentationFrame)
    case paneSurfaceSelectionRequested(BridgeProductPaneSurfaceSelectionRequestedFrame)
    case subscriptionAccepted(BridgeProductSubscriptionAcceptedFrame)
    case subscriptionInterestsCommitted(BridgeProductSubscriptionInterestsCommittedFrame)
    case subscriptionData(BridgeProductSubscriptionDataFrame)
    case subscriptionReset(BridgeProductSubscriptionResetFrame)
    case subscriptionEnd(BridgeProductSubscriptionEndFrame)
    case subscriptionCancelled(BridgeProductSubscriptionCancelledFrame)
    case contentCancelled(BridgeProductContentCancelledFrame)
    case metadataStreamError(BridgeProductMetadataStreamErrorFrame)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    var kind: String {
        switch self {
        case .metadataStreamAccepted: "metadataStream.accepted"
        case .panePresentation: "pane.presentation"
        case .paneSurfaceSelectionRequested: "pane.surfaceSelectionRequested"
        case .subscriptionAccepted: "subscription.accepted"
        case .subscriptionInterestsCommitted: "subscription.interestsCommitted"
        case .subscriptionData: "subscription.data"
        case .subscriptionReset: "subscription.reset"
        case .subscriptionEnd: "subscription.end"
        case .subscriptionCancelled: "subscription.cancelled"
        case .contentCancelled: "content.cancelled"
        case .metadataStreamError: "metadataStream.error"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "metadataStream.accepted":
            self = .metadataStreamAccepted(try BridgeProductMetadataStreamAcceptedFrame(from: decoder))
        case "pane.presentation":
            self = .panePresentation(try BridgeProductPanePresentationFrame(from: decoder))
        case "pane.surfaceSelectionRequested":
            self = .paneSurfaceSelectionRequested(
                try BridgeProductPaneSurfaceSelectionRequestedFrame(from: decoder)
            )
        case "subscription.accepted":
            self = .subscriptionAccepted(try BridgeProductSubscriptionAcceptedFrame(from: decoder))
        case "subscription.interestsCommitted":
            self = .subscriptionInterestsCommitted(
                try BridgeProductSubscriptionInterestsCommittedFrame(from: decoder)
            )
        case "subscription.data":
            self = .subscriptionData(try BridgeProductSubscriptionDataFrame(from: decoder))
        case "subscription.reset":
            self = .subscriptionReset(try BridgeProductSubscriptionResetFrame(from: decoder))
        case "subscription.end":
            self = .subscriptionEnd(try BridgeProductSubscriptionEndFrame(from: decoder))
        case "subscription.cancelled":
            self = .subscriptionCancelled(try BridgeProductSubscriptionCancelledFrame(from: decoder))
        case "content.cancelled":
            self = .contentCancelled(try BridgeProductContentCancelledFrame(from: decoder))
        case "metadataStream.error":
            self = .metadataStreamError(try BridgeProductMetadataStreamErrorFrame(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown Bridge product metadata frame kind"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .metadataStreamAccepted(let frame): try frame.encode(to: encoder)
        case .panePresentation(let frame): try frame.encode(to: encoder)
        case .paneSurfaceSelectionRequested(let frame): try frame.encode(to: encoder)
        case .subscriptionAccepted(let frame): try frame.encode(to: encoder)
        case .subscriptionInterestsCommitted(let frame): try frame.encode(to: encoder)
        case .subscriptionData(let frame): try frame.encode(to: encoder)
        case .subscriptionReset(let frame): try frame.encode(to: encoder)
        case .subscriptionEnd(let frame): try frame.encode(to: encoder)
        case .subscriptionCancelled(let frame): try frame.encode(to: encoder)
        case .contentCancelled(let frame): try frame.encode(to: encoder)
        case .metadataStreamError(let frame): try frame.encode(to: encoder)
        }
    }
}

struct BridgeProductPaneSurfaceSelectionRequestedFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case requestId
        case selectionRevision
        case surface
    }

    let frameIdentity: BridgeProductMetadataFrameIdentity
    let requestId: String
    let selectionRevision: Int
    let surface: BridgeProductSurface

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductMetadataFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "pane.surfaceSelectionRequested frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "pane.surfaceSelectionRequested" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid pane.surfaceSelectionRequested frame kind",
                codingPath: decoder.codingPath
            )
        }
        requestId = try container.decode(String.self, forKey: .requestId)
        selectionRevision = try container.decode(Int.self, forKey: .selectionRevision)
        surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        frameIdentity = try BridgeProductMetadataFrameIdentity(from: decoder)
        try frameIdentity.validateProgressSequence(codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(requestId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            selectionRevision,
            name: "selectionRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            selectionRevision,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "selectionRevision",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        try frameIdentity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("pane.surfaceSelectionRequested", forKey: .kind)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(selectionRevision, forKey: .selectionRevision)
        try container.encode(surface, forKey: .surface)
    }
}

struct BridgeProductPanePresentationFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case activityRevision
        case kind
        case nativeActivity
        case refreshingLanes
    }

    let frameIdentity: BridgeProductMetadataFrameIdentity
    let activityRevision: Int
    let nativeActivity: BridgePaneActivity
    let refreshingLanes: [BridgePaneRefreshLane]

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductMetadataFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "pane.presentation frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "pane.presentation" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid pane.presentation frame kind",
                codingPath: decoder.codingPath
            )
        }
        self.activityRevision = try container.decode(Int.self, forKey: .activityRevision)
        self.nativeActivity = try container.decode(BridgePaneActivity.self, forKey: .nativeActivity)
        self.refreshingLanes = try container.decode(
            [BridgePaneRefreshLane].self,
            forKey: .refreshingLanes
        )
        self.frameIdentity = try BridgeProductMetadataFrameIdentity(from: decoder)
        try frameIdentity.validateProgressSequence(codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            activityRevision,
            name: "activityRevision",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            activityRevision,
            maximum: BridgeProductWireContract.maximumSafeInteger,
            name: "activityRevision",
            codingPath: decoder.codingPath
        )
        let canonicalLanes = Array(Set(refreshingLanes)).sorted { $0.rawValue < $1.rawValue }
        guard refreshingLanes == canonicalLanes else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge pane refreshing lanes must be unique and canonical",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try frameIdentity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activityRevision, forKey: .activityRevision)
        try container.encode("pane.presentation", forKey: .kind)
        try container.encode(nativeActivity, forKey: .nativeActivity)
        try container.encode(refreshingLanes, forKey: .refreshingLanes)
    }
}

struct BridgeProductMetadataStreamAcceptedFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case resumeDisposition
    }

    let frameIdentity: BridgeProductMetadataFrameIdentity
    let resumeDisposition: BridgeProductMetadataStreamResumeDisposition

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductMetadataFrameIdentity.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "metadataStream.accepted frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "metadataStream.accepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid metadataStream.accepted frame kind",
                codingPath: decoder.codingPath
            )
        }
        self.resumeDisposition = try container.decode(
            BridgeProductMetadataStreamResumeDisposition.self,
            forKey: .resumeDisposition
        )
        self.frameIdentity = try BridgeProductMetadataFrameIdentity(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try frameIdentity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("metadataStream.accepted", forKey: .kind)
        try container.encode(resumeDisposition, forKey: .resumeDisposition)
    }
}

struct BridgeProductSubscriptionAcceptedFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
    }

    let frameIdentity: BridgeProductMetadataFrameIdentity
    let subscriptionIdentity: BridgeProductSubscriptionFrameIdentity

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductMetadataFrameIdentity.codingKeyNames
                .union(BridgeProductSubscriptionFrameIdentity.codingKeyNames)
                .union(CodingKeys.allCases.map(\.rawValue)),
            contract: "subscription.accepted frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "subscription.accepted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.accepted frame kind",
                codingPath: decoder.codingPath
            )
        }
        self.frameIdentity = try BridgeProductMetadataFrameIdentity(from: decoder)
        self.subscriptionIdentity = try BridgeProductSubscriptionFrameIdentity(from: decoder)
        try frameIdentity.validateProgressSequence(codingPath: decoder.codingPath)
        try subscriptionIdentity.validateAcceptedSequence(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try frameIdentity.encode(to: encoder)
        try subscriptionIdentity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("subscription.accepted", forKey: .kind)
    }
}

struct BridgeProductSubscriptionDataFrame: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case data
        case kind
    }

    let frameIdentity: BridgeProductMetadataFrameIdentity
    let subscriptionIdentity: BridgeProductSubscriptionFrameIdentity
    let data: BridgeProductSubscriptionData

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductMetadataFrameIdentity.codingKeyNames
                .union(BridgeProductSubscriptionFrameIdentity.codingKeyNames)
                .union(CodingKeys.allCases.map(\.rawValue)),
            contract: "subscription.data frame"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode(BridgeProductSubscriptionData.self, forKey: .data)
        guard try container.decode(String.self, forKey: .kind) == "subscription.data" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid subscription.data frame kind",
                codingPath: decoder.codingPath
            )
        }
        self.frameIdentity = try BridgeProductMetadataFrameIdentity(from: decoder)
        self.subscriptionIdentity = try BridgeProductSubscriptionFrameIdentity(from: decoder)
        try frameIdentity.validateProgressSequence(codingPath: decoder.codingPath)
        try subscriptionIdentity.validateProgressSequence(codingPath: decoder.codingPath)
        guard subscriptionIdentity.subscriptionKind == data.subscriptionKind else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product subscription frame kind does not match its data",
                codingPath: decoder.codingPath
            )
        }
        guard subscriptionIdentity.sourceGeneration == data.sourceGeneration else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product metadata frame generation does not match its event",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        try frameIdentity.encode(to: encoder)
        try subscriptionIdentity.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode("subscription.data", forKey: .kind)
    }
}
