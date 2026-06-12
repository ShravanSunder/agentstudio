import Foundation

actor AgentStudioJSONLTraceSink: AgentStudioTraceSink {
    private let writer: AgentStudioJSONLTraceWriter

    init(context: AgentStudioJSONLTraceSinkContext) {
        self.writer = AgentStudioJSONLTraceWriter(
            fileURL: context.fileURL,
            retainedLineLimit: context.retainedLineLimit,
            timeUnixNano: context.timeUnixNano
        )
    }

    func record(_ record: AgentStudioTraceRecord) async throws {
        try await writer.append(record)
    }

    func flush() async throws {
        try await writer.flush()
    }

    func shutdown() async throws {
        try await flush()
    }

    func diagnostics() async -> AgentStudioTraceWriterDiagnostics {
        await writer.diagnostics()
    }
}
