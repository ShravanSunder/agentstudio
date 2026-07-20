import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioStartupTraceRecorderTests {
    @Test
    func recorderEmitsAppStartupEventWithAttributes() async throws {
        let runtime = makeTraceRuntime(tags: "app.startup", timeUnixNano: { 101 })
        let recorder = AgentStudioStartupTraceRecorder(traceRuntime: runtime)

        recorder.recordAppStartup(
            "app.ghostty_init.started",
            phase: "ghostty_init",
            attributes: [
                "agentstudio.command.source": .string("main")
            ]
        )
        try await recorder.drain()

        let contents = try traceContents(from: runtime)
        #expect(contents.contains("\"body\":\"app.ghostty_init.started\""))
        #expect(contents.contains("\"time_unix_nano\":101"))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"app.startup\""))
        #expect(contents.contains("\"agentstudio.app.startup.phase\":\"ghostty_init\""))
        #expect(contents.contains("\"agentstudio.command.source\":\"main\""))
    }

    @Test
    func recorderEmitsTerminalStartupEventWithPaneSurfaceAndZmxAttributes() async throws {
        let paneID = UUID()
        let surfaceID = UUID()
        let runtime = makeTraceRuntime(tags: "terminal.startup", timeUnixNano: { 202 })
        let recorder = AgentStudioStartupTraceRecorder(traceRuntime: runtime)

        recorder.recordTerminalStartup(
            "terminal.startup.zmx_attach_prepared",
            paneID: paneID,
            surfaceID: surfaceID,
            phase: "zmx_attach_prepared",
            provider: "zmx",
            attributes: [
                "agentstudio.zmx.session_id": .string("as-d--session"),
                "agentstudio.zmx.socket_path_len": .int(72),
                "agentstudio.zmx.socket_path_headroom": .int(32),
            ]
        )
        try await recorder.drain()

        let contents = try traceContents(from: runtime)
        #expect(contents.contains("\"body\":\"terminal.startup.zmx_attach_prepared\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"terminal.startup\""))
        #expect(contents.contains("\"agentstudio.pane.id\":\"\(paneID.uuidString)\""))
        #expect(contents.contains("\"agentstudio.surface.id\":\"\(surfaceID.uuidString)\""))
        #expect(contents.contains("\"agentstudio.terminal.provider\":\"zmx\""))
        #expect(contents.contains("\"agentstudio.terminal.startup.phase\":\"zmx_attach_prepared\""))
        #expect(contents.contains("\"agentstudio.zmx.session_id\":\"as-d--session\""))
        #expect(contents.contains("\"agentstudio.zmx.socket_path_len\":72"))
        #expect(contents.contains("\"agentstudio.zmx.socket_path_headroom\":32"))
    }

    @Test
    func recorderIsNoopWhenRuntimeIsNilOrTagDisabled() async throws {
        let disabledRuntime = makeTraceRuntime(tags: "app.startup", timeUnixNano: { 303 })
        let nilRecorder = AgentStudioStartupTraceRecorder(traceRuntime: nil)
        let disabledTagRecorder = AgentStudioStartupTraceRecorder(traceRuntime: disabledRuntime)

        nilRecorder.recordTerminalStartup(
            "terminal.startup.surface_create_started",
            paneID: UUID(),
            phase: "surface_create_started",
            provider: "zmx"
        )
        disabledTagRecorder.recordTerminalStartup(
            "terminal.startup.surface_create_started",
            paneID: UUID(),
            phase: "surface_create_started",
            provider: "zmx"
        )
        try await nilRecorder.drain()
        try await disabledTagRecorder.drain()

        #expect(
            try traceContentsIfPresent(from: disabledRuntime)?.contains("terminal.startup.surface_create_started")
                != true)
    }

    @Test
    func firstMilestoneHelpersEmitOncePerSurfaceOrPane() async throws {
        let paneID = UUID()
        let surfaceID = UUID()
        let runtime = makeTraceRuntime(tags: "terminal.startup", timeUnixNano: { 404 })
        let recorder = AgentStudioStartupTraceRecorder(traceRuntime: runtime)

        recorder.recordFirstGhosttyAction(
            paneID: paneID,
            surfaceID: surfaceID,
            actionName: "pwd"
        )
        recorder.recordFirstGhosttyAction(
            paneID: paneID,
            surfaceID: surfaceID,
            actionName: "title"
        )
        recorder.recordFirstOutput(paneID: paneID, surfaceID: surfaceID)
        recorder.recordFirstOutput(paneID: paneID, surfaceID: surfaceID)
        recorder.recordCwdReady(paneID: paneID, surfaceID: surfaceID)
        recorder.recordCwdReady(paneID: paneID, surfaceID: surfaceID)
        recorder.recordTitleReady(paneID: paneID, surfaceID: surfaceID)
        recorder.recordTitleReady(paneID: paneID, surfaceID: surfaceID)
        recorder.recordChildExited(paneID: paneID, surfaceID: surfaceID, actionName: "showChildExited")
        recorder.recordChildExited(paneID: paneID, surfaceID: surfaceID, actionName: "showChildExited")
        try await recorder.drain()

        let contents = try traceContents(from: runtime)
        #expect(countOccurrences(of: "terminal.startup.first_ghostty_action", in: contents) == 1)
        #expect(countOccurrences(of: "terminal.startup.first_output", in: contents) == 1)
        #expect(countOccurrences(of: "terminal.startup.cwd_ready", in: contents) == 1)
        #expect(countOccurrences(of: "terminal.startup.title_ready", in: contents) == 1)
        #expect(countOccurrences(of: "terminal.startup.child_exited", in: contents) == 1)
        #expect(contents.contains("\"agentstudio.terminal.startup.outcome\":\"failed\""))
        #expect(contents.contains("\"agentstudio.ghostty.action\":\"showChildExited\""))
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
            processIdentifier: 919,
            timeUnixNano: timeUnixNano
        )
    }

    private func traceContents(from traceRuntime: AgentStudioTraceRuntime) throws -> String {
        try String(contentsOf: try #require(traceRuntime.outputFileURL), encoding: .utf8)
    }

    private func traceContentsIfPresent(from traceRuntime: AgentStudioTraceRuntime) throws -> String? {
        let outputFileURL = try #require(traceRuntime.outputFileURL)
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            return nil
        }
        return try String(contentsOf: outputFileURL, encoding: .utf8)
    }

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-startup-trace-recorder-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
