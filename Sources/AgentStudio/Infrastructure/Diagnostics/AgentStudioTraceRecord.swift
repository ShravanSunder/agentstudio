import Foundation

enum AgentStudioTraceSeverity: String, Encodable, Equatable, Sendable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

struct AgentStudioTraceRecord: Encodable, Equatable, Sendable {
    struct Scope: Encodable, Equatable, Sendable {
        let name: String
        let version: String
    }

    let timeUnixNano: UInt64
    let severityText: AgentStudioTraceSeverity
    let body: String
    let traceID: String?
    let spanID: String?
    let parentSpanID: String?
    let resource: [String: String]
    let scope: Scope
    let attributes: [String: AgentStudioTraceValue]

    enum CodingKeys: String, CodingKey {
        case attributes
        case body
        case parentSpanID = "parent_span_id"
        case resource
        case scope
        case severityText = "severity_text"
        case spanID = "span_id"
        case timeUnixNano = "time_unix_nano"
        case traceID = "trace_id"
    }
}

enum AgentStudioTraceValue: Encodable, Equatable, Sendable {
    case bool(Bool)
    case double(Double)
    case int(Int)
    case string(String)
    case stringArray([String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .stringArray(let value):
            try container.encode(value)
        }
    }
}
