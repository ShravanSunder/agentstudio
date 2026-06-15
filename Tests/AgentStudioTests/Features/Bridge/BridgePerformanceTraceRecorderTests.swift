import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgePerformanceTraceRecorderTests {
    @Test
    func recorderEmitsBridgeSwiftAndWebKitEventsThroughTraceRuntime() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "bridge-recorder",
                "AGENTSTUDIO_TRACE_TAGS": "bridge.performance.swift,bridge.performance.webkit",
            ]),
            processIdentifier: 337,
            timeUnixNano: { 123 }
        )
        let recorder = BridgePerformanceTraceRecorder(traceRuntime: runtime)

        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.package_build",
                durationMilliseconds: 4,
                traceContext: try BridgeTraceContext(
                    traceId: "11111111111111111111111111111111",
                    spanId: "2222222222222222",
                    parentSpanId: nil,
                    sampled: true
                ),
                stringAttributes: [
                    "agentstudio.bridge.phase": "package_build"
                ],
                numericAttributes: [
                    "agentstudio.bridge.content.byte_size_bucket": 100_000
                ],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: 123
        )
        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .webKit,
                name: "performance.bridge.webkit.package_push",
                durationMilliseconds: 2,
                traceContext: nil,
                stringAttributes: [
                    "agentstudio.bridge.transport": "push"
                ],
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: 123
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.bridge.swift.package_build\""))
        #expect(contents.contains("\"body\":\"performance.bridge.webkit.package_push\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"bridge.performance.swift\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"bridge.performance.webkit\""))
        #expect(contents.contains("\"trace_id\":\"11111111111111111111111111111111\""))
        #expect(contents.contains("\"agentstudio.bridge.phase\":\"package_build\""))
        #expect(contents.contains("\"agentstudio.bridge.test.scenario\":\"package_apply_content_fetch_v1\""))
        #expect(contents.contains("\"agentstudio.bridge.content.byte_size_bucket\":100000"))
        #expect(contents.contains("\"agentstudio.performance.elapsed_ms\":4"))
    }

    @Test
    func recorderStaysSilentWhenBridgeScopesAreDisabled() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 338,
            timeUnixNano: { 124 }
        )
        let recorder = BridgePerformanceTraceRecorder(traceRuntime: runtime)

        await recorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: "performance.bridge.swift.package_build",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [:],
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: 124
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        #expect(!FileManager.default.fileExists(atPath: outputFileURL.path))
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-bridge-performance-recorder-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
