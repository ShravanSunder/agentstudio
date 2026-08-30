import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite
struct AgentStudioPerformanceTraceRecorderTests {
    @Test("renderer delivery and projection accounting keeps deltas separate from current lifecycle state")
    func rendererDeliveryAndProjectionAccounting() {
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: nil)
        let surfaceID = UUIDv7.generate()

        recorder.recordRendererVisibilityDelivery(
            surfaceID: surfaceID,
            visible: true,
            outcome: .applied
        )
        recorder.recordRendererVisibilityDelivery(
            surfaceID: surfaceID,
            visible: true,
            outcome: .equal
        )
        recorder.recordRendererVisibilityProjection(
            trigger: .observedChange,
            applied: 1,
            equal: 2,
            missing: 3,
            failed: 4,
            duration: .milliseconds(5)
        )

        let snapshot = recorder.rendererLifecycleSnapshot()
        #expect(snapshot.visibilityDeliveryTotal == 1)
        #expect(snapshot.visibilityEqualSuppressedTotal == 1)
        #expect(snapshot.projectionEvaluationTotal == 1)
        #expect(snapshot.projectionEvaluatedSurfaceTotal == 7)
        #expect(snapshot.projectionChangedSurfaceTotal == 1)
        #expect(snapshot.projectionEqualSurfaceTotal == 2)
        #expect(snapshot.sampleSequence == 3)
        #expect(snapshot.isValid)
    }

    @Test("renderer lifecycle flows through the recorder, scrub projection, and metric mapping")
    func rendererLifecycleFlowsThroughRecorderProjectionAndMetrics() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let sink = RendererLifecycleRecordingTraceSink()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "renderer-lifecycle-integration",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 908,
            sinkFactory: AgentStudioTraceSinkFactory(
                makeJSONLSink: { _ in sink },
                makeOTLPSink: { _ in sink }
            ),
            timeUnixNano: { 116 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(
            traceRuntime: runtime,
            processMemorySampleWait: { false }
        )
        let surfaceID = UUIDv7.generate()

        recorder.recordRendererCreated(surfaceID: surfaceID, active: 0, hidden: 1, closeUndo: 0)
        recorder.recordRendererVisibilityDelivery(surfaceID: surfaceID, visible: false, outcome: .applied)
        recorder.recordRendererVisibilityDelivery(surfaceID: surfaceID, visible: false, outcome: .equal)
        recorder.recordRendererVisibilityProjection(
            trigger: .membershipChange,
            applied: 1,
            equal: 1,
            missing: 0,
            failed: 0,
            duration: .milliseconds(2)
        )
        recorder.recordRendererPermanentlyReleased(
            surfaceID: surfaceID,
            reason: "repair_replacement",
            active: 0,
            hidden: 0,
            closeUndo: 0
        )
        recorder.recordRendererDeinitialized(surfaceID: surfaceID)
        try await recorder.drain()

        let records = await sink.recordedRecords()
        let rendererRecords = records.filter { $0.body == "performance.renderer.lifecycle" }
        let projections = rendererRecords.map(AgentStudioOTLPTraceProjection.project)
        let metricEvents = projections.compactMap(AgentStudioOTLPPerformanceMetricEvent.init(record:))
        let counterLabels = metricEvents.flatMap(\.measurements).compactMap { measurement -> String? in
            guard case .counter(let sample) = measurement else { return nil }
            return sample.label
        }
        let finalSnapshot = recorder.rendererLifecycleSnapshot()

        #expect(rendererRecords.count == 6)
        #expect(metricEvents.count == 6)
        #expect(projections.allSatisfy { $0.attributes["agentstudio.performance.renderer.surface_id"] == nil })
        #expect(counterLabels.contains("agentstudio_performance_renderer_created_delta"))
        #expect(counterLabels.contains("agentstudio_performance_renderer_visibility_delivery_delta"))
        #expect(counterLabels.contains("agentstudio_performance_renderer_visibility_equal_suppressed_delta"))
        #expect(counterLabels.contains("agentstudio_performance_renderer_projection_evaluation_delta"))
        #expect(counterLabels.contains("agentstudio_performance_renderer_release_delta"))
        #expect(counterLabels.contains("agentstudio_performance_renderer_free_delta"))
        #expect(finalSnapshot.liveCurrent == 0)
        #expect(finalSnapshot.managerOwnedCurrent == 0)
        #expect(finalSnapshot.orphanCandidateCurrent == 0)
        #expect(finalSnapshot.isValid)
    }

    @Test("renderer lifecycle conservation exposes the release-to-free orphan interval")
    func rendererLifecycleConservationExposesReleaseToFreeInterval() {
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: nil)
        let surfaceID = UUIDv7.generate()

        recorder.recordRendererCreated(
            surfaceID: surfaceID,
            active: 0,
            hidden: 1,
            closeUndo: 0
        )
        let owned = recorder.rendererLifecycleSnapshot()
        recorder.recordRendererPermanentlyReleased(
            surfaceID: surfaceID,
            reason: "repair_replacement",
            active: 0,
            hidden: 0,
            closeUndo: 0
        )
        let released = recorder.rendererLifecycleSnapshot()
        recorder.recordRendererDeinitialized(surfaceID: surfaceID)
        let freed = recorder.rendererLifecycleSnapshot()

        #expect(owned.liveCurrent == 1)
        #expect(owned.managerOwnedCurrent == 1)
        #expect(owned.orphanCandidateCurrent == 0)
        #expect(released.permanentReleaseTotal == 1)
        #expect(released.liveCurrent == 1)
        #expect(released.managerOwnedCurrent == 0)
        #expect(released.orphanCandidateCurrent == 1)
        #expect(freed.deinitializedFreeTotal == 1)
        #expect(freed.liveCurrent == 0)
        #expect(freed.orphanCandidateCurrent == 0)
        #expect(freed.sampleSequence == 3)
    }

    @Test("renderer lifecycle invalid negative orphan is preserved rather than clamped")
    func rendererLifecycleNegativeOrphanIsPreserved() {
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: nil)

        recorder.recordRendererDeinitialized(surfaceID: UUIDv7.generate())
        let snapshot = recorder.rendererLifecycleSnapshot()

        #expect(snapshot.liveCurrent == -1)
        #expect(snapshot.orphanCandidateCurrent == -1)
        #expect(!snapshot.isValid)
    }

    @Test("pane association boot reconciliation records only aggregate counts")
    func paneAssociationBootReconciliationRecordsScrubbedCounts() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "pane-association-boot",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 909,
            timeUnixNano: { 117 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.recordPaneAssociationBootReconciliation(
            PaneAssociationBootReconciliationSummary(
                paneCount: 5,
                retainedKnownCount: 2,
                backfilledCount: 1,
                danglingClearedCount: 1,
                freeNilCount: 1,
                changedCount: 2
            )
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.pane.association_boot_reconciliation\""))
        #expect(contents.contains("\"agentstudio.performance.pane.association_boot.pane.count\":5"))
        #expect(contents.contains("\"agentstudio.performance.pane.association_boot.changed.count\":2"))
        #expect(!contents.contains("pane_id"))
        #expect(!contents.contains("worktree_id"))
        #expect(!contents.contains("cwd_path"))
    }

    @Test("pane association outcomes are bounded and admitted at the often-lane policy")
    func paneAssociationOutcomesAreControlledAndRateLimited() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "pane-association-outcomes",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 910,
            timeUnixNano: { 118 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        let controlledOutcomes: [PaneAssociationOutcome] = [
            .stampedKnown,
            .resolvedChanged,
            .resolvedEqual,
            .clearedNoMatch,
            .topologyRemoved,
            .deferredUncertain,
            .freeNil,
        ]

        for outcome in controlledOutcomes {
            recorder.recordPaneAssociationOutcome(outcome)
        }
        for _ in controlledOutcomes.count..<AppPolicies.Diagnostics.paneAssociationTraceAdmissionLimit + 1 {
            recorder.recordPaneAssociationOutcome(.resolvedEqual)
        }
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        for outcome in controlledOutcomes {
            #expect(
                contents.contains(
                    "\"agentstudio.performance.pane.association_outcome\":\"\(outcome.rawValue)\""
                )
            )
        }
        let emittedEventCount =
            contents.components(
                separatedBy: "\"body\":\"performance.pane.association\""
            ).count - 1
        #expect(emittedEventCount == AppPolicies.Diagnostics.paneAssociationTraceAdmissionLimit)
    }

    @Test("focus responder changes record only the bounded reason")
    func focusResponderChangeRecordsBoundedReason() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "focus-responder-change",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 911,
            timeUnixNano: { 119 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.recordFocusResponderChange(reason: .restoreTailSkippedUserFocus)
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.focus.responder_change\""))
        #expect(
            contents.contains(
                "\"agentstudio.performance.focus.responder_change.reason\":\"restore_tail_skipped_user_focus\""
            ))
    }

    @Test("startup deferral records bounded gate and outcome")
    func startupDeferralRecordsBoundedOutcome() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "startup-deferral",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 912,
            timeUnixNano: { 120 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.recordStartupDeferral(
            gate: "first_interactive_frame",
            outcome: .fallbackTimeout
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.startup.deferral\""))
        #expect(contents.contains("\"agentstudio.performance.startup.deferral.gate\":\"first_interactive_frame\""))
        #expect(contents.contains("\"agentstudio.performance.startup.deferral.outcome\":\"fallback_timeout\""))
    }

    @Test("startup usable records launch and layout phase durations without identity")
    func startupUsableRecordsSafeDurations() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "startup-usable",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 913,
            timeUnixNano: { 121 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.recordStartupUsable(
            launchToUsable: .milliseconds(125),
            layoutSettleToUsable: .milliseconds(8),
            source: "occluded_fallback"
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.startup.usable\""))
        #expect(contents.contains("\"agentstudio.performance.elapsed_ms\":125"))
        #expect(contents.contains("\"agentstudio.performance.startup.layout_settle_to_usable_elapsed_ms\":8"))
        #expect(contents.contains("\"agentstudio.performance.startup.source\":\"occluded_fallback\""))
        #expect(!contents.contains("pane_id"))
        #expect(!contents.contains("surface_id"))
    }

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
                drainClass: .titleDeadline,
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
            queueAge: .milliseconds(3),
            applyOutcome: .changed
        )
        recorder.recordTerminalEqualSuppressed(publicationKind: .title)
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
        #expect(contents.contains("\"body\":\"performance.terminal.equal_suppressed\""))
        #expect(
            contents.contains(
                "\"agentstudio.performance.terminal.publication.kind\":\"title\""
            )
        )
        #expect(contents.contains("\"agentstudio.performance.terminal.equal_suppressed.count\":1"))
        #expect(
            contents.contains(
                "\"agentstudio.performance.terminal.accumulator.drain.class\":\"title_deadline\""
            )
        )
        #expect(
            contents.contains(
                "\"agentstudio.performance.terminal.accumulator.apply.outcome\":\"changed\""
            )
        )
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

    @Test("Repo Explorer row and scroll instruments emit bounded JSONL receipts")
    func repoExplorerRowAndScrollInstrumentsEmitBoundedJSONLReceipts() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "repo-explorer-row-scroll",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 923,
            timeUnixNano: { 783 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)

        recorder.recordDuration(
            .repoExplorerRowBodyEvaluation,
            duration: .milliseconds(3),
            attributes: [
                "agentstudio.performance.repo_explorer.row_body_evaluation.outcome": .string("success"),
                "agentstudio.performance.repo_explorer.row_kind": .string("resolved_worktree"),
                "agentstudio.performance.repo_explorer.surface": .string("repo"),
                "agentstudio.performance.repo_explorer.scroll_active": .bool(true),
                "agentstudio.performance.repo_explorer.visible_row_count_bucket": .string("9_16"),
            ]
        )
        recorder.recordDuration(
            .repoExplorerScrollFrameGap,
            duration: .milliseconds(16),
            attributes: [
                "agentstudio.performance.repo_explorer.scroll_frame_gap.outcome": .string("sampled"),
                "agentstudio.performance.repo_explorer.surface": .string("repo"),
                "agentstudio.performance.repo_explorer.scroll_burst.sequence": .int(7),
                "agentstudio.performance.repo_explorer.frame_sample.sequence": .int(2),
                "agentstudio.performance.repo_explorer.visible_row_count_bucket": .string("9_16"),
            ]
        )
        try await recorder.drain()

        let outputFileURL = try #require(runtime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.contains("\"body\":\"performance.repo_explorer.row_body_evaluation\""))
        #expect(contents.contains("\"body\":\"performance.repo_explorer.scroll_frame_gap\""))
        #expect(contents.contains("\"agentstudio.performance.repo_explorer.row_kind\":\"resolved_worktree\""))
        #expect(contents.contains("\"agentstudio.performance.repo_explorer.scroll_burst.sequence\":7"))
        #expect(contents.contains("\"agentstudio.performance.repo_explorer.frame_sample.sequence\":2"))
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
    func disabledPerformanceTagDoesNotEvaluateAttributeBuilders() async throws {
        let traceDirectory = temporaryTraceDirectoryURL()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_TAGS": "runtime",
            ]),
            processIdentifier: 919,
            timeUnixNano: { 127 }
        )
        let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
        let attributeEvaluationCounter = AttributeEvaluationCounter()

        recorder.record(
            .gitStatusComputed,
            attributes: attributeEvaluationCounter.attributes()
        )
        recorder.recordDuration(
            .tabBarRefresh,
            duration: .milliseconds(1),
            attributes: attributeEvaluationCounter.attributes()
        )
        try await recorder.drain()

        #expect(attributeEvaluationCounter.evaluationCount == 0)
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

private final class AttributeEvaluationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var evaluationCountStorage = 0

    var evaluationCount: Int {
        lock.withLock { evaluationCountStorage }
    }

    func attributes() -> [String: AgentStudioTraceValue] {
        lock.withLock { evaluationCountStorage += 1 }
        return ["agentstudio.performance.git.running.count": .int(1)]
    }
}

private actor RendererLifecycleRecordingTraceSink: AgentStudioTraceSink {
    private var records: [AgentStudioTraceRecord] = []

    func record(_ record: AgentStudioTraceRecord) {
        records.append(record)
    }

    func flush() {}

    func shutdown() {}

    func diagnostics() -> AgentStudioTraceWriterDiagnostics {
        .empty
    }

    func recordedRecords() -> [AgentStudioTraceRecord] {
        records
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
