enum BridgeTelemetryDropReason: String, CaseIterable, Codable, Equatable, Sendable {
    case decodingFailed = "decoding_failed"
    case disabledScope = "disabled_scope"
    case encodedBatchTooLarge = "encoded_batch_too_large"
    case invalidDuration = "invalid_duration"
    case invalidTraceContext = "invalid_trace_context"
    case queueSaturated = "queue_saturated"
    case tooManySamples = "too_many_samples"
    case unsafeAttribute = "unsafe_attribute"
    case unsafeEventName = "unsafe_event_name"
    case unsupportedSchemaVersion = "unsupported_schema_version"
}
