import Foundation

extension Ghostty.ActionRouter {
    @MainActor
    static func flushLocalActions(for surfaceID: UUID) async {
        await drainLocalActions(for: surfaceID)
    }

    @MainActor
    static func applyOrderedActivityControl(
        surfaceID: UUID,
        paneID: UUID,
        control: TerminalActivityOrderedControl,
        contextBeforeControl: TerminalActivityProjectionContext? = nil,
        contextAfterControl: TerminalActivityProjectionContext? = nil
    ) async {
        let currentContext = terminalActivityProjectionContext(paneID: paneID)
        let precedingAggregate = localActionAccumulator.detachActivityBeforeControl(
            for: surfaceID,
            contextBeforeControl: contextBeforeControl ?? currentContext,
            contextAfterControl: contextAfterControl
        )
        await submitTerminalActivityInput(
            .orderedControl(
                surfaceID: surfaceID,
                paneID: paneID,
                precedingAggregate: precedingAggregate,
                control: control
            )
        )
    }

    @MainActor
    static func closeLocalActions(surfaceID: UUID, paneID: UUID) {
        let precedingAggregate = localActionAccumulator.detachActivityForSurfaceClose(
            surfaceID,
            defaultActivityContext: terminalActivityProjectionContext(paneID: paneID)
        )
        Task { @MainActor in
            await submitTerminalActivityInput(
                .orderedControl(
                    surfaceID: surfaceID,
                    paneID: paneID,
                    precedingAggregate: precedingAggregate,
                    control: .surfaceClosed
                )
            )
        }
    }

    static func offerLocalPresentation(
        _ presentation: TerminalLocalPresentationAction,
        for surfaceID: UUID
    ) {
        switch presentation {
        case .mouseShape(let shape):
            localActionAccumulator.offer(.mouseShape(shape), for: surfaceID)
        case .mouseVisibility(let isVisible):
            localActionAccumulator.offer(.mouseVisibility(isVisible), for: surfaceID)
        case .searchMatches(let totalMatches):
            localActionAccumulator.offer(.searchMatches(totalMatches), for: surfaceID)
        case .searchSelection(let selectedMatchIndex):
            localActionAccumulator.offer(.searchSelection(selectedMatchIndex), for: surfaceID)
        }
    }

    static func offerLocalActivityEvidence(
        _ evidence: TerminalLocalActivityEvidence,
        for surfaceID: UUID
    ) {
        switch evidence {
        case .scrollbar(let state):
            localActionAccumulator.offer(
                .scrollbar(
                    state,
                    observedAtMilliseconds: Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
                ),
                for: surfaceID
            )
        }
    }

    static func offerLocalLifecycle(
        _ lifecycle: TerminalLocalLifecycleAction,
        for surfaceID: UUID
    ) {
        switch lifecycle {
        case .searchStarted(let query):
            localActionAccumulator.offer(.searchStarted(query: query), for: surfaceID)
        case .searchEnded:
            localActionAccumulator.offer(.searchEnded, for: surfaceID)
        }
    }

    @MainActor
    static func drainLocalActions(for surfaceID: UUID) async {
        guard
            let surfaceView = SurfaceManager.shared.surface(for: surfaceID),
            surfaceView.managedSurfaceID == surfaceID,
            let paneUUID = SurfaceManager.shared.paneId(for: surfaceID)
        else {
            localActionAccumulator.removeSurface(surfaceID)
            return
        }

        guard
            let batch = localActionAccumulator.beginDrain(
                for: surfaceID,
                defaultActivityContext: terminalActivityProjectionContext(paneID: paneUUID)
            )
        else { return }
        defer {
            _ = localActionAccumulator.finishDrain(for: surfaceID)
        }

        let paneID = PaneId(existingUUID: paneUUID)
        let routedRuntime = runtimeRegistryForActionRouting.runtime(for: paneID) as? TerminalRuntime
        let runtime =
            routedRuntime
            ?? (ObjectIdentifier(runtimeRegistryForActionRouting) != ObjectIdentifier(RuntimeRegistry.shared)
                ? RuntimeRegistry.shared.runtime(for: paneID) as? TerminalRuntime
                : nil)
        guard let runtime else {
            localActionAccumulator.removeSurface(surfaceID)
            return
        }

        if let scrollbarState = batch.presentation.scrollbarState,
            surfaceView.hostScrollbarState != scrollbarState
        {
            surfaceView.updateHostScrollbarState(scrollbarState)
        }
        let clock = ContinuousClock()
        let applyStartedAt = clock.now
        let equalWriteSuppressedCount = runtime.applyLocalActionBatch(batch)
        if let aggregate = batch.activity,
            let latestState = batch.presentation.scrollbarState,
            let context = batch.activityContext
        {
            await submitTerminalActivityInput(
                .aggregate(
                    surfaceID: surfaceID,
                    paneID: paneUUID,
                    input: TerminalActivityAggregateInput(
                        aggregate: aggregate,
                        latestState: latestState,
                        context: context
                    )
                )
            )
        }
        surfaceView.performanceTraceRecorder?.recordTerminalCompactApply(
            TerminalCompactApplyPerformanceSnapshot(
                equalWriteSuppressedCount: UInt64(equalWriteSuppressedCount)
            ),
            serviceTime: applyStartedAt.duration(to: clock.now)
        )
        let currentUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let queueAgeNanoseconds =
            currentUptimeNanoseconds >= batch.firstOfferedAtNanoseconds
            ? currentUptimeNanoseconds - batch.firstOfferedAtNanoseconds
            : 0
        surfaceView.performanceTraceRecorder?.recordTerminalAccumulatorDrain(
            TerminalAccumulatorDrainPerformanceSnapshot(
                offeredCount: batch.metrics.offeredCount,
                replacedCount: batch.metrics.replacedCount,
                equalSuppressedCount: batch.metrics.equalSuppressedCount,
                scheduledDrainCount: batch.metrics.scheduledDrainCount,
                followUpDrainCount: batch.metrics.followUpDrainCount,
                mainActorTaskCount: 1,
                activityAggregateCount: batch.activity == nil ? 0 : 1,
                retainedEntryCount: UInt64(batch.retainedEntryCount),
                retainedSizeBytes: UInt64(batch.retainedEntryCount * 64)
            ),
            queueAge: .nanoseconds(Int64(clamping: queueAgeNanoseconds))
        )
    }
}
