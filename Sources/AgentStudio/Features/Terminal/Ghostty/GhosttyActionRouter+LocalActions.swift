import Foundation
import GhosttyKit

enum GhosttyTranslatedActionAdmission: Sendable, Equatable {
    case routeExactFactOrControl
    case updateDirectHostState
    case handledLocally
}

extension Ghostty.ActionRouter {
    static func admitTranslatedActionToTerminalRuntime(
        _ event: GhosttyEvent,
        surfaceID: UUID,
        accumulator: TerminalLocalActionAccumulator
    ) -> GhosttyTranslatedActionAdmission {
        switch GhosttyActionDisposition.classify(event) {
        case .exactFactOrControl:
            return .routeExactFactOrControl
        case .latestPresentation(let presentation):
            offerLocalPresentation(presentation, for: surfaceID, accumulator: accumulator)
            return .handledLocally
        case .latestSemanticMetadata(let metadata):
            offerLatestSemanticMetadata(metadata, for: surfaceID, accumulator: accumulator)
            return .handledLocally
        case .activityEvidence(let evidence):
            offerLocalActivityEvidence(evidence, for: surfaceID, accumulator: accumulator)
            return .handledLocally
        case .exactLocalLifecycle(let lifecycle):
            offerLocalLifecycle(lifecycle, for: surfaceID, accumulator: accumulator)
            return .handledLocally
        case .diagnostic(.directHostState):
            return .updateDirectHostState
        case .diagnostic(.localOnly), .diagnostic(.deferred), .diagnostic(.unhandled):
            return .handledLocally
        }
    }

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
        for surfaceID: UUID,
        accumulator: TerminalLocalActionAccumulator
    ) {
        switch presentation {
        case .mouseShape(let shape):
            accumulator.offer(.mouseShape(shape), for: surfaceID)
        case .mouseVisibility(let isVisible):
            accumulator.offer(.mouseVisibility(isVisible), for: surfaceID)
        case .searchMatches(let totalMatches):
            accumulator.offer(.searchMatches(totalMatches), for: surfaceID)
        case .searchSelection(let selectedMatchIndex):
            accumulator.offer(.searchSelection(selectedMatchIndex), for: surfaceID)
        }
    }

    static func offerLocalActivityEvidence(
        _ evidence: TerminalLocalActivityEvidence,
        for surfaceID: UUID,
        accumulator: TerminalLocalActionAccumulator
    ) {
        switch evidence {
        case .scrollbar(let state):
            accumulator.offer(
                .scrollbar(
                    state,
                    observedAtMilliseconds: Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
                ),
                for: surfaceID
            )
        }
    }

    static func offerLatestSemanticMetadata(
        _ metadata: TerminalLatestSemanticMetadataAction,
        for surfaceID: UUID,
        accumulator: TerminalLocalActionAccumulator
    ) {
        switch metadata {
        case .titleChanged(let title):
            accumulator.offer(.titleChanged(title), for: surfaceID)
        case .tabTitleChanged(let title):
            accumulator.offer(.tabTitleChanged(title), for: surfaceID)
        }
    }

    static func offerLocalLifecycle(
        _ lifecycle: TerminalLocalLifecycleAction,
        for surfaceID: UUID,
        accumulator: TerminalLocalActionAccumulator
    ) {
        switch lifecycle {
        case .searchStarted(let query):
            accumulator.offer(.searchStarted(query: query), for: surfaceID)
        case .searchEnded:
            accumulator.offer(.searchEnded, for: surfaceID)
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
        if let surfaceTitle = batch.titleMetadata?.surfaceTitle,
            surfaceView.title != surfaceTitle
        {
            surfaceView.titleDidChange(surfaceTitle)
        }
        let clock = ContinuousClock()
        let applyStartedAt = clock.now
        let equalWriteSuppressedCount = runtime.applyLocalActionBatch(batch)
        if let runtimeTitle = batch.titleMetadata?.runtimeTitle {
            routeContractedTitleMetadata(
                runtimeTitle,
                surfaceViewObjectID: ObjectIdentifier(surfaceView),
                routingLookup: SurfaceManager.shared
            )
        }
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

    @MainActor
    static func routeContractedTitleMetadata(
        _ metadata: TerminalLatestSemanticMetadataAction,
        surfaceViewObjectID: ObjectIdentifier,
        routingLookup: any GhosttyActionRoutingLookup
    ) {
        let actionTag: UInt32
        let payload: GhosttyAdapter.ActionPayload
        switch metadata {
        case .titleChanged(let title):
            actionTag = UInt32(GHOSTTY_ACTION_SET_TITLE.rawValue)
            payload = .titleChanged(title)
        case .tabTitleChanged(let title):
            actionTag = UInt32(GHOSTTY_ACTION_SET_TAB_TITLE.rawValue)
            payload = .tabTitleChanged(title)
        }
        _ = routeActionToTerminalRuntimeOnMainActor(
            actionTag: actionTag,
            payload: payload,
            surfaceViewObjectId: surfaceViewObjectID,
            routingLookup: routingLookup
        )
    }
}
