import Foundation

enum BridgeTelemetrySurface: String, Codable, Equatable, Sendable {
    case file
    case review
}

enum BridgeTelemetryLifecycleStage: String, Codable, Equatable, Sendable {
    case demandIssued = "demand_issued"
    case workerReady = "worker_ready"
    case mainReceived = "main_received"
    case validityAccepted = "validity_accepted"
    case validityRejected = "validity_rejected"
    case applyQueued = "apply_queued"
    case applied
    case superseded
    case painted
}

enum BridgeTelemetryDurationMetric: String, Codable, Equatable, Sendable {
    case clickToFirstVisible = "click_to_first_visible"
    case workerQueueWait = "worker_queue_wait"
    case workerTask = "worker_task"
    case mainApply = "main_apply"
    case paintWait = "paint_wait"
}

enum BridgeTelemetryFailureKind: String, Codable, Equatable, Sendable {
    case abort
    case stale
    case unavailable
    case timeout
    case reset
    case retry
    case failure
    case jank
}

enum BridgeTelemetryIntegrityFailure: String, Codable, Equatable, Sendable {
    case producerSequenceGap = "producer_sequence_gap"
    case batchSequenceGap = "batch_sequence_gap"
    case conflictingDuplicate = "conflicting_duplicate"
    case missingDrainAcknowledgement = "missing_drain_ack"
    case workerRestart = "worker_restart"
}

enum BridgeTelemetryDiagnosticCode: String, Codable, Equatable, Sendable {
    case workerQueueDepth = "worker_queue_depth"
    case bufferBytes = "buffer_bytes"
    case outboxBytes = "outbox_bytes"
}

struct BridgeTelemetryLifecycleCompactSample: Codable, Equatable, Sendable {
    let stage: BridgeTelemetryLifecycleStage
    let timestampMilliseconds: Double
    let attemptId: String
    let interactionSequence: Int
    let surface: BridgeTelemetrySurface
}

struct BridgeTelemetryDurationCompactSample: Codable, Equatable, Sendable {
    let metric: BridgeTelemetryDurationMetric
    let durationMilliseconds: Double
    let timestampMilliseconds: Double
    let attemptId: String
    let interactionSequence: Int
    let surface: BridgeTelemetrySurface
}

struct BridgeTelemetryFailureCompactSample: Codable, Equatable, Sendable {
    let failure: BridgeTelemetryFailureKind
    let timestampMilliseconds: Double
    let attemptId: String
    let interactionSequence: Int
    let surface: BridgeTelemetrySurface
}

struct BridgeTelemetryIntegrityCompactSample: Codable, Equatable, Sendable {
    let failure: BridgeTelemetryIntegrityFailure
    let timestampMilliseconds: Double
}

struct BridgeTelemetryDiagnosticCompactSample: Codable, Equatable, Sendable {
    let code: BridgeTelemetryDiagnosticCode
    let timestampMilliseconds: Double
    let value: Double
}

struct BridgeTelemetryEventCompactSample: Equatable, Sendable {
    let timestampMilliseconds: Double
    let sample: BridgeTelemetrySample
}

enum BridgeTelemetryCompactSample: Codable, Equatable, Sendable {
    case lifecycle(BridgeTelemetryLifecycleCompactSample)
    case duration(BridgeTelemetryDurationCompactSample)
    case failure(BridgeTelemetryFailureCompactSample)
    case integrity(BridgeTelemetryIntegrityCompactSample)
    case diagnostic(BridgeTelemetryDiagnosticCompactSample)
    case requiredEvent(BridgeTelemetryEventCompactSample)
    case optionalEvent(BridgeTelemetryEventCompactSample)

    var isRequired: Bool {
        switch self {
        case .diagnostic, .optionalEvent:
            false
        default:
            true
        }
    }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeCodingKeys.self)
        let type = try typeContainer.decode(SampleType.self, forKey: .type)
        switch type {
        case .lifecycle:
            let payload = try LifecycleWire(from: decoder)
            self = .lifecycle(payload.compactValue)
        case .duration:
            let payload = try DurationWire(from: decoder)
            self = .duration(payload.compactValue)
        case .failure:
            let payload = try FailureWire(from: decoder)
            self = .failure(payload.compactValue)
        case .integrity:
            let payload = try IntegrityWire(from: decoder)
            self = .integrity(payload.compactValue)
        case .diagnostic:
            let payload = try DiagnosticWire(from: decoder)
            self = .diagnostic(payload.compactValue)
        case .requiredEvent:
            let payload = try EventWire(from: decoder)
            guard
                Self.priority(of: payload.compactValue.sample) == .hot
                    || Self.priority(of: payload.compactValue.sample) == .warm
                    || Self.priority(of: payload.compactValue.sample) == .cold
            else {
                throw BridgeTelemetryContractValidation.invalidValue(
                    "Required telemetry event must have hot, warm, or cold priority",
                    codingPath: decoder.codingPath
                )
            }
            self = .requiredEvent(payload.compactValue)
        case .optionalEvent:
            let payload = try EventWire(from: decoder)
            guard Self.priority(of: payload.compactValue.sample) == .bestEffort else {
                throw BridgeTelemetryContractValidation.invalidValue(
                    "Optional telemetry event must have best-effort priority",
                    codingPath: decoder.codingPath
                )
            }
            self = .optionalEvent(payload.compactValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .lifecycle(let value):
            try LifecycleWire(value: value).encode(to: encoder)
        case .duration(let value):
            try DurationWire(value: value).encode(to: encoder)
        case .failure(let value):
            try FailureWire(value: value).encode(to: encoder)
        case .integrity(let value):
            try IntegrityWire(value: value).encode(to: encoder)
        case .diagnostic(let value):
            try DiagnosticWire(value: value).encode(to: encoder)
        case .requiredEvent(let value):
            try EventWire(type: .requiredEvent, value: value).encode(to: encoder)
        case .optionalEvent(let value):
            try EventWire(type: .optionalEvent, value: value).encode(to: encoder)
        }
    }

    private static func priority(of sample: BridgeTelemetrySample) -> BridgeTelemetryPriority? {
        guard let rawPriority = sample.stringAttributes["agentstudio.bridge.priority"] else {
            return nil
        }
        return BridgeTelemetryPriority(rawValue: rawPriority)
    }

    private enum TypeCodingKeys: String, CodingKey {
        case type
    }

    fileprivate enum SampleType: String, Codable {
        case lifecycle = "interaction.lifecycle"
        case duration
        case failure = "interaction.failure"
        case integrity
        case diagnostic
        case requiredEvent = "event.required"
        case optionalEvent = "event.optional"
    }
}

private struct LifecycleWire: CompactSampleWireContract {
    let type: BridgeTelemetryCompactSample.SampleType
    let stage: BridgeTelemetryLifecycleStage
    let timestampMilliseconds: Double
    let attemptId: String
    let interactionSequence: Int
    let surface: BridgeTelemetrySurface

    init(value: BridgeTelemetryLifecycleCompactSample) {
        self.type = .lifecycle
        self.stage = value.stage
        self.timestampMilliseconds = value.timestampMilliseconds
        self.attemptId = value.attemptId
        self.interactionSequence = value.interactionSequence
        self.surface = value.surface
    }

    init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(BridgeTelemetryCompactSample.SampleType.self, forKey: .type)
        self.stage = try container.decode(BridgeTelemetryLifecycleStage.self, forKey: .stage)
        self.timestampMilliseconds = try container.decode(Double.self, forKey: .timestampMilliseconds)
        self.attemptId = try container.decode(String.self, forKey: .attemptId)
        self.interactionSequence = try container.decode(Int.self, forKey: .interactionSequence)
        self.surface = try container.decode(BridgeTelemetrySurface.self, forKey: .surface)
        guard type == .lifecycle else { throw Self.invalidType(decoder) }
        try Self.validateCorrelation(
            timestampMilliseconds: timestampMilliseconds,
            attemptId: attemptId,
            interactionSequence: interactionSequence,
            codingPath: decoder.codingPath
        )
    }

    var compactValue: BridgeTelemetryLifecycleCompactSample {
        .init(
            stage: stage,
            timestampMilliseconds: timestampMilliseconds,
            attemptId: attemptId,
            interactionSequence: interactionSequence,
            surface: surface
        )
    }

    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case type, stage, timestampMilliseconds, attemptId, interactionSequence, surface
    }
}

private struct DurationWire: CompactSampleWireContract {
    let type: BridgeTelemetryCompactSample.SampleType
    let metric: BridgeTelemetryDurationMetric
    let durationMilliseconds: Double
    let timestampMilliseconds: Double
    let attemptId: String
    let interactionSequence: Int
    let surface: BridgeTelemetrySurface

    init(value: BridgeTelemetryDurationCompactSample) {
        self.type = .duration
        self.metric = value.metric
        self.durationMilliseconds = value.durationMilliseconds
        self.timestampMilliseconds = value.timestampMilliseconds
        self.attemptId = value.attemptId
        self.interactionSequence = value.interactionSequence
        self.surface = value.surface
    }

    init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(BridgeTelemetryCompactSample.SampleType.self, forKey: .type)
        self.metric = try container.decode(BridgeTelemetryDurationMetric.self, forKey: .metric)
        self.durationMilliseconds = try container.decode(Double.self, forKey: .durationMilliseconds)
        self.timestampMilliseconds = try container.decode(Double.self, forKey: .timestampMilliseconds)
        self.attemptId = try container.decode(String.self, forKey: .attemptId)
        self.interactionSequence = try container.decode(Int.self, forKey: .interactionSequence)
        self.surface = try container.decode(BridgeTelemetrySurface.self, forKey: .surface)
        guard type == .duration else { throw Self.invalidType(decoder) }
        try Self.validateCorrelation(
            timestampMilliseconds: timestampMilliseconds,
            attemptId: attemptId,
            interactionSequence: interactionSequence,
            codingPath: decoder.codingPath
        )
        try BridgeTelemetryContractValidation.validateNonnegativeFinite(
            durationMilliseconds,
            codingPath: decoder.codingPath
        )
    }

    var compactValue: BridgeTelemetryDurationCompactSample {
        .init(
            metric: metric,
            durationMilliseconds: durationMilliseconds,
            timestampMilliseconds: timestampMilliseconds,
            attemptId: attemptId,
            interactionSequence: interactionSequence,
            surface: surface
        )
    }

    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case type, metric, durationMilliseconds, timestampMilliseconds
        case attemptId, interactionSequence, surface
    }
}

private struct FailureWire: CompactSampleWireContract {
    let type: BridgeTelemetryCompactSample.SampleType
    let failure: BridgeTelemetryFailureKind
    let timestampMilliseconds: Double
    let attemptId: String
    let interactionSequence: Int
    let surface: BridgeTelemetrySurface

    init(value: BridgeTelemetryFailureCompactSample) {
        self.type = .failure
        self.failure = value.failure
        self.timestampMilliseconds = value.timestampMilliseconds
        self.attemptId = value.attemptId
        self.interactionSequence = value.interactionSequence
        self.surface = value.surface
    }

    init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(BridgeTelemetryCompactSample.SampleType.self, forKey: .type)
        self.failure = try container.decode(BridgeTelemetryFailureKind.self, forKey: .failure)
        self.timestampMilliseconds = try container.decode(Double.self, forKey: .timestampMilliseconds)
        self.attemptId = try container.decode(String.self, forKey: .attemptId)
        self.interactionSequence = try container.decode(Int.self, forKey: .interactionSequence)
        self.surface = try container.decode(BridgeTelemetrySurface.self, forKey: .surface)
        guard type == .failure else { throw Self.invalidType(decoder) }
        try Self.validateCorrelation(
            timestampMilliseconds: timestampMilliseconds,
            attemptId: attemptId,
            interactionSequence: interactionSequence,
            codingPath: decoder.codingPath
        )
    }

    var compactValue: BridgeTelemetryFailureCompactSample {
        .init(
            failure: failure,
            timestampMilliseconds: timestampMilliseconds,
            attemptId: attemptId,
            interactionSequence: interactionSequence,
            surface: surface
        )
    }

    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case type, failure, timestampMilliseconds, attemptId, interactionSequence, surface
    }
}

private struct IntegrityWire: CompactSampleWireContract {
    let type: BridgeTelemetryCompactSample.SampleType
    let failure: BridgeTelemetryIntegrityFailure
    let timestampMilliseconds: Double

    init(value: BridgeTelemetryIntegrityCompactSample) {
        self.type = .integrity
        self.failure = value.failure
        self.timestampMilliseconds = value.timestampMilliseconds
    }

    init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(BridgeTelemetryCompactSample.SampleType.self, forKey: .type)
        self.failure = try container.decode(BridgeTelemetryIntegrityFailure.self, forKey: .failure)
        self.timestampMilliseconds = try container.decode(Double.self, forKey: .timestampMilliseconds)
        guard type == .integrity else { throw Self.invalidType(decoder) }
        try BridgeTelemetryContractValidation.validateNonnegativeFinite(
            timestampMilliseconds,
            codingPath: decoder.codingPath
        )
    }

    var compactValue: BridgeTelemetryIntegrityCompactSample {
        .init(failure: failure, timestampMilliseconds: timestampMilliseconds)
    }

    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case type, failure, timestampMilliseconds
    }
}

private struct DiagnosticWire: CompactSampleWireContract {
    let type: BridgeTelemetryCompactSample.SampleType
    let code: BridgeTelemetryDiagnosticCode
    let timestampMilliseconds: Double
    let value: Double

    init(value: BridgeTelemetryDiagnosticCompactSample) {
        self.type = .diagnostic
        self.code = value.code
        self.timestampMilliseconds = value.timestampMilliseconds
        self.value = value.value
    }

    init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(BridgeTelemetryCompactSample.SampleType.self, forKey: .type)
        self.code = try container.decode(BridgeTelemetryDiagnosticCode.self, forKey: .code)
        self.timestampMilliseconds = try container.decode(Double.self, forKey: .timestampMilliseconds)
        self.value = try container.decode(Double.self, forKey: .value)
        guard type == .diagnostic, value.isFinite else { throw Self.invalidType(decoder) }
        try BridgeTelemetryContractValidation.validateNonnegativeFinite(
            timestampMilliseconds,
            codingPath: decoder.codingPath
        )
    }

    var compactValue: BridgeTelemetryDiagnosticCompactSample {
        .init(code: code, timestampMilliseconds: timestampMilliseconds, value: value)
    }

    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case type, code, timestampMilliseconds, value
    }
}

private struct EventWire: CompactSampleWireContract {
    let type: BridgeTelemetryCompactSample.SampleType
    let timestampMilliseconds: Double
    let sample: StrictLegacySample

    init(type: BridgeTelemetryCompactSample.SampleType, value: BridgeTelemetryEventCompactSample) {
        self.type = type
        self.timestampMilliseconds = value.timestampMilliseconds
        self.sample = StrictLegacySample(value.sample)
    }

    init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(BridgeTelemetryCompactSample.SampleType.self, forKey: .type)
        self.timestampMilliseconds = try container.decode(Double.self, forKey: .timestampMilliseconds)
        self.sample = try container.decode(StrictLegacySample.self, forKey: .sample)
        guard type == .requiredEvent || type == .optionalEvent else { throw Self.invalidType(decoder) }
        try BridgeTelemetryContractValidation.validateNonnegativeFinite(
            timestampMilliseconds,
            codingPath: decoder.codingPath
        )
    }

    var compactValue: BridgeTelemetryEventCompactSample {
        .init(timestampMilliseconds: timestampMilliseconds, sample: sample.value)
    }

    fileprivate enum CodingKeys: String, CodingKey, CaseIterable {
        case type, timestampMilliseconds, sample
    }
}

private struct StrictLegacySample: Codable {
    let value: BridgeTelemetrySample

    init(_ value: BridgeTelemetrySample) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge telemetry event sample"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let duration = try BridgeProductContractDecoding.decodeRequiredNullable(
            Double.self,
            forKey: .durationMilliseconds,
            from: container,
            codingPath: decoder.codingPath
        )
        if let duration {
            try BridgeTelemetryContractValidation.validateNonnegativeFinite(
                duration,
                codingPath: decoder.codingPath
            )
        }
        let strictTraceContext = try BridgeProductContractDecoding.decodeRequiredNullable(
            StrictTraceContext.self,
            forKey: .traceContext,
            from: container,
            codingPath: decoder.codingPath
        )
        let name = try container.decode(String.self, forKey: .name)
        guard !name.isEmpty else {
            throw BridgeTelemetryContractValidation.invalidValue("Empty event name", codingPath: decoder.codingPath)
        }
        self.value = BridgeTelemetrySample(
            scope: try container.decode(BridgeTelemetryScope.self, forKey: .scope),
            name: name,
            durationMilliseconds: duration,
            traceContext: strictTraceContext?.value,
            stringAttributes: try container.decode([String: String].self, forKey: .stringAttributes),
            numericAttributes: try container.decode([String: Double].self, forKey: .numericAttributes),
            booleanAttributes: try container.decode([String: Bool].self, forKey: .booleanAttributes)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.scope, forKey: .scope)
        try container.encode(value.name, forKey: .name)
        try container.encode(value.durationMilliseconds, forKey: .durationMilliseconds)
        try container.encode(value.traceContext, forKey: .traceContext)
        try container.encode(value.stringAttributes, forKey: .stringAttributes)
        try container.encode(value.numericAttributes, forKey: .numericAttributes)
        try container.encode(value.booleanAttributes, forKey: .booleanAttributes)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scope, name, durationMilliseconds, traceContext
        case stringAttributes, numericAttributes, booleanAttributes
    }
}

private struct StrictTraceContext: Codable {
    let value: BridgeTraceContext

    init(from decoder: Decoder) throws {
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "Bridge telemetry trace context"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try BridgeTraceContext(
            traceId: container.decode(String.self, forKey: .traceId),
            spanId: container.decode(String.self, forKey: .spanId),
            parentSpanId: BridgeProductContractDecoding.decodeRequiredNullable(
                String.self,
                forKey: .parentSpanId,
                from: container,
                codingPath: decoder.codingPath
            ),
            sampled: container.decode(Bool.self, forKey: .sampled)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.traceId, forKey: .traceId)
        try container.encode(value.spanId, forKey: .spanId)
        try container.encode(value.parentSpanId, forKey: .parentSpanId)
        try container.encode(value.sampled, forKey: .sampled)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case traceId, spanId, parentSpanId, sampled
    }
}

private protocol CompactSampleWireContract: Codable {
    associatedtype CodingKeys: CodingKey, CaseIterable
}

extension CompactSampleWireContract {
    fileprivate static func rejectUnknownKeys(from decoder: Decoder) throws {
        let codingKeys = Self.CodingKeys.allCases
        try BridgeTelemetryContractValidation.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(codingKeys.map(\.stringValue)),
            contract: "Bridge telemetry compact sample"
        )
    }

    fileprivate static func validateCorrelation(
        timestampMilliseconds: Double,
        attemptId: String,
        interactionSequence: Int,
        codingPath: [any CodingKey]
    ) throws {
        try BridgeTelemetryContractValidation.validateNonnegativeFinite(
            timestampMilliseconds,
            codingPath: codingPath
        )
        try BridgeTelemetryContractValidation.validateIdentifier(attemptId, codingPath: codingPath)
        try BridgeTelemetryContractValidation.validatePositive(interactionSequence, codingPath: codingPath)
    }

    fileprivate static func invalidType(_ decoder: Decoder) -> DecodingError {
        BridgeTelemetryContractValidation.invalidValue(
            "Invalid Bridge telemetry compact sample type",
            codingPath: decoder.codingPath
        )
    }
}
