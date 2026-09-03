import Foundation

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

struct RendererLifecyclePerformanceState {
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

struct PaneAssociationTraceAdmission {
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

struct TopologyLookupTraceAdmission {
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
