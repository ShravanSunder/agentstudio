import Foundation

struct BridgeNativeCapacityTraceSample: Sendable {
    let event: AgentStudioPerformanceTraceRecorder.Event
    let duration: Duration?
    let attributes: [String: AgentStudioTraceValue]
}

enum BridgeNativeCapacityTraceRecorder {
    static func schedulerEventSink(
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) -> BridgeGitReadSchedulerEventSink? {
        guard let performanceTraceRecorder, performanceTraceRecorder.isEnabled else { return nil }
        return { event in
            record(
                schedulerSample(for: event),
                performanceTraceRecorder: performanceTraceRecorder
            )
        }
    }

    static func constructionEventSink(
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    ) -> BridgeWorktreeProductConstructionEventSink? {
        guard let performanceTraceRecorder, performanceTraceRecorder.isEnabled else { return nil }
        return { event in
            record(
                constructionSample(for: event),
                performanceTraceRecorder: performanceTraceRecorder
            )
        }
    }

    static func schedulerSample(
        for event: BridgeGitReadSchedulerEvent
    ) -> BridgeNativeCapacityTraceSample {
        let operationClass = event.operationClass
        let snapshot = event.snapshot
        return BridgeNativeCapacityTraceSample(
            event: .bridgeGitReadScheduler,
            duration: event.queueWait,
            attributes: [
                "agentstudio.bridge.phase": .string("git_read_scheduler"),
                "agentstudio.bridge.plane": .string(BridgeTelemetryPlane.data.rawValue),
                "agentstudio.bridge.priority": .string(priority(for: event.activityRank).rawValue),
                "agentstudio.bridge.slice": .string(slice(for: operationClass).rawValue),
                "agentstudio.bridge.native_capacity.event": .string(schedulerEventToken(event.kind)),
                "agentstudio.bridge.native_capacity.operation_class": .string(
                    operationClassToken(operationClass)
                ),
                "agentstudio.bridge.native_capacity.activity_rank": .string(
                    event.activityRank.telemetryToken
                ),
                "agentstudio.bridge.native_capacity.worktree_hash": .string(event.worktreeKey.token),
                "agentstudio.bridge.native_capacity.queued.count": .int(
                    snapshot.queuedCountByOperationClass[operationClass] ?? 0
                ),
                "agentstudio.bridge.native_capacity.running.count": .int(
                    snapshot.runningCountByOperationClass[operationClass] ?? 0
                ),
                "agentstudio.bridge.native_capacity.draining.count": .int(
                    snapshot.drainingCountByOperationClass[operationClass] ?? 0
                ),
                "agentstudio.bridge.native_capacity.occupied_slot.count": .int(
                    snapshot.occupiedSlotIds.count
                ),
                "agentstudio.bridge.native_capacity.logical_waiter.count": .int(
                    snapshot.logicalWaiterCount
                ),
                "agentstudio.bridge.native_capacity.coalesced_waiter.count": .int(
                    snapshot.coalescedLogicalWaiterCount
                ),
                "agentstudio.bridge.native_capacity.deadline.count": .int(
                    snapshot.scheduledDeadlineCount
                ),
                "agentstudio.bridge.native_capacity.worktree.count": .int(
                    snapshot.admittedWorktreeKeys.count
                ),
                "agentstudio.bridge.native_capacity.pane_activity.count": .int(
                    snapshot.paneActivityCount
                ),
                "agentstudio.bridge.native_capacity.fairness_history.count": .int(
                    snapshot.fairnessHistoryCount
                ),
            ]
        )
    }

    static func constructionSample(
        for event: BridgeWorktreeProductConstructionEvent
    ) -> BridgeNativeCapacityTraceSample {
        let snapshot = event.snapshot
        return BridgeNativeCapacityTraceSample(
            event: .bridgeWorktreeProductConstruction,
            duration: nil,
            attributes: [
                "agentstudio.bridge.phase": .string("worktree_product_construction"),
                "agentstudio.bridge.plane": .string(BridgeTelemetryPlane.data.rawValue),
                "agentstudio.bridge.priority": .string(BridgeTelemetryPriority.bestEffort.rawValue),
                "agentstudio.bridge.slice": .string(slice(for: event.productKind).rawValue),
                "agentstudio.bridge.native_capacity.event": .string(
                    constructionEventToken(event.kind)
                ),
                "agentstudio.bridge.native_capacity.product_kind": .string(event.productKind.rawValue),
                "agentstudio.bridge.native_capacity.worktree_hash": .string(event.worktreeHash),
                "agentstudio.bridge.native_capacity.entry.count": .int(snapshot.entryCount),
                "agentstudio.bridge.native_capacity.waiter.count": .int(snapshot.waiterCount),
                "agentstudio.bridge.native_capacity.lease.count": .int(snapshot.leaseCount),
                "agentstudio.bridge.native_capacity.payload.count": .int(snapshot.payloadCount),
                "agentstudio.bridge.native_capacity.in_flight.count": .int(snapshot.inFlightCount),
                "agentstudio.bridge.native_capacity.locator.count": .int(snapshot.locatorCount),
                "agentstudio.bridge.native_capacity.tombstone.count": .int(
                    snapshot.drainingTombstoneCount
                ),
                "agentstudio.bridge.native_capacity.retained_artifact_byte.count": .int(
                    snapshot.retainedArtifactByteCount
                ),
            ]
        )
    }

    private static func record(
        _ sample: BridgeNativeCapacityTraceSample,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder
    ) {
        if let duration = sample.duration {
            performanceTraceRecorder.recordDuration(
                sample.event,
                duration: duration,
                attributes: sample.attributes
            )
        } else {
            performanceTraceRecorder.record(sample.event, attributes: sample.attributes)
        }
    }

    private static func priority(
        for activityRank: BridgeGitReadActivityRank
    ) -> BridgeTelemetryPriority {
        switch activityRank {
        case .foreground:
            return .hot
        case .loadedHidden:
            return .warm
        case .dormant, .unranked:
            return .bestEffort
        }
    }

    private static func slice(
        for operationClass: BridgeGitReadOperationClass
    ) -> BridgeTelemetrySlice {
        switch operationClass {
        case .reviewMetadata:
            return .reviewMetadata
        case .selectedVisibleContent:
            return .contentFetch
        }
    }

    private static func slice(
        for productKind: BridgeWorktreeProductKind
    ) -> BridgeTelemetrySlice {
        switch productKind {
        case .file:
            return .treePrepareInput
        case .review:
            return .reviewMetadata
        }
    }

    private static func operationClassToken(
        _ operationClass: BridgeGitReadOperationClass
    ) -> String {
        switch operationClass {
        case .reviewMetadata:
            return "review_metadata"
        case .selectedVisibleContent:
            return "selected_visible_content"
        }
    }

    private static func schedulerEventToken(_ kind: BridgeGitReadSchedulerEventKind) -> String {
        switch kind {
        case .queued:
            return "queued"
        case .coalesced:
            return "coalesced"
        case .started:
            return "started"
        case .logicalTimeout:
            return "logical_timeout"
        case .logicalCancellation:
            return "logical_cancellation"
        case .draining:
            return "draining"
        case .physicallyReturned:
            return "physically_returned"
        case .slotReleased:
            return "slot_released"
        }
    }

    private static func constructionEventToken(
        _ kind: BridgeWorktreeProductConstructionEventKind
    ) -> String {
        switch kind {
        case .buildStarted:
            return "build_started"
        case .consumerJoined:
            return "consumer_joined"
        case .consumerCancelled:
            return "consumer_cancelled"
        case .invalidated:
            return "invalidated"
        case .buildReady:
            return "build_ready"
        case .filePreparationPublished:
            return "file_preparation_published"
        case .fileWindowAppended:
            return "file_window_appended"
        case .buildFailed:
            return "build_failed"
        case .staleCompletionDropped:
            return "stale_completion_dropped"
        case .tombstoneCreated:
            return "tombstone_created"
        case .leaseReleased:
            return "lease_released"
        case .entryRemoved:
            return "entry_removed"
        }
    }
}
