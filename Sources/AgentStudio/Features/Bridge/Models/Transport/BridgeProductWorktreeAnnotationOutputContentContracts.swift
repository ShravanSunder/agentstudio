import Foundation

struct BridgeProductAnnotationOutputInspectRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case attemptId
    }

    let attemptID: UUID

    init(attemptID: UUID) {
        self.attemptID = attemptID
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation output inspection request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.attemptID = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .attemptId),
            codingPath: decoder.codingPath
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(attemptID),
            forKey: .attemptId
        )
    }
}

struct BridgeProductAnnotationOutputContentDescriptor: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case attemptId
        case contentKind
        case contentType
        case declaredByteLength
        case descriptorId
        case encoding
        case expectedSha256
        case formatVersion
        case maximumBytes
        case outputKind
        case surface
    }

    let attemptID: UUID
    let contentType: String
    let declaredByteLength: Int
    let descriptorID: String
    let expectedSHA256: String
    let formatVersion: Int
    let maximumBytes: Int
    let outputKind: WorktreeAnnotationOutputKind
    let surface: BridgeProductSurface

    init(
        attemptID: UUID,
        contentType: String,
        declaredByteLength: Int,
        descriptorID: String,
        expectedSHA256: String,
        formatVersion: Int,
        maximumBytes: Int,
        outputKind: WorktreeAnnotationOutputKind,
        surface: BridgeProductSurface
    ) throws {
        self.attemptID = attemptID
        self.contentType = contentType
        self.declaredByteLength = declaredByteLength
        self.descriptorID = descriptorID
        self.expectedSHA256 = expectedSHA256
        self.formatVersion = formatVersion
        self.maximumBytes = maximumBytes
        self.outputKind = outputKind
        self.surface = surface
        try validate(codingPath: [])
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation output content descriptor"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.attemptID = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .attemptId),
            codingPath: decoder.codingPath
        )
        guard try container.decode(String.self, forKey: .contentKind) == "annotation.output" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid worktree annotation output content kind",
                codingPath: decoder.codingPath
            )
        }
        self.contentType = try container.decode(String.self, forKey: .contentType)
        self.declaredByteLength = try container.decode(Int.self, forKey: .declaredByteLength)
        self.descriptorID = try container.decode(String.self, forKey: .descriptorId)
        guard try container.decode(String.self, forKey: .encoding) == "utf-8" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Worktree annotation output content must be UTF-8",
                codingPath: decoder.codingPath
            )
        }
        self.expectedSHA256 = try container.decode(String.self, forKey: .expectedSha256)
        self.formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        self.outputKind = try container.decode(WorktreeAnnotationOutputKind.self, forKey: .outputKind)
        self.surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(attemptID),
            forKey: .attemptId
        )
        try container.encode("annotation.output", forKey: .contentKind)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(declaredByteLength, forKey: .declaredByteLength)
        try container.encode(descriptorID, forKey: .descriptorId)
        try container.encode("utf-8", forKey: .encoding)
        try container.encode(expectedSHA256, forKey: .expectedSha256)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(outputKind, forKey: .outputKind)
        try container.encode(surface, forKey: .surface)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validatePositive(
            declaredByteLength,
            name: "declaredByteLength",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            declaredByteLength,
            maximum: BridgeProductWireContract.maximumContentStreamBytes,
            name: "declaredByteLength",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(descriptorID, codingPath: codingPath)
        try BridgeProductContractDecoding.validateSHA256(expectedSHA256, codingPath: codingPath)
        guard formatVersion == WorktreeAnnotationBatchSnapshot.currentFormatVersion else {
            throw BridgeProductContractDecoding.invalidValue(
                "Unsupported worktree annotation output format version",
                codingPath: codingPath
            )
        }
        guard maximumBytes == declaredByteLength else {
            throw BridgeProductContractDecoding.invalidValue(
                "Worktree annotation output maximum must equal its declared length",
                codingPath: codingPath
            )
        }
        let expectedContentType =
            switch outputKind {
            case .clipboardMarkdown: "text/markdown; charset=utf-8"
            case .jsonFile: "application/json; charset=utf-8"
            }
        guard contentType == expectedContentType else {
            throw BridgeProductContractDecoding.invalidValue(
                "Worktree annotation output content type does not match its kind",
                codingPath: codingPath
            )
        }
    }
}

struct BridgeProductAnnotationOutputContentIdentity: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case attemptId
        case contentKind
        case descriptorId
        case formatVersion
        case maximumBytes
        case outputKind
        case surface
    }

    let attemptID: UUID
    let descriptorID: String
    let formatVersion: Int
    let maximumBytes: Int
    let outputKind: WorktreeAnnotationOutputKind
    let surface: BridgeProductSurface

    init(descriptor: BridgeProductAnnotationOutputContentDescriptor) {
        self.attemptID = descriptor.attemptID
        self.descriptorID = descriptor.descriptorID
        self.formatVersion = descriptor.formatVersion
        self.maximumBytes = descriptor.maximumBytes
        self.outputKind = descriptor.outputKind
        self.surface = descriptor.surface
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation output content identity"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.attemptID = try BridgeProductReviewPublicationIdContract.decode(
            container.decode(String.self, forKey: .attemptId),
            codingPath: decoder.codingPath
        )
        guard try container.decode(String.self, forKey: .contentKind) == "annotation.output" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid worktree annotation output content identity kind",
                codingPath: decoder.codingPath
            )
        }
        self.descriptorID = try container.decode(String.self, forKey: .descriptorId)
        self.formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        self.outputKind = try container.decode(WorktreeAnnotationOutputKind.self, forKey: .outputKind)
        self.surface = try container.decode(BridgeProductSurface.self, forKey: .surface)
        try BridgeProductContractDecoding.validateIdentifier(descriptorID, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validatePositive(
            maximumBytes,
            name: "maximumBytes",
            codingPath: decoder.codingPath
        )
        guard formatVersion == WorktreeAnnotationBatchSnapshot.currentFormatVersion else {
            throw BridgeProductContractDecoding.invalidValue(
                "Unsupported worktree annotation output format version",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            BridgeProductReviewPublicationIdContract.encode(attemptID),
            forKey: .attemptId
        )
        try container.encode("annotation.output", forKey: .contentKind)
        try container.encode(descriptorID, forKey: .descriptorId)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(outputKind, forKey: .outputKind)
        try container.encode(surface, forKey: .surface)
    }
}

struct BridgeProductAnnotationOutputContentRequest: Codable, Equatable, Sendable {
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
    let descriptor: BridgeProductAnnotationOutputContentDescriptor
    let leaseID: String
    let operationCorrelationID: String?
    let paneSessionID: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceID: String

    var admission: BridgeProductContentAdmission {
        .init(
            contentKind: .annotationOutput,
            contentRequestId: contentRequestID,
            declaredByteLength: descriptor.declaredByteLength,
            expectedSha256: descriptor.expectedSHA256,
            identity: .annotationOutput(.init(descriptor: descriptor)),
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
            contract: "worktree annotation output content request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .contentKind) == "annotation.output",
            try container.decode(String.self, forKey: .kind) == "content.open"
        else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid worktree annotation output content request kind",
                codingPath: decoder.codingPath
            )
        }
        self.contentRequestID = try container.decode(String.self, forKey: .contentRequestId)
        self.descriptor = try container.decode(
            BridgeProductAnnotationOutputContentDescriptor.self,
            forKey: .descriptor
        )
        self.leaseID = try container.decode(String.self, forKey: .leaseId)
        self.operationCorrelationID = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .operationCorrelationId,
            from: container,
            codingPath: decoder.codingPath
        )
        self.paneSessionID = try container.decode(String.self, forKey: .paneSessionId)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerDerivationEpoch = try container.decode(Int.self, forKey: .workerDerivationEpoch)
        self.workerInstanceID = try container.decode(String.self, forKey: .workerInstanceId)
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
        try container.encode("annotation.output", forKey: .contentKind)
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

struct BridgeProductWorktreeAnnotationOutputInspectResult: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case descriptor
    }

    let descriptor: BridgeProductAnnotationOutputContentDescriptor

    init(descriptor: BridgeProductAnnotationOutputContentDescriptor) {
        self.descriptor = descriptor
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "worktree annotation output inspection result"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.descriptor = try container.decode(
            BridgeProductAnnotationOutputContentDescriptor.self,
            forKey: .descriptor
        )
    }
}
