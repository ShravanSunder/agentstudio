import AgentStudioCore
import AgentStudioInfrastructure
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
package actor TerminalActivityProjector {
    typealias OutcomeSink = @MainActor @Sendable ([TerminalActivityProjectionOutcome]) -> Void
    /// Reads the raw trailing viewport text for a surface, bounded to a
    /// small row window — one Ghostty call per settled burst. The projector
    /// owns all Contract 7 line-level contraction on that text
    /// (`TerminalLastOutputLineContract`): learned prompt-signature
    /// exclusion and unchanged-line suppression both need per-pane settle
    /// state that only the projector holds.
    typealias LastOutputLineReader = @MainActor @Sendable (_ surfaceID: UUID) -> String?

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
        /// The last contracted output-line candidate published at this
        /// pane's previous settle, used to suppress an unchanged repeat.
        var previousLastOutputLine: String?
        /// This pane's learned shell prompt line, re-recorded from the
        /// trailing non-empty viewport line at every commandFinished-driven
        /// settle (that line is by construction the shell's freshly-printed
        /// prompt). Excluded from later last-output-line candidates so a
        /// prompt that embeds real text — directory names, branch names —
        /// is never mistaken for output, even across `cd`/branch changes
        /// that alter the prompt's exact text. Scrollbar-driven settles read
        /// this but never write it: there is no settle-boundary invariant
        /// tying their trailing line to the prompt.
        var promptSignature: String?
    }

    private let unseenQuietDuration: Duration
    private let agentSettledQuietDuration: Duration
    private let delay: AsyncDelay
    private let nowMilliseconds: @Sendable () -> Int64
    private var outcomeSink: OutcomeSink?
    private var lastOutputLineReader: LastOutputLineReader?
    private var paneStates: [UUID: PaneState] = [:]
    private var unseenCloseTasks: [UUID: Task<Void, Never>] = [:]
    private var agentCloseTasks: [UUID: Task<Void, Never>] = [:]
    private var unseenRetirementTasks: [UUID: Task<Void, Never>] = [:]
    private var agentRetirementTasks: [UUID: Task<Void, Never>] = [:]

    init(
        unseenQuietDuration: Duration = AppPolicies.InboxNotification.terminalActivityQuietDebounceDuration,
        agentSettledQuietDuration: Duration = AppPolicies.InboxNotification.agentSettledQuietDuration,
        clock: (any Clock<Duration> & Sendable)? = nil,
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        }
    ) {
        self.unseenQuietDuration = unseenQuietDuration
        self.agentSettledQuietDuration = agentSettledQuietDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.nowMilliseconds = nowMilliseconds
    }

    func configure(
        lastOutputLineReader: LastOutputLineReader? = nil,
        outcomeSink: @escaping OutcomeSink
    ) {
        self.lastOutputLineReader = lastOutputLineReader
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

    /// A `terminal.commandFinished` shell-integration signal is a contracted semantic "this pane's
    /// current command just completed" fact (Contract 7 exact-fact route) — independent of
    /// scrollbar-derived activity evidence, and not gated by attention state. The scrollbar/unseen-
    /// window path above deliberately excludes attended panes (see `consumeAggregateState`'s
    /// `context.isAttended` branch), which is exactly the common case this signal exists to cover:
    /// typing into the pane you're looking at. It settles the pane's current burst immediately — if
    /// scrollbar evidence was already accumulating, close that window now instead of waiting out its
    /// remaining debounce; otherwise synthesize a minimal settle carrying just the resolved
    /// last-output-line, so a pane with zero scrollbar signal still reaches the existing settle path
    /// (status-fact write, notification lane, and all of that lane's suppression rules) unchanged.
    func commandFinished(surfaceID: UUID, paneID: UUID) async {
        var closedWindow: ActivityWindow?
        if var state = paneStates[paneID], state.surfaceID == surfaceID,
            let window = state.unseenWindow, window.rowsAdded > 0
        {
            cancelUnseenWindow(for: paneID)
            state.unseenWindow = nil
            paneStates[paneID] = state
            closedWindow = window
        }

        let lastOutputLine = await resolveLastOutputLine(
            surfaceID: surfaceID,
            paneID: paneID,
            learnPromptSignature: true
        )
        guard closedWindow != nil || lastOutputLine != nil else { return }

        let activity: TerminalSettledActivity
        if let closedWindow {
            activity = settledActivity(closedWindow, quietDuration: unseenQuietDuration, lastOutputLine: lastOutputLine)
        } else {
            let now = nowMilliseconds()
            let scrollbarState = paneStates[paneID]?.scrollbarState
            activity = TerminalSettledActivity(
                burstWindowId: UUIDv7.generate(),
                thresholdRows: AppPolicies.InboxNotification.terminalActivityOutputBurstThresholdRows,
                debounceMilliseconds: 0,
                startedAtMilliseconds: now,
                settledAtMilliseconds: now,
                eventCount: 0,
                rowsAdded: 0,
                baselineRows: scrollbarState?.total ?? 0,
                latestRows: scrollbarState?.total ?? 0,
                isPinnedToBottom: paneStates[paneID]?.isPinnedToBottom ?? true,
                lastOutputLine: lastOutputLine
            )
        }
        await emit([.unseenActivitySettled(surfaceID: surfaceID, paneID: paneID, activity: activity)])
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

    func reset() async {
        let closeTasks = Array(unseenCloseTasks.values) + Array(agentCloseTasks.values)
        let retirementTasks = Array(unseenRetirementTasks.values) + Array(agentRetirementTasks.values)
        for task in closeTasks { task.cancel() }
        unseenCloseTasks.removeAll()
        agentCloseTasks.removeAll()
        unseenRetirementTasks.removeAll()
        agentRetirementTasks.removeAll()
        paneStates.removeAll()
        outcomeSink = nil
        lastOutputLineReader = nil
        for task in closeTasks { await task.value }
        for task in retirementTasks { await task.value }
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
        let crossAggregatePositiveRowGrowth =
            existing.map {
                max(0, aggregate.firstTotalRows - $0.latestRows)
            } ?? 0
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
        window.rowsAdded += crossAggregatePositiveRowGrowth + aggregate.cumulativePositiveRowGrowth
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
        cancelUnseenWindow(for: paneID)
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
        cancelAgentCandidate(for: paneID)
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
        let lastOutputLine = await resolveLastOutputLine(
            surfaceID: window.surfaceID,
            paneID: target.paneID,
            learnPromptSignature: false
        )
        await emit([
            .unseenActivitySettled(
                surfaceID: window.surfaceID,
                paneID: target.paneID,
                activity: settledActivity(window, quietDuration: unseenQuietDuration, lastOutputLine: lastOutputLine)
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
        let lastOutputLine = await resolveLastOutputLine(
            surfaceID: candidate.surfaceID,
            paneID: target.paneID,
            learnPromptSignature: false
        )
        await emit([
            .agentSettledActivityPromoted(
                surfaceID: candidate.surfaceID,
                paneID: target.paneID,
                activity: settledActivity(
                    candidate,
                    quietDuration: agentSettledQuietDuration,
                    lastOutputLine: lastOutputLine
                )
            )
        ])
    }

    /// Reads the settle-time candidate line for `surfaceID`: fetches the raw
    /// trailing viewport text once, optionally re-learns this pane's prompt
    /// signature from it, contracts a candidate excluding that signature,
    /// then applies unchanged-line suppression against the pane's previous
    /// settle. Learning happens strictly before contraction ("learn then
    /// contract") so even a pane's very first settle — where the trailing
    /// line is unavoidably the prompt itself, since nothing has been learned
    /// yet — never publishes that prompt: it becomes the signature and is
    /// excluded in the same pass. `learnPromptSignature` is true only for
    /// commandFinished-driven settles, where the trailing line is
    /// guaranteed by shell-integration semantics to be the freshly-printed
    /// prompt; scrollbar-driven settles have no such invariant and read the
    /// pane's last-known signature without writing it. Always re-fetches
    /// `paneStates` after the reader's MainActor hop rather than reusing a
    /// pre-await snapshot, since the actor is reentrant across that
    /// suspension point.
    ///
    /// Known one-settle degradation (F3, owner-ratified, no fix this round):
    /// Ghostty's shell integration emits the command-end OSC sequence before
    /// the prompt-start sequence, and before PS1 is actually painted. If a
    /// commandFinished settle races that ordering, the trailing viewport row
    /// can still be the just-completed command's real output rather than the
    /// new prompt, so that output is wrongly learned as `promptSignature` and
    /// suppressed for this one settle. This is self-correcting: the pane's
    /// *next* commandFinished-driven settle re-learns from whatever is then
    /// the trailing row. Once the prompt has actually painted by that point,
    /// the signature corrects to the real prompt and the previously
    /// misclassified output line's class recovers on the following settle.
    /// A fix would require reading a real prompt semantic boundary (e.g. OSC
    /// 133) instead of "the trailing row," which is out of scope here.
    private func resolveLastOutputLine(
        surfaceID: UUID,
        paneID: UUID,
        learnPromptSignature: Bool
    ) async -> String? {
        guard let lastOutputLineReader else { return nil }
        let rawText = await lastOutputLineReader(surfaceID)

        var state: PaneState
        if let existingState = paneStates[paneID], existingState.surfaceID == surfaceID {
            state = existingState
        } else if learnPromptSignature {
            // A commandFinished-driven settle can be the first thing this pane
            // ever sees (no prior scrollbar ingestion, e.g. right after boot) —
            // still track state so the learned signature persists into later
            // settles, matching the default-state pattern `consumeAggregateState`
            // already uses for a pane's first scrollbar sample.
            state = PaneState(surfaceID: surfaceID, outputBurst: .unknown)
        } else {
            // Scrollbar-driven settles only run after an ingested window closes,
            // so untracked state here means the pane was replaced/removed
            // mid-flight; fall back to unscoped contraction with no persisted
            // signature rather than fabricating state for a pane we no longer own.
            return rawText.flatMap { TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: $0) }
        }

        if learnPromptSignature, let rawText {
            state.promptSignature = TerminalLastOutputLineContract.trailingNonEmptyLine(fromRawViewportText: rawText)
        }
        let candidate = rawText.flatMap {
            TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: $0, excluding: state.promptSignature)
        }
        let isUnchanged = candidate == state.previousLastOutputLine
        state.previousLastOutputLine = candidate
        paneStates[paneID] = state
        return isUnchanged ? nil : candidate
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

    private func settledActivity(
        _ window: ActivityWindow,
        quietDuration: Duration,
        lastOutputLine: String?
    ) -> TerminalSettledActivity {
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
            isPinnedToBottom: window.latestIsPinnedToBottom,
            lastOutputLine: lastOutputLine
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
