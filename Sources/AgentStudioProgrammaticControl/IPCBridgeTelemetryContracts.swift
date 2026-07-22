import Foundation

public enum IPCBridgeTelemetryUnavailableReason: String, Codable, Equatable, Sendable {
    case disabled
    case failed
}

public enum IPCBridgeTelemetryResultKind: String, Codable, Equatable, Sendable {
    case report
    case unavailable
}

public enum IPCBridgeTelemetryDrainSettlementDisposition: String, Codable, Equatable, Sendable {
    case closed
    case reopened
}

public enum IPCBridgeTelemetryWorkerState: String, Codable, Equatable, Sendable {
    case active, closed, draining, failed
}

public enum IPCBridgeTelemetryProducerId: String, Codable, Equatable, Sendable {
    case main, comm
}

public enum IPCBridgeTelemetryLossOrigin: String, Codable, Equatable, Sendable {
    case producer, worker
}

public enum IPCBridgeTelemetryLossReason: String, Codable, Equatable, Sendable {
    case creditExhausted = "credit_exhausted"
    case encodedByteCap = "encoded_byte_cap"
    case queueSaturated = "queue_saturated"
    case outboxSaturated = "outbox_saturated"
    case producerFailure = "producer_failure"
    case transportRetryExhausted = "transport_retry_exhausted"
}

public struct IPCBridgeTelemetryProducerDiagnostics: Codable, Equatable, Sendable {
    public let generation: Int
    public let nextSampleSequence: Int
    public let nextControlSequence: Int
    public let sampleCredits: Int
    public let controlCredits: Int

    public init(
        generation: Int,
        nextSampleSequence: Int,
        nextControlSequence: Int,
        sampleCredits: Int,
        controlCredits: Int
    ) {
        self.generation = generation
        self.nextSampleSequence = nextSampleSequence
        self.nextControlSequence = nextControlSequence
        self.sampleCredits = sampleCredits
        self.controlCredits = controlCredits
    }
}

public struct IPCBridgeTelemetryHeadOutboxDiagnostics: Codable, Equatable, Sendable {
    public let batchSequence: Int
    public let retryAttemptCount: Int
    public let retryScheduled: Bool

    public init(batchSequence: Int, retryAttemptCount: Int, retryScheduled: Bool) {
        self.batchSequence = batchSequence
        self.retryAttemptCount = retryAttemptCount
        self.retryScheduled = retryScheduled
    }
}

public enum IPCBridgeTelemetryTransportFailureStage: String, Codable, Equatable, Sendable {
    case fetch
    case httpStatus = "http_status"
    case responseBody = "response_body"
    case responseSchema = "response_schema"
}

public enum IPCBridgeTelemetryTransportFailureDiagnostics: Codable, Equatable, Sendable {
    case fetch(retryAttemptCount: Int)
    case httpStatus(statusCode: Int, retryAttemptCount: Int)
    case responseBody(statusCode: Int, retryAttemptCount: Int)
    case responseSchema(statusCode: Int, retryAttemptCount: Int)

    public var stage: IPCBridgeTelemetryTransportFailureStage {
        switch self {
        case .fetch: .fetch
        case .httpStatus: .httpStatus
        case .responseBody: .responseBody
        case .responseSchema: .responseSchema
        }
    }

    public var httpStatus: Int? {
        switch self {
        case .fetch: nil
        case .httpStatus(let statusCode, _), .responseBody(let statusCode, _),
            .responseSchema(let statusCode, _):
            statusCode
        }
    }

    public var retryAttemptCount: Int {
        switch self {
        case .fetch(let count), .httpStatus(_, let count), .responseBody(_, let count),
            .responseSchema(_, let count):
            count
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stage = try container.decode(IPCBridgeTelemetryTransportFailureStage.self, forKey: .stage)
        let retryAttemptCount = try container.decode(Int.self, forKey: .retryAttempts)
        guard retryAttemptCount > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .retryAttempts,
                in: container,
                debugDescription: "Transport retry attempts must be positive"
            )
        }
        switch stage {
        case .fetch:
            guard try container.decodeNil(forKey: .httpStatus) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .httpStatus,
                    in: container,
                    debugDescription: "Fetch telemetry failure cannot carry HTTP status"
                )
            }
            self = .fetch(retryAttemptCount: retryAttemptCount)
        case .httpStatus:
            self = .httpStatus(
                statusCode: try Self.decodeHTTPStatus(from: container),
                retryAttemptCount: retryAttemptCount
            )
        case .responseBody:
            self = .responseBody(
                statusCode: try Self.decodeHTTPStatus(from: container),
                retryAttemptCount: retryAttemptCount
            )
        case .responseSchema:
            self = .responseSchema(
                statusCode: try Self.decodeHTTPStatus(from: container),
                retryAttemptCount: retryAttemptCount
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stage, forKey: .stage)
        try container.encode(retryAttemptCount, forKey: .retryAttempts)
        if let httpStatus {
            try container.encode(httpStatus, forKey: .httpStatus)
        } else {
            try container.encodeNil(forKey: .httpStatus)
        }
    }

    private static func decodeHTTPStatus(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        let statusCode = try container.decode(Int.self, forKey: .httpStatus)
        guard (100...599).contains(statusCode) else {
            throw DecodingError.dataCorruptedError(
                forKey: .httpStatus,
                in: container,
                debugDescription: "Telemetry HTTP status must be between 100 and 599"
            )
        }
        return statusCode
    }

    private enum CodingKeys: String, CodingKey {
        case stage, httpStatus, retryAttempts
    }
}

public enum IPCBridgeTelemetryNativeRejectionReason: String, Codable, Equatable, Sendable {
    case conflict
    case invalidBody = "invalid_body"
    case sequenceGap = "sequence_gap"
    case unavailable
}

public enum IPCBridgeTelemetryResponseMismatchField: String, Codable, Equatable, Sendable {
    case telemetrySessionId = "telemetry_session_id"
    case batchSequence = "batch_sequence"
    case nextExpectedBatchSequence = "next_expected_batch_sequence"
    case acceptedSampleCount = "accepted_sample_count"
    case acceptedLossCount = "accepted_loss_count"
}

public struct IPCBridgeTelemetryNativeRejectionDiagnostics: Equatable, Sendable {
    public let batchSequence: Int
    public let retryAttemptCount: Int
    public let reason: IPCBridgeTelemetryNativeRejectionReason
    public let retryable: Bool

    public init(
        batchSequence: Int,
        retryAttemptCount: Int,
        reason: IPCBridgeTelemetryNativeRejectionReason,
        retryable: Bool
    ) {
        self.batchSequence = batchSequence
        self.retryAttemptCount = retryAttemptCount
        self.reason = reason
        self.retryable = retryable
    }
}

public struct IPCBridgeTelemetryResponseMismatchDiagnostics: Equatable, Sendable {
    public let batchSequence: Int
    public let retryAttemptCount: Int
    public let mismatchField: IPCBridgeTelemetryResponseMismatchField

    public init(
        batchSequence: Int,
        retryAttemptCount: Int,
        mismatchField: IPCBridgeTelemetryResponseMismatchField
    ) {
        self.batchSequence = batchSequence
        self.retryAttemptCount = retryAttemptCount
        self.mismatchField = mismatchField
    }
}

public enum IPCBridgeTelemetryBatchDeliveryFailureDiagnostics: Codable, Equatable, Sendable {
    case transport(IPCBridgeTelemetryTransportFailureDiagnostics)
    case nativeRejection(IPCBridgeTelemetryNativeRejectionDiagnostics)
    case responseMismatch(IPCBridgeTelemetryResponseMismatchDiagnostics)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .transport:
            self = .transport(
                try container.decode(
                    IPCBridgeTelemetryTransportFailureDiagnostics.self,
                    forKey: .transport
                )
            )
        case .nativeRejection:
            let batchSequence = try Self.decodePositiveBatchSequence(from: container)
            let retryAttemptCount = try Self.decodeNonnegativeRetryAttempts(from: container)
            self = .nativeRejection(
                IPCBridgeTelemetryNativeRejectionDiagnostics(
                    batchSequence: batchSequence,
                    retryAttemptCount: retryAttemptCount,
                    reason: try container.decode(
                        IPCBridgeTelemetryNativeRejectionReason.self,
                        forKey: .reason
                    ),
                    retryable: try container.decode(Bool.self, forKey: .retryable)
                )
            )
        case .responseMismatch:
            let batchSequence = try Self.decodePositiveBatchSequence(from: container)
            let retryAttemptCount = try Self.decodeNonnegativeRetryAttempts(from: container)
            self = .responseMismatch(
                IPCBridgeTelemetryResponseMismatchDiagnostics(
                    batchSequence: batchSequence,
                    retryAttemptCount: retryAttemptCount,
                    mismatchField: try container.decode(
                        IPCBridgeTelemetryResponseMismatchField.self,
                        forKey: .mismatchField
                    )
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .transport(let transport):
            try container.encode(Kind.transport, forKey: .kind)
            try container.encode(transport, forKey: .transport)
        case .nativeRejection(let rejection):
            try container.encode(Kind.nativeRejection, forKey: .kind)
            try container.encode(rejection.batchSequence, forKey: .batchSequence)
            try container.encode(rejection.retryAttemptCount, forKey: .retryAttempts)
            try container.encode(rejection.reason, forKey: .reason)
            try container.encode(rejection.retryable, forKey: .retryable)
        case .responseMismatch(let mismatch):
            try container.encode(Kind.responseMismatch, forKey: .kind)
            try container.encode(mismatch.batchSequence, forKey: .batchSequence)
            try container.encode(mismatch.retryAttemptCount, forKey: .retryAttempts)
            try container.encode(mismatch.mismatchField, forKey: .mismatchField)
        }
    }

    private static func decodePositiveBatchSequence(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        let batchSequence = try container.decode(Int.self, forKey: .batchSequence)
        guard batchSequence > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .batchSequence,
                in: container,
                debugDescription: "Telemetry batch sequence must be positive"
            )
        }
        return batchSequence
    }

    private static func decodeNonnegativeRetryAttempts(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        let retryAttemptCount = try container.decode(Int.self, forKey: .retryAttempts)
        guard retryAttemptCount >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .retryAttempts,
                in: container,
                debugDescription: "Telemetry retry attempts cannot be negative"
            )
        }
        return retryAttemptCount
    }

    private enum Kind: String, Codable {
        case transport
        case nativeRejection = "native_rejection"
        case responseMismatch = "response_mismatch"
    }

    private enum CodingKeys: String, CodingKey {
        case kind, transport, batchSequence, retryAttempts, reason, retryable, mismatchField
    }
}

public struct IPCBridgeTelemetryLossDiagnostic: Codable, Equatable, Sendable {
    public let origin: IPCBridgeTelemetryLossOrigin
    public let producerId: IPCBridgeTelemetryProducerId
    public let lostSequenceStart: Int
    public let lostSequenceEnd: Int
    public let requiredCount: Int
    public let optionalCount: Int
    public let reason: IPCBridgeTelemetryLossReason

    public init(
        origin: IPCBridgeTelemetryLossOrigin,
        producerId: IPCBridgeTelemetryProducerId,
        lostSequenceStart: Int,
        lostSequenceEnd: Int,
        requiredCount: Int,
        optionalCount: Int,
        reason: IPCBridgeTelemetryLossReason
    ) {
        self.origin = origin
        self.producerId = producerId
        self.lostSequenceStart = lostSequenceStart
        self.lostSequenceEnd = lostSequenceEnd
        self.requiredCount = requiredCount
        self.optionalCount = optionalCount
        self.reason = reason
    }
}

public struct IPCBridgeTelemetryWorkerDiagnostics: Codable, Equatable, Sendable {
    public let state: IPCBridgeTelemetryWorkerState
    public let bufferedSampleCount: Int
    public let bufferedSampleByteCount: Int
    public let bufferedLossSummaryCount: Int
    public let bufferedLossSummaryByteCount: Int
    public let outboxCount: Int
    public let outboxByteCount: Int
    public let nextBatchSequence: Int
    public let isPostInFlight: Bool
    public let mainProducer: IPCBridgeTelemetryProducerDiagnostics?
    public let commProducer: IPCBridgeTelemetryProducerDiagnostics?
    public let headOutbox: IPCBridgeTelemetryHeadOutboxDiagnostics?
    public let lastBatchDeliveryFailure: IPCBridgeTelemetryBatchDeliveryFailureDiagnostics?
    public let lossDiagnostics: [IPCBridgeTelemetryLossDiagnostic]

    public init(
        state: IPCBridgeTelemetryWorkerState,
        bufferedSampleCount: Int,
        bufferedSampleByteCount: Int,
        bufferedLossSummaryCount: Int,
        bufferedLossSummaryByteCount: Int,
        outboxCount: Int,
        outboxByteCount: Int,
        nextBatchSequence: Int,
        isPostInFlight: Bool,
        mainProducer: IPCBridgeTelemetryProducerDiagnostics?,
        commProducer: IPCBridgeTelemetryProducerDiagnostics?,
        headOutbox: IPCBridgeTelemetryHeadOutboxDiagnostics?,
        lastBatchDeliveryFailure: IPCBridgeTelemetryBatchDeliveryFailureDiagnostics?,
        lossDiagnostics: [IPCBridgeTelemetryLossDiagnostic]
    ) {
        self.state = state
        self.bufferedSampleCount = bufferedSampleCount
        self.bufferedSampleByteCount = bufferedSampleByteCount
        self.bufferedLossSummaryCount = bufferedLossSummaryCount
        self.bufferedLossSummaryByteCount = bufferedLossSummaryByteCount
        self.outboxCount = outboxCount
        self.outboxByteCount = outboxByteCount
        self.nextBatchSequence = nextBatchSequence
        self.isPostInFlight = isPostInFlight
        self.mainProducer = mainProducer
        self.commProducer = commProducer
        self.headOutbox = headOutbox
        self.lastBatchDeliveryFailure = lastBatchDeliveryFailure
        self.lossDiagnostics = Array(lossDiagnostics.prefix(16))
    }
}

public struct IPCBridgeTelemetryReport: Codable, Equatable, Sendable {
    public let telemetrySessionId: String
    public let proofEligible: Bool
    public let lossy: Bool
    public let requiredLossCount: Int
    public let optionalLossCount: Int
    public let workerSequenceGapCount: Int
    public let nativeBatchSequenceGapCount: Int
    public let acceptedBatchSequence: Int
    public let mainProducerHighWatermark: Int?
    public let commProducerHighWatermark: Int?
    public let drainSettlementDisposition: IPCBridgeTelemetryDrainSettlementDisposition?
    public let workerDiagnostics: IPCBridgeTelemetryWorkerDiagnostics?

    public init(
        telemetrySessionId: String,
        proofEligible: Bool,
        lossy: Bool,
        requiredLossCount: Int,
        optionalLossCount: Int,
        workerSequenceGapCount: Int,
        nativeBatchSequenceGapCount: Int,
        acceptedBatchSequence: Int,
        mainProducerHighWatermark: Int?,
        commProducerHighWatermark: Int?,
        drainSettlementDisposition: IPCBridgeTelemetryDrainSettlementDisposition?,
        workerDiagnostics: IPCBridgeTelemetryWorkerDiagnostics?
    ) {
        self.telemetrySessionId = telemetrySessionId
        self.proofEligible = proofEligible
        self.lossy = lossy
        self.requiredLossCount = requiredLossCount
        self.optionalLossCount = optionalLossCount
        self.workerSequenceGapCount = workerSequenceGapCount
        self.nativeBatchSequenceGapCount = nativeBatchSequenceGapCount
        self.acceptedBatchSequence = acceptedBatchSequence
        self.mainProducerHighWatermark = mainProducerHighWatermark
        self.commProducerHighWatermark = commProducerHighWatermark
        self.drainSettlementDisposition = drainSettlementDisposition
        self.workerDiagnostics = workerDiagnostics
    }
}

public struct IPCBridgeTelemetrySnapshotResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let kind: IPCBridgeTelemetryResultKind
    public let unavailableReason: IPCBridgeTelemetryUnavailableReason?
    public let report: IPCBridgeTelemetryReport?

    public init(
        paneId: UUID,
        kind: IPCBridgeTelemetryResultKind,
        unavailableReason: IPCBridgeTelemetryUnavailableReason?,
        report: IPCBridgeTelemetryReport?
    ) {
        precondition(
            (kind == .unavailable && unavailableReason != nil && report == nil)
                || (kind == .report && unavailableReason == nil && report != nil)
        )
        self.paneId = paneId
        self.kind = kind
        self.unavailableReason = unavailableReason
        self.report = report
    }
}

public struct IPCBridgeTelemetryFlushResult: Codable, Equatable, Sendable {
    public let paneId: UUID
    public let kind: IPCBridgeTelemetryResultKind
    public let unavailableReason: IPCBridgeTelemetryUnavailableReason?
    public let report: IPCBridgeTelemetryReport?
    public let drained: Bool?

    public init(
        paneId: UUID,
        kind: IPCBridgeTelemetryResultKind,
        unavailableReason: IPCBridgeTelemetryUnavailableReason?,
        report: IPCBridgeTelemetryReport?,
        drained: Bool?
    ) {
        precondition(
            (kind == .unavailable && unavailableReason != nil && report == nil
                && drained == nil)
                || (kind == .report && unavailableReason == nil && report != nil
                    && drained != nil)
        )
        self.paneId = paneId
        self.kind = kind
        self.unavailableReason = unavailableReason
        self.report = report
        self.drained = drained
    }
}
