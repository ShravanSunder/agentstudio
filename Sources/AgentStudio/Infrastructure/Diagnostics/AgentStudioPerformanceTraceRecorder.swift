import Foundation

package enum TerminalAccumulatorDrainClass: String, Equatable, Sendable {
    case immediate
    case titleDeadline = "title_deadline"
    case exactBarrier = "exact_barrier"
}

package enum TerminalPerformancePublicationKind: String, Equatable, Sendable {
    case activity
    case cwd
    case title
}

package enum TerminalAccumulatorApplyOutcome: String, Equatable, Sendable {
    case equal
    case changed
}

package enum PaneAssociationOutcome: String, Equatable, Sendable {
    case stampedKnown = "stamped_known"
    case resolvedChanged = "resolved_changed"
    case resolvedEqual = "resolved_equal"
    case clearedNoMatch = "cleared_no_match"
    case topologyRemoved = "topology_removed"
    case deferredUncertain = "deferred_uncertain"
    case freeNil = "free_nil"
}

package struct PaneAssociationBootReconciliationSummary: Equatable, Sendable {
    package let paneCount: UInt64
    package let retainedKnownCount: UInt64
    package let backfilledCount: UInt64
    package let danglingClearedCount: UInt64
    package let freeNilCount: UInt64
    package let changedCount: UInt64

    package init(
        paneCount: UInt64,
        retainedKnownCount: UInt64,
        backfilledCount: UInt64,
        danglingClearedCount: UInt64,
        freeNilCount: UInt64,
        changedCount: UInt64
    ) {
        self.paneCount = paneCount
        self.retainedKnownCount = retainedKnownCount
        self.backfilledCount = backfilledCount
        self.danglingClearedCount = danglingClearedCount
        self.freeNilCount = freeNilCount
        self.changedCount = changedCount
    }
}

package struct TerminalAccumulatorDrainPerformanceSnapshot: Equatable, Sendable {
    let drainClass: TerminalAccumulatorDrainClass
    let offeredCount: UInt64
    let replacedCount: UInt64
    let equalSuppressedCount: UInt64
    let scheduledDrainCount: UInt64
    let followUpDrainCount: UInt64
    let mainActorTaskCount: UInt64
    let activityAggregateCount: UInt64
    let retainedEntryCount: UInt64
    let retainedSizeBytes: UInt64

    package init(
        drainClass: TerminalAccumulatorDrainClass,
        offeredCount: UInt64,
        replacedCount: UInt64,
        equalSuppressedCount: UInt64,
        scheduledDrainCount: UInt64,
        followUpDrainCount: UInt64,
        mainActorTaskCount: UInt64,
        activityAggregateCount: UInt64,
        retainedEntryCount: UInt64,
        retainedSizeBytes: UInt64
    ) {
        self.drainClass = drainClass
        self.offeredCount = offeredCount
        self.replacedCount = replacedCount
        self.equalSuppressedCount = equalSuppressedCount
        self.scheduledDrainCount = scheduledDrainCount
        self.followUpDrainCount = followUpDrainCount
        self.mainActorTaskCount = mainActorTaskCount
        self.activityAggregateCount = activityAggregateCount
        self.retainedEntryCount = retainedEntryCount
        self.retainedSizeBytes = retainedSizeBytes
    }
}

package struct TerminalCompactApplyPerformanceSnapshot: Equatable, Sendable {
    let equalWriteSuppressedCount: UInt64
    let activityProjectionRoundTrip: TerminalActivityProjectionRoundTripPerformance

    package init(
        equalWriteSuppressedCount: UInt64,
        activityProjectionRoundTrip: TerminalActivityProjectionRoundTripPerformance
    ) {
        self.equalWriteSuppressedCount = equalWriteSuppressedCount
        self.activityProjectionRoundTrip = activityProjectionRoundTrip
    }
}

package enum TerminalActivityProjectionRoundTripPerformance: Equatable, Sendable {
    case notSubmitted
    case completed(Duration)
}

package struct FilesystemEffectPerformanceSnapshot: Equatable, Sendable {
    let fullReconciliationRequestCount: UInt64
    let affectedKeyRequestCount: UInt64

    package init(
        fullReconciliationRequestCount: UInt64,
        affectedKeyRequestCount: UInt64
    ) {
        self.fullReconciliationRequestCount = fullReconciliationRequestCount
        self.affectedKeyRequestCount = affectedKeyRequestCount
    }
}

package struct TraceIdentityPerformanceSnapshot: Equatable, Sendable {
    let refreshRequestCount: UInt64
    let coalescedRequestCount: UInt64
    let fleetCaptureCount: UInt64
    let equalSnapshotSuppressedCount: UInt64

    package init(
        refreshRequestCount: UInt64,
        coalescedRequestCount: UInt64,
        fleetCaptureCount: UInt64,
        equalSnapshotSuppressedCount: UInt64
    ) {
        self.refreshRequestCount = refreshRequestCount
        self.coalescedRequestCount = coalescedRequestCount
        self.fleetCaptureCount = fleetCaptureCount
        self.equalSnapshotSuppressedCount = equalSnapshotSuppressedCount
    }
}

package enum AgentStudioFocusResponderChangeReason: String, Sendable {
    case userClick = "user_click"
    case restoreTail = "restore_tail"
    case restoreTailSkippedUserFocus = "restore_tail_skipped_user_focus"
    case parkedReplay = "parked_replay"
    case parkedCleared = "parked_cleared"
}

package struct RendererLifecyclePerformanceSnapshot: Equatable, Sendable {
    package let successfulCreatedTotal: Int
    package let permanentReleaseTotal: Int
    package let deinitializedFreeTotal: Int
    package let visibilityDeliveryTotal: Int
    package let visibilityEqualSuppressedTotal: Int
    package let projectionEvaluationTotal: Int
    package let projectionEvaluatedSurfaceTotal: Int
    package let projectionChangedSurfaceTotal: Int
    package let projectionEqualSurfaceTotal: Int
    package let activeCurrent: Int
    package let hiddenCurrent: Int
    package let closeUndoCurrent: Int
    package let liveCurrent: Int
    package let managerOwnedCurrent: Int
    package let orphanCandidateCurrent: Int
    package let sampleSequence: Int

    package var isValid: Bool {
        liveCurrent >= 0
            && managerOwnedCurrent >= 0
            && orphanCandidateCurrent >= 0
            && managerOwnedCurrent <= liveCurrent
    }
}

package enum RendererVisibilityDeliveryOutcome: String, Equatable, Sendable {
    case applied
    case equal
    case failed
    case missing
}

package enum RendererVisibilityProjectionTrigger: String, Equatable, Sendable {
    case initialBind = "initial_bind"
    case membershipChange = "membership_change"
    case observedChange = "observed_change"
}

private struct RendererLifecyclePerformanceState {
    var successfulCreatedTotal = 0
    var permanentReleaseTotal = 0
    var deinitializedFreeTotal = 0
    var visibilityDeliveryTotal = 0
    var visibilityEqualSuppressedTotal = 0
    var projectionEvaluationTotal = 0
    var projectionEvaluatedSurfaceTotal = 0
    var projectionChangedSurfaceTotal = 0
    var projectionEqualSurfaceTotal = 0
    var activeCurrent = 0
    var hiddenCurrent = 0
    var closeUndoCurrent = 0
    var sampleSequence = 0

    var snapshot: RendererLifecyclePerformanceSnapshot {
        let liveCurrent = successfulCreatedTotal - deinitializedFreeTotal
        let managerOwnedCurrent = activeCurrent + hiddenCurrent + closeUndoCurrent
        return RendererLifecyclePerformanceSnapshot(
            successfulCreatedTotal: successfulCreatedTotal,
            permanentReleaseTotal: permanentReleaseTotal,
            deinitializedFreeTotal: deinitializedFreeTotal,
            visibilityDeliveryTotal: visibilityDeliveryTotal,
            visibilityEqualSuppressedTotal: visibilityEqualSuppressedTotal,
            projectionEvaluationTotal: projectionEvaluationTotal,
            projectionEvaluatedSurfaceTotal: projectionEvaluatedSurfaceTotal,
            projectionChangedSurfaceTotal: projectionChangedSurfaceTotal,
            projectionEqualSurfaceTotal: projectionEqualSurfaceTotal,
            activeCurrent: activeCurrent,
            hiddenCurrent: hiddenCurrent,
            closeUndoCurrent: closeUndoCurrent,
            liveCurrent: liveCurrent,
            managerOwnedCurrent: managerOwnedCurrent,
            orphanCandidateCurrent: liveCurrent - managerOwnedCurrent,
            sampleSequence: sampleSequence
        )
    }
}

package final class AgentStudioPerformanceTraceRecorder: @unchecked Sendable {
    package struct TopologyLookupFact: Hashable, Sendable {
        let normalizedCWD: String
        let worktreePathIndexGeneration: UInt64
        let repoId: UUID?
        let worktreeId: UUID?

        package init(
            normalizedCWD: String,
            worktreePathIndexGeneration: UInt64,
            repoId: UUID?,
            worktreeId: UUID?
        ) {
            self.normalizedCWD = normalizedCWD
            self.worktreePathIndexGeneration = worktreePathIndexGeneration
            self.repoId = repoId
            self.worktreeId = worktreeId
        }
    }

    package enum Event: String, Sendable {
        case atomDerived = "performance.atom.derived"
        case atomMutation = "performance.atom.mutation"
        case atomRead = "performance.atom.read"
        case applyGovernorDrain = "performance.apply_governor.drain"
        case bridgeGitReadScheduler = "performance.bridge.git_read_scheduler"
        case bridgeWorktreeProductConstruction = "performance.bridge.worktree_product_construction"
        case commandBarFilter = "performance.commandbar.filter"
        case commandBarItems = "performance.commandbar.items"
        case commandBarCache = "performance.commandbar.cache"
        case coordinatorWrite = "performance.coordinator.write"
        case filesystemEffectSnapshot = "performance.filesystem.effect_snapshot"
        case filesystemStageOutcome = "performance.filesystem.stage_outcome"
        case filesystemLogicalDebt = "performance.filesystem.logical_debt"
        case focusResponderChange = "performance.focus.responder_change"
        case forgeRefresh = "performance.forge.refresh"
        case gitAdmission = "performance.git.admission"
        case gitBackoff = "performance.git.backoff"
        case gitEventPosted = "performance.git.event_posted"
        case gitPathQuarantine = "performance.git.path_quarantine"
        case gitLogicalDebt = "performance.git.logical_debt"
        case gitSnapshotDedup = "performance.git.snapshot_dedup"
        case gitStatusComputed = "performance.git.status"
        case gitStatusUnavailable = "performance.git.status_unavailable"
        case gitSuppressedInputSkipped = "performance.git.suppressed_input_skipped"
        case gitTick = "performance.git.tick"
        case interactionLatency = "performance.interaction.latency"
        case managementLayerAppKitState = "performance.management_layer.appkit_state"
        case managementLayerCommand = "performance.management_layer.command"
        case paneAssociation = "performance.pane.association"
        case paneAssociationBootReconciliation = "performance.pane.association_boot_reconciliation"
        case paneActionExecution = "performance.pane_action.execution"
        case paneTabLayout = "performance.pane_tab.layout"
        case paneViewRestore = "performance.pane_view.restore"
        case paneViewRestoreVisible = "performance.pane_view.restore_visible"
        case repoExplorerCommandPresentation = "performance.repo_explorer.command_presentation"
        case repoExplorerKeyedWake = "performance.repo_explorer.keyed_wake"
        case repoExplorerOutlineApplyProxy = "performance.repo_explorer.outline_apply_proxy"
        case repoExplorerRowBodyEvaluation = "performance.repo_explorer.row_body_evaluation"
        case repoExplorerScrollFrameGap = "performance.repo_explorer.scroll_frame_gap"
        case repoAndWorktreeLookup = "performance.topology.repo_and_worktree"
        case rendererLifecycle = "performance.renderer.lifecycle"
        case processMallocZone = "performance.process.malloc_zone"
        case runtimeDeliverySnapshot = "performance.runtime_delivery.snapshot"
        case sidebarFilterInput = "performance.sidebar.filter_input"
        case sidebarProjection = "performance.sidebar.projection"
        case sidebarRowIndex = "performance.sidebar.row_index"
        case sidebarResize = "performance.sidebar.resize"
        case sidebarToggle = "performance.sidebar.toggle"
        case startupUsable = "performance.startup.usable"
        case startupDeferral = "performance.startup.deferral"
        case tabBarCurrent = "performance.tabbar.current"
        case tabBarCapture = "performance.tabbar.capture"
        case tabBarContextMenu = "performance.tabbar.context_menu"
        case tabBarPaneDrop = "performance.tabbar.pane_drop"
        case tabBarPublication = "performance.tabbar.publication"
        case tabBarRefresh = "performance.tabbar.refresh"
        case tabBarTerminal = "performance.tabbar.terminal"
        case tabBarVisible = "performance.tabbar.visible"
        case tabBarWorker = "performance.tabbar.worker"
        case terminalAccumulatorDrain = "performance.terminal.accumulator_drain"
        case terminalCompactApply = "performance.terminal.compact_apply"
        case terminalEqualSuppressed = "performance.terminal.equal_suppressed"
        case terminalForceGeometrySync = "performance.terminal.force_geometry_sync"
        case terminalGeometrySync = "performance.terminal.geometry_sync"
        case terminalMountLayout = "performance.terminal.mount_layout"
        case terminalSurfaceSizeDidChange = "performance.terminal.surface_size"
        case traceIdentitySnapshot = "performance.trace_identity.snapshot"
    }

    private let traceRuntime: AgentStudioTraceRuntime?
    private let eventQueue: AgentStudioTraceEventQueue?
    private let lock = NSLock()
    private var topologyLookupAdmission = TopologyLookupTraceAdmission()
    private var paneAssociationAdmission = PaneAssociationTraceAdmission()
    private var rendererLifecycleState = RendererLifecyclePerformanceState()
    private let processMemorySampler: AgentStudioProcessMemorySampler?
    private let runtimeDeliveryPerformanceReporter: RuntimeDeliveryPerformanceReporter?
    private var recordedStartupLaunchInstant: ContinuousClock.Instant

    package init(
        traceRuntime: AgentStudioTraceRuntime?,
        runtimeDeliveryPerformanceReporter: RuntimeDeliveryPerformanceReporter? = nil,
        processMemorySampleWait: @escaping AgentStudioProcessMemorySampler.WaitForNextSample =
            AgentStudioProcessMemorySampler.waitOneSecond
    ) {
        self.recordedStartupLaunchInstant = ContinuousClock.now
        self.traceRuntime = traceRuntime
        if let traceRuntime, traceRuntime.isEnabled(.performance) {
            runtimeDeliveryPerformanceReporter?.enable()
            self.runtimeDeliveryPerformanceReporter = runtimeDeliveryPerformanceReporter
            let eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
            self.eventQueue = eventQueue
            let processMemorySampler = AgentStudioProcessMemorySampler(
                waitForNextSample: processMemorySampleWait
            ) { snapshot in
                eventQueue.record(
                    tag: .performance,
                    body: Event.processMallocZone.rawValue,
                    eventTimeUnixNano: traceRuntime.timestampUnixNano(),
                    attributes: snapshot.traceAttributes
                )
                if let runtimeDeliverySnapshot = runtimeDeliveryPerformanceReporter?.snapshot() {
                    eventQueue.record(
                        tag: .performance,
                        body: Event.runtimeDeliverySnapshot.rawValue,
                        eventTimeUnixNano: traceRuntime.timestampUnixNano(),
                        attributes: runtimeDeliverySnapshot.traceAttributes
                    )
                }
            }
            self.processMemorySampler = processMemorySampler
            processMemorySampler.start()
        } else {
            self.eventQueue = nil
            self.processMemorySampler = nil
            self.runtimeDeliveryPerformanceReporter = nil
        }
    }

    deinit {
        processMemorySampler?.cancel()
        runtimeDeliveryPerformanceReporter?.disable()
    }

    package var isEnabled: Bool {
        eventQueue != nil
    }

    package var startupLaunchInstant: ContinuousClock.Instant {
        lock.withLock { recordedStartupLaunchInstant }
    }

    package func markStartupLaunchStarted() {
        lock.withLock {
            recordedStartupLaunchInstant = ContinuousClock.now
        }
    }

    package func record(
        _ event: Event,
        attributes: @autoclosure () -> [String: AgentStudioTraceValue] = [:]
    ) {
        guard let traceRuntime, traceRuntime.isEnabled(.performance), let eventQueue else { return }
        eventQueue.record(
            tag: .performance,
            body: event.rawValue,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes()
        )
    }

    package func recordDuration(
        _ event: Event,
        duration: Duration,
        attributes: @autoclosure () -> [String: AgentStudioTraceValue] = [:]
    ) {
        guard isEnabled else { return }
        var mergedAttributes = attributes()
        mergedAttributes["agentstudio.performance.elapsed_ms"] = .double(Self.milliseconds(from: duration))
        record(event, attributes: mergedAttributes)
    }

    package func recordInteractionLatency(
        kind: AgentStudioInteractionKind,
        duration: Duration
    ) {
        recordDuration(
            .interactionLatency,
            duration: duration,
            attributes: [
                "agentstudio.performance.interaction.kind": .string(kind.rawValue)
            ]
        )
    }

    package func recordStartupUsable(
        launchToUsable: Duration,
        layoutSettleToUsable: Duration,
        source: String
    ) {
        recordDuration(
            .startupUsable,
            duration: launchToUsable,
            attributes: [
                "agentstudio.performance.startup.layout_settle_to_usable_elapsed_ms": .double(
                    Self.milliseconds(from: layoutSettleToUsable)
                ),
                "agentstudio.performance.startup.source": .string(source),
            ]
        )
    }

    package func recordStartupDeferral(
        gate: String,
        outcome: StartupDeferralOutcome
    ) {
        record(
            .startupDeferral,
            attributes: [
                "agentstudio.performance.startup.deferral.gate": .string(gate),
                "agentstudio.performance.startup.deferral.outcome": .string(outcome.rawValue),
            ]
        )
    }

    package func recordFocusResponderChange(reason: AgentStudioFocusResponderChangeReason) {
        record(
            .focusResponderChange,
            attributes: [
                "agentstudio.performance.focus.responder_change.reason": .string(reason.rawValue)
            ]
        )
    }

    package func recordRendererCreated(
        surfaceID: UUID,
        active: Int,
        hidden: Int,
        closeUndo: Int
    ) {
        let snapshot = lock.withLock {
            rendererLifecycleState.successfulCreatedTotal += 1
            rendererLifecycleState.activeCurrent = active
            rendererLifecycleState.hiddenCurrent = hidden
            rendererLifecycleState.closeUndoCurrent = closeUndo
            rendererLifecycleState.sampleSequence += 1
            return rendererLifecycleState.snapshot
        }
        recordRendererLifecycleSnapshot(
            snapshot,
            eventKind: "created",
            surfaceID: surfaceID,
            createdDelta: 1
        )
    }

    package func recordRendererManagerPopulation(
        active: Int,
        hidden: Int,
        closeUndo: Int
    ) {
        let snapshot = lock.withLock {
            rendererLifecycleState.activeCurrent = active
            rendererLifecycleState.hiddenCurrent = hidden
            rendererLifecycleState.closeUndoCurrent = closeUndo
            rendererLifecycleState.sampleSequence += 1
            return rendererLifecycleState.snapshot
        }
        recordRendererLifecycleSnapshot(snapshot, eventKind: "manager_population")
    }

    package func recordRendererPermanentlyReleased(
        surfaceID: UUID,
        reason: String,
        active: Int,
        hidden: Int,
        closeUndo: Int
    ) {
        let snapshot = lock.withLock {
            rendererLifecycleState.permanentReleaseTotal += 1
            rendererLifecycleState.activeCurrent = active
            rendererLifecycleState.hiddenCurrent = hidden
            rendererLifecycleState.closeUndoCurrent = closeUndo
            rendererLifecycleState.sampleSequence += 1
            return rendererLifecycleState.snapshot
        }
        recordRendererLifecycleSnapshot(
            snapshot,
            eventKind: "permanent_release",
            surfaceID: surfaceID,
            releaseReason: reason,
            releaseDelta: 1
        )
    }

    package func recordRendererDeinitialized(surfaceID: UUID) {
        let snapshot = lock.withLock {
            rendererLifecycleState.deinitializedFreeTotal += 1
            rendererLifecycleState.sampleSequence += 1
            return rendererLifecycleState.snapshot
        }
        recordRendererLifecycleSnapshot(
            snapshot,
            eventKind: "deinitialized_free",
            surfaceID: surfaceID,
            deinitializedFreeDelta: 1
        )
    }

    package func recordRendererVisibilityDelivery(
        surfaceID: UUID,
        visible: Bool,
        outcome: RendererVisibilityDeliveryOutcome
    ) {
        let deliveryDelta = outcome == .applied ? 1 : 0
        let equalSuppressedDelta = outcome == .equal ? 1 : 0
        let snapshot = lock.withLock {
            rendererLifecycleState.visibilityDeliveryTotal += deliveryDelta
            rendererLifecycleState.visibilityEqualSuppressedTotal += equalSuppressedDelta
            rendererLifecycleState.sampleSequence += 1
            return rendererLifecycleState.snapshot
        }
        recordRendererLifecycleSnapshot(
            snapshot,
            eventKind: "visibility_delivery",
            surfaceID: surfaceID,
            visibilityOutcome: outcome.rawValue,
            requestedVisibility: visible,
            visibilityDeliveryDelta: deliveryDelta,
            visibilityEqualSuppressedDelta: equalSuppressedDelta
        )
    }

    package func recordRendererVisibilityProjection(
        trigger: RendererVisibilityProjectionTrigger,
        applied: Int,
        equal: Int,
        missing: Int,
        failed: Int,
        duration: Duration
    ) {
        let evaluated = applied + equal + failed
        let snapshot = lock.withLock {
            rendererLifecycleState.projectionEvaluationTotal += 1
            rendererLifecycleState.projectionEvaluatedSurfaceTotal += evaluated
            rendererLifecycleState.projectionChangedSurfaceTotal += applied
            rendererLifecycleState.projectionEqualSurfaceTotal += equal
            rendererLifecycleState.sampleSequence += 1
            return rendererLifecycleState.snapshot
        }
        recordRendererLifecycleSnapshot(
            snapshot,
            eventKind: "projection_evaluation",
            projectionTrigger: trigger.rawValue,
            projectionEvaluationDelta: 1,
            projectionEvaluatedSurfaceDelta: evaluated,
            projectionChangedSurfaceDelta: applied,
            projectionEqualSurfaceDelta: equal,
            projectionMissingSurfaceDelta: missing,
            projectionFailedSurfaceDelta: failed,
            elapsedMilliseconds: Self.milliseconds(from: duration)
        )
    }

    package func rendererLifecycleSnapshot() -> RendererLifecyclePerformanceSnapshot {
        lock.withLock { rendererLifecycleState.snapshot }
    }

    private func recordRendererLifecycleSnapshot(
        _ snapshot: RendererLifecyclePerformanceSnapshot,
        eventKind: String,
        surfaceID: UUID? = nil,
        releaseReason: String? = nil,
        visibilityOutcome: String? = nil,
        projectionTrigger: String? = nil,
        requestedVisibility: Bool? = nil,
        createdDelta: Int = 0,
        releaseDelta: Int = 0,
        deinitializedFreeDelta: Int = 0,
        visibilityDeliveryDelta: Int = 0,
        visibilityEqualSuppressedDelta: Int = 0,
        projectionEvaluationDelta: Int = 0,
        projectionEvaluatedSurfaceDelta: Int = 0,
        projectionChangedSurfaceDelta: Int = 0,
        projectionEqualSurfaceDelta: Int = 0,
        projectionMissingSurfaceDelta: Int = 0,
        projectionFailedSurfaceDelta: Int = 0,
        elapsedMilliseconds: Double? = nil
    ) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.renderer.event.kind": .string(eventKind),
            "agentstudio.performance.renderer.created.delta": .int(createdDelta),
            "agentstudio.performance.renderer.created.total": .int(snapshot.successfulCreatedTotal),
            "agentstudio.performance.renderer.release.delta": .int(releaseDelta),
            "agentstudio.performance.renderer.release.total": .int(snapshot.permanentReleaseTotal),
            "agentstudio.performance.renderer.free.delta": .int(deinitializedFreeDelta),
            "agentstudio.performance.renderer.free.total": .int(snapshot.deinitializedFreeTotal),
            "agentstudio.performance.renderer.visibility.delivery.delta": .int(visibilityDeliveryDelta),
            "agentstudio.performance.renderer.visibility.delivery.total": .int(snapshot.visibilityDeliveryTotal),
            "agentstudio.performance.renderer.visibility.equal_suppressed.delta": .int(
                visibilityEqualSuppressedDelta
            ),
            "agentstudio.performance.renderer.visibility.equal_suppressed.total": .int(
                snapshot.visibilityEqualSuppressedTotal
            ),
            "agentstudio.performance.renderer.projection.evaluation.delta": .int(projectionEvaluationDelta),
            "agentstudio.performance.renderer.projection.evaluation.total": .int(
                snapshot.projectionEvaluationTotal
            ),
            "agentstudio.performance.renderer.projection.evaluated_surface.delta": .int(
                projectionEvaluatedSurfaceDelta
            ),
            "agentstudio.performance.renderer.projection.evaluated_surface.total": .int(
                snapshot.projectionEvaluatedSurfaceTotal
            ),
            "agentstudio.performance.renderer.projection.changed_surface.delta": .int(
                projectionChangedSurfaceDelta
            ),
            "agentstudio.performance.renderer.projection.changed_surface.total": .int(
                snapshot.projectionChangedSurfaceTotal
            ),
            "agentstudio.performance.renderer.projection.equal_surface.delta": .int(
                projectionEqualSurfaceDelta
            ),
            "agentstudio.performance.renderer.projection.equal_surface.total": .int(
                snapshot.projectionEqualSurfaceTotal
            ),
            "agentstudio.performance.renderer.projection.missing_surface.delta": .int(
                projectionMissingSurfaceDelta
            ),
            "agentstudio.performance.renderer.projection.failed_surface.delta": .int(
                projectionFailedSurfaceDelta
            ),
            "agentstudio.performance.renderer.active.current": .int(snapshot.activeCurrent),
            "agentstudio.performance.renderer.hidden.current": .int(snapshot.hiddenCurrent),
            "agentstudio.performance.renderer.close_undo.current": .int(snapshot.closeUndoCurrent),
            "agentstudio.performance.renderer.live.current": .int(snapshot.liveCurrent),
            "agentstudio.performance.renderer.manager_owned.current": .int(snapshot.managerOwnedCurrent),
            "agentstudio.performance.renderer.orphan_candidate.current": .int(snapshot.orphanCandidateCurrent),
            "agentstudio.performance.renderer.lifecycle.valid": .bool(snapshot.isValid),
            "agentstudio.performance.renderer.sample.sequence": .int(snapshot.sampleSequence),
        ]
        if let surfaceID {
            attributes["agentstudio.performance.renderer.surface_id"] = .string(surfaceID.uuidString)
        }
        if let releaseReason {
            attributes["agentstudio.performance.renderer.release.reason"] = .string(releaseReason)
        }
        if let visibilityOutcome {
            attributes["agentstudio.performance.renderer.visibility.outcome"] = .string(visibilityOutcome)
        }
        if let projectionTrigger {
            attributes["agentstudio.performance.renderer.projection.trigger"] = .string(projectionTrigger)
        }
        if let requestedVisibility {
            attributes["agentstudio.performance.renderer.visibility.requested_visible"] = .bool(requestedVisibility)
        }
        if let elapsedMilliseconds {
            attributes["agentstudio.performance.elapsed_ms"] = .double(elapsedMilliseconds)
        }
        record(.rendererLifecycle, attributes: attributes)
    }

    package func recordRepoAndWorktreeLookup(
        duration: Duration,
        indexCount: Int,
        hasMatch: Bool,
        fact: TopologyLookupFact
    ) {
        guard shouldRecordTopologyLookup(fact) else { return }
        recordDuration(
            .repoAndWorktreeLookup,
            duration: duration,
            attributes: [
                "agentstudio.performance.topology.index.count": .int(indexCount),
                "agentstudio.performance.topology.has_match": .bool(hasMatch),
            ]
        )
    }

    package func recordPaneAssociationOutcome(_ outcome: PaneAssociationOutcome) {
        guard shouldRecordPaneAssociationOutcome() else { return }
        record(
            .paneAssociation,
            attributes: [
                "agentstudio.performance.pane.association_outcome": .string(outcome.rawValue)
            ]
        )
    }

    package func recordPaneAssociationBootReconciliation(
        _ summary: PaneAssociationBootReconciliationSummary
    ) {
        record(
            .paneAssociationBootReconciliation,
            attributes: [
                "agentstudio.performance.pane.association_boot.pane.count": Self.traceInteger(
                    summary.paneCount
                ),
                "agentstudio.performance.pane.association_boot.retained_known.count": Self.traceInteger(
                    summary.retainedKnownCount
                ),
                "agentstudio.performance.pane.association_boot.backfilled.count": Self.traceInteger(
                    summary.backfilledCount
                ),
                "agentstudio.performance.pane.association_boot.dangling_cleared.count": Self.traceInteger(
                    summary.danglingClearedCount
                ),
                "agentstudio.performance.pane.association_boot.free_nil.count": Self.traceInteger(
                    summary.freeNilCount
                ),
                "agentstudio.performance.pane.association_boot.changed.count": Self.traceInteger(
                    summary.changedCount
                ),
            ]
        )
    }

    package func recordTerminalAccumulatorDrain(
        _ snapshot: TerminalAccumulatorDrainPerformanceSnapshot,
        queueAge: Duration,
        applyOutcome: TerminalAccumulatorApplyOutcome?
    ) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.terminal.accumulator.drain.class": .string(
                snapshot.drainClass.rawValue
            ),
            "agentstudio.performance.terminal.accumulator.offered.count": Self.traceInteger(
                snapshot.offeredCount),
            "agentstudio.performance.terminal.accumulator.replaced.count": Self.traceInteger(
                snapshot.replacedCount),
            "agentstudio.performance.terminal.accumulator.equal_suppressed.count": Self.traceInteger(
                snapshot.equalSuppressedCount),
            "agentstudio.performance.terminal.accumulator.scheduled_drain.count": Self.traceInteger(
                snapshot.scheduledDrainCount),
            "agentstudio.performance.terminal.accumulator.follow_up_drain.count": Self.traceInteger(
                snapshot.followUpDrainCount),
            "agentstudio.performance.terminal.accumulator.mainactor_task.count": Self.traceInteger(
                snapshot.mainActorTaskCount),
            "agentstudio.performance.terminal.activity_aggregate.count": Self.traceInteger(
                snapshot.activityAggregateCount),
            "agentstudio.performance.terminal.accumulator.retained_entry.count": Self.traceInteger(
                snapshot.retainedEntryCount),
            "agentstudio.performance.terminal.accumulator.retained_size_bytes": Self.traceInteger(
                snapshot.retainedSizeBytes),
        ]
        if let applyOutcome {
            attributes["agentstudio.performance.terminal.accumulator.apply.outcome"] = .string(
                applyOutcome.rawValue
            )
        }
        recordDuration(
            .terminalAccumulatorDrain,
            duration: queueAge,
            attributes: attributes
        )
    }

    package func recordTerminalEqualSuppressed(
        publicationKind: TerminalPerformancePublicationKind
    ) {
        record(
            .terminalEqualSuppressed,
            attributes: [
                "agentstudio.performance.terminal.publication.kind": .string(
                    publicationKind.rawValue
                ),
                "agentstudio.performance.terminal.equal_suppressed.count": .int(1),
            ]
        )
    }

    package func recordTerminalCompactApply(
        _ snapshot: TerminalCompactApplyPerformanceSnapshot,
        serviceTime: Duration
    ) {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.terminal.equal_write_suppressed.count": Self.traceInteger(
                snapshot.equalWriteSuppressedCount)
        ]
        switch snapshot.activityProjectionRoundTrip {
        case .notSubmitted:
            attributes["agentstudio.performance.terminal.activity_projection.submitted"] = .bool(false)
        case .completed(let duration):
            attributes["agentstudio.performance.terminal.activity_projection.submitted"] = .bool(true)
            attributes["agentstudio.performance.terminal.activity_projection.round_trip_ms"] = .double(
                Self.milliseconds(from: duration)
            )
        }
        recordDuration(
            .terminalCompactApply,
            duration: serviceTime,
            attributes: attributes
        )
    }

    package func recordFilesystemEffectSnapshot(_ snapshot: FilesystemEffectPerformanceSnapshot) {
        record(
            .filesystemEffectSnapshot,
            attributes: [
                "agentstudio.performance.filesystem.full_reconciliation_request.count": Self.traceInteger(
                    snapshot.fullReconciliationRequestCount),
                "agentstudio.performance.filesystem.affected_key_request.count": Self.traceInteger(
                    snapshot.affectedKeyRequestCount),
            ]
        )
    }

    package func recordTraceIdentitySnapshot(_ snapshot: TraceIdentityPerformanceSnapshot) {
        record(
            .traceIdentitySnapshot,
            attributes: [
                "agentstudio.performance.trace_identity.refresh_request.count": Self.traceInteger(
                    snapshot.refreshRequestCount),
                "agentstudio.performance.trace_identity.coalesced_request.count": Self.traceInteger(
                    snapshot.coalescedRequestCount),
                "agentstudio.performance.trace_identity.fleet_capture.count": Self.traceInteger(
                    snapshot.fleetCaptureCount),
                "agentstudio.performance.trace_identity.equal_snapshot_suppressed.count": Self.traceInteger(
                    snapshot.equalSnapshotSuppressedCount),
            ]
        )
    }

    func measure<T>(
        _ event: Event,
        attributes: @autoclosure () -> [String: AgentStudioTraceValue] = [:],
        operation: () throws -> T
    ) rethrows -> T {
        guard isEnabled else {
            return try operation()
        }

        let clock = ContinuousClock()
        let start = clock.now
        let result = try operation()
        recordDuration(
            event,
            duration: start.duration(to: clock.now),
            attributes: attributes()
        )
        return result
    }

    package func drain() async throws {
        await processMemorySampler?.stop()
        runtimeDeliveryPerformanceReporter?.disable()
        try await eventQueue?.drain()
        if eventQueue == nil {
            try await traceRuntime?.flush()
        }
    }

    package func flush() async throws {
        if let eventQueue {
            try await eventQueue.flush()
        } else {
            try await traceRuntime?.flush()
        }
    }

    package static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        let secondsMilliseconds = Double(components.seconds) * 1000
        let attosecondsMilliseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMilliseconds + attosecondsMilliseconds
    }

    private func shouldRecordTopologyLookup(_ fact: TopologyLookupFact) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return topologyLookupAdmission.admit(
            fact,
            now: ContinuousClock().now,
            window: AppPolicies.Diagnostics.topologyLookupTraceAdmissionWindow,
            limit: AppPolicies.Diagnostics.topologyLookupTraceAdmissionLimit
        )
    }

    private func shouldRecordPaneAssociationOutcome() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paneAssociationAdmission.admit(
            now: ContinuousClock().now,
            window: AppPolicies.Diagnostics.paneAssociationTraceAdmissionWindow,
            limit: AppPolicies.Diagnostics.paneAssociationTraceAdmissionLimit
        )
    }

    private static func traceInteger(_ value: UInt64) -> AgentStudioTraceValue {
        .int(Int(clamping: value))
    }
}

private struct PaneAssociationTraceAdmission {
    private var windowStart: ContinuousClock.Instant?
    private var admittedInWindow = 0

    mutating func admit(
        now: ContinuousClock.Instant,
        window: Duration,
        limit: Int
    ) -> Bool {
        resetWindowIfNeeded(now: now, window: window)
        guard admittedInWindow < limit else { return false }
        admittedInWindow += 1
        return true
    }

    private mutating func resetWindowIfNeeded(now: ContinuousClock.Instant, window: Duration) {
        guard let windowStart else {
            self.windowStart = now
            admittedInWindow = 0
            return
        }
        guard windowStart.duration(to: now) >= window else { return }
        self.windowStart = now
        admittedInWindow = 0
    }
}

private struct TopologyLookupTraceAdmission {
    private var windowStart: ContinuousClock.Instant?
    private var admittedInWindow = 0
    private var emittedFactGeneration: UInt64?
    private var emittedFacts: Set<AgentStudioPerformanceTraceRecorder.TopologyLookupFact> = []

    mutating func admit(
        _ fact: AgentStudioPerformanceTraceRecorder.TopologyLookupFact,
        now: ContinuousClock.Instant,
        window: Duration,
        limit: Int
    ) -> Bool {
        resetDeduplicationIfNeeded(for: fact)
        guard !emittedFacts.contains(fact) else { return false }
        resetWindowIfNeeded(now: now, window: window)
        guard admittedInWindow < limit else { return false }
        admittedInWindow += 1
        emittedFacts.insert(fact)
        return true
    }

    private mutating func resetDeduplicationIfNeeded(
        for fact: AgentStudioPerformanceTraceRecorder.TopologyLookupFact
    ) {
        guard emittedFactGeneration != fact.worktreePathIndexGeneration else { return }
        emittedFactGeneration = fact.worktreePathIndexGeneration
        emittedFacts.removeAll(keepingCapacity: true)
    }

    private mutating func resetWindowIfNeeded(now: ContinuousClock.Instant, window: Duration) {
        guard let windowStart else {
            self.windowStart = now
            admittedInWindow = 0
            return
        }
        guard windowStart.duration(to: now) >= window else { return }
        self.windowStart = now
        admittedInWindow = 0
    }
}
