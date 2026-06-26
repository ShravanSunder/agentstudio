import Foundation
import Testing

@testable import AgentStudio

@Suite
struct GlobalPreferencesStartupTelemetryTests {
    @Test
    func recordsLoadedPreferencesWithSafeStartupAttributes() async throws {
        let runtime = makeTraceRuntime(tags: "app.startup", timeUnixNano: { 707 })
        let recorder = AgentStudioStartupTraceRecorder(traceRuntime: runtime)
        let loadResult = GlobalPreferencesLoadResult(
            status: .loaded(
                .init(
                    enabled: true,
                    traceTags: "*",
                    traceBackend: "otlp",
                    traceFlush: "buffered",
                    otlpEndpoint: "http://127.0.0.1:4318"
                )
            ),
            elapsedMilliseconds: 1.25
        )

        GlobalPreferencesStartupTelemetry.recordLoaded(loadResult, recorder: recorder)
        try await recorder.drain()

        let contents = try traceContents(from: runtime)
        #expect(contents.contains("\"body\":\"app.preferences.global.loaded\""))
        #expect(contents.contains("\"time_unix_nano\":707"))
        #expect(contents.contains("\"agentstudio.app.startup.phase\":\"global_preferences\""))
        #expect(contents.contains("\"agentstudio.app.startup.outcome\":\"loaded\""))
        #expect(contents.contains("\"agentstudio.preferences.global.status\":\"loaded\""))
        #expect(contents.contains("\"agentstudio.preferences.global.schema_version\":1"))
        #expect(contents.contains("\"agentstudio.preferences.global.observability_enabled\":true"))
        #expect(contents.contains("\"agentstudio.preferences.global.load_elapsed_ms\":1.25"))
        #expect(!contents.contains("127.0.0.1"))
    }

    @Test
    func recordsInvalidPreferencesWithoutRawPayloadDetails() async throws {
        let runtime = makeTraceRuntime(tags: "app.startup", timeUnixNano: { 808 })
        let recorder = AgentStudioStartupTraceRecorder(traceRuntime: runtime)
        let loadResult = GlobalPreferencesLoadResult(
            status: .invalidEndpoint("http://example.com:4318"),
            elapsedMilliseconds: 0.5
        )

        GlobalPreferencesStartupTelemetry.recordLoaded(loadResult, recorder: recorder)
        try await recorder.drain()

        let contents = try traceContents(from: runtime)
        #expect(contents.contains("\"agentstudio.app.startup.outcome\":\"invalid_endpoint\""))
        #expect(contents.contains("\"agentstudio.preferences.global.status\":\"invalid_endpoint\""))
        #expect(contents.contains("\"agentstudio.preferences.global.load_elapsed_ms\":0.5"))
        #expect(!contents.contains("example.com"))
        #expect(!contents.contains("http://"))
    }

    private func makeTraceRuntime(
        tags: String,
        timeUnixNano: @escaping @Sendable () -> UInt64
    ) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_TAGS": tags,
            ]),
            processIdentifier: 920,
            timeUnixNano: timeUnixNano
        )
    }

    private func traceContents(from traceRuntime: AgentStudioTraceRuntime) throws -> String {
        try String(contentsOf: try #require(traceRuntime.outputFileURL), encoding: .utf8)
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("global-preferences-startup-telemetry-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
