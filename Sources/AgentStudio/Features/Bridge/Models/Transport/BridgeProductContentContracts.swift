import Foundation

enum BridgeProductContentKind: String, Codable, Equatable, Sendable {
    case fileContent = "file.content"
    case reviewContent = "review.content"

    var surface: BridgeProductSurface {
        switch self {
        case .fileContent: .file
        case .reviewContent: .review
        }
    }
}

struct BridgeProductFileContentWindow: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case maximumBytes
        case maximumLines
        case startByte
    }

    let maximumBytes: Int
    let maximumLines: Int

    init(maximumBytes: Int, maximumLines: Int) throws {
        self.maximumBytes = maximumBytes
        self.maximumLines = maximumLines
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file content window"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "prefix" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product file content window must be a prefix",
                codingPath: decoder.codingPath
            )
        }
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        self.maximumLines = try container.decode(Int.self, forKey: .maximumLines)
        guard try container.decode(Int.self, forKey: .startByte) == 0 else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product file content prefix must start at byte zero",
                codingPath: decoder.codingPath
            )
        }
        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validatePositive(
            maximumBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            maximumBytes,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validatePositive(
            maximumLines,
            name: "maximumLines",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            maximumLines,
            maximum: BridgeProductWireContract.maximumContentLines,
            name: "maximumLines",
            codingPath: codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("prefix", forKey: .kind)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(maximumLines, forKey: .maximumLines)
        try container.encode(0, forKey: .startByte)
    }
}

struct BridgeProductFileContentDescriptor: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentKind
        case declaredByteLength
        case descriptorId
        case encoding
        case expectedSha256
        case fileId
        case maximumBytes
        case source
        case window
    }

    let declaredByteLength: Int
    let descriptorId: String
    let expectedSha256: String
    let fileId: String
    let maximumBytes: Int
    let source: BridgeProductFileSourceIdentity
    let window: BridgeProductFileContentWindow

    init(
        declaredByteLength: Int,
        descriptorId: String,
        expectedSha256: String,
        fileId: String,
        maximumBytes: Int,
        source: BridgeProductFileSourceIdentity,
        window: BridgeProductFileContentWindow
    ) throws {
        self.declaredByteLength = declaredByteLength
        self.descriptorId = descriptorId
        self.expectedSha256 = expectedSha256
        self.fileId = fileId
        self.maximumBytes = maximumBytes
        self.source = source
        self.window = window
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file content descriptor"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "file.content" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product file content kind",
                codingPath: decoder.codingPath
            )
        }
        self.declaredByteLength = try container.decode(Int.self, forKey: .declaredByteLength)
        self.descriptorId = try container.decode(String.self, forKey: .descriptorId)
        guard try container.decode(String.self, forKey: .encoding) == "utf-8" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product file content encoding must be utf-8",
                codingPath: decoder.codingPath
            )
        }
        self.expectedSha256 = try container.decode(String.self, forKey: .expectedSha256)
        self.fileId = try container.decode(String.self, forKey: .fileId)
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
        self.window = try container.decode(BridgeProductFileContentWindow.self, forKey: .window)

        try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
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
        try BridgeProductContractDecoding.validateIdentifier(descriptorId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateSHA256(expectedSha256, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(fileId, codingPath: codingPath)
        try BridgeProductContractDecoding.validatePositive(
            maximumBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            maximumBytes,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        guard declaredByteLength <= maximumBytes else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product declared content length exceeds its maximum",
                codingPath: codingPath
            )
        }
        guard window.maximumBytes == maximumBytes else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product content window must equal its request maximum",
                codingPath: codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.content", forKey: .contentKind)
        try container.encode(declaredByteLength, forKey: .declaredByteLength)
        try container.encode(descriptorId, forKey: .descriptorId)
        try container.encode("utf-8", forKey: .encoding)
        try container.encode(expectedSha256, forKey: .expectedSha256)
        try container.encode(fileId, forKey: .fileId)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(source, forKey: .source)
        try container.encode(window, forKey: .window)
    }
}

struct BridgeProductFileContentIdentity: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentKind
        case descriptorId
        case fileId
        case source
        case window
    }

    let descriptorId: String
    let fileId: String
    let source: BridgeProductFileSourceIdentity
    let window: BridgeProductFileContentWindow

    init(descriptor: BridgeProductFileContentDescriptor) {
        self.descriptorId = descriptor.descriptorId
        self.fileId = descriptor.fileId
        self.source = descriptor.source
        self.window = descriptor.window
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "file content identity"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "file.content" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product file content identity kind",
                codingPath: decoder.codingPath
            )
        }
        self.descriptorId = try container.decode(String.self, forKey: .descriptorId)
        self.fileId = try container.decode(String.self, forKey: .fileId)
        self.source = try container.decode(BridgeProductFileSourceIdentity.self, forKey: .source)
        self.window = try container.decode(BridgeProductFileContentWindow.self, forKey: .window)
        try BridgeProductContractDecoding.validateIdentifier(descriptorId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(fileId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("file.content", forKey: .contentKind)
        try container.encode(descriptorId, forKey: .descriptorId)
        try container.encode(fileId, forKey: .fileId)
        try container.encode(source, forKey: .source)
        try container.encode(window, forKey: .window)
    }
}

enum BridgeProductContentIdentity: Codable, Equatable, Sendable {
    case fileContent(BridgeProductFileContentIdentity)
    case reviewContent(BridgeProductReviewContentIdentity)

    private enum CodingKeys: String, CodingKey {
        case contentKind
    }

    var contentKind: BridgeProductContentKind {
        switch self {
        case .fileContent: .fileContent
        case .reviewContent: .reviewContent
        }
    }

    var surface: BridgeProductSurface { contentKind.surface }

    var descriptorId: String {
        switch self {
        case .fileContent(let identity): identity.descriptorId
        case .reviewContent(let identity): identity.descriptorId
        }
    }

    var maximumBytes: Int {
        switch self {
        case .fileContent(let identity): identity.window.maximumBytes
        case .reviewContent(let identity): identity.window.maximumBytes
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BridgeProductContentKind.self, forKey: .contentKind) {
        case .fileContent:
            self = .fileContent(try BridgeProductFileContentIdentity(from: decoder))
        case .reviewContent:
            self = .reviewContent(try BridgeProductReviewContentIdentity(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .fileContent(let identity):
            try identity.encode(to: encoder)
        case .reviewContent(let identity):
            try identity.encode(to: encoder)
        }
    }
}

struct BridgeProductContentAdmission: Equatable, Sendable {
    let contentKind: BridgeProductContentKind
    let contentRequestId: String
    let declaredByteLength: Int?
    let expectedSha256: String?
    let identity: BridgeProductContentIdentity
    let leaseId: String
    let maximumBytes: Int
    let paneSessionId: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceId: String
}

struct BridgeProductFileContentRequest: Codable, Equatable, Sendable {
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
    let descriptor: BridgeProductFileContentDescriptor
    let leaseId: String
    let paneSessionId: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceId: String

    var admission: BridgeProductContentAdmission {
        .init(
            contentKind: .fileContent,
            contentRequestId: contentRequestId,
            declaredByteLength: descriptor.declaredByteLength,
            expectedSha256: descriptor.expectedSha256,
            identity: .fileContent(.init(descriptor: descriptor)),
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
            contract: "file content request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "file.content" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product content request kind",
                codingPath: decoder.codingPath
            )
        }
        self.contentRequestId = try container.decode(String.self, forKey: .contentRequestId)
        self.descriptor = try container.decode(BridgeProductFileContentDescriptor.self, forKey: .descriptor)
        guard try container.decode(String.self, forKey: .kind) == "content.open" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid Bridge product content request operation",
                codingPath: decoder.codingPath
            )
        }
        self.leaseId = try container.decode(String.self, forKey: .leaseId)
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerDerivationEpoch = try container.decode(
            Int.self,
            forKey: .workerDerivationEpoch
        )
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
        try container.encode("file.content", forKey: .contentKind)
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

enum BridgeProductContentRequest: Codable, Equatable, Sendable {
    case fileContent(BridgeProductFileContentRequest)
    case reviewContent(BridgeProductReviewContentRequest)

    private enum CodingKeys: String, CodingKey {
        case contentKind
    }

    var kind: String { "content.open" }

    var surface: BridgeProductSurface {
        switch self {
        case .fileContent: .file
        case .reviewContent: .review
        }
    }

    var admission: BridgeProductContentAdmission {
        switch self {
        case .fileContent(let request): request.admission
        case .reviewContent(let request): request.admission
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BridgeProductContentKind.self, forKey: .contentKind) {
        case .fileContent:
            self = .fileContent(try BridgeProductFileContentRequest(from: decoder))
        case .reviewContent:
            self = .reviewContent(try BridgeProductReviewContentRequest(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .fileContent(let request):
            try request.encode(to: encoder)
        case .reviewContent(let request):
            try request.encode(to: encoder)
        }
    }
}
