enum BridgeTelemetryDropReason: String, CaseIterable, Codable, Equatable, Sendable {
    case decodingFailed
    case disabledScope
    case encodedBatchTooLarge
    case invalidDuration
    case invalidTraceContext
    case queueSaturated
    case tooManySamples
    case unsafeAttribute
    case unsafeEventName
    case unsupportedSchemaVersion
}
