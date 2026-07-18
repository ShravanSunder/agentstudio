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
        recorder.recordDuration(
            .managementLayerCommand,
            duration: .milliseconds(2),
            attributes: [
                "agentstudio.performance.management_layer.command": .string("toggleManagementLayer")
            ]
        )
        recorder.record(.paneActionExecution)
        recorder.record(.paneTabLayout)
        recorder.record(.paneViewRestore)
        recorder.record(.paneViewRestoreVisible)
        recorder.record(.sidebarResize)
        recorder.record(.sidebarToggle)
        recorder.record(.terminalForceGeometrySync)
        recorder.record(.terminalGeometrySync)
        recorder.record(.terminalMountLayout)
        recorder.record(.terminalSurfaceSizeDidChange)
        recorder.record(
            .atomRead,
            attributes: [
                "agentstudio.performance.atom.kind": .string("entity_map"),
                "agentstudio.performance.atom.operation": .string("value"),
                "agentstudio.performance.atom.slot.count": .int(2),
                "agentstudio.performance.atom.cached_key.count": .int(1),
            ]
        )
        recorder.record(
            .atomMutation,
            attributes: [
                "agentstudio.performance.atom.kind": .string("entity_map"),
                "agentstudio.performance.atom.operation": .string("set"),
                "agentstudio.performance.atom.accepted_change.count": .int(1),
            ]
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.git.status\""))
        #expect(contents.contains("\"body\":\"performance.management_layer.command\""))
        #expect(contents.contains("\"body\":\"performance.pane_action.execution\""))
        #expect(contents.contains("\"body\":\"performance.pane_tab.layout\""))
        #expect(contents.contains("\"body\":\"performance.pane_view.restore\""))
        #expect(contents.contains("\"body\":\"performance.pane_view.restore_visible\""))
        #expect(contents.contains("\"body\":\"performance.sidebar.resize\""))
        #expect(contents.contains("\"body\":\"performance.sidebar.toggle\""))
        #expect(contents.contains("\"body\":\"performance.terminal.force_geometry_sync\""))
        #expect(contents.contains("\"body\":\"performance.terminal.geometry_sync\""))
        #expect(contents.contains("\"body\":\"performance.terminal.mount_layout\""))
        #expect(contents.contains("\"body\":\"performance.terminal.surface_size\""))
        #expect(contents.contains("\"body\":\"performance.atom.read\""))
        #expect(contents.contains("\"body\":\"performance.atom.mutation\""))
        #expect(contents.contains("\"agentstudio.trace.tag\":\"performance\""))
        #expect(contents.contains("\"agentstudio.performance.git.running.count\":3"))
        #expect(contents.contains("\"agentstudio.performance.git.status.duration_ms\":1.5"))
        #expect(contents.contains("\"agentstudio.performance.management_layer.command\":\"toggleManagementLayer\""))
        #expect(contents.contains("\"agentstudio.performance.atom.kind\":\"entity_map\""))
        #expect(contents.contains("\"agentstudio.performance.atom.operation\":\"value\""))
        #expect(contents.contains("\"agentstudio.performance.atom.slot.count\":2"))
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

    @Test
    func durationHistogramResolvesRuntimePressureBudgets() {
        let buckets = AgentStudioOTLPPerformanceMetrics.elapsedHistogramBuckets

        for requiredBoundary in [0.25, 0.5, 1, 2, 5, 8, 16, 20, 60] {
            #expect(buckets.contains(requiredBoundary))
        }
        #expect(buckets == buckets.sorted())
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-performance-trace-recorder-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
