package enum BridgeTelemetryWireSchema {
    package static let unknownRejectedEventName = "unknown"

    package static func dropReason(
        eventName: String,
        durationMilliseconds: Double?,
        stringAttributes: [String: String],
        numericAttributes: [String: Double],
        booleanAttributes: [String: Bool]
    ) -> BridgeTelemetryDropReason? {
        guard allowedEventNames.contains(eventName) else {
            return .unsafeEventName
        }
        if let durationMilliseconds {
            guard durationMilliseconds.isFinite, durationMilliseconds >= 0 else {
                return .invalidDuration
            }
        }
        guard
            attributesAreSafe(
                stringAttributes: stringAttributes,
                numericAttributes: numericAttributes,
                booleanAttributes: booleanAttributes
            ),
            attributesMatchEventContract(
                eventName: eventName,
                stringAttributes: stringAttributes,
                numericAttributes: numericAttributes,
                booleanAttributes: booleanAttributes
            )
        else {
            return .unsafeAttribute
        }
        return nil
    }

    package static func allowedStringValues(for key: String) -> Set<String>? {
        allowedStringValuesByAttributeKey[key]
    }

    package static func hasCompleteTaxonomy(stringAttributes: [String: String]) -> Bool {
        stringAttributes["agentstudio.bridge.phase"] != nil
            && BridgeTelemetryPlane(rawValue: stringAttributes["agentstudio.bridge.plane"] ?? "") != nil
            && BridgeTelemetryPriority(rawValue: stringAttributes["agentstudio.bridge.priority"] ?? "") != nil
            && BridgeTelemetrySlice(rawValue: stringAttributes["agentstudio.bridge.slice"] ?? "") != nil
    }

    private static func attributesAreSafe(
        stringAttributes: [String: String],
        numericAttributes: [String: Double],
        booleanAttributes: [String: Bool]
    ) -> Bool {
        guard requiredStringAttributeKeys.allSatisfy({ stringAttributes[$0] != nil }) else {
            return false
        }
        for (key, value) in stringAttributes {
            let isAllowedOperationID =
                key == "agentstudio.bridge.operation.id"
                && value.count == 64
                && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            guard isAllowedOperationID || allowedStringValuesByAttributeKey[key]?.contains(value) == true else {
                return false
            }
        }
        for (key, value) in numericAttributes {
            let isSafeStageAttempt =
                key == "agentstudio.bridge.stage.attempt"
                && value.isFinite
                && value >= 0
                && value.rounded(.towardZero) == value
                && value <= 9_007_199_254_740_991
            guard allowedNumericAttributeKeys.contains(key),
                value.isFinite,
                key != "agentstudio.bridge.stage.attempt" || isSafeStageAttempt
            else {
                return false
            }
        }
        for key in booleanAttributes.keys {
            guard allowedBooleanAttributeKeys.contains(key) else {
                return false
            }
        }
        return true
    }
}

extension BridgeTelemetryWireSchema {
    struct EventExpectation: Sendable {
        let phase: String
        let plane: BridgeTelemetryPlane
        let priority: BridgeTelemetryPriority
        let slice: BridgeTelemetrySlice
        let transport: String
        let attributeKeys: EventAttributeKeys

        init(
            phase: String,
            plane: BridgeTelemetryPlane,
            priority: BridgeTelemetryPriority,
            slice: BridgeTelemetrySlice,
            transport: String,
            attributeKeys: EventAttributeKeys = .commonOnly
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

    struct EventAttributeKeys: Sendable {
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

    struct EventContract: Sendable {
        let phase: String
        let plane: BridgeTelemetryPlane
        let priority: BridgeTelemetryPriority
        let slice: BridgeTelemetrySlice
        let transport: String
        let stringKeys: Set<String>
        let numericKeys: Set<String>
        let booleanKeys: Set<String>

        init?(
            stringAttributes: [String: String],
            numericAttributes: [String: Double],
            booleanAttributes: [String: Bool]
        ) {
            guard let phase = stringAttributes["agentstudio.bridge.phase"],
                let planeValue = stringAttributes["agentstudio.bridge.plane"],
                let plane = BridgeTelemetryPlane(rawValue: planeValue),
                let priorityValue = stringAttributes["agentstudio.bridge.priority"],
                let priority = BridgeTelemetryPriority(rawValue: priorityValue),
                let sliceValue = stringAttributes["agentstudio.bridge.slice"],
                let slice = BridgeTelemetrySlice(rawValue: sliceValue),
                let transport = stringAttributes["agentstudio.bridge.transport"]
            else {
                return nil
            }

            self.phase = phase
            self.plane = plane
            self.priority = priority
            self.slice = slice
            self.transport = transport
            stringKeys = Set(stringAttributes.keys)
            numericKeys = Set(numericAttributes.keys)
            booleanKeys = Set(booleanAttributes.keys)
        }

        func matches(_ expectation: EventExpectation) -> Bool {
            let expectedStringKeys = BridgeTelemetryWireSchema.requiredStringAttributeKeys
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
            stringKeys == BridgeTelemetryWireSchema.requiredStringAttributeKeys
                && numericKeys.isEmpty
                && booleanKeys.isEmpty
        }
    }
}
