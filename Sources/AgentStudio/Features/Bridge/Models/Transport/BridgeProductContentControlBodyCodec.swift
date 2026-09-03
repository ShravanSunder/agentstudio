import Foundation

struct BridgeProductContentAcceptedControlBody: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contentRequestId
        case declaredByteLength
        case expectedSha256
        case identity
        case leaseId
        case maximumBytes
        case operationCorrelationId
        case paneSessionId
        case wireVersion
        case workerDerivationEpoch
        case workerInstanceId
    }

    let contentRequestId: String
    let declaredByteLength: Int?
    let expectedSha256: String?
    let identity: BridgeProductContentIdentity
    let leaseId: String
    let maximumBytes: Int
    let operationCorrelationID: String?
    let paneSessionId: String
    let wireVersion: Int
    let workerDerivationEpoch: Int
    let workerInstanceId: String

    init(header: BridgeProductContentAcceptedHeader) {
        self.contentRequestId = header.contentRequestId
        self.declaredByteLength = header.declaredByteLength
        self.expectedSha256 = header.expectedSha256
        self.identity = header.identity
        self.leaseId = header.leaseId
        self.maximumBytes = header.maximumBytes
        self.operationCorrelationID = header.frameIdentity.operationCorrelationID
        self.paneSessionId = header.paneSessionId
        self.wireVersion = header.wireVersion
        self.workerDerivationEpoch = header.workerDerivationEpoch
        self.workerInstanceId = header.workerInstanceId
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.accepted control body"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentRequestId = try container.decode(String.self, forKey: .contentRequestId)
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
        self.identity = try container.decode(BridgeProductContentIdentity.self, forKey: .identity)
        self.leaseId = try container.decode(String.self, forKey: .leaseId)
        self.maximumBytes = try container.decode(Int.self, forKey: .maximumBytes)
        self.operationCorrelationID = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .operationCorrelationId,
            from: container,
            codingPath: decoder.codingPath
        )
        self.paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        self.wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        self.workerDerivationEpoch = try container.decode(
            Int.self,
            forKey: .workerDerivationEpoch
        )
        self.workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try validate(codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentRequestId, forKey: .contentRequestId)
        try container.encode(declaredByteLength, forKey: .declaredByteLength)
        try container.encode(expectedSha256, forKey: .expectedSha256)
        try container.encode(identity, forKey: .identity)
        try container.encode(leaseId, forKey: .leaseId)
        try container.encode(maximumBytes, forKey: .maximumBytes)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerDerivationEpoch, forKey: .workerDerivationEpoch)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }

    private func validate(codingPath: [any CodingKey]) throws {
        try BridgeProductContractDecoding.validateIdentifier(contentRequestId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(leaseId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: codingPath)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: codingPath)
        try BridgeProductContractDecoding.validateNonnegative(
            workerDerivationEpoch,
            name: "workerDerivationEpoch",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: codingPath)
        if let declaredByteLength {
            try BridgeProductContractDecoding.validateNonnegative(
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
        }
        if let expectedSha256 {
            try BridgeProductContractDecoding.validateSHA256(expectedSha256, codingPath: codingPath)
        }
        if let operationCorrelationID {
            try BridgeProductContractDecoding.validateSHA256(operationCorrelationID, codingPath: codingPath)
        }
        try BridgeProductContractDecoding.validateNonnegative(
            maximumBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            maximumBytes,
            maximum: BridgeProductWireContract.maximumContentStreamBytes,
            name: "maximumBytes",
            codingPath: codingPath
        )
        guard identity.maximumBytes == maximumBytes else {
            throw BridgeProductContractDecoding.invalidValue(
                "Bridge product accepted content bounds are inconsistent",
                codingPath: codingPath
            )
        }
        switch identity {
        case .annotationOutput:
            guard declaredByteLength == maximumBytes else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Bridge product accepted annotation output maximum must equal its declared length",
                    codingPath: codingPath
                )
            }
        case .annotationProjection:
            guard declaredByteLength == nil, expectedSha256 == nil else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Bridge product accepted annotation projection exact facts must remain unknown",
                    codingPath: codingPath
                )
            }
        case .fileContent:
            guard declaredByteLength == maximumBytes else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Bridge product accepted File maximum must equal its declared length",
                    codingPath: codingPath
                )
            }
        case .reviewContent:
            guard declaredByteLength.map({ $0 <= maximumBytes }) ?? true else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Bridge product accepted Review declaration exceeds its range maximum",
                    codingPath: codingPath
                )
            }
        case .reviewComparisonTargets:
            guard declaredByteLength == nil, expectedSha256 == nil else {
                throw BridgeProductContractDecoding.invalidValue(
                    "Bridge product accepted comparison-target exact facts must remain unknown",
                    codingPath: codingPath
                )
            }
        }
    }
}

struct BridgeProductContentEndControlBody: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case endOfSource
        case observedByteLength
        case observedSha256
        case operationCorrelationId
    }

    let endOfSource: Bool
    let observedByteLength: Int
    let observedSha256: String
    let operationCorrelationID: String?

    init(header: BridgeProductContentEndHeader) {
        self.endOfSource = header.endOfSource
        self.observedByteLength = header.observedByteLength
        self.observedSha256 = header.observedSha256
        self.operationCorrelationID = header.operationCorrelationID
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.end control body"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.endOfSource = try container.decode(Bool.self, forKey: .endOfSource)
        self.observedByteLength = try container.decode(Int.self, forKey: .observedByteLength)
        self.observedSha256 = try container.decode(String.self, forKey: .observedSha256)
        self.operationCorrelationID = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .operationCorrelationId,
            from: container,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateNonnegative(
            observedByteLength,
            name: "observedByteLength",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateMaximum(
            observedByteLength,
            maximum: BridgeProductWireContract.maximumContentStreamBytes,
            name: "observedByteLength",
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateSHA256(
            observedSha256,
            codingPath: decoder.codingPath
        )
        if let operationCorrelationID {
            try BridgeProductContractDecoding.validateSHA256(operationCorrelationID, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endOfSource, forKey: .endOfSource)
        try container.encode(observedByteLength, forKey: .observedByteLength)
        try container.encode(observedSha256, forKey: .observedSha256)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
    }
}

struct BridgeProductContentErrorControlBody: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case code
        case retryable
        case safeMessage
        case operationCorrelationId
    }

    let code: BridgeProductRequestErrorCode
    let retryable: Bool
    let safeMessage: String?
    let operationCorrelationID: String?

    init(header: BridgeProductContentErrorHeader) {
        self.code = header.code
        self.retryable = header.retryable
        self.safeMessage = header.safeMessage
        self.operationCorrelationID = header.operationCorrelationID
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.error control body"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(BridgeProductRequestErrorCode.self, forKey: .code)
        self.retryable = try container.decode(Bool.self, forKey: .retryable)
        self.safeMessage = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .safeMessage,
            from: container,
            codingPath: decoder.codingPath
        )
        self.operationCorrelationID = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .operationCorrelationId,
            from: container,
            codingPath: decoder.codingPath
        )
        if let safeMessage {
            try BridgeProductContractDecoding.validateSafeMessage(
                safeMessage,
                codingPath: decoder.codingPath
            )
        }
        if let operationCorrelationID {
            try BridgeProductContractDecoding.validateSHA256(operationCorrelationID, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(retryable, forKey: .retryable)
        try container.encode(safeMessage, forKey: .safeMessage)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
    }
}

struct BridgeProductContentResetControlBody: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case reason
        case operationCorrelationId
    }

    let reason: BridgeProductResetReason
    let operationCorrelationID: String?

    init(header: BridgeProductContentResetHeader) {
        self.reason = header.reason
        self.operationCorrelationID = header.operationCorrelationID
    }

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "content.reset control body"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.reason = try container.decode(BridgeProductResetReason.self, forKey: .reason)
        self.operationCorrelationID = try BridgeProductContractDecoding.decodeRequiredNullable(
            String.self,
            forKey: .operationCorrelationId,
            from: container,
            codingPath: decoder.codingPath
        )
        if let operationCorrelationID {
            try BridgeProductContractDecoding.validateSHA256(operationCorrelationID, codingPath: decoder.codingPath)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason, forKey: .reason)
        try container.encode(operationCorrelationID, forKey: .operationCorrelationId)
    }
}

extension BridgeProductContentFrameIdentity {
    init(wireBody: BridgeProductContentAcceptedControlBody) {
        self.contentRequestId = wireBody.contentRequestId
        self.contentSequence = 0
        self.identity = wireBody.identity
        self.leaseId = wireBody.leaseId
        self.operationCorrelationID = wireBody.operationCorrelationID
        self.paneSessionId = wireBody.paneSessionId
        self.wireVersion = wireBody.wireVersion
        self.workerDerivationEpoch = wireBody.workerDerivationEpoch
        self.workerInstanceId = wireBody.workerInstanceId
    }
}

extension BridgeProductContentAcceptedHeader {
    init(wireBody: BridgeProductContentAcceptedControlBody) {
        self.frameIdentity = .init(wireBody: wireBody)
        self.declaredByteLength = wireBody.declaredByteLength
        self.expectedSha256 = wireBody.expectedSha256
        self.maximumBytes = wireBody.maximumBytes
    }
}

extension BridgeProductContentEndHeader {
    init(
        contentSequence: Int,
        wireBody: BridgeProductContentEndControlBody
    ) {
        self.contentSequence = contentSequence
        self.endOfSource = wireBody.endOfSource
        self.observedByteLength = wireBody.observedByteLength
        self.observedSha256 = wireBody.observedSha256
        self.operationCorrelationID = wireBody.operationCorrelationID
    }
}

extension BridgeProductContentErrorHeader {
    init(
        contentSequence: Int,
        wireBody: BridgeProductContentErrorControlBody
    ) {
        self.contentSequence = contentSequence
        self.code = wireBody.code
        self.retryable = wireBody.retryable
        self.safeMessage = wireBody.safeMessage
        self.operationCorrelationID = wireBody.operationCorrelationID
    }
}

extension BridgeProductContentResetHeader {
    init(
        contentSequence: Int,
        wireBody: BridgeProductContentResetControlBody
    ) {
        self.contentSequence = contentSequence
        self.reason = wireBody.reason
        self.operationCorrelationID = wireBody.operationCorrelationID
    }
}
