import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Foundation
import Testing

@testable import AgentStudioCommandBar
@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct CommandBarProductionProbeWiringTests {
    @Test("production recorder wiring emits command bar open and close interactions")
    func productionRecorderWiringEmitsOpenAndCloseInteractions() async throws {
        installTestCoreAtomsIfNeeded()
        let traceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-command-bar-wiring-tests")
            .appending(path: UUIDv7.generate().uuidString)
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "command-bar-production-wiring",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 267,
            timeUnixNano: { 1 }
        )
        let performanceTraceRecorder = AgentStudioPerformanceTraceRecorder(
            traceRuntime: traceRuntime
        )
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            octiconLoader: makeCommandBarTestOcticonLoader(),
            repoCache: RepoCacheAtom(),
            dispatcher: FakeAppCommandDispatcher(),
            quickOpenDirectoryHandler: { _, _ in },
            commandBarSurface: CommandBarSurfaceAtom(),
            performanceTraceRecorder: performanceTraceRecorder
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let outputFileURL = try #require(traceRuntime.outputFileURL)

        controller.show(parentWindow: window)
        try await eventuallyTraceContains(
            "\"agentstudio.performance.interaction.kind\":\"command_bar_open\"",
            recorder: performanceTraceRecorder,
            outputFileURL: outputFileURL
        )
        controller.dismiss()
        try await eventuallyTraceContains(
            "\"agentstudio.performance.interaction.kind\":\"command_bar_close\"",
            recorder: performanceTraceRecorder,
            outputFileURL: outputFileURL
        )
        try await performanceTraceRecorder.drain()

        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"agentstudio.performance.interaction.kind\":\"command_bar_open\""))
        #expect(contents.contains("\"agentstudio.performance.interaction.kind\":\"command_bar_close\""))
    }

    private func eventuallyTraceContains(
        _ expectedText: String,
        recorder: AgentStudioPerformanceTraceRecorder,
        outputFileURL: URL,
        maxTurns: Int = 200
    ) async throws {
        for turn in 0..<maxTurns {
            await Task.yield()
            guard turn.isMultiple(of: 10) else { continue }
            try await recorder.flush()
            let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
            if contents.contains(expectedText) {
                return
            }
        }
        try await recorder.flush()
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains(expectedText), "expected trace record did not arrive")
    }
}
