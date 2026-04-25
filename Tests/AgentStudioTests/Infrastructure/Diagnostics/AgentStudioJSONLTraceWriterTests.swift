import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioJSONLTraceWriterTests {
    @Test
    func flushWritesBufferedRecordsToFile() async throws {
        let fileURL = temporaryTraceFileURL()
        let writer = AgentStudioJSONLTraceWriter(fileURL: fileURL)

        try await writer.append(traceRecord(body: "drag.begin", sequence: 1))
        try await writer.append(traceRecord(body: "drag.end", sequence: 2))
        try await writer.flush()

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0].contains("\"body\":\"drag.begin\""))
        #expect(lines[1].contains("\"body\":\"drag.end\""))
    }

    @Test
    func flushAppendsAfterPreviousFlush() async throws {
        let fileURL = temporaryTraceFileURL()
        let writer = AgentStudioJSONLTraceWriter(fileURL: fileURL)

        try await writer.append(traceRecord(body: "drag.begin", sequence: 1))
        try await writer.flush()
        try await writer.append(traceRecord(body: "drag.end", sequence: 2))
        try await writer.flush()

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0].contains("\"body\":\"drag.begin\""))
        #expect(lines[1].contains("\"body\":\"drag.end\""))
    }

    @Test
    func retainedLineLimitDropsOldestBufferedRecords() async throws {
        let fileURL = temporaryTraceFileURL()
        let writer = AgentStudioJSONLTraceWriter(fileURL: fileURL, retainedLineLimit: 2)

        try await writer.append(traceRecord(body: "drag.one", sequence: 1))
        try await writer.append(traceRecord(body: "drag.two", sequence: 2))
        try await writer.append(traceRecord(body: "drag.three", sequence: 3))
        try await writer.flush()

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(await writer.droppedLineCount == 1)
        #expect(lines.count == 2)
        #expect(!lines.contains { $0.contains("\"body\":\"drag.one\"") })
        #expect(lines[0].contains("\"body\":\"drag.two\""))
        #expect(lines[1].contains("\"body\":\"drag.three\""))
    }

    private func temporaryTraceFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-trace-writer-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).jsonl")
    }

    private func traceRecord(body: String, sequence: Int) -> AgentStudioTraceRecord {
        AgentStudioTraceRecord(
            timeUnixNano: UInt64(sequence),
            severityText: "INFO",
            body: body,
            traceID: "trace-1",
            spanID: "span-\(sequence)",
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.drag", version: "0.1.0"),
            attributes: [
                "agentstudio.trace.tag": .string("drag"),
                "drag.sequence": .int(sequence),
            ]
        )
    }
}
