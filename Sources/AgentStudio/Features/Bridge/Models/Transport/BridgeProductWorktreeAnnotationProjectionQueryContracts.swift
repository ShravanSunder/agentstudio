import Foundation

enum BridgeProductAnnotationProjectionContract {
    static let maximumDemandedSessionCount = 128
    static let maximumPageCount = 128
    static let maximumPageBytes = 2 * 1024 * 1024
}

struct BridgeProductReviewAnnotationPublicationIdentity: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case packageId
        case publicationId
        case reviewGeneration
        case revision
        case sourceIdentity
    }

    let packageId: String
    let publicationId: UUID
    let reviewGeneration: Int
    let revision: Int
    let sourceIdentity: String

    init(
        packageId: String,
        publicationId: UUID,
        reviewGeneration: Int,
        revision: Int,
        sourceIdentity: String
    ) throws {
        self.packageId = packageId
        self.publicationId = publicationId
        self.reviewGeneration = reviewGeneration
        self.revision = revision
        self.sourceIdentity = sourceIdentity
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review annotation publication identity"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageId = try container.decode(String.self, forKey: .packageId)
        publicationId = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .publicationId),
            codingPath: decoder.codingPath
        )
        reviewGeneration = try container.decode(Int.self, forKey: .reviewGeneration)
        revision = try container.decode(Int.self, forKey: .revision)
        sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageId, forKey: .packageId)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(publicationId),
            forKey: .publicationId
        )
        try container.encode(reviewGeneration, forKey: .reviewGeneration)
        try container.encode(revision, forKey: .revision)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            reviewGeneration,
            name: "reviewGeneration",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            revision,
            name: "revision",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: codingPath)
    }
}

struct BridgeProductAnnotationProjectionQueryRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cursor
        case operationCorrelationId
        case reviewPublicationIdentity
        case sessionIds
        case sourceGeneration
        case surface
    }

    let cursor: String?
    let operationCorrelationID: String
    let reviewPublicationIdentity: BridgeProductReviewAnnotationPublicationIdentity?
    let sessionIDs: [UUID]
    let sourceGeneration: Int
    let surface: BridgeProductSurface

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation projection query request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .cursor,
            from: container,
            codingPath: decoder.codingPath
        )
        operationCorrelationID = try container.decode(String.self, forKey: .operationCorrelationId)
        reviewPublicationIdentity = try container.decodeIfPresent(
            BridgeProductReviewAnnotationPublicationIdentity.self,
            forKey: .reviewPublicationIdentity
        )
        let encodedSessionIDs = try container.decode([String].self, forKey: .sessionIds)
        guard encodedSessionIDs.count <= BridgeProductAnnotationProjectionContract.maximumDemandedSessionCount else {
            throw BridgeProductContractDecoding.invalidValue(
                "Too many demanded annotation sessions",
                codingPath: decoder.codingPath
            )
        }
        sessionIDs = try encodedSessionIDs.map {
            try BridgeProductReviewPublicationIdContract.decode($0, codingPath: decoder.codingPath)
        }
        guard Set(sessionIDs).count == sessionIDs.count else {
            throw BridgeProductContractDecoding.invalidValue(
                "Demanded annotation sessions must be unique",
                codingPath: decoder.codingPath
            )
        }
        sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        switch surface {
        case .file:
            guard reviewPublicationIdentity == nil else {
                throw BridgeProductContractDecoding.invalidValue(
                    "File annotation projection cannot carry Review publication identity",
                    codingPath: decoder.codingPath
                )
            }
        case .review:
            guard let reviewPublicationIdentity,
                reviewPublicationIdentity.reviewGeneration == sourceGeneration
            else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Review annotation projection requires exact installed publication identity",
                    codingPath: decoder.codingPath
                )
            }
        }
        if let cursor {
            try BridgeProductContractDecoding.validateOpaqueReference(cursor, codingPath: decoder.codingPath)
        }
        try BridgeProductContractDecoding.validateSHA256(
            operationCorrelationID,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            sourceGeneration,
            name: "sourceGeneration",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
        try container.encodeIfPresent(reviewPublicationIdentity, forKey: .reviewPublicationIdentity)
        try container.encode(
            sessionIDs.map(BridgeProductReviewPublicationIdContract.encode),
            forKey: .sessionIds
        )
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(surface, forKey: .surface)
    }
}

struct BridgeProductAnnotationProjectionPageContract: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case aggregateSha256
        case expectedMessageCount
        case expectedPageCount
        case expectedSessionCount
        case expectedThreadCount
        case isLastPage
        case nextCursor
        case operationCorrelationId
        case pageOrdinal
        case projectionRevision
        case snapshotId
        case sourceGeneration
    }

    let aggregateSHA256: String
    let expectedMessageCount: Int
    let expectedPageCount: Int
    let expectedSessionCount: Int
    let expectedThreadCount: Int
    let isLastPage: Bool
    let nextCursor: String?
    let operationCorrelationID: String
    let pageOrdinal: Int
    let projectionRevision: Int
    let snapshotID: UUID
    let sourceGeneration: Int

    init(
        aggregateSHA256: String,
        expectedMessageCount: Int,
        expectedPageCount: Int,
        expectedSessionCount: Int,
        expectedThreadCount: Int,
        isLastPage: Bool,
        nextCursor: String?,
        operationCorrelationID: String,
        pageOrdinal: Int,
        projectionRevision: Int,
        snapshotID: UUID,
        sourceGeneration: Int
    ) throws {
        self.aggregateSHA256 = aggregateSHA256
        self.expectedMessageCount = expectedMessageCount
        self.expectedPageCount = expectedPageCount
        self.expectedSessionCount = expectedSessionCount
        self.expectedThreadCount = expectedThreadCount
        self.isLastPage = isLastPage
        self.nextCursor = nextCursor
        self.operationCorrelationID = operationCorrelationID
        self.pageOrdinal = pageOrdinal
        self.projectionRevision = projectionRevision
        self.snapshotID = snapshotID
        self.sourceGeneration = sourceGeneration
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation projection page contract"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aggregateSHA256 = try container.decode(String.self, forKey: .aggregateSha256)
        expectedMessageCount = try container.decode(Int.self, forKey: .expectedMessageCount)
        expectedPageCount = try container.decode(Int.self, forKey: .expectedPageCount)
        expectedSessionCount = try container.decode(Int.self, forKey: .expectedSessionCount)
        expectedThreadCount = try container.decode(Int.self, forKey: .expectedThreadCount)
        isLastPage = try container.decode(Bool.self, forKey: .isLastPage)
        nextCursor = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .nextCursor,
            from: container,
            codingPath: decoder.codingPath
        )
        operationCorrelationID = try container.decode(String.self, forKey: .operationCorrelationId)
        pageOrdinal = try container.decode(Int.self, forKey: .pageOrdinal)
        projectionRevision = try container.decode(Int.self, forKey: .projectionRevision)
        snapshotID = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .snapshotId),
            codingPath: decoder.codingPath
        )
        sourceGeneration = try container.decode(Int.self, forKey: .sourceGeneration)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aggregateSHA256, forKey: .aggregateSha256)
        try container.encode(expectedMessageCount, forKey: .expectedMessageCount)
        try container.encode(expectedPageCount, forKey: .expectedPageCount)
        try container.encode(expectedSessionCount, forKey: .expectedSessionCount)
        try container.encode(expectedThreadCount, forKey: .expectedThreadCount)
        try container.encode(isLastPage, forKey: .isLastPage)
        try container.encode(nextCursor, forKey: .nextCursor)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
        try container.encode(pageOrdinal, forKey: .pageOrdinal)
        try container.encode(projectionRevision, forKey: .projectionRevision)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(snapshotID),
            forKey: .snapshotId
        )
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
    }

    func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateSHA256(aggregateSHA256, codingPath: codingPath)
        try BridgeProductContractDecoding.validateSHA256(
            operationCorrelationID,
            codingPath: codingPath
        )
        for (name, count) in [
            ("expectedMessageCount", expectedMessageCount),
            ("expectedPageCount", expectedPageCount),
            ("expectedSessionCount", expectedSessionCount),
            ("expectedThreadCount", expectedThreadCount),
            ("pageOrdinal", pageOrdinal),
            ("projectionRevision", projectionRevision),
            ("sourceGeneration", sourceGeneration),
        ] {
            try BridgeProductContractDecoding.validateNonnegative(
                count,
                name: name,
                codingPath: codingPath
            )
        }
        if let nextCursor {
            try BridgeProductContractDecoding.validateOpaqueReference(nextCursor, codingPath: codingPath)
        }
        guard isLastPage == (nextCursor == nil) else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation projection continuation must agree with isLastPage",
                codingPath: codingPath
            )
        }
        guard expectedPageCount > 0,
            expectedPageCount <= BridgeProductAnnotationProjectionContract.maximumPageCount,
            isLastPage == (pageOrdinal + 1 == expectedPageCount)
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Annotation projection final page must agree with bounded expectedPageCount",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductAnnotationProjectionContentDescriptor: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentKind
        case descriptorId
        case maximumBytes
        case page
        case surface
    }

    let descriptorID: String
    let maximumBytes: Int
    let page: BridgeProductAnnotationProjectionPageContract
    let surface: BridgeProductSurface

    init(
        descriptorID: String,
        maximumBytes: Int,
        page: BridgeProductAnnotationProjectionPageContract,
        surface: BridgeProductSurface
    ) throws {
        self.descriptorID = descriptorID
        self.maximumBytes = maximumBytes
        self.page = page
        self.surface = surface
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation projection content descriptor"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "annotation.projection" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid worktree annotation projection content kind",
                codingPath: decoder.codingPath
            )
        }
        descriptorID = try container.decode(String.self, forKey: .descriptorId)
        maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        page = try container.decode(BridgeProductAnnotationProjectionPageContract.self, forKey: .page)
        surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("annotation.projection", forKey: .contentKind)
        try container.encode(descriptorID, forKey: .descriptorId)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(page, forKey: .page)
        try container.encode(surface, forKey: .surface)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateIdentifier(descriptorID, codingPath: codingPath)
        try BridgeProductContractDecoding.validatePositive(
            maximumBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            maximumBytes,
            maximum: BridgeProductAnnotationProjectionContract.maximumPageBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
    }
}

struct BridgeProductAnnotationProjectionContentIdentity: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentKind
        case descriptorId
        case maximumBytes
        case page
        case surface
    }

    let descriptorID: String
    let maximumBytes: Int
    let page: BridgeProductAnnotationProjectionPageContract
    let surface: BridgeProductSurface

    init(descriptor: BridgeProductAnnotationProjectionContentDescriptor) {
        descriptorID = descriptor.descriptorID
        maximumBytes = descriptor.maximumBytes
        page = descriptor.page
        surface = descriptor.surface
    }

    init(from decoder: Decoder) throws {
        let descriptor = try BridgeProductAnnotationProjectionContentDescriptor(from: decoder)
        descriptorID = descriptor.descriptorID
        maximumBytes = descriptor.maximumBytes
        page = descriptor.page
        surface = descriptor.surface
    }

    func encode(to encoder: Encoder) throws {
        try BridgeProductAnnotationProjectionContentDescriptor(
            descriptorID: descriptorID,
            maximumBytes: maximumBytes,
            page: page,
            surface: surface
        ).encode(to: encoder)
    }
}

struct BridgeProductAnnotationProjectionContentRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentKind
        case contentRequestId
        case descriptor
        case kind
        case leaseId
        case operationCorrelationId
        case paneSessionId
        case wireVersion
        case workerDerivationEpoch
        case workerInstanceId
    }

    let contentRequestID: String
    let descriptor: BridgeProductAnnotationProjectionContentDescriptor
    let leaseID: String
    let operationCorrelationID: String?
    let paneSessionID: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceID: String

    var admission: BridgeProductContentAdmission {
        .init(
            contentKind: .annotationProjection,
            contentRequestId: contentRequestID,
            declaredByteLength: nil,
            expectedSha256: nil,
            identity: .annotationProjection(.init(descriptor: descriptor)),
            leaseId: leaseID,
            operationCorrelationID: operationCorrelationID,
            maximumBytes: descriptor.maximumBytes,
            paneSessionId: paneSessionID,
            wireVersion: wireVersion,
            workerDerivationEpoch: workerDerivationEpoch,
            workerInstanceId: workerInstanceID
        )
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation projection content request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "annotation.projection",
            try container.decode(String.self, forKey: .kind) == "content.open"
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid worktree annotation projection content request kind",
                codingPath: decoder.codingPath
            )
        }
        contentRequestID = try container.decode(String.self, forKey: .contentRequestId)
        descriptor = try container.decode(
            BridgeProductAnnotationProjectionContentDescriptor.self,
            forKey: .descriptor
        )
        leaseID = try container.decode(String.self, forKey: .leaseId)
        operationCorrelationID = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .operationCorrelationId,
            from: container,
            codingPath: decoder.codingPath
        )
        paneSessionID = try container.decode(String.self, forKey: .paneSessionId)
        wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        workerDerivationEpoch = try container.decode(Int.self, forKey: .workerDerivationEpoch)
        workerInstanceID = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(contentRequestID, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(leaseID, codingPath: decoder.codingPath)
        if let operationCorrelationID {
            try BridgeProductContractDecoding.validateSHA256(operationCorrelationID, codingPath: decoder.codingPath)
        }
        try BridgeProductContractDecoding.validateIdentifier(paneSessionID, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceID, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("annotation.projection", forKey: .contentKind)
        try container.encode(contentRequestID, forKey: .contentRequestId)
        try container.encode(descriptor, forKey: .descriptor)
        try container.encode("content.open", forKey: .kind)
        try container.encode(leaseID, forKey: .leaseId)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
        try container.encode(paneSessionID, forKey: .paneSessionId)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerDerivationEpoch, forKey: .workerDerivationEpoch)
        try container.encode(workerInstanceID, forKey: .workerInstanceId)
    }
}

enum BridgeProductAnnotationProjectionQueryResult: Codable, Equatable, Sendable {
    case content(BridgeProductAnnotationProjectionContentDescriptor)
    case sourceStale(currentSourceGeneration: Int)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case currentSourceGeneration
        case descriptor
        case kind
    }

    private enum Kind: String, Codable {
        case content
        case sourceStale = "source_stale"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .content:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.descriptor.rawValue, CodingKeys.kind.rawValue],
                contract: "annotation projection content query result"
            )
            self = .content(
                try container.decode(
                    BridgeProductAnnotationProjectionContentDescriptor.self,
                    forKey: .descriptor
                )
            )
        case .sourceStale:
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [CodingKeys.currentSourceGeneration.rawValue, CodingKeys.kind.rawValue],
                contract: "annotation projection stale-source query result"
            )
            let currentSourceGeneration = try container.decode(
                Int.self,
                forKey: .currentSourceGeneration
            )
            try BridgeProductContractDecoding.validateNonnegative(
                currentSourceGeneration,
                name: "currentSourceGeneration",
                codingPath: decoder.codingPath
            )
            self = .sourceStale(currentSourceGeneration: currentSourceGeneration)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .content(let descriptor):
            try container.encode(Kind.content, forKey: .kind)
            try container.encode(descriptor, forKey: .descriptor)
        case .sourceStale(let currentSourceGeneration):
            try container.encode(Kind.sourceStale, forKey: .kind)
            try container.encode(currentSourceGeneration, forKey: .currentSourceGeneration)
        }
    }
}
