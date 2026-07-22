enum BridgeTelemetryEventValidationResult: Equatable, Sendable {
    case accepted
    case dropped(BridgeTelemetryDropReason)
}

struct BridgeTelemetryEventValidator: Sendable {
    private let scopeGate: BridgeTelemetryScopeGate

    init(scopeGate: BridgeTelemetryScopeGate) {
        self.scopeGate = scopeGate
    }

    func validate(_ sample: BridgeTelemetrySample) -> BridgeTelemetryEventValidationResult {
        guard sample.scope == .web, scopeGate.isEnabled(sample.scope) else {
            return .dropped(.disabledScope)
        }
        guard Self.allowedEventNames.contains(sample.name) else {
            return .dropped(.unsafeEventName)
        }
        if let durationMilliseconds = sample.durationMilliseconds {
            guard durationMilliseconds.isFinite, durationMilliseconds >= 0 else {
                return .dropped(.invalidDuration)
            }
        }
        guard Self.attributesAreSafe(sample), Self.attributesMatchEventContract(sample) else {
            return .dropped(.unsafeAttribute)
        }
        return .accepted
    }
}

extension BridgeTelemetryEventValidator {
    static let unknownRejectedEventName = "unknown"

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
            let expectedStringKeys = BridgeTelemetryEventValidator.requiredStringAttributeKeys
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
            stringKeys == BridgeTelemetryEventValidator.requiredStringAttributeKeys
                && numericKeys.isEmpty
                && booleanKeys.isEmpty
        }
    }
}
