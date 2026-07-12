import Foundation

extension BridgeProductContentFrameIdentity {
    init(admission: BridgeProductContentAdmission) {
        self.contentRequestId = admission.contentRequestId
        self.contentSequence = 0
        self.identity = admission.identity
        self.leaseId = admission.leaseId
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
    init(contentSequence: Int, offsetBytes: Int) throws {
        try validateRuntimeContentSequence(contentSequence)
        try BridgeProductContractDecoding.validateNonnegative(
            offsetBytes,
            name: "offsetBytes",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateMaximum(
            offsetBytes,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "offsetBytes",
            codingPath: []
        )
        self.contentSequence = contentSequence
        self.offsetBytes = offsetBytes
    }
}

extension BridgeProductContentEndHeader {
    init(
        contentSequence: Int,
        endOfSource: Bool,
        observedByteLength: Int,
        observedSha256: String
    ) throws {
        try validateRuntimeContentSequence(contentSequence)
        try BridgeProductContractDecoding.validateNonnegative(
            observedByteLength,
            name: "observedByteLength",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateMaximum(
            observedByteLength,
            maximum: BridgeProductWireContract.maximumContentBytes,
            name: "observedByteLength",
            codingPath: []
        )
        try BridgeProductContractDecoding.validateSHA256(observedSha256, codingPath: [])
        self.contentSequence = contentSequence
        self.endOfSource = endOfSource
        self.observedByteLength = observedByteLength
        self.observedSha256 = observedSha256
    }
}

extension BridgeProductContentErrorHeader {
    init(
        contentSequence: Int,
        code: BridgeProductRequestErrorCode,
        retryable: Bool,
        safeMessage: String?
    ) throws {
        try validateRuntimeContentSequence(contentSequence)
        if let safeMessage {
            try BridgeProductContractDecoding.validateSafeMessage(safeMessage, codingPath: [])
        }
        self.contentSequence = contentSequence
        self.code = code
        self.retryable = retryable
        self.safeMessage = safeMessage
    }
}

extension BridgeProductContentResetHeader {
    init(contentSequence: Int, reason: BridgeProductResetReason) throws {
        try validateRuntimeContentSequence(contentSequence)
        self.contentSequence = contentSequence
        self.reason = reason
    }
}

extension BridgeProductContentHeader {
    static func accepted(for admission: BridgeProductContentAdmission) -> Self {
        .accepted(.init(admission: admission))
    }

    static func data(contentSequence: Int, offsetBytes: Int) throws -> Self {
        .data(
            try .init(
                contentSequence: contentSequence,
                offsetBytes: offsetBytes
            )
        )
    }

    static func end(
        contentSequence: Int,
        endOfSource: Bool,
        observedByteLength: Int,
        observedSha256: String
    ) throws -> Self {
        .end(
            try .init(
                contentSequence: contentSequence,
                endOfSource: endOfSource,
                observedByteLength: observedByteLength,
                observedSha256: observedSha256
            )
        )
    }

    static func error(
        contentSequence: Int,
        code: BridgeProductRequestErrorCode,
        retryable: Bool,
        safeMessage: String?
    ) throws -> Self {
        .error(
            try .init(
                contentSequence: contentSequence,
                code: code,
                retryable: retryable,
                safeMessage: safeMessage
            )
        )
    }

    static func reset(
        contentSequence: Int,
        reason: BridgeProductResetReason
    ) throws -> Self {
        .reset(
            try .init(
                contentSequence: contentSequence,
                reason: reason
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
