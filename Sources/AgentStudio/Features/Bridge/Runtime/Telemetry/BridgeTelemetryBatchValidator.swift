import Foundation

enum BridgeTelemetryBatchValidationResult: Equatable, Sendable {
    case accepted(BridgeTelemetryBatch)
    case dropped(BridgeTelemetryDropReason)
}

struct BridgeTelemetryBatchValidationOutcome: Equatable, Sendable {
    let result: BridgeTelemetryBatchValidationResult
    let firstRejectedEventName: String?
}

private struct BridgeTelemetryBatchSequenceValidationFailure: Equatable, Sendable {
    let reason: BridgeTelemetryDropReason
    let firstRejectedEventName: String?
}

struct BridgeTelemetryBatchValidator: Sendable {
    private let scopeGate: BridgeTelemetryScopeGate
    private let decoder: JSONDecoder
    private let sequenceState = BridgeTelemetryBatchSequenceState()

    init(scopeGate: BridgeTelemetryScopeGate, decoder: JSONDecoder = JSONDecoder()) {
        self.scopeGate = scopeGate
        self.decoder = decoder
    }

    func decodeAndValidate(_ data: Data) -> BridgeTelemetryBatchValidationResult {
        decodeAndValidateWithDetails(data).result
    }

    func decodeAndValidateWithDetails(_ data: Data) -> BridgeTelemetryBatchValidationOutcome {
        guard data.count <= BridgeTelemetryLimits.maxEncodedBatchBytes else {
            return Self.dropped(.encodedBatchTooLarge)
        }

        do {
            return try validateWithDetails(decoder.decode(BridgeTelemetryBatch.self, from: data))
        } catch is BridgeTraceContext.ValidationError {
            return Self.dropped(.invalidTraceContext)
        } catch {
            return Self.dropped(.decodingFailed)
        }
    }

    func validate(_ batch: BridgeTelemetryBatch) -> BridgeTelemetryBatchValidationResult {
        validateWithDetails(batch).result
    }

    func validateWithDetails(_ batch: BridgeTelemetryBatch) -> BridgeTelemetryBatchValidationOutcome {
        guard batch.schemaVersion == 1 else {
            return Self.dropped(.unsupportedSchemaVersion)
        }
        guard batch.samples.count <= BridgeTelemetryLimits.maxSamplesPerBatch else {
            return Self.dropped(.tooManySamples)
        }
        guard Self.isSafeControlledString(batch.scenario) else {
            return Self.dropped(.unsafeAttribute)
        }
        guard Self.isSafeControlledString(batch.streamId.rawValue) else {
            return Self.dropped(.unsafeAttribute)
        }
        if let sequenceFailure = sequenceState.validateSequence(batch) {
            return Self.dropped(
                sequenceFailure.reason,
                firstRejectedEventName: sequenceFailure.firstRejectedEventName
            )
        }
        if Self.hasRequiredEventShedCounter(batch) {
            return Self.dropped(
                .requiredEventShed,
                firstRejectedEventName: Self.firstAllowedEventName(in: batch)
            )
        }

        for sample in batch.samples {
            guard sample.scope == .web else {
                return Self.dropped(.disabledScope, sample: sample)
            }
            guard scopeGate.isEnabled(sample.scope) else {
                return Self.dropped(.disabledScope, sample: sample)
            }
            guard Self.allowedEventNames.contains(sample.name) else {
                return Self.dropped(.unsafeEventName, sample: sample)
            }
            if let durationMilliseconds = sample.durationMilliseconds {
                guard durationMilliseconds.isFinite, durationMilliseconds >= 0 else {
                    return Self.dropped(.invalidDuration, sample: sample)
                }
            }
            guard Self.attributesAreSafe(sample) else {
                return Self.dropped(.unsafeAttribute, sample: sample)
            }
            guard Self.attributesMatchEventContract(sample) else {
                return Self.dropped(.unsafeAttribute, sample: sample)
            }
        }

        return BridgeTelemetryBatchValidationOutcome(
            result: .accepted(batch),
            firstRejectedEventName: nil
        )
    }
}

private final class BridgeTelemetryBatchSequenceState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSequenceByStreamId: [BridgeTelemetryStreamId: Int] = [:]

    func validateSequence(_ batch: BridgeTelemetryBatch) -> BridgeTelemetryBatchSequenceValidationFailure? {
        guard let sequence = batch.sequence else {
            return nil
        }
        return lock.withLock {
            let streamId = batch.streamId
            guard let previousSequence = lastSequenceByStreamId[streamId] else {
                lastSequenceByStreamId[streamId] = sequence
                return nil
            }
            let expectedSequence = previousSequence + 1
            guard sequence > expectedSequence else {
                lastSequenceByStreamId[streamId] = max(sequence, previousSequence)
                return nil
            }
            if BridgeTelemetryBatchValidator.hasRequiredEventShedCounter(batch) {
                return BridgeTelemetryBatchSequenceValidationFailure(
                    reason: .requiredEventShed,
                    firstRejectedEventName: BridgeTelemetryBatchValidator.firstAllowedEventName(in: batch)
                )
            }
            let missingCount = sequence - expectedSequence
            guard Self.hasMatchingDropCounter(batch, missingCount: missingCount) else {
                return BridgeTelemetryBatchSequenceValidationFailure(
                    reason: .missingDropCounter,
                    firstRejectedEventName: BridgeTelemetryBatchValidator.firstAllowedEventName(in: batch)
                )
            }
            lastSequenceByStreamId[streamId] = sequence
            return nil
        }
    }

    private static func hasMatchingDropCounter(_ batch: BridgeTelemetryBatch, missingCount: Int) -> Bool {
        batch.samples.contains { sample in
            sample.name == "performance.bridge.web.telemetry_drop"
                && sample.stringAttributes["agentstudio.bridge.telemetry.drop_reason"]
                    == BridgeTelemetryDropReason.encodedByteCap.rawValue
                && Int(sample.numericAttributes["agentstudio.bridge.telemetry.dropped_count"] ?? 0)
                    >= missingCount
        }
    }
}

extension BridgeTelemetryBatchValidator {
    static let unknownRejectedEventName = "unknown"

    private static func dropped(
        _ reason: BridgeTelemetryDropReason,
        sample: BridgeTelemetrySample? = nil,
        firstRejectedEventName explicitFirstRejectedEventName: String? = nil
    ) -> BridgeTelemetryBatchValidationOutcome {
        BridgeTelemetryBatchValidationOutcome(
            result: .dropped(reason),
            firstRejectedEventName: explicitFirstRejectedEventName ?? firstRejectedEventName(for: sample)
        )
    }

    fileprivate static func firstAllowedEventName(in batch: BridgeTelemetryBatch) -> String {
        guard let sample = batch.samples.first else {
            return unknownRejectedEventName
        }
        return firstRejectedEventName(for: sample)
    }

    fileprivate static func hasRequiredEventShedCounter(_ batch: BridgeTelemetryBatch) -> Bool {
        batch.samples.contains { sample in
            sample.name == "performance.bridge.web.telemetry_drop"
                && sample.stringAttributes["agentstudio.bridge.telemetry.drop_reason"]
                    == BridgeTelemetryDropReason.requiredEventShed.rawValue
                && Int(sample.numericAttributes["agentstudio.bridge.telemetry.dropped_count"] ?? 0) > 0
        }
    }

    private static func firstRejectedEventName(for sample: BridgeTelemetrySample?) -> String {
        guard let sample, allowedEventNames.contains(sample.name) else {
            return unknownRejectedEventName
        }
        return sample.name
    }

    private static func attributesAreSafe(_ sample: BridgeTelemetrySample) -> Bool {
        guard requiredStringAttributeKeys.allSatisfy({ sample.stringAttributes[$0] != nil }) else {
            return false
        }
        for (key, value) in sample.stringAttributes {
            guard allowedStringValuesByAttributeKey[key]?.contains(value) == true else {
                return false
            }
        }
        for (key, value) in sample.numericAttributes {
            guard allowedNumericAttributeKeys.contains(key), value.isFinite else {
                return false
            }
        }
        for key in sample.booleanAttributes.keys {
            guard allowedBooleanAttributeKeys.contains(key) else {
                return false
            }
        }
        return true
    }

    struct BridgeTelemetryEventExpectation: Sendable {
        let phase: String
        let plane: BridgeTelemetryPlane
        let priority: BridgeTelemetryPriority
        let slice: BridgeTelemetrySlice
        let transport: String
        let attributeKeys: BridgeTelemetryEventAttributeKeys

        init(
            phase: String,
            plane: BridgeTelemetryPlane,
            priority: BridgeTelemetryPriority,
            slice: BridgeTelemetrySlice,
            transport: String,
            attributeKeys: BridgeTelemetryEventAttributeKeys = .commonOnly
        ) {
            self.phase = phase
            self.plane = plane
            self.priority = priority
            self.slice = slice
            self.transport = transport
            self.attributeKeys = attributeKeys
        }

        init(
            phase: String,
            plane: BridgeTelemetryPlane,
            priority: BridgeTelemetryPriority,
            slice: BridgeTelemetrySlice,
            transport: String,
            additionalStringKeys: Set<String>
        ) {
            self.init(
                phase: phase,
                plane: plane,
                priority: priority,
                slice: slice,
                transport: transport,
                attributeKeys: .init(additionalStringKeys: additionalStringKeys)
            )
        }
    }

    struct BridgeTelemetryEventAttributeKeys: Sendable {
        static let commonOnly = Self()

        let additionalStringKeys: Set<String>
        let numericKeys: Set<String>
        let booleanKeys: Set<String>

        init(
            additionalStringKeys: Set<String> = [],
            numericKeys: Set<String> = [],
            booleanKeys: Set<String> = []
        ) {
            self.additionalStringKeys = additionalStringKeys
            self.numericKeys = numericKeys
            self.booleanKeys = booleanKeys
        }
    }

    struct BridgeTelemetryEventContract: Sendable {
        let phase: String
        let plane: BridgeTelemetryPlane
        let priority: BridgeTelemetryPriority
        let slice: BridgeTelemetrySlice
        let transport: String
        let stringKeys: Set<String>
        let numericKeys: Set<String>
        let booleanKeys: Set<String>

        init?(sample: BridgeTelemetrySample) {
            guard let phase = sample.stringAttributes["agentstudio.bridge.phase"],
                let planeValue = sample.stringAttributes["agentstudio.bridge.plane"],
                let plane = BridgeTelemetryPlane(rawValue: planeValue),
                let priorityValue = sample.stringAttributes["agentstudio.bridge.priority"],
                let priority = BridgeTelemetryPriority(rawValue: priorityValue),
                let sliceValue = sample.stringAttributes["agentstudio.bridge.slice"],
                let slice = BridgeTelemetrySlice(rawValue: sliceValue),
                let transport = sample.stringAttributes["agentstudio.bridge.transport"]
            else {
                return nil
            }

            self.phase = phase
            self.plane = plane
            self.priority = priority
            self.slice = slice
            self.transport = transport
            stringKeys = Set(sample.stringAttributes.keys)
            numericKeys = Set(sample.numericAttributes.keys)
            booleanKeys = Set(sample.booleanAttributes.keys)
        }

        func matches(_ expectation: BridgeTelemetryEventExpectation) -> Bool {
            let expectedStringKeys = BridgeTelemetryBatchValidator.requiredStringAttributeKeys
                .union(expectation.attributeKeys.additionalStringKeys)
            return phase == expectation.phase
                && plane == expectation.plane
                && priority == expectation.priority
                && slice == expectation.slice
                && transport == expectation.transport
                && stringKeys == expectedStringKeys
                && numericKeys == expectation.attributeKeys.numericKeys
                && booleanKeys == expectation.attributeKeys.booleanKeys
        }

        func hasOnlyCommonKeys() -> Bool {
            stringKeys == BridgeTelemetryBatchValidator.requiredStringAttributeKeys
                && numericKeys.isEmpty
                && booleanKeys.isEmpty
        }
    }

    static func isSafeControlledString(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
                || scalar == ":"
        }
    }
}
