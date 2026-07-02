import Foundation

enum GlobalPreferencesStartupTelemetry {
    static func recordLoaded(
        _ result: GlobalPreferencesLoadResult,
        recorder: AgentStudioStartupTraceRecorder
    ) {
        var attributes = result.safeStartupAttributes
        attributes["agentstudio.preferences.global.load_elapsed_ms"] = .double(result.elapsedMilliseconds)

        recorder.recordAppStartup(
            "app.preferences.global.loaded",
            phase: "global_preferences",
            outcome: result.status.safeTelemetryStatus,
            attributes: attributes
        )
    }
}

extension GlobalPreferencesLoadResult {
    fileprivate var safeStartupAttributes: [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.preferences.global.status": .string(status.safeTelemetryStatus)
        ]

        if let schemaVersion = status.safeTelemetrySchemaVersion {
            attributes["agentstudio.preferences.global.schema_version"] = .int(schemaVersion)
        }

        if case .loaded(let preferences) = status {
            attributes["agentstudio.preferences.global.observability_enabled"] = .bool(preferences.enabled)
        }

        return attributes
    }
}

extension GlobalPreferencesLoadStatus {
    fileprivate var safeTelemetryStatus: String {
        switch self {
        case .missing:
            "missing"
        case .loaded:
            "loaded"
        case .invalidMalformedJSON:
            "invalid_malformed_json"
        case .invalidUnsupportedSchema:
            "invalid_unsupported_schema"
        case .invalidOversized:
            "invalid_oversized"
        case .invalidField:
            "invalid_field"
        case .invalidEndpoint:
            "invalid_endpoint"
        case .readFailed:
            "read_failed"
        }
    }

    fileprivate var safeTelemetrySchemaVersion: Int? {
        switch self {
        case .loaded:
            1
        case .invalidUnsupportedSchema(let schemaVersion):
            schemaVersion
        case .missing, .invalidMalformedJSON, .invalidOversized, .invalidField, .invalidEndpoint, .readFailed:
            nil
        }
    }
}
