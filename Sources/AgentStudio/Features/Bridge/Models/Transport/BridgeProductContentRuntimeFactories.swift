import Foundation

extension BridgeProductContentFrameIdentity {
    init(admission: BridgeProductContentAdmission) {
        self.contentRequestId = admission.contentRequestId
        self.contentSequence = 0
        self.identity = admission.identity
        self.leaseId = admission.leaseId
        self.operationCorrelationID = admission.operationCorrelationID
        self.paneSessionId = admission.paneSessionId
        self.wireVersion = admission.wireVersion
        self.workerDerivationEpoch = admission.workerDerivationEpoch
        self.workerInstanceId = admission.workerInstanceId
    }
}

extension BridgeProductContentAcceptedHeader {
    init(admission: BridgeProductContentAdmission) {
        self.frameIdentity = .init(admission: admission)
        self.declaredByteLength = admission.declaredByteLength
        self.expectedSha256 = admission.expectedSha256
        self.maximumBytes = admission.maximumBytes
    }
}

extension BridgeProductContentDataHeader {
    init(contentSequence: Int, offsetBytes: Int, operationCorrelationID: String? = nil) throws {
        try validateRuntimeContentSequence(contentSequence)
        try BridgeProductContractDecoding.validateNonnegative(
            offsetBytes,
            name: "offsetBytes",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateMaximum(
            offsetBytes,
            maximum: BridgeProductWireContract.maximumContentStreamBytes,
            name: "offsetBytes",
            codingPath: []
        )
        self.contentSequence = contentSequence
        self.offsetBytes = offsetBytes
        self.operationCorrelationID = operationCorrelationID
    }
}

extension BridgeProductContentEndHeader {
    init(
        contentSequence: Int,
        endOfSource: Bool,
        observedByteLength: Int,
        observedSha256: String,
        operationCorrelationID: String? = nil
    ) throws {
        try validateRuntimeContentSequence(contentSequence)
        try BridgeProductContractDecoding.validateNonnegative(
            observedByteLength,
            name: "observedByteLength",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateMaximum(
            observedByteLength,
            maximum: BridgeProductWireContract.maximumContentStreamBytes,
            name: "observedByteLength",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateSHA256(observedSha256, codingPath: [])
        self.contentSequence = contentSequence
        self.endOfSource = endOfSource
        self.observedByteLength = observedByteLength
        self.observedSha256 = observedSha256
        self.operationCorrelationID = operationCorrelationID
    }
}

extension BridgeProductContentErrorHeader {
    init(
        contentSequence: Int,
        code: BridgeProductRequestErrorCode,
        retryable: Bool,
        safeMessage: String?,
        operationCorrelationID: String? = nil
    ) throws {
        try validateRuntimeContentSequence(contentSequence)
        if let safeMessage {
            try BridgeProductContractDecoding.validateSafeMessage(safeMessage, codingPath: [])
        }
        self.contentSequence = contentSequence
        self.code = code
        self.retryable = retryable
        self.safeMessage = safeMessage
        self.operationCorrelationID = operationCorrelationID
    }
}

extension BridgeProductContentResetHeader {
    init(
        contentSequence: Int,
        reason: BridgeProductResetReason,
        operationCorrelationID: String? = nil
    ) throws {
        try validateRuntimeContentSequence(contentSequence)
        self.contentSequence = contentSequence
        self.reason = reason
        self.operationCorrelationID = operationCorrelationID
    }
}

extension BridgeProductContentHeader {
    static func accepted(for admission: BridgeProductContentAdmission) -> Self {
        .accepted(.init(admission: admission))
    }

    static func data(
        contentSequence: Int,
        offsetBytes: Int,
        operationCorrelationID: String? = nil
    ) throws -> Self {
        .data(
            try .init(
                contentSequence: contentSequence,
                offsetBytes: offsetBytes,
                operationCorrelationID: operationCorrelationID
            )
        )
    }

    static func end(
        contentSequence: Int,
        endOfSource: Bool,
        observedByteLength: Int,
        observedSha256: String,
        operationCorrelationID: String? = nil
    ) throws -> Self {
        .end(
            try .init(
                contentSequence: contentSequence,
                endOfSource: endOfSource,
                observedByteLength: observedByteLength,
                observedSha256: observedSha256,
                operationCorrelationID: operationCorrelationID
            )
        )
    }

    static func error(
        contentSequence: Int,
        code: BridgeProductRequestErrorCode,
        retryable: Bool,
        safeMessage: String?,
        operationCorrelationID: String? = nil
    ) throws -> Self {
        .error(
            try .init(
                contentSequence: contentSequence,
                code: code,
                retryable: retryable,
                safeMessage: safeMessage,
                operationCorrelationID: operationCorrelationID
            )
        )
    }

    static func reset(
        contentSequence: Int,
        reason: BridgeProductResetReason,
        operationCorrelationID: String? = nil
    ) throws -> Self {
        .reset(
            try .init(
                contentSequence: contentSequence,
                reason: reason,
                operationCorrelationID: operationCorrelationID
            )
        )
    }
}

private func validateRuntimeContentSequence(_ contentSequence: Int) throws {
    try BridgeProductContractDecoding.validatePositive(
        contentSequence,
        name: "contentSequence",
        codingPath: []
    )
    try BridgeProductContractDecoding.validateMaximum(
        contentSequence,
        maximum: Int(UInt32.max),
        name: "contentSequence",
        codingPath: []
    )
}
