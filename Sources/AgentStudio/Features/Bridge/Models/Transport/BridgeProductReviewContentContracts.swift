import Foundation

enum BridgeProductReviewContentDigest: Codable, Equatable, Sendable {
    case authoritativeSHA256(String)
    case provisional(algorithm: String, value: String)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case algorithm
        case authority
        case value
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review content digest"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let authority = try container.decode(String.self, forKey: .authority)
        let algorithm = try container.decode(String.self, forKey: .algorithm)
        let value = try container.decode(String.self, forKey: .value)
        switch authority {
        case "authoritative":
            guard algorithm == "sha256" else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Authoritative Review content digest must use SHA-256",
                    codingPath: decoder.codingPath
                )
            }
            try BridgeProductContractDecoding.validateSHA256(value, codingPath: decoder.codingPath)
            self = .authoritativeSHA256(value)
        case "provisional":
            try BridgeProductContractDecoding.validateOpaqueReference(algorithm, codingPath: decoder.codingPath)
            try BridgeProductContractDecoding.validateOpaqueReference(value, codingPath: decoder.codingPath)
            self = .provisional(algorithm: algorithm, value: value)
        default:
            throw BridgeProductContractDecoding.invalidValue(
                "Unknown Review content digest authority",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .authoritativeSHA256(let value):
            try container.encode("sha256", forKey: .algorithm)
            try container.encode("authoritative", forKey: .authority)
            try container.encode(value, forKey: .value)
        case .provisional(let algorithm, let value):
            try container.encode(algorithm, forKey: .algorithm)
            try container.encode("provisional", forKey: .authority)
            try container.encode(value, forKey: .value)
        }
    }

    fileprivate func validate(codingPath: [any CodingKey]) throws {
        switch self {
        case .authoritativeSHA256(let value):
            try BridgeProductContractDecoding.validateSHA256(value, codingPath: codingPath)
        case .provisional(let algorithm, let value):
            try BridgeProductContractDecoding.validateOpaqueReference(algorithm, codingPath: codingPath)
            try BridgeProductContractDecoding.validateOpaqueReference(value, codingPath: codingPath)
        }
    }
}

struct BridgeProductReviewContentSourceDescriptor: Codable, Equatable, Sendable {
    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case contentDigest
        case contentKind
        case descriptorId
        case encoding
        case endpointId
        case handleId
        case isBinary
        case itemId
        case language
        case mimeType
        case packageId
        case reviewGeneration
        case role
        case sourceIdentity
        case wholeByteLength
    }

    let contentDigest: BridgeProductReviewContentDigest
    let descriptorId: String
    let encoding: String?
    let endpointId: String
    let handleId: String
    let isBinary: Bool
    let itemId: String
    let language: String?
    let mimeType: String
    let packageId: String
    let reviewGeneration: Int
    let role: BridgeContentHandle.Role
    let sourceIdentity: String
    let wholeByteLength: Int?

    init(
        contentDigest: BridgeProductReviewContentDigest,
        descriptorId: String,
        encoding: String?,
        endpointId: String,
        handleId: String,
        isBinary: Bool,
        itemId: String,
        language: String?,
        mimeType: String,
        packageId: String,
        reviewGeneration: Int,
        role: BridgeContentHandle.Role,
        sourceIdentity: String,
        wholeByteLength: Int?
    ) throws {
        self.contentDigest = contentDigest
        self.descriptorId = descriptorId
        self.encoding = encoding
        self.endpointId = endpointId
        self.handleId = handleId
        self.isBinary = isBinary
        self.itemId = itemId
        self.language = language
        self.mimeType = mimeType
        self.packageId = packageId
        self.reviewGeneration = reviewGeneration
        self.role = role
        self.sourceIdentity = sourceIdentity
        self.wholeByteLength = wholeByteLength
        try contentDigest.validate(codingPath: [])
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try self.init(from: decoder, rejectingUnknownKeys: true)
    }

    fileprivate init(from decoder: Decoder, rejectingUnknownKeys: Bool) throws {
        if rejectingUnknownKeys {
            try BridgeProductContractDecoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
                contract: "Review content source descriptor"
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "review.content" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review content source kind",
                codingPath: decoder.codingPath
            )
        }
        self.contentDigest = try container.decode(BridgeProductReviewContentDigest.self, forKey: .contentDigest)
        self.descriptorId = try container.decode(String.self, forKey: .descriptorId)
        self.encoding = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .encoding,
            from: container,
            codingPath: decoder.codingPath
        )
        self.endpointId = try container.decode(String.self, forKey: .endpointId)
        self.handleId = try container.decode(String.self, forKey: .handleId)
        self.isBinary = try container.decode(Bool.self, forKey: .isBinary)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        self.language = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .language,
            from: container,
            codingPath: decoder.codingPath
        )
        self.mimeType = try container.decode(String.self, forKey: .mimeType)
        self.packageId = try container.decode(String.self, forKey: .packageId)
        self.reviewGeneration = try container.decode(Int.self, forKey: .reviewGeneration)
        self.role = try container.decode(BridgeContentHandle.Role.self, forKey: .role)
        self.sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        self.wholeByteLength = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .wholeByteLength,
            from: container,
            codingPath: decoder.codingPath
        )
        try validate(codingPath: decoder.codingPath)
    }

    fileprivate func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateIdentifier(descriptorId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(endpointId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(handleId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: codingPath)
        if let language {
            try BridgeProductContractDecoding.validateOpaqueReference(language, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateOpaqueReference(mimeType, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            reviewGeneration,
            name: "reviewGeneration",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: codingPath)
        if let wholeByteLength {
            try BridgeProductContractDecoding.validateNonnegative(
                wholeByteLength,
                name: "wholeByteLength",
                codingPath: codingPath
            )
        }
        guard isBinary ? encoding == nil : encoding == "utf-8" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review content encoding must be UTF-8 exactly for text sources",
                codingPath: codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentDigest, forKey: .contentDigest)
        try container.encode("review.content", forKey: .contentKind)
        try container.encode(descriptorId, forKey: .descriptorId)
        try container.encode(encoding, forKey: .encoding)
        try container.encode(endpointId, forKey: .endpointId)
        try container.encode(handleId, forKey: .handleId)
        try container.encode(isBinary, forKey: .isBinary)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(language, forKey: .language)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(packageId, forKey: .packageId)
        try container.encode(reviewGeneration, forKey: .reviewGeneration)
        try container.encode(role, forKey: .role)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
        try container.encode(wholeByteLength, forKey: .wholeByteLength)
    }
}

struct BridgeProductReviewContentWindow: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case maximumBytes
        case startByte
    }

    static let maximumRangeBytes = 512 * 1024

    let maximumBytes: Int
    let startByte: Int

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review content window"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "byteRange" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review content window must be a byte range",
                codingPath: decoder.codingPath
            )
        }
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        self.startByte = try container.decode(Int.self, forKey: .startByte)
        try BridgeProductContractDecoding.validatePositive(
            maximumBytes,
            name: "maximumBytes",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            maximumBytes,
            maximum: Self.maximumRangeBytes,
            name: "maximumBytes",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            startByte,
            name: "startByte",
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("byteRange", forKey: .kind)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(startByte, forKey: .startByte)
    }
}

struct BridgeProductReviewContentDescriptor: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case declaredByteLength
        case expectedSha256
        case maximumBytes
        case window
    }

    let source: BridgeProductReviewContentSourceDescriptor
    let declaredByteLength: Int?
    let expectedSha256: String?
    let maximumBytes: Int
    let window: BridgeProductReviewContentWindow

    var contentDigest: BridgeProductReviewContentDigest { source.contentDigest }
    var descriptorId: String { source.descriptorId }
    var endpointId: String { source.endpointId }
    var handleId: String { source.handleId }
    var itemId: String { source.itemId }
    var packageId: String { source.packageId }
    var reviewGeneration: Int { source.reviewGeneration }
    var role: BridgeContentHandle.Role { source.role }
    var sourceIdentity: String { source.sourceIdentity }
    var wholeByteLength: Int? { source.wholeByteLength }

    init(from decoder: Decoder) throws {
        let allowedKeys = Set(BridgeProductReviewContentSourceDescriptor.CodingKeys.allCases.map(\.rawValue))
            .union(CodingKeys.allCases.map(\.rawValue))
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: allowedKeys,
            contract: "Review content descriptor"
        )
        self.source = try BridgeProductReviewContentSourceDescriptor(
            from: decoder,
            rejectingUnknownKeys: false
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.declaredByteLength = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .declaredByteLength,
            from: container,
            codingPath: decoder.codingPath
        )
        self.expectedSha256 = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .expectedSha256,
            from: container,
            codingPath: decoder.codingPath
        )
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        self.window = try container.decode(BridgeProductReviewContentWindow.self, forKey: .window)
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        guard source.isBinary == false, source.encoding == "utf-8" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review range descriptors require UTF-8 text content",
                codingPath: codingPath
            )
        }
        if let declaredByteLength {
            try BridgeProductContractDecoding.validateNonnegative(
                declaredByteLength,
                name: "declaredByteLength",
                codingPath: codingPath
            )
            try BridgeProductContractDecoding.validateMaximum(
                declaredByteLength,
                maximum: BridgeProductWireContract.maximumContentBytes,
                name: "declaredByteLength",
                codingPath: codingPath
            )
            guard declaredByteLength <= maximumBytes else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Review declared range length exceeds its maximum",
                    codingPath: codingPath
                )
            }
        }
        if let expectedSha256 {
            try BridgeProductContractDecoding.validateSHA256(expectedSha256, codingPath: codingPath)
        }
        guard maximumBytes == window.maximumBytes else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review content range must equal its request maximum",
                codingPath: codingPath
            )
        }
        guard let wholeByteLength else { return }
        guard window.startByte <= wholeByteLength else {
            throw BridgeProductContractDecoding.invalidValue(
                "Review range starts beyond the whole content length",
                codingPath: codingPath
            )
        }
        if let declaredByteLength {
            let (endByte, overflowed) = window.startByte.addingReportingOverflow(declaredByteLength)
            guard !overflowed, endByte <= wholeByteLength else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Review declared range exceeds the whole content length",
                    codingPath: codingPath
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try source.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(declaredByteLength, forKey: .declaredByteLength)
        try container.encode(expectedSha256, forKey: .expectedSha256)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(window, forKey: .window)
    }
}

struct BridgeProductReviewContentIdentity: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentDigest
        case contentKind
        case descriptorId
        case endpointId
        case handleId
        case itemId
        case packageId
        case reviewGeneration
        case role
        case sourceIdentity
        case wholeByteLength
        case window
    }

    let contentDigest: BridgeProductReviewContentDigest
    let descriptorId: String
    let endpointId: String
    let handleId: String
    let itemId: String
    let packageId: String
    let reviewGeneration: Int
    let role: BridgeContentHandle.Role
    let sourceIdentity: String
    let wholeByteLength: Int?
    let window: BridgeProductReviewContentWindow

    init(descriptor: BridgeProductReviewContentDescriptor) {
        self.contentDigest = descriptor.contentDigest
        self.descriptorId = descriptor.descriptorId
        self.endpointId = descriptor.endpointId
        self.handleId = descriptor.handleId
        self.itemId = descriptor.itemId
        self.packageId = descriptor.packageId
        self.reviewGeneration = descriptor.reviewGeneration
        self.role = descriptor.role
        self.sourceIdentity = descriptor.sourceIdentity
        self.wholeByteLength = descriptor.wholeByteLength
        self.window = descriptor.window
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review content identity"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "review.content" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review content identity kind",
                codingPath: decoder.codingPath
            )
        }
        self.contentDigest = try container.decode(BridgeProductReviewContentDigest.self, forKey: .contentDigest)
        self.descriptorId = try container.decode(String.self, forKey: .descriptorId)
        self.endpointId = try container.decode(String.self, forKey: .endpointId)
        self.handleId = try container.decode(String.self, forKey: .handleId)
        self.itemId = try container.decode(String.self, forKey: .itemId)
        self.packageId = try container.decode(String.self, forKey: .packageId)
        self.reviewGeneration = try container.decode(Int.self, forKey: .reviewGeneration)
        self.role = try container.decode(BridgeContentHandle.Role.self, forKey: .role)
        self.sourceIdentity = try container.decode(String.self, forKey: .sourceIdentity)
        self.wholeByteLength = try BridgeProductContractDecoding.decodeRequiredNullable(
            Int.self,
            forKey: .wholeByteLength,
            from: container,
            codingPath: decoder.codingPath
        )
        self.window = try container.decode(BridgeProductReviewContentWindow.self, forKey: .window)
        try BridgeProductContractDecoding.validateIdentifier(descriptorId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(endpointId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(handleId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(itemId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(packageId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            reviewGeneration,
            name: "reviewGeneration",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(sourceIdentity, codingPath: decoder.codingPath)
        if let wholeByteLength {
            try BridgeProductContractDecoding.validateNonnegative(
                wholeByteLength,
                name: "wholeByteLength",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentDigest, forKey: .contentDigest)
        try container.encode("review.content", forKey: .contentKind)
        try container.encode(descriptorId, forKey: .descriptorId)
        try container.encode(endpointId, forKey: .endpointId)
        try container.encode(handleId, forKey: .handleId)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(packageId, forKey: .packageId)
        try container.encode(reviewGeneration, forKey: .reviewGeneration)
        try container.encode(role, forKey: .role)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
        try container.encode(wholeByteLength, forKey: .wholeByteLength)
        try container.encode(window, forKey: .window)
    }
}

struct BridgeProductReviewContentRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentKind
        case contentRequestId
        case descriptor
        case kind
        case leaseId
        case paneSessionId
        case wireVersion
        case workerDerivationEpoch
        case workerInstanceId
    }

    let contentRequestId: String
    let descriptor: BridgeProductReviewContentDescriptor
    let leaseId: String
    let paneSessionId: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceId: String

    var admission: BridgeProductContentAdmission {
        .init(
            contentKind: .reviewContent,
            contentRequestId: contentRequestId,
            declaredByteLength: descriptor.declaredByteLength,
            expectedSha256: descriptor.expectedSha256,
            identity: .reviewContent(.init(descriptor: descriptor)),
            leaseId: leaseId,
            maximumBytes: descriptor.maximumBytes,
            paneSessionId: paneSessionId,
            wireVersion: wireVersion,
            workerDerivationEpoch: workerDerivationEpoch,
            workerInstanceId: workerInstanceId
        )
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Review content request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "review.content",
            try container.decode(String.self, forKey: .kind) == "content.open"
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Review content request kind",
                codingPath: decoder.codingPath
            )
        }
        self.contentRequestId = try container.decode(String.self, forKey: .contentRequestId)
        self.descriptor = try container.decode(BridgeProductReviewContentDescriptor.self, forKey: .descriptor)
        self.leaseId = try container.decode(String.self, forKey: .leaseId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerDerivationEpoch = try container.decode(Int.self, forKey: .workerDerivationEpoch)
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(contentRequestId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(leaseId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("review.content", forKey: .contentKind)
        try container.encode(contentRequestId, forKey: .contentRequestId)
        try container.encode(descriptor, forKey: .descriptor)
        try container.encode("content.open", forKey: .kind)
        try container.encode(leaseId, forKey: .leaseId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerDerivationEpoch, forKey: .workerDerivationEpoch)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}
