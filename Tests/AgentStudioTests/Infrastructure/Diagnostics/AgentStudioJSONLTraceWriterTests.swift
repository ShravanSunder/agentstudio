import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioJSONLTraceWriterTests {
    @Test
    func flushWritesBufferedRecordsToFile() async throws {
        let fileURL = temporaryTraceFileURL()
        let writer = AgentStudioJSONLTraceWriter(fileURL: fileURL)

        try await writer.append(traceRecord(body: "runtime.begin", sequence: 1))
        try await writer.append(traceRecord(body: "runtime.end", sequence: 2))
        try await writer.flush()

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0].contains("\"body\":\"runtime.begin\""))
        #expect(lines[1].contains("\"body\":\"runtime.end\""))
    }

    @Test
    func flushAppendsAfterPreviousFlush() async throws {
        let fileURL = temporaryTraceFileURL()
        let writer = AgentStudioJSONLTraceWriter(fileURL: fileURL)

        try await writer.append(traceRecord(body: "runtime.begin", sequence: 1))
        try await writer.flush()
        try await writer.append(traceRecord(body: "runtime.end", sequence: 2))
        try await writer.flush()

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0].contains("\"body\":\"runtime.begin\""))
        #expect(lines[1].contains("\"body\":\"runtime.end\""))
    }

    @Test
    func retainedLineLimitDropsOldestBufferedRecords() async throws {
        let fileURL = temporaryTraceFileURL()
        let writer = AgentStudioJSONLTraceWriter(
            fileURL: fileURL,
            retainedLineLimit: 2,
            timeUnixNano: { 9999 }
        )

        try await writer.append(traceRecord(body: "runtime.one", sequence: 1))
        try await writer.append(traceRecord(body: "runtime.two", sequence: 2))
        try await writer.append(traceRecord(body: "runtime.three", sequence: 3))
        try await writer.flush()

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)

        #expect(await writer.droppedLineCount == 2)
        #expect(lines.count == 2)
        #expect(!lines.contains { $0.contains("\"body\":\"runtime.one\"") })
        #expect(!lines.contains { $0.contains("\"body\":\"runtime.two\"") })
        #expect(lines[0].contains("\"body\":\"trace.buffer_overflow\""))
        #expect(lines[0].contains("\"time_unix_nano\":9999"))
        #expect(lines[0].contains("\"agentstudio.trace.dropped_count\":2"))
        #expect(lines[1].contains("\"body\":\"runtime.three\""))
    }

    @Test
    func flushRotatesExistingFileWhenSizeLimitWouldBeExceeded() async throws {
        let fileURL = temporaryTraceFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "previous-line\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let writer = AgentStudioJSONLTraceWriter(fileURL: fileURL, maximumFileSizeBytes: 12)
        try await writer.append(traceRecord(body: "runtime.after-rotate", sequence: 1))
        try await writer.flush()

        let rotatedFileURL = fileURL.appendingPathExtension("1")
        let rotatedContents = try String(contentsOf: rotatedFileURL, encoding: .utf8)
        let currentContents = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(rotatedContents == "previous-line\n")
        #expect(currentContents.contains("\"body\":\"runtime.after-rotate\""))
    }

    private func temporaryTraceFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-trace-writer-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).jsonl")
    }

    private func traceRecord(body: String, sequence: Int) -> AgentStudioTraceRecord {
        AgentStudioTraceRecord(
            timeUnixNano: UInt64(sequence),
            severityText: .info,
            body: body,
            traceID: "trace-1",
            spanID: "span-\(sequence)",
            parentSpanID: nil,
            resource: [
                "service.name": "AgentStudio"
            ],
            scope: .init(name: "agentstudio.runtime", version: "0.1.0"),
            attributes: [
                "agentstudio.trace.tag": .string("runtime"),
                "agentstudio.runtime.sequence": .int(sequence),
            ]
        )
    }
}
