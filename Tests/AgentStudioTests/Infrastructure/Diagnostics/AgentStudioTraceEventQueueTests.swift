import Foundation
import Testing

@testable import AgentStudio

@Suite("AgentStudio trace event queue")
struct AgentStudioTraceEventQueueTests {
    @Test("flush makes queued records visible without closing the queue")
    func flushMakesQueuedRecordsVisibleWithoutClosingQueue() async throws {
        let traceRuntime = makeTraceRuntime()
        let queue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        let outputFileURL = try #require(traceRuntime.outputFileURL)

        queue.record(tag: .inbox, body: "trace.queue.first", attributes: [:])
        try await queue.flush()

        let firstContents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(firstContents.contains("\"body\":\"trace.queue.first\""))

        queue.record(tag: .inbox, body: "trace.queue.second", attributes: [:])
        try await queue.flush()

        let secondContents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(secondContents.contains("\"body\":\"trace.queue.first\""))
        #expect(secondContents.contains("\"body\":\"trace.queue.second\""))

        queue.cancel()
    }

    private func makeTraceRuntime() -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": "trace-event-queue",
                "AGENTSTUDIO_TRACE_TAGS": "inbox",
            ]),
            processIdentifier: 620,
            sessionID: "trace-event-queue-session",
            timeUnixNano: { 6200 }
        )
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-trace-event-queue-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
