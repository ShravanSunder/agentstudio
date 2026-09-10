import Foundation

/// One call to `AgentStudioPerformanceTraceRecorder.recordRendererLifecycle` /
/// `recordRendererFreed`, naming the exact population transition the manager (or the renderer's
/// own `deinit`) just made. `SurfaceManager` and `Ghostty.SurfaceView` never see this type name
/// mapped to identity — only the aggregate counts flow through.
package enum RendererLifecycleAction: String, Equatable, Sendable {
    case created
    case attached
    case hidden
    case closedForUndo = "closed_for_undo"
    case undoRestored = "undo_restored"
    case released
    case freed
    case reconciled
}

/// Owning-window presentation facts as read by `WorkspaceSurfaceCoordinator` at the moment of a
/// renderer lifecycle emission. `SurfaceManager` has no window concept, so its `attached`/`hidden`
/// emissions always pass `nil`; only the coordinator's `reconciled` emission supplies this.
package struct RendererLifecycleWindowFacts: Equatable, Sendable {
    package let visible: Bool
    package let miniaturized: Bool
    package let occluded: Bool

    package init(visible: Bool, miniaturized: Bool, occluded: Bool) {
        self.visible = visible
        self.miniaturized = miniaturized
        self.occluded = occluded
    }
}

/// Point-in-time renderer lifecycle aggregate, derived from monotonic totals and the
/// caller-supplied current population counts. `liveCurrent` and `orphanCandidateCurrent` are
/// intentionally allowed to go negative — that is the conservation-violation signal the runtime
/// proof is built to catch, so this type must never clamp them.
package struct RendererLifecyclePerformanceSnapshot: Equatable, Sendable {
    package let createdTotal: Int
    package let releasedTotal: Int
    package let freedTotal: Int
    package let activeCurrent: Int
    package let hiddenCurrent: Int
    package let closeUndoCurrent: Int
    package let liveCurrent: Int
    package let managerOwnedCurrent: Int
    package let orphanCandidateCurrent: Int
    package let sampleSequence: Int

    /// A healthy renderer population can never show the manager owning more surfaces than are
    /// live, and none of the derived counts may be negative.
    package var isValid: Bool {
        liveCurrent >= 0
            && managerOwnedCurrent >= 0
            && orphanCandidateCurrent >= 0
            && managerOwnedCurrent <= liveCurrent
    }
}

/// Mutable accumulator behind `AgentStudioPerformanceTraceRecorder`'s renderer lifecycle
/// bookkeeping. Every mutation happens under the recorder's existing `lock`; this type has no
/// synchronization of its own.
struct RendererLifecyclePerformanceState {
    var createdTotal = 0
    var releasedTotal = 0
    var freedTotal = 0
    var activeCurrent = 0
    var hiddenCurrent = 0
    var closeUndoCurrent = 0
    var sampleSequence = 0

    /// Equal-outcome reconciliations accumulated since the last emitted `reconciled` record.
    /// Reset to zero every time a `reconciled` record is actually emitted.
    var reconciliationEqualSinceLastEmit = 0

    var snapshot: RendererLifecyclePerformanceSnapshot {
        let liveCurrent = createdTotal - freedTotal
        let managerOwnedCurrent = activeCurrent + hiddenCurrent + closeUndoCurrent
        return RendererLifecyclePerformanceSnapshot(
            createdTotal: createdTotal,
            releasedTotal: releasedTotal,
            freedTotal: freedTotal,
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
