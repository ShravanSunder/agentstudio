import Foundation

enum TerminalLocalAccumulatorAction: Sendable, Equatable {
    case scrollbar(ScrollbarState, observedAtMilliseconds: Int64)
    case mouseShape(TerminalMouseShape)
    case mouseVisibility(Bool)
    case searchStarted(query: String?)
    case searchEnded
    case searchMatches(Int?)
    case searchSelection(Int?)
    case titleChanged(String)
    case tabTitleChanged(String)
}

enum TerminalSearchLifecycleState: Sendable, Equatable {
    case active(query: String?, epoch: UInt64)
    case inactive(lastEndedEpoch: UInt64)
}

struct TerminalSearchLifecycleSummary: Sendable, Equatable {
    let firstEpoch: UInt64
    private(set) var latestEpoch: UInt64
    private(set) var transitionCount: UInt64
    private(set) var state: TerminalSearchLifecycleState

    init(query: String?, epoch: UInt64) {
        firstEpoch = epoch
        latestEpoch = epoch
        transitionCount = 1
        state = .active(query: query, epoch: epoch)
    }

    init(endedEpoch: UInt64) {
        firstEpoch = endedEpoch
        latestEpoch = endedEpoch
        transitionCount = 1
        state = .inactive(lastEndedEpoch: endedEpoch)
    }

    mutating func recordStarted(query: String?, epoch: UInt64) {
        latestEpoch = epoch
        transitionCount += 1
        state = .active(query: query, epoch: epoch)
    }

    mutating func recordEnded(epoch: UInt64) {
        latestEpoch = epoch
        transitionCount += 1
        state = .inactive(lastEndedEpoch: epoch)
    }
}

struct TerminalSearchPresentationUpdate: Sendable, Equatable {
    let epoch: UInt64
    var hasTotalMatchesUpdate: Bool
    var totalMatches: Int?
    var hasSelectionUpdate: Bool
    var selectedMatchIndex: Int?
}

struct TerminalLocalPresentationBatch: Sendable, Equatable {
    var scrollbarState: ScrollbarState?
    var mouseShape: TerminalMouseShape?
    var mouseVisibility: Bool?
    var searchUpdate: TerminalSearchPresentationUpdate?
}

struct TerminalTitleMetadataBatch: Sendable, Equatable {
    var runtimeTitle: TerminalLatestSemanticMetadataAction
    var surfaceTitle: String?
}

struct TerminalScrollbarActivityAggregate: Sendable, Equatable {
    let firstObservedAtMilliseconds: Int64
    private(set) var latestObservedAtMilliseconds: Int64
    let firstTotalRows: Int
    private(set) var latestTotalRows: Int
    private(set) var cumulativePositiveRowGrowth: Int
    private(set) var sampleCount: Int
    let firstIsPinnedToBottom: Bool
    private(set) var latestIsPinnedToBottom: Bool
    private(set) var didEnterPinnedToBottom: Bool
    private(set) var didExitPinnedToBottom: Bool

    init(state: ScrollbarState, observedAtMilliseconds: Int64) {
        firstObservedAtMilliseconds = observedAtMilliseconds
        latestObservedAtMilliseconds = observedAtMilliseconds
        firstTotalRows = state.total
        latestTotalRows = state.total
        cumulativePositiveRowGrowth = 0
        sampleCount = 1
        firstIsPinnedToBottom = state.isPinnedToBottom
        latestIsPinnedToBottom = state.isPinnedToBottom
        didEnterPinnedToBottom = false
        didExitPinnedToBottom = false
    }

    mutating func merge(state: ScrollbarState, observedAtMilliseconds: Int64) {
        cumulativePositiveRowGrowth += max(0, state.total - latestTotalRows)
        if state.isPinnedToBottom != latestIsPinnedToBottom {
            if state.isPinnedToBottom {
                didEnterPinnedToBottom = true
            } else {
                didExitPinnedToBottom = true
            }
        }
        latestObservedAtMilliseconds = observedAtMilliseconds
        latestTotalRows = state.total
        latestIsPinnedToBottom = state.isPinnedToBottom
        sampleCount += 1
    }
}

struct TerminalLocalAccumulatorMetrics: Sendable, Equatable {
    var offeredCount: UInt64 = 0
    var replacedCount: UInt64 = 0
    var equalSuppressedCount: UInt64 = 0
    var scheduledDrainCount: UInt64 = 0
    var followUpDrainCount: UInt64 = 0
}

struct TerminalLocalActionBatch: Sendable, Equatable {
    let surfaceID: UUID
    let presentation: TerminalLocalPresentationBatch
    let activity: TerminalScrollbarActivityAggregate?
    let activityContext: TerminalActivityProjectionContext?
    let searchLifecycle: TerminalSearchLifecycleSummary?
    let titleMetadata: TerminalTitleMetadataBatch?
    let metrics: TerminalLocalAccumulatorMetrics
    let firstOfferedAtNanoseconds: UInt64

    var retainedEntryCount: Int {
        var count = searchLifecycle == nil ? 0 : 1
        if presentation.scrollbarState != nil { count += 1 }
        if presentation.mouseShape != nil { count += 1 }
        if presentation.mouseVisibility != nil { count += 1 }
        if presentation.searchUpdate != nil { count += 1 }
        if activity != nil { count += 1 }
        if titleMetadata != nil {
            count += 1
            if titleMetadata?.surfaceTitle != nil { count += 1 }
        }
        return count
    }
}

enum TerminalLocalAccumulatorOfferResult: Sendable, Equatable {
    case scheduled
    case coalesced
    case equalSuppressed
    case rejectedInactiveSearch
}

enum TerminalLocalAccumulatorDrainCompletion: Sendable, Equatable {
    case idle
    case followUpScheduled
}

/// Terminal-owned fixed-key contraction point for high-rate local Ghostty signals.
/// It retains no view, runtime, borrowed pointer, or globally replayable event.
final class TerminalLocalActionAccumulator: @unchecked Sendable {
    static let maximumRetainedEntriesPerSurface = 9

    private enum DrainPhase {
        case idle
        case scheduled
        case draining
    }

    private struct SearchLifecycleState {
        var epoch: UInt64 = 0
        var isActive = false
    }

    private struct PendingBatch {
        var presentation = TerminalLocalPresentationBatch()
        var activity: TerminalScrollbarActivityAggregate?
        var activityContext: TerminalActivityProjectionContext?
        var searchLifecycle: TerminalSearchLifecycleSummary?
        var titleMetadata: TerminalTitleMetadataBatch?
        var metrics = TerminalLocalAccumulatorMetrics()
        var firstOfferedAtNanoseconds: UInt64?

        var hasWork: Bool {
            presentation.scrollbarState != nil
                || presentation.mouseShape != nil
                || presentation.mouseVisibility != nil
                || presentation.searchUpdate != nil
                || activity != nil
                || searchLifecycle != nil
                || titleMetadata != nil
        }
    }

    private struct SurfaceState {
        var phase: DrainPhase = .idle
        var pending = PendingBatch()
        var search = SearchLifecycleState()
        var activityContext: TerminalActivityProjectionContext?
    }

    private let lock = NSLock()
    private let scheduleDrain: @Sendable (UUID) -> Void
    private var statesBySurfaceID: [UUID: SurfaceState] = [:]

    init(scheduleDrain: @escaping @Sendable (UUID) -> Void) {
        self.scheduleDrain = scheduleDrain
    }

    @discardableResult
    func offer(_ action: TerminalLocalAccumulatorAction, for surfaceID: UUID) -> TerminalLocalAccumulatorOfferResult {
        var shouldSchedule = false
        let result = lock.withLock { () -> TerminalLocalAccumulatorOfferResult in
            var state = statesBySurfaceID[surfaceID] ?? SurfaceState()
            if state.pending.firstOfferedAtNanoseconds == nil {
                state.pending.firstOfferedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
            }
            state.pending.metrics.offeredCount += 1
            let mutationResult = apply(action, to: &state)
            guard mutationResult != .rejectedInactiveSearch else {
                if state.pending.hasWork || state.phase != .idle || state.search.isActive {
                    statesBySurfaceID[surfaceID] = state
                }
                return mutationResult
            }
            if state.phase == .idle {
                state.phase = .scheduled
                state.pending.metrics.scheduledDrainCount += 1
                shouldSchedule = true
                statesBySurfaceID[surfaceID] = state
                return .scheduled
            }
            statesBySurfaceID[surfaceID] = state
            return mutationResult
        }
        if shouldSchedule {
            scheduleDrain(surfaceID)
        }
        return result
    }

    func beginDrain(
        for surfaceID: UUID,
        defaultActivityContext: TerminalActivityProjectionContext? = nil
    ) -> TerminalLocalActionBatch? {
        lock.withLock {
            guard var state = statesBySurfaceID[surfaceID], state.phase == .scheduled, state.pending.hasWork else {
                return nil
            }
            state.phase = .draining
            let detached = state.pending
            state.pending = PendingBatch()
            statesBySurfaceID[surfaceID] = state
            return TerminalLocalActionBatch(
                surfaceID: surfaceID,
                presentation: detached.presentation,
                activity: detached.activity,
                activityContext: detached.activity == nil
                    ? nil
                    : detached.activityContext ?? state.activityContext ?? defaultActivityContext,
                searchLifecycle: detached.searchLifecycle,
                titleMetadata: detached.titleMetadata,
                metrics: detached.metrics,
                firstOfferedAtNanoseconds: detached.firstOfferedAtNanoseconds
                    ?? DispatchTime.now().uptimeNanoseconds
            )
        }
    }

    func detachActivityBeforeControl(
        for surfaceID: UUID,
        contextBeforeControl: TerminalActivityProjectionContext?,
        contextAfterControl: TerminalActivityProjectionContext?
    ) -> TerminalActivityAggregateInput? {
        lock.withLock {
            guard var state = statesBySurfaceID[surfaceID] else { return nil }
            defer {
                state.activityContext = contextAfterControl ?? state.activityContext
                statesBySurfaceID[surfaceID] = state
            }
            guard
                let aggregate = state.pending.activity,
                let latestState = state.pending.presentation.scrollbarState,
                let context = state.pending.activityContext ?? state.activityContext ?? contextBeforeControl
            else { return nil }
            state.pending.activity = nil
            state.pending.activityContext = nil
            return TerminalActivityAggregateInput(
                aggregate: aggregate,
                latestState: latestState,
                context: context
            )
        }
    }

    func detachActivityForSurfaceClose(
        _ surfaceID: UUID,
        defaultActivityContext: TerminalActivityProjectionContext?
    ) -> TerminalActivityAggregateInput? {
        lock.withLock {
            guard let state = statesBySurfaceID.removeValue(forKey: surfaceID),
                let aggregate = state.pending.activity,
                let latestState = state.pending.presentation.scrollbarState,
                let context = state.pending.activityContext ?? state.activityContext ?? defaultActivityContext
            else { return nil }
            return TerminalActivityAggregateInput(
                aggregate: aggregate,
                latestState: latestState,
                context: context
            )
        }
    }

    func finishDrain(for surfaceID: UUID) -> TerminalLocalAccumulatorDrainCompletion {
        var shouldSchedule = false
        let completion = lock.withLock { () -> TerminalLocalAccumulatorDrainCompletion in
            guard var state = statesBySurfaceID[surfaceID], state.phase == .draining else { return .idle }
            if state.pending.hasWork {
                state.phase = .scheduled
                state.pending.metrics.followUpDrainCount += 1
                statesBySurfaceID[surfaceID] = state
                shouldSchedule = true
                return .followUpScheduled
            }
            if state.search.isActive {
                state.phase = .idle
                statesBySurfaceID[surfaceID] = state
            } else {
                statesBySurfaceID.removeValue(forKey: surfaceID)
            }
            return .idle
        }
        if shouldSchedule {
            scheduleDrain(surfaceID)
        }
        return completion
    }

    func removeSurface(_ surfaceID: UUID) {
        _ = lock.withLock {
            statesBySurfaceID.removeValue(forKey: surfaceID)
        }
    }

    var pendingSurfaceCount: Int {
        lock.withLock {
            statesBySurfaceID.values.count { $0.phase != .idle || $0.pending.hasWork }
        }
    }

    func hasPendingActions(for surfaceID: UUID) -> Bool {
        lock.withLock {
            statesBySurfaceID[surfaceID]?.pending.hasWork == true
        }
    }

    var retainedEntryCount: Int {
        lock.withLock {
            statesBySurfaceID.values.reduce(into: 0) { result, state in
                if state.pending.presentation.scrollbarState != nil { result += 1 }
                if state.pending.presentation.mouseShape != nil { result += 1 }
                if state.pending.presentation.mouseVisibility != nil { result += 1 }
                if state.pending.presentation.searchUpdate != nil { result += 1 }
                if state.pending.activity != nil { result += 1 }
                if state.pending.searchLifecycle != nil { result += 1 }
                if state.pending.titleMetadata != nil {
                    result += 1
                    if state.pending.titleMetadata?.surfaceTitle != nil { result += 1 }
                }
            }
        }
    }

    private func apply(
        _ action: TerminalLocalAccumulatorAction,
        to state: inout SurfaceState
    ) -> TerminalLocalAccumulatorOfferResult {
        switch action {
        case .scrollbar(let scrollbarState, let observedAtMilliseconds):
            return applyScrollbar(
                scrollbarState,
                observedAtMilliseconds: observedAtMilliseconds,
                to: &state
            )
        case .mouseShape(let mouseShape):
            let hadCurrentValue = state.pending.presentation.mouseShape != nil
            let result = replacementResult(current: state.pending.presentation.mouseShape, next: mouseShape)
            state.pending.presentation.mouseShape = mouseShape
            record(result, replacedExistingValue: hadCurrentValue, in: &state.pending.metrics)
            return result
        case .mouseVisibility(let isVisible):
            let hadCurrentValue = state.pending.presentation.mouseVisibility != nil
            let result = replacementResult(current: state.pending.presentation.mouseVisibility, next: isVisible)
            state.pending.presentation.mouseVisibility = isVisible
            record(result, replacedExistingValue: hadCurrentValue, in: &state.pending.metrics)
            return result
        case .searchStarted(let query):
            state.search.epoch &+= 1
            state.search.isActive = true
            state.pending.presentation.searchUpdate = nil
            if var summary = state.pending.searchLifecycle {
                summary.recordStarted(query: query, epoch: state.search.epoch)
                state.pending.searchLifecycle = summary
            } else {
                state.pending.searchLifecycle = TerminalSearchLifecycleSummary(
                    query: query,
                    epoch: state.search.epoch
                )
            }
            return .coalesced
        case .searchEnded:
            guard state.search.isActive else { return .equalSuppressed }
            state.search.isActive = false
            state.pending.presentation.searchUpdate = nil
            if var summary = state.pending.searchLifecycle {
                summary.recordEnded(epoch: state.search.epoch)
                state.pending.searchLifecycle = summary
            } else {
                state.pending.searchLifecycle = TerminalSearchLifecycleSummary(endedEpoch: state.search.epoch)
            }
            return .coalesced
        case .searchMatches(let totalMatches):
            guard state.search.isActive else { return .rejectedInactiveSearch }
            var update =
                state.pending.presentation.searchUpdate
                ?? TerminalSearchPresentationUpdate(
                    epoch: state.search.epoch,
                    hasTotalMatchesUpdate: false,
                    totalMatches: nil,
                    hasSelectionUpdate: false,
                    selectedMatchIndex: nil
                )
            let hadCurrentValue = update.hasTotalMatchesUpdate
            let result: TerminalLocalAccumulatorOfferResult =
                hadCurrentValue && update.totalMatches == totalMatches ? .equalSuppressed : .coalesced
            update.hasTotalMatchesUpdate = true
            update.totalMatches = totalMatches
            state.pending.presentation.searchUpdate = update
            record(result, replacedExistingValue: hadCurrentValue, in: &state.pending.metrics)
            return result
        case .searchSelection(let selectedMatchIndex):
            guard state.search.isActive else { return .rejectedInactiveSearch }
            var update =
                state.pending.presentation.searchUpdate
                ?? TerminalSearchPresentationUpdate(
                    epoch: state.search.epoch,
                    hasTotalMatchesUpdate: false,
                    totalMatches: nil,
                    hasSelectionUpdate: false,
                    selectedMatchIndex: nil
                )
            let hadCurrentValue = update.hasSelectionUpdate
            let result: TerminalLocalAccumulatorOfferResult =
                hadCurrentValue && update.selectedMatchIndex == selectedMatchIndex ? .equalSuppressed : .coalesced
            update.hasSelectionUpdate = true
            update.selectedMatchIndex = selectedMatchIndex
            state.pending.presentation.searchUpdate = update
            record(result, replacedExistingValue: hadCurrentValue, in: &state.pending.metrics)
            return result
        case .titleChanged(let title):
            return applyTitleMetadata(.titleChanged(title), to: &state)
        case .tabTitleChanged(let title):
            return applyTitleMetadata(.tabTitleChanged(title), to: &state)
        }
    }

    private func applyScrollbar(
        _ scrollbarState: ScrollbarState,
        observedAtMilliseconds: Int64,
        to state: inout SurfaceState
    ) -> TerminalLocalAccumulatorOfferResult {
        let hadCurrentValue = state.pending.presentation.scrollbarState != nil
        let result = replacementResult(current: state.pending.presentation.scrollbarState, next: scrollbarState)
        if result == .equalSuppressed {
            record(result, replacedExistingValue: hadCurrentValue, in: &state.pending.metrics)
            return result
        }
        state.pending.presentation.scrollbarState = scrollbarState
        if var activity = state.pending.activity {
            activity.merge(state: scrollbarState, observedAtMilliseconds: observedAtMilliseconds)
            state.pending.activity = activity
        } else {
            state.pending.activity = TerminalScrollbarActivityAggregate(
                state: scrollbarState,
                observedAtMilliseconds: observedAtMilliseconds
            )
            state.pending.activityContext = state.activityContext
        }
        record(result, replacedExistingValue: hadCurrentValue, in: &state.pending.metrics)
        return result
    }

    private func applyTitleMetadata(
        _ metadata: TerminalLatestSemanticMetadataAction,
        to state: inout SurfaceState
    ) -> TerminalLocalAccumulatorOfferResult {
        let hadCurrentValue = state.pending.titleMetadata != nil
        let result = replacementResult(current: state.pending.titleMetadata?.runtimeTitle, next: metadata)
        let surfaceTitle: String?
        switch metadata {
        case .titleChanged(let title):
            surfaceTitle = title
        case .tabTitleChanged:
            surfaceTitle = state.pending.titleMetadata?.surfaceTitle
        }
        state.pending.titleMetadata = TerminalTitleMetadataBatch(
            runtimeTitle: metadata,
            surfaceTitle: surfaceTitle
        )
        record(result, replacedExistingValue: hadCurrentValue, in: &state.pending.metrics)
        return result
    }

    private func replacementResult<Value: Equatable>(
        current: Value?,
        next: Value
    ) -> TerminalLocalAccumulatorOfferResult {
        guard let current else { return .coalesced }
        return current == next ? .equalSuppressed : .coalesced
    }

    private func record(
        _ result: TerminalLocalAccumulatorOfferResult,
        replacedExistingValue: Bool,
        in metrics: inout TerminalLocalAccumulatorMetrics
    ) {
        switch result {
        case .coalesced:
            if replacedExistingValue {
                metrics.replacedCount += 1
            }
        case .equalSuppressed:
            metrics.equalSuppressedCount += 1
        case .scheduled, .rejectedInactiveSearch:
            break
        }
    }
}
