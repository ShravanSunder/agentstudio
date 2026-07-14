import Foundation

struct BridgeProductFileSourceCurrentRequest: Codable, Equatable, Sendable {
    private struct EmptyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue _: String) { nil }
        init?(intValue _: Int) { nil }
    }

    init() {}

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: [],
            contract: "file.source.current request"
        )
        _ = try decoder.container(keyedBy: EmptyCodingKey.self)
    }

    func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: EmptyCodingKey.self)
    }
}

enum BridgeProductFileSourceCurrentUnavailableReason: String, Codable, Equatable, Sendable {
    case noFileSourceAuthority = "no-file-source-authority"
}

enum BridgeProductFileSourceCurrentResult: Codable, Equatable, Sendable {
    case available(BridgeProductFileSourceSpec)
    case unavailable(BridgeProductFileSourceCurrentUnavailableReason)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case reason
        case source
        case status
    }

    private enum Status: String, Codable {
        case available
        case unavailable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Status.self, forKey: .status) {
        case .available:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.source.rawValue, CodingKeys.status.rawValue],
                contract: "available file.source.current result"
            )
            self = .available(
                try container.decode(BridgeProductFileSourceSpec.self, forKey: .source)
            )
        case .unavailable:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.reason.rawValue, CodingKeys.status.rawValue],
                contract: "unavailable file.source.current result"
            )
            self = .unavailable(
                try container.decode(
                    BridgeProductFileSourceCurrentUnavailableReason.self,
                    forKey: .reason
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .available(let source):
            try container.encode(Status.available, forKey: .status)
            try container.encode(source, forKey: .source)
        case .unavailable(let reason):
            try container.encode(Status.unavailable, forKey: .status)
            try container.encode(reason, forKey: .reason)
        }
    }
}

extension BridgeProductFileSourceSpec {
    init(
        currentAuthorityRepoId: UUID,
        currentAuthorityRootPathToken: String,
        currentAuthorityWorktreeId: UUID
    ) {
        self.cwdScope = nil
        self.includeStatuses = true
        self.repoId = currentAuthorityRepoId.uuidString
        self.rootPathToken = currentAuthorityRootPathToken
        self.worktreeId = currentAuthorityWorktreeId.uuidString
    }
}

struct BridgeProductReviewMarkFileViewedRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case itemId
    }

    let itemId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.markFileViewed request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
    }
}

struct BridgeProductReviewIntakeReadyRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case reason
        case streamId
    }

    let reason: String?
    let streamId: String?

    init(reason: String?, streamId: String?) {
        self.reason = reason
        self.streamId = streamId
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.intake.ready request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reason = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .reason,
            from: container,
            codingPath: decoder.codingPath
        )
        self.streamId = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .streamId,
            from: container,
            codingPath: decoder.codingPath
        )
        if let reason {
            try BridgeProductContractDecoding.validateIdentifier(reason, codingPath: decoder.codingPath)
        }
        if let streamId {
            try BridgeProductContractDecoding.validateIdentifier(streamId, codingPath: decoder.codingPath)
        }
    }
}

struct BridgeProductActiveViewerSourceRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case generation
        case streamId
    }

    let generation: Int
    let streamId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "active viewer source request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generation = try container.decode(Int.self, forKey: .generation)
        self.streamId = try container.decode(String.self, forKey: .streamId)
        guard generation >= 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Active viewer source generation must be nonnegative",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.validateIdentifier(streamId, codingPath: decoder.codingPath)
    }
}

struct BridgeProductActiveViewerModeUpdateRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case activeSource
        case sequence
        case sessionId
    }

    let activeSource: BridgeProductActiveViewerSourceRequest?
    let sequence: Int
    let sessionId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "active viewer mode update request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.activeSource = try container.decodeIfPresent(
            BridgeProductActiveViewerSourceRequest.self,
            forKey: .activeSource
        )
        self.sequence = try container.decode(Int.self, forKey: .sequence)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        guard sequence > 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Active viewer mode update sequence must be positive",
                codingPath: decoder.codingPath
            )
        }
        try BridgeProductContractDecoding.validateIdentifier(sessionId, codingPath: decoder.codingPath)
    }
}

enum BridgeProductCallRequest: Codable, Equatable, Sendable {
    case fileSourceCurrent(BridgeProductFileSourceCurrentRequest)
    case fileActiveViewerModeUpdate(BridgeProductActiveViewerModeUpdateRequest)
    case reviewActiveViewerModeUpdate(BridgeProductActiveViewerModeUpdateRequest)
    case reviewIntakeReady(BridgeProductReviewIntakeReadyRequest)
    case reviewMarkFileViewed(BridgeProductReviewMarkFileViewedRequest)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case request
    }

    var method: String {
        switch self {
        case .fileSourceCurrent: "file.source.current"
        case .fileActiveViewerModeUpdate: "file.activeViewerMode.update"
        case .reviewActiveViewerModeUpdate: "review.activeViewerMode.update"
        case .reviewIntakeReady: "review.intake.ready"
        case .reviewMarkFileViewed: "review.markFileViewed"
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .fileSourceCurrent, .fileActiveViewerModeUpdate: .file
        case .reviewActiveViewerModeUpdate, .reviewIntakeReady, .reviewMarkFileViewed: .review
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product call request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .method) {
        case "file.source.current":
            self = .fileSourceCurrent(
                try container.decode(BridgeProductFileSourceCurrentRequest.self, forKey: .request)
            )
        case "file.activeViewerMode.update":
            self = .fileActiveViewerModeUpdate(
                try container.decode(BridgeProductActiveViewerModeUpdateRequest.self, forKey: .request)
            )
        case "review.activeViewerMode.update":
            self = .reviewActiveViewerModeUpdate(
                try container.decode(BridgeProductActiveViewerModeUpdateRequest.self, forKey: .request)
            )
        case "review.markFileViewed":
            self = .reviewMarkFileViewed(
                try container.decode(BridgeProductReviewMarkFileViewedRequest.self, forKey: .request)
            )
        case "review.intake.ready":
            self = .reviewIntakeReady(
                try container.decode(BridgeProductReviewIntakeReadyRequest.self, forKey: .request)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "Unknown Bridge product call method"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        switch self {
        case .fileSourceCurrent(let request):
            try container.encode(request, forKey: .request)
        case .fileActiveViewerModeUpdate(let request),
            .reviewActiveViewerModeUpdate(let request):
            try container.encode(request, forKey: .request)
        case .reviewMarkFileViewed(let request):
            try container.encode(request, forKey: .request)
        case .reviewIntakeReady(let request):
            try container.encode(request, forKey: .request)
        }
    }
}

enum BridgeProductCallResult: Codable, Equatable, Sendable {
    case fileSourceCurrent(BridgeProductFileSourceCurrentResult)
    case fileActiveViewerModeUpdate
    case reviewActiveViewerModeUpdate
    case reviewIntakeReady
    case reviewMarkFileViewed

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case result
    }

    var method: String {
        switch self {
        case .fileSourceCurrent: "file.source.current"
        case .fileActiveViewerModeUpdate: "file.activeViewerMode.update"
        case .reviewActiveViewerModeUpdate: "review.activeViewerMode.update"
        case .reviewIntakeReady: "review.intake.ready"
        case .reviewMarkFileViewed: "review.markFileViewed"
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .fileSourceCurrent, .fileActiveViewerModeUpdate: .file
        case .reviewActiveViewerModeUpdate, .reviewIntakeReady, .reviewMarkFileViewed: .review
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product call result"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .method) {
        case "file.source.current":
            self = .fileSourceCurrent(
                try container.decode(BridgeProductFileSourceCurrentResult.self, forKey: .result)
            )
        case "file.activeViewerMode.update":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            self = .fileActiveViewerModeUpdate
        case "review.activeViewerMode.update":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            self = .reviewActiveViewerModeUpdate
        case "review.markFileViewed":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            self = .reviewMarkFileViewed
        case "review.intake.ready":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            self = .reviewIntakeReady
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .method,
                in: container,
                debugDescription: "Unknown Bridge product call result method"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        switch self {
        case .fileSourceCurrent(let result):
            try container.encode(result, forKey: .result)
        case .fileActiveViewerModeUpdate, .reviewActiveViewerModeUpdate,
            .reviewIntakeReady, .reviewMarkFileViewed:
            try container.encodeNil(forKey: .result)
        }
    }
}
