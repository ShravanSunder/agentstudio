import Foundation

struct AgentStudioTracePreferenceLayer: Equatable, Sendable {
    let enabled: Bool?
    let traceTags: String?
    let traceBackend: String?
    let traceFlush: String?
    let otlpEndpoint: String?

    static func invalidSemanticField(in observability: [String: Any]) -> String? {
        if let invalidTraceTags = invalidTraceTags(in: observability["traceTags"]) {
            return invalidTraceTags
        }
        if let invalidTraceBackend = invalidTraceBackend(in: observability["traceBackend"]) {
            return invalidTraceBackend
        }
        if let invalidTraceFlush = invalidTraceFlush(in: observability["traceFlush"]) {
            return invalidTraceFlush
        }
        return nil
    }

    static func rejectedOTLPEndpointSelector(_ rawValue: String?) -> String? {
        guard let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedValue.isEmpty else {
            return nil
        }

        guard let endpointURL = URL(string: trimmedValue), isLoopbackHTTPEndpoint(endpointURL) else {
            return trimmedValue
        }
        return nil
    }

    private static func invalidTraceTags(in rawValue: Any?) -> String? {
        guard let rawString = rawValue as? String else { return nil }
        let selection = AgentStudioTraceTag.parseSelection(rawString)
        return selection.unknownSelectors.isEmpty ? nil : "observability.traceTags"
    }

    private static func invalidTraceBackend(in rawValue: Any?) -> String? {
        guard let rawString = rawValue as? String else { return nil }
        let normalizedValue = rawString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedValue.isEmpty else { return nil }
        let allowedValues: Set<String> = ["jsonl", "otlp", "both"]
        return allowedValues.contains(normalizedValue) ? nil : "observability.traceBackend"
    }

    private static func invalidTraceFlush(in rawValue: Any?) -> String? {
        guard let rawString = rawValue as? String else { return nil }
        let normalizedValue = rawString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedValue.isEmpty else { return nil }
        let allowedValues: Set<String> = ["buffered", "immediate"]
        return allowedValues.contains(normalizedValue) ? nil : "observability.traceFlush"
    }

    private static func isLoopbackHTTPEndpoint(_ url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "http",
            let host = url.host(percentEncoded: false)?.lowercased()
        else { return false }

        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
