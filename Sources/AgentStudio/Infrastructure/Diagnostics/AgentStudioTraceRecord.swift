import Foundation

package enum AgentStudioTraceSeverity: String, Encodable, Equatable, Sendable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

package struct AgentStudioTraceRecord: Encodable, Equatable, Sendable {
    package struct Scope: Encodable, Equatable, Sendable {
        let name: String
        let version: String

        package init(name: String, version: String) {
            self.name = name
            self.version = version
        }
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

    package init(
        timeUnixNano: UInt64,
        severityText: AgentStudioTraceSeverity,
        body: String,
        traceID: String?,
        spanID: String?,
        parentSpanID: String?,
        resource: [String: String],
        scope: Scope,
        attributes: [String: AgentStudioTraceValue]
    ) {
        self.timeUnixNano = timeUnixNano
        self.severityText = severityText
        self.body = body
        self.traceID = traceID
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.resource = resource
        self.scope = scope
        self.attributes = attributes
    }

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

package enum AgentStudioTraceValue: Encodable, Equatable, Sendable {
    case bool(Bool)
    case double(Double)
    case int(Int)
    case string(String)
    case stringArray([String])

    package func encode(to encoder: Encoder) throws {
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
