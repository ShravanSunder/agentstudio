package struct AgentStudioOTLPProjectedLogRecord: Equatable, Sendable {
    let timeUnixNano: UInt64
    let severityText: AgentStudioTraceSeverity
    let body: String
    let traceID: String?
    let spanID: String?
    let parentSpanID: String?
    let resource: [String: String]
    let scope: AgentStudioTraceRecord.Scope
    package let attributes: [String: AgentStudioTraceValue]
}
