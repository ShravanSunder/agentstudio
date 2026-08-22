import AgentStudioCore
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

struct BridgeProductFileRefreshRetryRequest: Codable, Equatable, Sendable {
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
            contract: "file.refresh.retry request"
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

struct BridgeProductReviewComparisonUpdateRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
    }

    let target: WorkspaceReviewContributionTarget

    init(target: WorkspaceReviewContributionTarget) {
        self.target = target
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.comparison.update request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.target = try container.decode(
            BridgeProductReviewComparisonTransportTarget.self,
            forKey: .target
        ).workspaceTarget
    }
}

struct BridgeProductReviewComparisonTargetsQueryRequest: Codable, Equatable, Sendable {
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
            contract: "review.comparisonTargets.query request"
        )
        _ = try decoder.container(keyedBy: EmptyCodingKey.self)
    }

    func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: EmptyCodingKey.self)
    }
}

struct BridgeProductReviewPublicationAppliedRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case publicationId
    }

    let publicationId: UUID

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.publication.applied request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let publicationIdValue = try container.decode(String.self, forKey: .publicationId)
        self.publicationId = try BridgeProductReviewPublicationIdContract.decode(
            publicationIdValue,
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(publicationId),
            forKey: .publicationId
        )
    }
}

struct BridgeProductReviewInstallAdmissionRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case candidatePublicationId
        case expectedDisplayedPublicationId
    }

    let expectedDisplayedPublicationId: UUID?
    let candidatePublicationId: UUID

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.publication.install.admit request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.candidatePublicationId = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .candidatePublicationId),
            codingPath: decoder.codingPath
        )
        if let expectedDisplayedPublicationIdValue = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .expectedDisplayedPublicationId,
            from: container,
            codingPath: decoder.codingPath
        ) {
            self.expectedDisplayedPublicationId = try BridgeProductReviewPublicationIdContract.decode(
                expectedDisplayedPublicationIdValue,
                codingPath: decoder.codingPath
            )
        } else {
            self.expectedDisplayedPublicationId = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(candidatePublicationId),
            forKey: .candidatePublicationId
        )
        if let expectedDisplayedPublicationId {
            try container.encode(
                BridgeProductReviewPublicationIdContract.encode(expectedDisplayedPublicationId),
                forKey: .expectedDisplayedPublicationId
            )
        } else {
            try container.encodeNil(forKey: .expectedDisplayedPublicationId)
        }
    }
}

enum BridgeProductReviewInstallAdmissionStatus: String, Codable, Equatable, Sendable {
    case admitted
    case rejected
}

struct BridgeProductReviewInstallAdmissionResult: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
    }

    let status: BridgeProductReviewInstallAdmissionStatus

    init(status: BridgeProductReviewInstallAdmissionStatus) {
        self.status = status
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "review.publication.install.admit result"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(
            BridgeProductReviewInstallAdmissionStatus.self,
            forKey: .status
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let reason {
            try container.encode(reason, forKey: .reason)
        } else {
            try container.encodeNil(forKey: .reason)
        }
        if let streamId {
            try container.encode(streamId, forKey: .streamId)
        } else {
            try container.encodeNil(forKey: .streamId)
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
        case nativeSelectionRequestId
        case sequence
        case sessionId
    }

    let activeSource: BridgeProductActiveViewerSourceRequest?
    let nativeSelectionRequestId: String?
    let sequence: Int
    let sessionId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "active viewer mode update request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.nativeSelectionRequestId) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Active viewer mode update nativeSelectionRequestId must be explicit",
                codingPath: decoder.codingPath
            )
        }
        self.activeSource = try container.decodeIfPresent(
            BridgeProductActiveViewerSourceRequest.self,
            forKey: .activeSource
        )
        self.nativeSelectionRequestId = try container.decodeIfPresent(
            String.self,
            forKey: .nativeSelectionRequestId
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
        if let nativeSelectionRequestId {
            try BridgeProductContractDecoding.validateIdentifier(
                nativeSelectionRequestId,
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let activeSource {
            try container.encode(activeSource, forKey: .activeSource)
        } else {
            try container.encodeNil(forKey: .activeSource)
        }
        if let nativeSelectionRequestId {
            try container.encode(nativeSelectionRequestId, forKey: .nativeSelectionRequestId)
        } else {
            try container.encodeNil(forKey: .nativeSelectionRequestId)
        }
        try container.encode(sequence, forKey: .sequence)
        try container.encode(sessionId, forKey: .sessionId)
    }
}

enum BridgeProductCallRequest: Codable, Equatable, Sendable {
    case fileAnnotationsCommand(BridgeProductWorktreeAnnotationCommandRequest)
    case fileAnnotationsOutputInspect(BridgeProductAnnotationOutputInspectRequest)
    case fileAnnotationsProjectionQuery(BridgeProductAnnotationProjectionQueryRequest)
    case fileSourceCurrent(BridgeProductFileSourceCurrentRequest)
    case fileRefreshRetry(BridgeProductFileRefreshRetryRequest)
    case fileActiveViewerModeUpdate(BridgeProductActiveViewerModeUpdateRequest)
    case reviewActiveViewerModeUpdate(BridgeProductActiveViewerModeUpdateRequest)
    case reviewComparisonUpdate(BridgeProductReviewComparisonUpdateRequest)
    case reviewComparisonTargetsQuery(BridgeProductReviewComparisonTargetsQueryRequest)
    case reviewIntakeReady(BridgeProductReviewIntakeReadyRequest)
    case reviewMarkFileViewed(BridgeProductReviewMarkFileViewedRequest)
    case reviewPublicationInstallAdmission(BridgeProductReviewInstallAdmissionRequest)
    case reviewPublicationApplied(BridgeProductReviewPublicationAppliedRequest)
    case reviewAnnotationsCommand(BridgeProductWorktreeAnnotationCommandRequest)
    case reviewAnnotationsOutputInspect(BridgeProductAnnotationOutputInspectRequest)
    case reviewAnnotationsProjectionQuery(BridgeProductAnnotationProjectionQueryRequest)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case request
    }

    var method: String {
        switch self {
        case .fileAnnotationsCommand: "file.annotations.command"
        case .fileAnnotationsOutputInspect: "file.annotations.output.inspect"
        case .fileAnnotationsProjectionQuery: "file.annotations.projection.query"
        case .fileSourceCurrent: "file.source.current"
        case .fileRefreshRetry: "file.refresh.retry"
        case .fileActiveViewerModeUpdate: "file.activeViewerMode.update"
        case .reviewActiveViewerModeUpdate: "review.activeViewerMode.update"
        case .reviewComparisonUpdate: "review.comparison.update"
        case .reviewComparisonTargetsQuery: "review.comparisonTargets.query"
        case .reviewIntakeReady: "review.intake.ready"
        case .reviewMarkFileViewed: "review.markFileViewed"
        case .reviewPublicationInstallAdmission: "review.publication.install.admit"
        case .reviewPublicationApplied: "review.publication.applied"
        case .reviewAnnotationsCommand: "review.annotations.command"
        case .reviewAnnotationsOutputInspect: "review.annotations.output.inspect"
        case .reviewAnnotationsProjectionQuery: "review.annotations.projection.query"
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .fileAnnotationsCommand, .fileAnnotationsOutputInspect,
            .fileAnnotationsProjectionQuery,
            .fileSourceCurrent,
            .fileRefreshRetry,
            .fileActiveViewerModeUpdate:
            .file
        case .reviewActiveViewerModeUpdate, .reviewComparisonUpdate, .reviewComparisonTargetsQuery, .reviewIntakeReady,
            .reviewMarkFileViewed,
            .reviewPublicationInstallAdmission, .reviewPublicationApplied,
            .reviewAnnotationsCommand, .reviewAnnotationsOutputInspect,
            .reviewAnnotationsProjectionQuery:
            .review
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product call request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(String.self, forKey: .method)
        if method.hasPrefix("file.") {
            self = try Self.decodeFileRequest(method: method, from: container, decoder: decoder)
        } else if method.hasPrefix("review.") {
            self = try Self.decodeReviewRequest(method: method, from: container, decoder: decoder)
        } else {
            throw Self.unknownMethodError(forKey: .method, in: container)
        }
    }

    private static func decodeFileRequest(
        method: String,
        from container: KeyedDecodingContainer<CodingKeys>,
        decoder: Decoder
    ) throws -> Self {
        switch method {
        case "file.annotations.command":
            let request = try container.decode(
                BridgeProductWorktreeAnnotationCommandRequest.self,
                forKey: .request
            )
            try request.validateSource(surface: .file, codingPath: decoder.codingPath)
            return .fileAnnotationsCommand(request)
        case "file.annotations.output.inspect":
            return .fileAnnotationsOutputInspect(
                try container.decode(
                    BridgeProductAnnotationOutputInspectRequest.self,
                    forKey: .request
                )
            )
        case "file.annotations.projection.query":
            let request = try container.decode(
                BridgeProductAnnotationProjectionQueryRequest.self,
                forKey: .request
            )
            guard request.surface == .file else {
                throw BridgeProductContractDecoding.invalidValue(
                    "File annotation projection queries must remain File-surface bound",
                    codingPath: decoder.codingPath
                )
            }
            return .fileAnnotationsProjectionQuery(request)
        case "file.source.current":
            return .fileSourceCurrent(
                try container.decode(BridgeProductFileSourceCurrentRequest.self, forKey: .request)
            )
        case "file.refresh.retry":
            return .fileRefreshRetry(
                try container.decode(BridgeProductFileRefreshRetryRequest.self, forKey: .request)
            )
        case "file.activeViewerMode.update":
            return .fileActiveViewerModeUpdate(
                try container.decode(BridgeProductActiveViewerModeUpdateRequest.self, forKey: .request)
            )
        default:
            throw unknownMethodError(forKey: .method, in: container)
        }
    }

    private static func decodeReviewRequest(
        method: String,
        from container: KeyedDecodingContainer<CodingKeys>,
        decoder: Decoder
    ) throws -> Self {
        switch method {
        case "review.activeViewerMode.update":
            return .reviewActiveViewerModeUpdate(
                try container.decode(BridgeProductActiveViewerModeUpdateRequest.self, forKey: .request)
            )
        case "review.comparison.update":
            return .reviewComparisonUpdate(
                try container.decode(
                    BridgeProductReviewComparisonUpdateRequest.self,
                    forKey: .request
                )
            )
        case "review.comparisonTargets.query":
            return .reviewComparisonTargetsQuery(
                try container.decode(
                    BridgeProductReviewComparisonTargetsQueryRequest.self,
                    forKey: .request
                )
            )
        case "review.markFileViewed":
            return .reviewMarkFileViewed(
                try container.decode(BridgeProductReviewMarkFileViewedRequest.self, forKey: .request)
            )
        case "review.intake.ready":
            return .reviewIntakeReady(
                try container.decode(BridgeProductReviewIntakeReadyRequest.self, forKey: .request)
            )
        case "review.publication.applied":
            return .reviewPublicationApplied(
                try container.decode(
                    BridgeProductReviewPublicationAppliedRequest.self,
                    forKey: .request
                )
            )
        case "review.publication.install.admit":
            return .reviewPublicationInstallAdmission(
                try container.decode(
                    BridgeProductReviewInstallAdmissionRequest.self,
                    forKey: .request
                )
            )
        case "review.annotations.command":
            let request = try container.decode(
                BridgeProductWorktreeAnnotationCommandRequest.self,
                forKey: .request
            )
            try request.validateSource(surface: .review, codingPath: decoder.codingPath)
            return .reviewAnnotationsCommand(request)
        case "review.annotations.output.inspect":
            return .reviewAnnotationsOutputInspect(
                try container.decode(
                    BridgeProductAnnotationOutputInspectRequest.self,
                    forKey: .request
                )
            )
        case "review.annotations.projection.query":
            let request = try container.decode(
                BridgeProductAnnotationProjectionQueryRequest.self,
                forKey: .request
            )
            guard request.surface == .review else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Review annotation projection queries must remain Review-surface bound",
                    codingPath: decoder.codingPath
                )
            }
            return .reviewAnnotationsProjectionQuery(request)
        default:
            throw unknownMethodError(forKey: .method, in: container)
        }
    }

    private static func unknownMethodError(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) -> DecodingError {
        DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Unknown Bridge product call method"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        switch self {
        case .fileAnnotationsCommand(let request), .reviewAnnotationsCommand(let request):
            try container.encode(request, forKey: .request)
        case .fileAnnotationsOutputInspect(let request),
            .reviewAnnotationsOutputInspect(let request):
            try container.encode(request, forKey: .request)
        case .fileAnnotationsProjectionQuery(let request),
            .reviewAnnotationsProjectionQuery(let request):
            try container.encode(request, forKey: .request)
        case .fileSourceCurrent(let request):
            try container.encode(request, forKey: .request)
        case .fileRefreshRetry(let request):
            try container.encode(request, forKey: .request)
        case .fileActiveViewerModeUpdate(let request),
            .reviewActiveViewerModeUpdate(let request):
            try container.encode(request, forKey: .request)
        case .reviewComparisonUpdate(let request):
            try container.encode(request, forKey: .request)
        case .reviewComparisonTargetsQuery(let request):
            try container.encode(request, forKey: .request)
        case .reviewMarkFileViewed(let request):
            try container.encode(request, forKey: .request)
        case .reviewIntakeReady(let request):
            try container.encode(request, forKey: .request)
        case .reviewPublicationApplied(let request):
            try container.encode(request, forKey: .request)
        case .reviewPublicationInstallAdmission(let request):
            try container.encode(request, forKey: .request)
        }
    }
}

enum BridgeProductCallResult: Codable, Equatable, Sendable {
    case fileAnnotationsCommand(BridgeProductWorktreeAnnotationCommandResult)
    case fileAnnotationsOutputInspect(BridgeProductWorktreeAnnotationOutputInspectResult)
    case fileAnnotationsProjectionQuery(BridgeProductAnnotationProjectionQueryResult)
    case fileSourceCurrent(BridgeProductFileSourceCurrentResult)
    case fileRefreshRetry
    case fileActiveViewerModeUpdate
    case reviewActiveViewerModeUpdate
    case reviewComparisonUpdate
    case reviewComparisonTargetsQuery(BridgeProductReviewComparisonTargetsQueryResult)
    case reviewIntakeReady
    case reviewMarkFileViewed
    case reviewPublicationInstallAdmission(BridgeProductReviewInstallAdmissionResult)
    case reviewPublicationApplied
    case reviewAnnotationsCommand(BridgeProductWorktreeAnnotationCommandResult)
    case reviewAnnotationsOutputInspect(BridgeProductWorktreeAnnotationOutputInspectResult)
    case reviewAnnotationsProjectionQuery(BridgeProductAnnotationProjectionQueryResult)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case method
        case result
    }

    var method: String {
        switch self {
        case .fileAnnotationsCommand: "file.annotations.command"
        case .fileAnnotationsOutputInspect: "file.annotations.output.inspect"
        case .fileAnnotationsProjectionQuery: "file.annotations.projection.query"
        case .fileSourceCurrent: "file.source.current"
        case .fileRefreshRetry: "file.refresh.retry"
        case .fileActiveViewerModeUpdate: "file.activeViewerMode.update"
        case .reviewActiveViewerModeUpdate: "review.activeViewerMode.update"
        case .reviewComparisonUpdate: "review.comparison.update"
        case .reviewComparisonTargetsQuery: "review.comparisonTargets.query"
        case .reviewIntakeReady: "review.intake.ready"
        case .reviewMarkFileViewed: "review.markFileViewed"
        case .reviewPublicationInstallAdmission: "review.publication.install.admit"
        case .reviewPublicationApplied: "review.publication.applied"
        case .reviewAnnotationsCommand: "review.annotations.command"
        case .reviewAnnotationsOutputInspect: "review.annotations.output.inspect"
        case .reviewAnnotationsProjectionQuery: "review.annotations.projection.query"
        }
    }

    var surface: BridgeProductSurface {
        switch self {
        case .fileAnnotationsCommand, .fileAnnotationsOutputInspect,
            .fileAnnotationsProjectionQuery,
            .fileSourceCurrent,
            .fileRefreshRetry,
            .fileActiveViewerModeUpdate:
            .file
        case .reviewActiveViewerModeUpdate, .reviewComparisonUpdate, .reviewComparisonTargetsQuery, .reviewIntakeReady,
            .reviewMarkFileViewed,
            .reviewPublicationInstallAdmission, .reviewPublicationApplied,
            .reviewAnnotationsCommand, .reviewAnnotationsOutputInspect,
            .reviewAnnotationsProjectionQuery:
            .review
        }
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge product call result"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(String.self, forKey: .method)
        if method.hasPrefix("file.") {
            self = try Self.decodeFileResult(method: method, from: container, decoder: decoder)
        } else if method.hasPrefix("review.") {
            self = try Self.decodeReviewResult(method: method, from: container, decoder: decoder)
        } else {
            throw Self.unknownResultMethodError(forKey: .method, in: container)
        }
    }

    private static func decodeFileResult(
        method: String,
        from container: KeyedDecodingContainer<CodingKeys>,
        decoder: Decoder
    ) throws -> Self {
        switch method {
        case "file.annotations.command":
            return .fileAnnotationsCommand(
                try container.decode(BridgeProductWorktreeAnnotationCommandResult.self, forKey: .result)
            )
        case "file.annotations.output.inspect":
            return .fileAnnotationsOutputInspect(
                try Self.decodeOutputInspection(from: container, surface: .file, decoder: decoder)
            )
        case "file.annotations.projection.query":
            return .fileAnnotationsProjectionQuery(
                try Self.decodeProjectionQuery(from: container, surface: .file, decoder: decoder)
            )
        case "file.source.current":
            return .fileSourceCurrent(
                try container.decode(BridgeProductFileSourceCurrentResult.self, forKey: .result)
            )
        case "file.refresh.retry":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            return .fileRefreshRetry
        case "file.activeViewerMode.update":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            return .fileActiveViewerModeUpdate
        default:
            throw unknownResultMethodError(forKey: .method, in: container)
        }
    }

    private static func decodeReviewResult(
        method: String,
        from container: KeyedDecodingContainer<CodingKeys>,
        decoder: Decoder
    ) throws -> Self {
        switch method {
        case "review.activeViewerMode.update":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            return .reviewActiveViewerModeUpdate
        case "review.comparison.update":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            return .reviewComparisonUpdate
        case "review.comparisonTargets.query":
            return .reviewComparisonTargetsQuery(
                try container.decode(
                    BridgeProductReviewComparisonTargetsQueryResult.self,
                    forKey: .result
                )
            )
        case "review.markFileViewed":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            return .reviewMarkFileViewed
        case "review.intake.ready":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            return .reviewIntakeReady
        case "review.publication.applied":
            try BridgeProductContractDecoding.decodeRequiredNull(
                forKey: .result,
                from: container,
                codingPath: decoder.codingPath
            )
            return .reviewPublicationApplied
        case "review.publication.install.admit":
            return .reviewPublicationInstallAdmission(
                try container.decode(
                    BridgeProductReviewInstallAdmissionResult.self,
                    forKey: .result
                )
            )
        case "review.annotations.command":
            return .reviewAnnotationsCommand(
                try container.decode(BridgeProductWorktreeAnnotationCommandResult.self, forKey: .result)
            )
        case "review.annotations.output.inspect":
            return .reviewAnnotationsOutputInspect(
                try Self.decodeOutputInspection(from: container, surface: .review, decoder: decoder)
            )
        case "review.annotations.projection.query":
            return .reviewAnnotationsProjectionQuery(
                try Self.decodeProjectionQuery(from: container, surface: .review, decoder: decoder)
            )
        default:
            throw unknownResultMethodError(forKey: .method, in: container)
        }
    }

    private static func unknownResultMethodError(
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) -> DecodingError {
        DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Unknown Bridge product call result method"
        )
    }

    private static func decodeOutputInspection(
        from container: KeyedDecodingContainer<CodingKeys>,
        surface: BridgeProductSurface,
        decoder: Decoder
    ) throws -> BridgeProductWorktreeAnnotationOutputInspectResult {
        let result = try container.decode(
            BridgeProductWorktreeAnnotationOutputInspectResult.self,
            forKey: .result
        )
        guard result.descriptor.surface == surface else {
            let surfaceName = surface == .file ? "File" : "Review"
            throw BridgeProductContractDecoding.invalidValue(
                "\(surfaceName) annotation output descriptor must remain on the \(surfaceName) surface",
                codingPath: decoder.codingPath
            )
        }
        return result
    }

    private static func decodeProjectionQuery(
        from container: KeyedDecodingContainer<CodingKeys>,
        surface: BridgeProductSurface,
        decoder: Decoder
    ) throws -> BridgeProductAnnotationProjectionQueryResult {
        let result = try container.decode(
            BridgeProductAnnotationProjectionQueryResult.self,
            forKey: .result
        )
        let matchesSurface =
            switch result {
            case .content(let descriptor): descriptor.surface == surface
            case .sourceStale: true
            }
        guard matchesSurface else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation projection descriptor surface does not match its call method",
                codingPath: decoder.codingPath
            )
        }
        return result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        switch self {
        case .fileAnnotationsCommand(let result), .reviewAnnotationsCommand(let result):
            try container.encode(result, forKey: .result)
        case .fileAnnotationsOutputInspect(let result),
            .reviewAnnotationsOutputInspect(let result):
            try container.encode(result, forKey: .result)
        case .fileAnnotationsProjectionQuery(let result),
            .reviewAnnotationsProjectionQuery(let result):
            try container.encode(result, forKey: .result)
        case .fileSourceCurrent(let result):
            try container.encode(result, forKey: .result)
        case .fileRefreshRetry, .fileActiveViewerModeUpdate, .reviewActiveViewerModeUpdate,
            .reviewComparisonUpdate,
            .reviewIntakeReady, .reviewMarkFileViewed, .reviewPublicationApplied:
            try container.encodeNil(forKey: .result)
        case .reviewComparisonTargetsQuery(let result):
            try container.encode(result, forKey: .result)
        case .reviewPublicationInstallAdmission(let result):
            try container.encode(result, forKey: .result)
        }
    }
}
