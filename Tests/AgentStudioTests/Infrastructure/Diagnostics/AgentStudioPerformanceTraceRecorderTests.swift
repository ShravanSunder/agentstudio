import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioPerformanceTraceRecorderTests {
    @Test
    func recorderEmitsTypedRuntimePressureAggregateSnapshots() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "runtime-pressure-aggregates",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 914,
            timeUnixNano: { 122 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.recordTerminalAccumulatorDrain(
            TerminalAccumulatorDrainPerformanceSnapshot(
                offeredCount: 100,
                replacedCount: 80,
                equalSuppressedCount: 10,
                scheduledDrainCount: 1,
                followUpDrainCount: 1,
                mainActorTaskCount: 1,
                activityAggregateCount: 2,
                retainedEntryCount: 4,
                retainedSizeBytes: 256
            ),
            queueAge: .milliseconds(3)
        )
        recorder.recordTerminalCompactApply(
            TerminalCompactApplyPerformanceSnapshot(
                equalWriteSuppressedCount: 7,
                activityProjectionRoundTrip: .completed(.milliseconds(4))
            ),
            serviceTime: .milliseconds(1)
        )
        recorder.recordTerminalCompactApply(
            TerminalCompactApplyPerformanceSnapshot(
                equalWriteSuppressedCount: 0,
                activityProjectionRoundTrip: .notSubmitted
            ),
            serviceTime: .milliseconds(2)
        )
        recorder.recordFilesystemEffectSnapshot(
            FilesystemEffectPerformanceSnapshot(
                fullReconciliationRequestCount: 0,
                affectedKeyRequestCount: 12
            )
        )
        recorder.recordTraceIdentitySnapshot(
            TraceIdentityPerformanceSnapshot(
                refreshRequestCount: 9,
                coalescedRequestCount: 8,
                fleetCaptureCount: 1,
                equalSnapshotSuppressedCount: 1
            )
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.terminal.accumulator_drain\""))
        #expect(contents.contains("\"body\":\"performance.terminal.compact_apply\""))
        #expect(contents.contains("\"body\":\"performance.filesystem.effect_snapshot\""))
        #expect(contents.contains("\"body\":\"performance.trace_identity.snapshot\""))
        #expect(contents.contains("\"agentstudio.performance.terminal.accumulator.offered.count\":100"))
        #expect(contents.contains("\"agentstudio.performance.terminal.accumulator.retained_entry.count\":4"))
        #expect(contents.contains("\"agentstudio.performance.terminal.equal_write_suppressed.count\":7"))
        #expect(contents.contains("\"agentstudio.performance.terminal.activity_projection.submitted\":true"))
        #expect(contents.contains("\"agentstudio.performance.terminal.activity_projection.submitted\":false"))
        #expect(contents.contains("\"agentstudio.performance.terminal.activity_projection.round_trip_ms\":4"))
        #expect(contents.contains("\"agentstudio.performance.filesystem.affected_key_request.count\":12"))
        #expect(contents.contains("\"agentstudio.performance.trace_identity.coalesced_request.count\":8"))
    }

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
        recorder.record(
            .filesystemLogicalDebt,
            attributes: [
                "agentstudio.performance.filesystem.logical_debt.count": .int(4)
            ]
        )
        recorder.record(
            .gitLogicalDebt,
            attributes: [
                "agentstudio.performance.git.logical_debt.count": .int(3)
            ]
        )
        recorder.record(
            .runtimeDeliverySnapshot,
            attributes: [
                "agentstudio.performance.runtime_delivery.total_pending.count": .int(2)
            ]
        )
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
        #expect(contents.contains("\"body\":\"performance.filesystem.logical_debt\""))
        #expect(contents.contains("\"body\":\"performance.git.logical_debt\""))
        #expect(contents.contains("\"body\":\"performance.runtime_delivery.snapshot\""))
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
    func recorderPiggybacksRuntimeDeliverySnapshotOnMemorySample() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "runtime-delivery-recorder",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 917,
            timeUnixNano: { 125 }
        )
        let runtimeDeliveryPerformanceReporter = RuntimeDeliveryPerformanceReporter()
        let runtimeChannelToken = RuntimeDeliveryChannelToken.make()
        runtimeDeliveryPerformanceReporter.enable()
        runtimeDeliveryPerformanceReporter.registerRuntimeChannel(runtimeChannelToken)
        runtimeDeliveryPerformanceReporter.recordRuntimeChannelOutboundEnqueued(runtimeChannelToken)
        runtimeDeliveryPerformanceReporter.recordEventBusDeliveryEnqueued()
        let controlledSampleWait = ControlledPerformanceSampleWait()
        let recorder = AgentStudioPerformanceTraceRecorder(
            traceRuntime: runtime,
            runtimeDeliveryPerformanceReporter: runtimeDeliveryPerformanceReporter,
            processMemorySampleWait: { await controlledSampleWait.wait() }
        )

        await controlledSampleWait.waitUntilEntered()
        try await recorder.drain()
        controlledSampleWait.release()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.runtime_delivery.snapshot\""))
        #expect(
            contents.contains(
                "\"agentstudio.performance.runtime_delivery.runtime_channel_outbound_pending.count\":1"
            ))
        #expect(
            contents.contains(
                "\"agentstudio.performance.runtime_delivery.eventbus_active_delivery_debt.count\":1"
            ))
        #expect(contents.contains("\"agentstudio.performance.runtime_delivery.total_pending.count\":2"))
        #expect(runtimeDeliveryPerformanceReporter.snapshot() == .zero)
    }

    @Test
    func recorderEnablesRuntimeDeliveryReporterOnlyForPerformanceTracing() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "runtime-delivery-enablement",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 918,
            timeUnixNano: { 126 }
        )
        let runtimeDeliveryPerformanceReporter = RuntimeDeliveryPerformanceReporter()
        let runtimeChannelToken = RuntimeDeliveryChannelToken.make()
        let recorder = AgentStudioPerformanceTraceRecorder(
            traceRuntime: runtime,
            runtimeDeliveryPerformanceReporter: runtimeDeliveryPerformanceReporter
        )

        runtimeDeliveryPerformanceReporter.registerRuntimeChannel(runtimeChannelToken)
        runtimeDeliveryPerformanceReporter.recordRuntimeChannelOutboundEnqueued(runtimeChannelToken)

        #expect(runtimeDeliveryPerformanceReporter.snapshot().runtimeChannelOutboundPendingCount == 1)

        try await recorder.drain()

        #expect(runtimeDeliveryPerformanceReporter.snapshot() == .zero)
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

private final class ControlledPerformanceSampleWait: @unchecked Sendable {
    private let enteredStream: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let releaseStream: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init() {
        (enteredStream, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        (releaseStream, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func wait() async -> Bool {
        enteredContinuation.yield(())
        return await withTaskCancellationHandler {
            var iterator = releaseStream.makeAsyncIterator()
            return await iterator.next() != nil && !Task.isCancelled
        } onCancel: {
            releaseContinuation.finish()
        }
    }

    func waitUntilEntered() async {
        var iterator = enteredStream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        releaseContinuation.yield(())
        releaseContinuation.finish()
        enteredContinuation.finish()
    }
}
