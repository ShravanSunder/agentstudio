import Foundation

enum BridgeTelemetrySidecarControlAction: String, Sendable {
    case drain
    case drainAndClose
    case snapshot
}

enum BridgeTelemetrySidecarUnavailableReason: String, Codable, Equatable, Sendable {
    case disabled
    case failed
}

enum BridgeTelemetrySidecarEnvelopeKind: String, Codable, Equatable, Sendable {
    case report
    case unavailable
}

enum BridgeTelemetrySidecarState: String, Codable, Equatable, Sendable {
    case active
    case closed
    case draining
    case failed
}

enum BridgeTelemetrySidecarDrainResultType: String, Codable, Equatable, Sendable {
    case drained
}

struct BridgeTelemetrySidecarProducerSnapshot: Codable, Equatable, Sendable {
    let generation: Int
    let nextExpectedSequence: Int
    let nextExpectedControlSequence: Int
    let availableSampleCredits: Int
    let availableControlCredits: Int
    let barrierHighWatermark: Int?
}

enum BridgeTelemetrySidecarLossOrigin: String, Codable, Equatable, Sendable {
    case producer
    case worker
}

enum BridgeTelemetrySidecarLossReason: String, Codable, Equatable, Sendable {
    case creditExhausted = "credit_exhausted"
    case encodedByteCap = "encoded_byte_cap"
    case queueSaturated = "queue_saturated"
    case outboxSaturated = "outbox_saturated"
    case producerFailure = "producer_failure"
    case transportRetryExhausted = "transport_retry_exhausted"
}

struct BridgeTelemetrySidecarHeadOutboxSnapshot: Codable, Equatable, Sendable {
    let batchSequence: Int
    let retryAttemptCount: Int
    let retryScheduled: Bool

    private enum CodingKeys: String, CodingKey {
        case batchSequence
        case retryAttemptCount = "retryAttempts"
        case retryScheduled
    }
}

enum BridgeTelemetrySidecarTransportFailureStage: String, Codable, Equatable, Sendable {
    case fetch
    case httpStatus = "http_status"
    case responseBody = "response_body"
    case responseSchema = "response_schema"
}

enum BridgeTelemetrySidecarTransportFailureSnapshot: Codable, Equatable, Sendable {
    case fetch(retryAttempts: Int)
    case httpStatus(statusCode: Int, retryAttempts: Int)
    case responseBody(statusCode: Int, retryAttempts: Int)
    case responseSchema(statusCode: Int, retryAttempts: Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stage = try container.decode(BridgeTelemetrySidecarTransportFailureStage.self, forKey: .stage)
        let retryAttempts = try container.decode(Int.self, forKey: .retryAttempts)
        guard retryAttempts > 0 else {
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
            self = .fetch(retryAttempts: retryAttempts)
        case .httpStatus:
            let statusCode = try Self.decodeHTTPStatus(from: container)
            self = .httpStatus(statusCode: statusCode, retryAttempts: retryAttempts)
        case .responseBody:
            let statusCode = try Self.decodeHTTPStatus(from: container)
            self = .responseBody(statusCode: statusCode, retryAttempts: retryAttempts)
        case .responseSchema:
            let statusCode = try Self.decodeHTTPStatus(from: container)
            self = .responseSchema(statusCode: statusCode, retryAttempts: retryAttempts)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fetch(let retryAttempts):
            try container.encode(BridgeTelemetrySidecarTransportFailureStage.fetch, forKey: .stage)
            try container.encodeNil(forKey: .httpStatus)
            try container.encode(retryAttempts, forKey: .retryAttempts)
        case .httpStatus(let statusCode, let retryAttempts):
            try encodeResponse(.httpStatus, statusCode, retryAttempts, into: &container)
        case .responseBody(let statusCode, let retryAttempts):
            try encodeResponse(.responseBody, statusCode, retryAttempts, into: &container)
        case .responseSchema(let statusCode, let retryAttempts):
            try encodeResponse(.responseSchema, statusCode, retryAttempts, into: &container)
        }
    }

    private func encodeResponse(
        _ stage: BridgeTelemetrySidecarTransportFailureStage,
        _ statusCode: Int,
        _ retryAttempts: Int,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(stage, forKey: .stage)
        try container.encode(statusCode, forKey: .httpStatus)
        try container.encode(retryAttempts, forKey: .retryAttempts)
    }

    private enum CodingKeys: String, CodingKey {
        case stage, httpStatus, retryAttempts
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
}

enum BridgeTelemetrySidecarNativeRejectionReason: String, Codable, Equatable, Sendable {
    case conflict
    case invalidBody = "invalid_body"
    case sequenceGap = "sequence_gap"
    case unavailable
}

enum BridgeTelemetrySidecarResponseMismatchField: String, Codable, Equatable, Sendable {
    case telemetrySessionId = "telemetry_session_id"
    case batchSequence = "batch_sequence"
    case nextExpectedBatchSequence = "next_expected_batch_sequence"
    case acceptedSampleCount = "accepted_sample_count"
    case acceptedLossCount = "accepted_loss_count"
}

struct BridgeTelemetrySidecarNativeRejectionSnapshot: Equatable, Sendable {
    let batchSequence: Int
    let retryAttemptCount: Int
    let reason: BridgeTelemetrySidecarNativeRejectionReason
    let retryable: Bool
}

struct BridgeTelemetrySidecarResponseMismatchSnapshot: Equatable, Sendable {
    let batchSequence: Int
    let retryAttemptCount: Int
    let mismatchField: BridgeTelemetrySidecarResponseMismatchField
}

enum BridgeTelemetrySidecarBatchDeliveryFailureSnapshot: Codable, Equatable, Sendable {
    case noRecordedFailure
    case transport(BridgeTelemetrySidecarTransportFailureSnapshot)
    case nativeRejection(BridgeTelemetrySidecarNativeRejectionSnapshot)
    case responseMismatch(BridgeTelemetrySidecarResponseMismatchSnapshot)

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if singleValueContainer.decodeNil() {
            self = .noRecordedFailure
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .transport:
            self = .transport(
                try container.decode(
                    BridgeTelemetrySidecarTransportFailureSnapshot.self,
                    forKey: .transport
                )
            )
        case .nativeRejection:
            let batchSequence = try Self.decodePositiveBatchSequence(from: container)
            let retryAttempts = try Self.decodeNonnegativeRetryAttempts(from: container)
            self = .nativeRejection(
                BridgeTelemetrySidecarNativeRejectionSnapshot(
                    batchSequence: batchSequence,
                    retryAttemptCount: retryAttempts,
                    reason: try container.decode(
                        BridgeTelemetrySidecarNativeRejectionReason.self,
                        forKey: .reason
                    ),
                    retryable: try container.decode(Bool.self, forKey: .retryable)
                )
            )
        case .responseMismatch:
            let batchSequence = try Self.decodePositiveBatchSequence(from: container)
            let retryAttempts = try Self.decodeNonnegativeRetryAttempts(from: container)
            self = .responseMismatch(
                BridgeTelemetrySidecarResponseMismatchSnapshot(
                    batchSequence: batchSequence,
                    retryAttemptCount: retryAttempts,
                    mismatchField: try container.decode(
                        BridgeTelemetrySidecarResponseMismatchField.self,
                        forKey: .mismatchField
                    )
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        if case .noRecordedFailure = self {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noRecordedFailure:
            return
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
        let retryAttempts = try container.decode(Int.self, forKey: .retryAttempts)
        guard retryAttempts >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .retryAttempts,
                in: container,
                debugDescription: "Telemetry retry attempts cannot be negative"
            )
        }
        return retryAttempts
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

struct BridgeTelemetrySidecarLossDiagnostic: Codable, Equatable, Sendable {
    let origin: BridgeTelemetrySidecarLossOrigin
    let producerId: BridgeTelemetryProducerId
    let lostSequenceStart: Int
    let lostSequenceEnd: Int
    let requiredCount: Int
    let optionalCount: Int
    let reason: BridgeTelemetrySidecarLossReason

    init(
        origin: BridgeTelemetrySidecarLossOrigin = .worker,
        producerId: BridgeTelemetryProducerId,
        lostSequenceStart: Int,
        lostSequenceEnd: Int,
        requiredCount: Int,
        optionalCount: Int,
        reason: BridgeTelemetrySidecarLossReason
    ) {
        self.origin = origin
        self.producerId = producerId
        self.lostSequenceStart = lostSequenceStart
        self.lostSequenceEnd = lostSequenceEnd
        self.requiredCount = requiredCount
        self.optionalCount = optionalCount
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case origin, producerId, requiredCount, optionalCount, reason
        case lostSequenceStart = "lastLostSequenceStart"
        case lostSequenceEnd = "lastLostSequenceEnd"
    }
}

struct BridgeTelemetrySidecarSnapshot: Codable, Equatable, Sendable {
    let state: BridgeTelemetrySidecarState
    let proofEligible: Bool
    let lossy: Bool
    let requiredLossCount: Int
    let optionalLossCount: Int
    let sequenceGapCount: Int
    let bufferedSampleCount: Int
    let bufferedSampleBytes: Int
    let bufferedLossSummaryCount: Int
    let bufferedLossSummaryBytes: Int
    let bufferedBytes: Int
    let outboxCount: Int
    let outboxBytes: Int
    let nextBatchSequence: Int
    let acceptedBatchSequence: Int
    let isPostInFlight: Bool
    let producers: [String: BridgeTelemetrySidecarProducerSnapshot?]
    let headOutbox: BridgeTelemetrySidecarHeadOutboxSnapshot?
    let lastBatchDeliveryFailure: BridgeTelemetrySidecarBatchDeliveryFailureSnapshot
    let lossDiagnostics: [BridgeTelemetrySidecarLossDiagnostic]
}

struct BridgeTelemetrySidecarDrainResult: Codable, Equatable, Sendable {
    let type: BridgeTelemetrySidecarDrainResultType
    let proofEligible: Bool
    let settlementDisposition: BridgeTelemetrySidecarSettlementDisposition
    let requiredLossCount: Int
    let optionalLossCount: Int
    let sequenceGapCount: Int
    let producerHighWatermarks: [String: Int]
    let acceptedBatchSequence: Int
}

enum BridgeTelemetrySidecarSettlementDisposition: String, Codable, Equatable, Sendable {
    case closed
    case reopened
}

struct BridgeTelemetrySidecarSnapshotEnvelope: Codable, Equatable, Sendable {
    let kind: BridgeTelemetrySidecarEnvelopeKind
    let reason: BridgeTelemetrySidecarUnavailableReason?
    let telemetrySessionId: String?
    let sidecar: BridgeTelemetrySidecarSnapshot?
}

struct BridgeTelemetrySidecarDrainEnvelope: Codable, Equatable, Sendable {
    let kind: BridgeTelemetrySidecarEnvelopeKind
    let reason: BridgeTelemetrySidecarUnavailableReason?
    let telemetrySessionId: String?
    let sidecar: BridgeTelemetrySidecarDrainResult?
}

enum BridgeTelemetrySidecarControlError: Error, Equatable {
    case invalidResponse
    case unavailable(BridgeTelemetrySidecarUnavailableReason)
}
