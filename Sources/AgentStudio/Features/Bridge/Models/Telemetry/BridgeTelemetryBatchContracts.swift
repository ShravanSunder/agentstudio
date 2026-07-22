import Foundation

struct BridgeTelemetryStampedSample: Codable, Equatable, Sendable {
    let producerId: BridgeTelemetryProducerId
    let producerSequence: Int
    let sample: BridgeTelemetryCompactSample

    init(
        producerId: BridgeTelemetryProducerId,
        producerSequence: Int,
        sample: BridgeTelemetryCompactSample
    ) {
        self.producerId = producerId
        self.producerSequence = producerSequence
        self.sample = sample
    }

    init(from decoder: Decoder) throws {
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge telemetry stamped sample"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.producerId = try container.decode(BridgeTelemetryProducerId.self, forKey: .producerId)
        self.producerSequence = try container.decode(Int.self, forKey: .producerSequence)
        self.sample = try container.decode(BridgeTelemetryCompactSample.self, forKey: .sample)
        try BridgeTelemetryContractValidation.validatePositive(
            producerSequence,
            codingPath: decoder.codingPath
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case producerId, producerSequence, sample
    }
}

struct BridgeTelemetryStampedLossSummary: Codable, Equatable, Sendable {
    let producerId: BridgeTelemetryProducerId
    let lostSequenceStart: Int
    let lostSequenceEnd: Int
    let requiredCount: Int
    let optionalCount: Int
    let reason: BridgeTelemetryLossReason

    init(
        producerId: BridgeTelemetryProducerId,
        lostSequenceStart: Int,
        lostSequenceEnd: Int,
        requiredCount: Int,
        optionalCount: Int,
        reason: BridgeTelemetryLossReason
    ) {
        self.producerId = producerId
        self.lostSequenceStart = lostSequenceStart
        self.lostSequenceEnd = lostSequenceEnd
        self.requiredCount = requiredCount
        self.optionalCount = optionalCount
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge telemetry stamped loss summary"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.producerId = try container.decode(BridgeTelemetryProducerId.self, forKey: .producerId)
        self.lostSequenceStart = try container.decode(Int.self, forKey: .lostSequenceStart)
        self.lostSequenceEnd = try container.decode(Int.self, forKey: .lostSequenceEnd)
        self.requiredCount = try container.decode(Int.self, forKey: .requiredCount)
        self.optionalCount = try container.decode(Int.self, forKey: .optionalCount)
        self.reason = try container.decode(BridgeTelemetryLossReason.self, forKey: .reason)
        try validate(codingPath: decoder.codingPath)
    }

    func validate(codingPath: [any CodingKey]) throws {
        try BridgeTelemetryContractValidation.validatePositive(lostSequenceStart, codingPath: codingPath)
        try BridgeTelemetryContractValidation.validatePositive(lostSequenceEnd, codingPath: codingPath)
        let lostCount = lostSequenceEnd - lostSequenceStart + 1
        guard
            lostSequenceEnd >= lostSequenceStart,
            requiredCount >= 0,
            optionalCount >= 0,
            requiredCount + optionalCount == lostCount
        else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid Bridge telemetry loss range",
                codingPath: codingPath
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case producerId, lostSequenceStart, lostSequenceEnd
        case requiredCount, optionalCount, reason
    }
}

struct BridgeTelemetryBatchRequest: Codable, Equatable, Sendable {
    let telemetrySessionId: String
    let batchSequence: Int
    let samples: [BridgeTelemetryStampedSample]
    let lossSummaries: [BridgeTelemetryStampedLossSummary]

    init(
        telemetrySessionId: String,
        batchSequence: Int,
        samples: [BridgeTelemetryStampedSample],
        lossSummaries: [BridgeTelemetryStampedLossSummary]
    ) {
        self.telemetrySessionId = telemetrySessionId
        self.batchSequence = batchSequence
        self.samples = samples
        self.lossSummaries = lossSummaries
    }

    init(from decoder: Decoder) throws {
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge telemetry batch request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .type) == "telemetry.batch" else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid Bridge telemetry batch type",
                codingPath: decoder.codingPath
            )
        }
        guard
            try container.decode(Int.self, forKey: .schemaVersion)
                == BridgeTelemetryWorkerWireContract.schemaVersion
        else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Bridge telemetry schemaVersion must be 2",
                codingPath: decoder.codingPath
            )
        }
        self.telemetrySessionId = try container.decode(String.self, forKey: .telemetrySessionId)
        self.batchSequence = try container.decode(Int.self, forKey: .batchSequence)
        self.samples = try container.decode([BridgeTelemetryStampedSample].self, forKey: .samples)
        self.lossSummaries = try container.decode(
            [BridgeTelemetryStampedLossSummary].self,
            forKey: .lossSummaries
        )
        try BridgeTelemetryContractValidation.validateIdentifier(
            telemetrySessionId,
            codingPath: decoder.codingPath
        )
        try BridgeTelemetryContractValidation.validatePositive(batchSequence, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("telemetry.batch", forKey: .type)
        try container.encode(BridgeTelemetryWorkerWireContract.schemaVersion, forKey: .schemaVersion)
        try container.encode(telemetrySessionId, forKey: .telemetrySessionId)
        try container.encode(batchSequence, forKey: .batchSequence)
        try container.encode(samples, forKey: .samples)
        try container.encode(lossSummaries, forKey: .lossSummaries)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, schemaVersion, telemetrySessionId, batchSequence, samples, lossSummaries
    }
}

enum BridgeTelemetryBatchRequestDecodingError: Error, Equatable {
    case bodyTooLarge
    case invalidBody
    case tooManyEntries
    case compactSampleTooLarge
}

protocol BridgeTelemetryBatchRequestDecoding: Sendable {
    func decode(_ data: Data) throws -> BridgeTelemetryBatchRequest
}

struct BridgeTelemetryBatchRequestDecoder: BridgeTelemetryBatchRequestDecoding {
    let policy: BridgeTelemetryWorkerPolicy

    func decode(_ data: Data) throws -> BridgeTelemetryBatchRequest {
        guard data.count <= policy.batchMaxBytes else {
            throw BridgeTelemetryBatchRequestDecodingError.bodyTooLarge
        }
        do {
            try BridgeProductStrictJSON.validate(data)
            let request = try JSONDecoder().decode(BridgeTelemetryBatchRequest.self, from: data)
            guard request.samples.count + request.lossSummaries.count <= policy.batchMaxSamples else {
                throw BridgeTelemetryBatchRequestDecodingError.tooManyEntries
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard
                try request.samples.allSatisfy({
                    try encoder.encode($0.sample).count <= policy.compactSampleMaxEncodedBytes
                })
            else {
                throw BridgeTelemetryBatchRequestDecodingError.compactSampleTooLarge
            }
            return request
        } catch let error as BridgeTelemetryBatchRequestDecodingError {
            throw error
        } catch {
            throw BridgeTelemetryBatchRequestDecodingError.invalidBody
        }
    }
}

struct BridgeTelemetryAcceptedBatchResponse: Codable, Equatable, Sendable {
    let telemetrySessionId: String
    let batchSequence: Int
    let nextExpectedBatchSequence: Int
    let acceptedSampleCount: Int
    let acceptedLossCount: Int
}

struct BridgeTelemetryAcceptedWithLossBatchResponse: Codable, Equatable, Sendable {
    let telemetrySessionId: String
    let batchSequence: Int
    let nextExpectedBatchSequence: Int
    let acceptedSampleCount: Int
    let acceptedLossCount: Int
    let nativeRequiredLossCount: Int
    let nativeOptionalLossCount: Int
}

enum BridgeTelemetryBatchRejectionReason: String, Codable, Equatable, Sendable {
    case conflict
    case invalidBody = "invalid_body"
    case sequenceGap = "sequence_gap"
    case unavailable
}

struct BridgeTelemetryRejectedBatchResponse: Codable, Equatable, Sendable {
    let telemetrySessionId: String
    let batchSequence: Int
    let nextExpectedBatchSequence: Int
    let reason: BridgeTelemetryBatchRejectionReason
    let retryable: Bool
    let retryAfterMilliseconds: Int?
}

enum BridgeTelemetryBatchResponse: Codable, Equatable, Sendable {
    case accepted(BridgeTelemetryAcceptedBatchResponse)
    case duplicate(BridgeTelemetryAcceptedBatchResponse)
    case acceptedWithLoss(BridgeTelemetryAcceptedWithLossBatchResponse)
    case rejected(BridgeTelemetryRejectedBatchResponse)

    var type: String {
        switch self {
        case .accepted: "accepted"
        case .duplicate: "duplicate"
        case .acceptedWithLoss: "accepted_with_loss"
        case .rejected: "rejected"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeCodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "accepted":
            self = .accepted(try AcceptedWire(from: decoder).value)
        case "duplicate":
            self = .duplicate(try AcceptedWire(from: decoder).value)
        case "accepted_with_loss":
            self = .acceptedWithLoss(try AcceptedWithLossWire(from: decoder).value)
        case "rejected":
            self = .rejected(try RejectedWire(from: decoder).value)
        default:
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid Bridge telemetry response type",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .accepted(let value):
            try AcceptedWire(type: "accepted", value: value).encode(to: encoder)
        case .duplicate(let value):
            try AcceptedWire(type: "duplicate", value: value).encode(to: encoder)
        case .acceptedWithLoss(let value):
            try AcceptedWithLossWire(value: value).encode(to: encoder)
        case .rejected(let value):
            try RejectedWire(value: value).encode(to: encoder)
        }
    }

    private enum TypeCodingKeys: String, CodingKey {
        case type
    }
}

struct BridgeTelemetrySessionSnapshot: Codable, Equatable, Sendable {
    let telemetrySessionId: String
    let nextExpectedBatchSequence: Int
    let acceptedBatchSequence: Int
    let batchSequenceGapCount: Int
    let proofEligible: Bool
    let lossy: Bool
    let requiredLossCount: Int
    let optionalLossCount: Int
    let revoked: Bool
}

private struct AcceptedWire: Codable {
    let type: String
    let telemetrySessionId: String
    let batchSequence: Int
    let nextExpectedBatchSequence: Int
    let acceptedSampleCount: Int
    let acceptedLossCount: Int

    init(type: String, value: BridgeTelemetryAcceptedBatchResponse) {
        self.type = type
        self.telemetrySessionId = value.telemetrySessionId
        self.batchSequence = value.batchSequence
        self.nextExpectedBatchSequence = value.nextExpectedBatchSequence
        self.acceptedSampleCount = value.acceptedSampleCount
        self.acceptedLossCount = value.acceptedLossCount
    }

    init(from decoder: Decoder) throws {
        try rejectResponseUnknownKeys(from: decoder, codingKeys: Array(CodingKeys.allCases))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.telemetrySessionId = try container.decode(String.self, forKey: .telemetrySessionId)
        self.batchSequence = try container.decode(Int.self, forKey: .batchSequence)
        self.nextExpectedBatchSequence = try container.decode(Int.self, forKey: .nextExpectedBatchSequence)
        self.acceptedSampleCount = try container.decode(Int.self, forKey: .acceptedSampleCount)
        self.acceptedLossCount = try container.decode(Int.self, forKey: .acceptedLossCount)
        try BridgeTelemetryContractValidation.validateIdentifier(
            telemetrySessionId,
            codingPath: decoder.codingPath
        )
        try BridgeTelemetryContractValidation.validatePositive(batchSequence, codingPath: decoder.codingPath)
        try BridgeTelemetryContractValidation.validatePositive(
            nextExpectedBatchSequence,
            codingPath: decoder.codingPath
        )
        guard
            type == "accepted" || type == "duplicate",
            acceptedSampleCount >= 0,
            acceptedLossCount >= 0
        else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid accepted telemetry response",
                codingPath: decoder.codingPath
            )
        }
    }

    var value: BridgeTelemetryAcceptedBatchResponse {
        .init(
            telemetrySessionId: telemetrySessionId,
            batchSequence: batchSequence,
            nextExpectedBatchSequence: nextExpectedBatchSequence,
            acceptedSampleCount: acceptedSampleCount,
            acceptedLossCount: acceptedLossCount
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, telemetrySessionId, batchSequence, nextExpectedBatchSequence
        case acceptedSampleCount, acceptedLossCount
    }
}

private struct AcceptedWithLossWire: Codable {
    let type = "accepted_with_loss"
    let telemetrySessionId: String
    let batchSequence: Int
    let nextExpectedBatchSequence: Int
    let acceptedSampleCount: Int
    let acceptedLossCount: Int
    let nativeRequiredLossCount: Int
    let nativeOptionalLossCount: Int

    init(value: BridgeTelemetryAcceptedWithLossBatchResponse) {
        self.telemetrySessionId = value.telemetrySessionId
        self.batchSequence = value.batchSequence
        self.nextExpectedBatchSequence = value.nextExpectedBatchSequence
        self.acceptedSampleCount = value.acceptedSampleCount
        self.acceptedLossCount = value.acceptedLossCount
        self.nativeRequiredLossCount = value.nativeRequiredLossCount
        self.nativeOptionalLossCount = value.nativeOptionalLossCount
    }

    init(from decoder: Decoder) throws {
        try rejectResponseUnknownKeys(from: decoder, codingKeys: Array(CodingKeys.allCases))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .type) == type else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid response type", codingPath: decoder.codingPath)
        }
        self.telemetrySessionId = try container.decode(String.self, forKey: .telemetrySessionId)
        self.batchSequence = try container.decode(Int.self, forKey: .batchSequence)
        self.nextExpectedBatchSequence = try container.decode(Int.self, forKey: .nextExpectedBatchSequence)
        self.acceptedSampleCount = try container.decode(Int.self, forKey: .acceptedSampleCount)
        self.acceptedLossCount = try container.decode(Int.self, forKey: .acceptedLossCount)
        self.nativeRequiredLossCount = try container.decode(Int.self, forKey: .nativeRequiredLossCount)
        self.nativeOptionalLossCount = try container.decode(Int.self, forKey: .nativeOptionalLossCount)
        try BridgeTelemetryContractValidation.validateIdentifier(
            telemetrySessionId,
            codingPath: decoder.codingPath
        )
        try BridgeTelemetryContractValidation.validatePositive(batchSequence, codingPath: decoder.codingPath)
        try BridgeTelemetryContractValidation.validatePositive(
            nextExpectedBatchSequence,
            codingPath: decoder.codingPath
        )
        guard
            acceptedSampleCount >= 0,
            acceptedLossCount >= 0,
            nativeRequiredLossCount >= 0,
            nativeOptionalLossCount >= 0
        else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid accepted-with-loss telemetry response",
                codingPath: decoder.codingPath
            )
        }
    }

    var value: BridgeTelemetryAcceptedWithLossBatchResponse {
        .init(
            telemetrySessionId: telemetrySessionId,
            batchSequence: batchSequence,
            nextExpectedBatchSequence: nextExpectedBatchSequence,
            acceptedSampleCount: acceptedSampleCount,
            acceptedLossCount: acceptedLossCount,
            nativeRequiredLossCount: nativeRequiredLossCount,
            nativeOptionalLossCount: nativeOptionalLossCount
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, telemetrySessionId, batchSequence, nextExpectedBatchSequence
        case acceptedSampleCount, acceptedLossCount, nativeRequiredLossCount, nativeOptionalLossCount
    }
}

private struct RejectedWire: Codable {
    let type = "rejected"
    let telemetrySessionId: String
    let batchSequence: Int
    let nextExpectedBatchSequence: Int
    let reason: BridgeTelemetryBatchRejectionReason
    let retryable: Bool
    let retryAfterMilliseconds: Int?

    init(value: BridgeTelemetryRejectedBatchResponse) {
        self.telemetrySessionId = value.telemetrySessionId
        self.batchSequence = value.batchSequence
        self.nextExpectedBatchSequence = value.nextExpectedBatchSequence
        self.reason = value.reason
        self.retryable = value.retryable
        self.retryAfterMilliseconds = value.retryAfterMilliseconds
    }

    init(from decoder: Decoder) throws {
        try rejectResponseUnknownKeys(from: decoder, codingKeys: Array(CodingKeys.allCases))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .type) == type else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid response type", codingPath: decoder.codingPath)
        }
        self.telemetrySessionId = try container.decode(String.self, forKey: .telemetrySessionId)
        self.batchSequence = try container.decode(Int.self, forKey: .batchSequence)
        self.nextExpectedBatchSequence = try container.decode(Int.self, forKey: .nextExpectedBatchSequence)
        self.reason = try container.decode(BridgeTelemetryBatchRejectionReason.self, forKey: .reason)
        self.retryable = try container.decode(Bool.self, forKey: .retryable)
        if container.contains(.retryAfterMilliseconds) {
            guard try !container.decodeNil(forKey: .retryAfterMilliseconds) else {
                throw BridgeTelemetryContractValidation.invalidValue(
                    "Telemetry retry delay cannot be null",
                    codingPath: decoder.codingPath
                )
            }
            self.retryAfterMilliseconds = try container.decode(Int.self, forKey: .retryAfterMilliseconds)
        } else {
            self.retryAfterMilliseconds = nil
        }
        try BridgeTelemetryContractValidation.validateIdentifier(
            telemetrySessionId,
            codingPath: decoder.codingPath
        )
        try BridgeTelemetryContractValidation.validatePositive(batchSequence, codingPath: decoder.codingPath)
        try BridgeTelemetryContractValidation.validatePositive(
            nextExpectedBatchSequence,
            codingPath: decoder.codingPath
        )
        guard retryAfterMilliseconds.map({ $0 >= 0 }) ?? true else {
            throw BridgeTelemetryContractValidation.invalidValue(
                "Invalid telemetry retry delay",
                codingPath: decoder.codingPath
            )
        }
    }

    var value: BridgeTelemetryRejectedBatchResponse {
        .init(
            telemetrySessionId: telemetrySessionId,
            batchSequence: batchSequence,
            nextExpectedBatchSequence: nextExpectedBatchSequence,
            reason: reason,
            retryable: retryable,
            retryAfterMilliseconds: retryAfterMilliseconds
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, telemetrySessionId, batchSequence, nextExpectedBatchSequence
        case reason, retryable, retryAfterMilliseconds
    }
}

private func rejectResponseUnknownKeys<Key: CodingKey>(
    from decoder: Decoder,
    codingKeys: [Key]
) throws {
    try BridgeTelemetryContractValidation.rejectUnknownKeys(
        from: decoder,
        allowedKeys: Set(codingKeys.map(\.stringValue)),
        contract: "Bridge telemetry batch response"
    )
}
