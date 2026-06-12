import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioPerformanceTraceRecorderTests {
    @Test
    func recorderEmitsPerformanceRecordsThroughTraceRuntime() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "perf-recorder",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 915,
            timeUnixNano: { 123 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.record(
            .gitStatusComputed,
            attributes: [
                "agentstudio.performance.git.running.count": .int(3),
                "agentstudio.performance.git.status.duration_ms": .double(1.5),
            ]
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.git.status\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"performance\""))
        #expect(contents.contains("\"agentstudio.performance.git.running.count\":3"))
        #expect(contents.contains("\"agentstudio.performance.git.status.duration_ms\":1.5"))
    }

    @Test
    func recorderStaysSilentWhenPerformanceTagIsDisabled() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 916,
            timeUnixNano: { 124 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.record(.gitStatusComputed)
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        #expect(!FileManager.default.fileExists(atPath: outputFileURL.path))
    }

    @Test
    func durationConversionReportsFractionalMilliseconds() {
        let duration = Duration.seconds(2) + .milliseconds(250) + .microseconds(500)

        #expect(AgentStudioPerformanceTraceRecorder.milliseconds(from: duration) == 2250.5)
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-performance-trace-recorder-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
