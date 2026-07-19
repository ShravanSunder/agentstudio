import Foundation

struct TerminalActivityProjectionContext: Sendable, Equatable {
    let isAttended: Bool
    let isAgentClassified: Bool
    let outputBurstThreshold: Int
}

struct TerminalActivityAggregateInput: Sendable, Equatable {
    let aggregate: TerminalScrollbarActivityAggregate
    let latestState: ScrollbarState
    let context: TerminalActivityProjectionContext
}

enum TerminalActivityOrderedControl: Sendable, Equatable {
    case contextChanged(TerminalActivityProjectionContext)
    case observed
    case semanticSignal
    case surfaceClosed
}

struct TerminalActivityCompactUpdate: Sendable, Equatable {
    let surfaceID: UUID
    let paneID: UUID
    let scrollbarState: ScrollbarState
    let outputBurst: TerminalOutputBurstState
}

enum TerminalActivityProjectionOutcome: Sendable, Equatable {
    case compactStateChanged(TerminalActivityCompactUpdate)
    case firstOutput(surfaceID: UUID, paneID: UUID)
    case paneObservationChanged(surfaceID: UUID, paneID: UUID, isPinnedToBottom: Bool)
    case unseenActivitySettled(surfaceID: UUID, paneID: UUID, activity: TerminalSettledActivity)
    case agentSettledActivityPromoted(surfaceID: UUID, paneID: UUID, activity: TerminalSettledActivity)
    case agentSettledActivityRevoked(surfaceID: UUID, paneID: UUID)
    case surfaceClosed(surfaceID: UUID, paneID: UUID?)
}

enum TerminalActivitySourceInput: Sendable, Equatable {
    case aggregate(
        surfaceID: UUID,
        paneID: UUID,
        input: TerminalActivityAggregateInput
    )
    case orderedControl(
        surfaceID: UUID,
        paneID: UUID,
        precedingAggregate: TerminalActivityAggregateInput?,
        control: TerminalActivityOrderedControl
    )
}

/// Owns terminal activity derivation and quiet timers off MainActor.
/// Admission is bounded by the upstream per-surface accumulator: its drain awaits
/// each ingestion, so a live surface can have at most one actor call plus one
/// coalesced follow-up batch.
actor TerminalActivityProjector {
    typealias OutcomeSink = @MainActor @Sendable ([TerminalActivityProjectionOutcome]) -> Void

    private struct ActivityWindow: Sendable {
        let id: UUID
        let surfaceID: UUID
        let paneID: UUID
        let thresholdRows: Int
        let startedAtMilliseconds: Int64
        var lastObservedAtMilliseconds: Int64
        var eventCount: Int
        var rowsAdded: Int
        var baselineRows: Int
        var latestRows: Int
        var latestIsPinnedToBottom: Bool
        var generation: UInt64
    }

    private struct ActivityWindowCloseTarget: Sendable {
        let windowID: UUID
        let surfaceID: UUID
        let paneID: UUID
        let generation: UInt64
    }

    private struct PaneState {
        let surfaceID: UUID
        var outputBurst: TerminalOutputBurstState
        var scrollbarState: ScrollbarState?
        var isPinnedToBottom: Bool?
        var didObserveFirstOutput = false
        var unseenWindow: ActivityWindow?
        var agentCandidate: ActivityWindow?
        var agentSettledLatestRows: Int?
        var isAgentSettledSuppressed = false
    }

    private let unseenQuietDuration: Duration
    private let agentSettledQuietDuration: Duration
    private let delay: AsyncDelay
    private var outcomeSink: OutcomeSink?
    private var paneStates: [UUID: PaneState] = [:]
    private var unseenCloseTasks: [UUID: Task<Void, Never>] = [:]
    private var agentCloseTasks: [UUID: Task<Void, Never>] = [:]
    private var unseenRetirementTasks: [UUID: Task<Void, Never>] = [:]
    private var agentRetirementTasks: [UUID: Task<Void, Never>] = [:]

    init(
        unseenQuietDuration: Duration = AppPolicies.InboxNotification.terminalActivityQuietDebounceDuration,
        agentSettledQuietDuration: Duration = AppPolicies.InboxNotification.agentSettledQuietDuration,
        clock: (any Clock<Duration> & Sendable)? = nil
    ) {
        self.unseenQuietDuration = unseenQuietDuration
        self.agentSettledQuietDuration = agentSettledQuietDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
    }

    func configure(outcomeSink: @escaping OutcomeSink) {
        self.outcomeSink = outcomeSink
    }

    func ingest(
        surfaceID: UUID,
        paneID: UUID,
        aggregate: TerminalScrollbarActivityAggregate,
        latestState: ScrollbarState,
        context: TerminalActivityProjectionContext
    ) async {
        let outcomes = consumeAggregateState(
            surfaceID: surfaceID,
            paneID: paneID,
            aggregate: aggregate,
            latestState: latestState,
            context: context
        )
        await emit(outcomes)
    }

    private func consumeAggregateState(
        surfaceID: UUID,
        paneID: UUID,
        aggregate: TerminalScrollbarActivityAggregate,
        latestState: ScrollbarState,
        context: TerminalActivityProjectionContext
    ) -> [TerminalActivityProjectionOutcome] {
        var state: PaneState
        var replacedSurfaceID: UUID?
        if let existingState = paneStates[paneID], existingState.surfaceID != surfaceID {
            cancelTimers(for: paneID)
            paneStates.removeValue(forKey: paneID)
            replacedSurfaceID = existingState.surfaceID
            state = PaneState(surfaceID: surfaceID, outputBurst: .unknown)
        } else {
            state =
                paneStates[paneID]
                ?? PaneState(surfaceID: surfaceID, outputBurst: .unknown)
        }

        let outputBurst = nextOutputBurst(
            current: state.outputBurst,
            aggregate: aggregate,
            threshold: context.outputBurstThreshold
        )
        let compactStateChanged = state.scrollbarState != latestState || state.outputBurst != outputBurst
        state.outputBurst = outputBurst
        let previousPinned = state.isPinnedToBottom
        let observationTransitions = pinnedObservationTransitions(
            previousIsPinnedToBottom: previousPinned,
            aggregate: aggregate,
            latestIsPinnedToBottom: latestState.isPinnedToBottom
        )
        state.isPinnedToBottom = latestState.isPinnedToBottom
        state.scrollbarState = latestState

        if context.isAttended {
            cancelUnseenWindow(for: paneID)
            state.unseenWindow = nil
        } else {
            state.unseenWindow = mergeWindow(
                state.unseenWindow,
                surfaceID: surfaceID,
                paneID: paneID,
                threshold: context.outputBurstThreshold,
                aggregate: aggregate,
                latestState: latestState
            )
            scheduleUnseenClose(for: paneID, state: state)
        }

        var shouldRevokeAgentSettledActivity = false
        if state.agentSettledLatestRows != nil {
            state.agentSettledLatestRows = nil
            state.isAgentSettledSuppressed = true
            shouldRevokeAgentSettledActivity = true
        }
        if context.isAgentClassified, !state.isAgentSettledSuppressed {
            state.agentCandidate = mergeWindow(
                state.agentCandidate,
                surfaceID: surfaceID,
                paneID: paneID,
                threshold: context.outputBurstThreshold,
                aggregate: aggregate,
                latestState: latestState
            )
            scheduleAgentClose(for: paneID, state: state)
        } else {
            cancelAgentCandidate(for: paneID)
            state.agentCandidate = nil
        }

        let isFirstOutput = aggregate.latestTotalRows > 0 && !state.didObserveFirstOutput
        state.didObserveFirstOutput = state.didObserveFirstOutput || aggregate.latestTotalRows > 0
        paneStates[paneID] = state
        var outcomes: [TerminalActivityProjectionOutcome] = []
        if let replacedSurfaceID {
            outcomes.append(.surfaceClosed(surfaceID: replacedSurfaceID, paneID: paneID))
        }
        if shouldRevokeAgentSettledActivity {
            outcomes.append(.agentSettledActivityRevoked(surfaceID: surfaceID, paneID: paneID))
        }
        if compactStateChanged {
            outcomes.append(
                .compactStateChanged(
                    TerminalActivityCompactUpdate(
                        surfaceID: surfaceID,
                        paneID: paneID,
                        scrollbarState: latestState,
                        outputBurst: outputBurst
                    )
                )
            )
        }
        if isFirstOutput {
            outcomes.append(.firstOutput(surfaceID: surfaceID, paneID: paneID))
        }
        for isPinnedToBottom in observationTransitions {
            outcomes.append(
                .paneObservationChanged(
                    surfaceID: surfaceID,
                    paneID: paneID,
                    isPinnedToBottom: isPinnedToBottom
                )
            )
        }
        return outcomes
    }

    private func pinnedObservationTransitions(
        previousIsPinnedToBottom: Bool?,
        aggregate: TerminalScrollbarActivityAggregate,
        latestIsPinnedToBottom: Bool
    ) -> [Bool] {
        var projectedIsPinnedToBottom = previousIsPinnedToBottom
        var transitions: [Bool] = []
        func appendChangedState(_ isPinnedToBottom: Bool) {
            guard isPinnedToBottom != projectedIsPinnedToBottom else { return }
            transitions.append(isPinnedToBottom)
            projectedIsPinnedToBottom = isPinnedToBottom
        }

        appendChangedState(aggregate.firstIsPinnedToBottom)
        if aggregate.firstIsPinnedToBottom {
            if aggregate.didExitPinnedToBottom { appendChangedState(false) }
            if aggregate.didEnterPinnedToBottom { appendChangedState(true) }
        } else {
            if aggregate.didEnterPinnedToBottom { appendChangedState(true) }
            if aggregate.didExitPinnedToBottom { appendChangedState(false) }
        }
        appendChangedState(latestIsPinnedToBottom)
        return transitions
    }

    func applyOrderedControl(
        surfaceID: UUID,
        paneID: UUID,
        precedingAggregate: TerminalActivityAggregateInput?,
        control: TerminalActivityOrderedControl
    ) async {
        var outcomes: [TerminalActivityProjectionOutcome] = []
        if let precedingAggregate {
            outcomes.append(
                contentsOf: consumeAggregateState(
                    surfaceID: surfaceID,
                    paneID: paneID,
                    aggregate: precedingAggregate.aggregate,
                    latestState: precedingAggregate.latestState,
                    context: precedingAggregate.context
                )
            )
        }
        switch control {
        case .contextChanged(let context):
            applyContextChange(surfaceID: surfaceID, paneID: paneID, context: context)
        case .observed:
            markObserved(surfaceID: surfaceID, paneID: paneID)
        case .semanticSignal:
            semanticSignal(surfaceID: surfaceID, paneID: paneID)
        case .surfaceClosed:
            closeSurfaceState(surfaceID: surfaceID, paneID: paneID)
            outcomes.append(.surfaceClosed(surfaceID: surfaceID, paneID: paneID))
        }
        await emit(outcomes)
    }

    func markObserved(surfaceID: UUID, paneID: UUID) {
        guard var state = paneStates[paneID], state.surfaceID == surfaceID else { return }
        cancelTimers(for: paneID)
        state.unseenWindow = nil
        state.agentCandidate = nil
        state.agentSettledLatestRows = nil
        state.isAgentSettledSuppressed = false
        paneStates[paneID] = state
    }

    func semanticSignal(surfaceID: UUID, paneID: UUID) {
        guard var state = paneStates[paneID], state.surfaceID == surfaceID else { return }
        cancelAgentCandidate(for: paneID)
        state.agentCandidate = nil
        paneStates[paneID] = state
    }

    private func applyContextChange(
        surfaceID: UUID,
        paneID: UUID,
        context: TerminalActivityProjectionContext
    ) {
        guard var state = paneStates[paneID], state.surfaceID == surfaceID else { return }
        if context.isAttended {
            cancelUnseenWindow(for: paneID)
            state.unseenWindow = nil
        }
        if !context.isAgentClassified {
            cancelAgentCandidate(for: paneID)
            state.agentCandidate = nil
        }
        paneStates[paneID] = state
    }

    func closeSurface(surfaceID: UUID, paneID: UUID?) async {
        closeSurfaceState(surfaceID: surfaceID, paneID: paneID)
        await emit([.surfaceClosed(surfaceID: surfaceID, paneID: paneID)])
    }

    private func closeSurfaceState(surfaceID: UUID, paneID: UUID?) {
        if let paneID, paneStates[paneID]?.surfaceID == surfaceID {
            cancelTimers(for: paneID)
            paneStates.removeValue(forKey: paneID)
        }
    }

    private func emit(_ outcomes: [TerminalActivityProjectionOutcome]) async {
        guard !outcomes.isEmpty, let outcomeSink else { return }
        await outcomeSink(outcomes)
    }

    func reset() {
        for task in unseenCloseTasks.values { task.cancel() }
        for task in agentCloseTasks.values { task.cancel() }
        unseenCloseTasks.removeAll()
        agentCloseTasks.removeAll()
        unseenRetirementTasks.removeAll()
        agentRetirementTasks.removeAll()
        paneStates.removeAll()
        outcomeSink = nil
    }

    var retainedPaneCount: Int { paneStates.count }
    var scheduledTimerCount: Int { unseenCloseTasks.count + agentCloseTasks.count }

    private func mergeWindow(
        _ existing: ActivityWindow?,
        surfaceID: UUID,
        paneID: UUID,
        threshold: Int,
        aggregate: TerminalScrollbarActivityAggregate,
        latestState: ScrollbarState
    ) -> ActivityWindow {
        var window =
            existing
            ?? ActivityWindow(
                id: UUIDv7.generate(),
                surfaceID: surfaceID,
                paneID: paneID,
                thresholdRows: threshold,
                startedAtMilliseconds: aggregate.firstObservedAtMilliseconds,
                lastObservedAtMilliseconds: aggregate.firstObservedAtMilliseconds,
                eventCount: 0,
                rowsAdded: 0,
                baselineRows: aggregate.firstTotalRows,
                latestRows: aggregate.firstTotalRows,
                latestIsPinnedToBottom: aggregate.firstIsPinnedToBottom,
                generation: 0
            )
        window.lastObservedAtMilliseconds = aggregate.latestObservedAtMilliseconds
        window.eventCount += aggregate.sampleCount
        window.rowsAdded += aggregate.cumulativePositiveRowGrowth
        window.latestRows = aggregate.latestTotalRows
        window.latestIsPinnedToBottom = latestState.isPinnedToBottom
        window.generation &+= 1
        return window
    }

    private func nextOutputBurst(
        current: TerminalOutputBurstState,
        aggregate: TerminalScrollbarActivityAggregate,
        threshold: Int
    ) -> TerminalOutputBurstState {
        let baseline: Int
        let priorRowsAdded: Int
        switch current {
        case .unknown:
            baseline = aggregate.firstTotalRows
            priorRowsAdded = 0
        case .quiet(let lastTotal):
            baseline = lastTotal
            priorRowsAdded = 0
        case .accumulating(let burst):
            baseline = burst.baselineTotal
            priorRowsAdded = burst.addedRows
        }
        let rowsAdded =
            priorRowsAdded
            + max(0, aggregate.firstTotalRows - (currentLatestTotal(current) ?? aggregate.firstTotalRows))
            + aggregate.cumulativePositiveRowGrowth
        guard rowsAdded > 0 else { return .quiet(lastTotal: aggregate.latestTotalRows) }
        return .accumulating(
            TerminalOutputBurst(
                baselineTotal: baseline,
                latestTotal: aggregate.latestTotalRows,
                addedRows: rowsAdded,
                threshold: threshold
            )
        )
    }

    private func currentLatestTotal(_ state: TerminalOutputBurstState) -> Int? {
        switch state {
        case .unknown: return nil
        case .quiet(let lastTotal): return lastTotal
        case .accumulating(let burst): return burst.latestTotal
        }
    }

    private func scheduleUnseenClose(for paneID: UUID, state: PaneState) {
        unseenCloseTasks[paneID]?.cancel()
        guard let window = state.unseenWindow else { return }
        let delay = self.delay
        let duration = unseenQuietDuration
        let retirementTask = unseenRetirementTasks.removeValue(forKey: paneID)
        let closeTarget = ActivityWindowCloseTarget(
            windowID: window.id,
            surfaceID: window.surfaceID,
            paneID: window.paneID,
            generation: window.generation
        )
        unseenCloseTasks[paneID] = Task { [weak self] in
            await retirementTask?.value
            guard !Task.isCancelled else { return }
            do { try await delay.wait(duration) } catch { return }
            await self?.closeUnseenWindow(target: closeTarget)
        }
    }

    private func scheduleAgentClose(for paneID: UUID, state: PaneState) {
        agentCloseTasks[paneID]?.cancel()
        guard let candidate = state.agentCandidate else { return }
        let delay = self.delay
        let duration = agentSettledQuietDuration
        let retirementTask = agentRetirementTasks.removeValue(forKey: paneID)
        let closeTarget = ActivityWindowCloseTarget(
            windowID: candidate.id,
            surfaceID: candidate.surfaceID,
            paneID: candidate.paneID,
            generation: candidate.generation
        )
        agentCloseTasks[paneID] = Task { [weak self] in
            await retirementTask?.value
            guard !Task.isCancelled else { return }
            do { try await delay.wait(duration) } catch { return }
            await self?.closeAgentCandidate(target: closeTarget)
        }
    }

    private func closeUnseenWindow(target: ActivityWindowCloseTarget) async {
        guard var state = paneStates[target.paneID],
            state.surfaceID == target.surfaceID,
            let window = state.unseenWindow,
            window.id == target.windowID,
            window.surfaceID == target.surfaceID,
            window.paneID == target.paneID,
            window.generation == target.generation
        else { return }
        unseenCloseTasks[target.paneID] = nil
        state.unseenWindow = nil
        paneStates[target.paneID] = state
        guard window.rowsAdded > 0 else { return }
        await emit([
            .unseenActivitySettled(
                surfaceID: window.surfaceID,
                paneID: target.paneID,
                activity: settledActivity(window, quietDuration: unseenQuietDuration)
            )
        ])
    }

    private func closeAgentCandidate(target: ActivityWindowCloseTarget) async {
        guard var state = paneStates[target.paneID],
            state.surfaceID == target.surfaceID,
            let candidate = state.agentCandidate,
            candidate.id == target.windowID,
            candidate.surfaceID == target.surfaceID,
            candidate.paneID == target.paneID,
            candidate.generation == target.generation
        else { return }
        agentCloseTasks[target.paneID] = nil
        state.agentCandidate = nil
        guard isAgentSettledCandidate(candidate) else {
            paneStates[target.paneID] = state
            return
        }
        state.agentSettledLatestRows = candidate.latestRows
        paneStates[target.paneID] = state
        await emit([
            .agentSettledActivityPromoted(
                surfaceID: candidate.surfaceID,
                paneID: target.paneID,
                activity: settledActivity(candidate, quietDuration: agentSettledQuietDuration)
            )
        ])
    }

    private func isAgentSettledCandidate(_ candidate: ActivityWindow) -> Bool {
        guard candidate.rowsAdded >= AppPolicies.InboxNotification.agentSettledMinimumRows else { return false }
        let activeDuration = candidate.lastObservedAtMilliseconds - candidate.startedAtMilliseconds
        let minimumCandidate = Self.milliseconds(
            AppPolicies.InboxNotification.agentSettledMinimumCandidateDuration
        )
        guard activeDuration >= Int64(minimumCandidate) else { return false }
        let minimumActive = Self.milliseconds(AppPolicies.InboxNotification.agentSettledMinimumActiveDuration)
        return candidate.rowsAdded >= AppPolicies.InboxNotification.agentSettledHighConfidenceRows
            || activeDuration >= Int64(minimumActive)
    }

    private func settledActivity(_ window: ActivityWindow, quietDuration: Duration) -> TerminalSettledActivity {
        let debounceMilliseconds = Self.milliseconds(quietDuration)
        return TerminalSettledActivity(
            burstWindowId: window.id,
            thresholdRows: window.thresholdRows,
            debounceMilliseconds: debounceMilliseconds,
            startedAtMilliseconds: window.startedAtMilliseconds,
            settledAtMilliseconds: window.lastObservedAtMilliseconds + Int64(debounceMilliseconds),
            eventCount: window.eventCount,
            rowsAdded: window.rowsAdded,
            baselineRows: window.baselineRows,
            latestRows: window.latestRows,
            isPinnedToBottom: window.latestIsPinnedToBottom
        )
    }

    private func cancelTimers(for paneID: UUID) {
        cancelUnseenWindow(for: paneID)
        cancelAgentCandidate(for: paneID)
    }

    private func cancelUnseenWindow(for paneID: UUID) {
        guard let closeTask = unseenCloseTasks.removeValue(forKey: paneID) else { return }
        closeTask.cancel()
        let precedingRetirementTask = unseenRetirementTasks[paneID]
        unseenRetirementTasks[paneID] = Task {
            await precedingRetirementTask?.value
            await closeTask.value
        }
    }

    private func cancelAgentCandidate(for paneID: UUID) {
        guard let closeTask = agentCloseTasks.removeValue(forKey: paneID) else { return }
        closeTask.cancel()
        let precedingRetirementTask = agentRetirementTasks[paneID]
        agentRetirementTasks[paneID] = Task {
            await precedingRetirementTask?.value
            await closeTask.value
        }
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
