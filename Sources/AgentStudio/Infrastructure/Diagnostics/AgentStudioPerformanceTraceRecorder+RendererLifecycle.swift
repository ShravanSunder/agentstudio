import Foundation

/// Renderer lifecycle bookkeeping (`performance.renderer.lifecycle`): population transitions, native
/// frees and visibility reconciliations. Split from `AgentStudioPerformanceTraceRecorder.swift` by
/// responsibility; state access goes through `withRendererLifecycleState` so the recorder's lock and
/// counters stay private to the main file.
extension AgentStudioPerformanceTraceRecorder {
    /// Records one renderer lifecycle population transition (`created`, `attached`, `hidden`,
    /// `closed_for_undo`, `undo_restored`, or `released`). `active`/`hidden`/`closeUndo` are the
    /// manager's exact current population counts at the moment of the call — not deltas — so a
    /// caller emitting `released` must compute them as-if the surface were already removed and
    /// emit before actually removing it (see `SurfaceManager.destroy`/`expireUndoEntry`).
    /// `windowFacts` is only ever non-`nil` from `WorkspaceSurfaceCoordinator`'s `reconciled`
    /// path; `SurfaceManager` has no window concept and always passes `nil`.
    package func recordRendererLifecycle(
        _ action: RendererLifecycleAction,
        active: Int,
        hidden: Int,
        closeUndo: Int,
        windowFacts: RendererLifecycleWindowFacts?
    ) {
        let attributes = withRendererLifecycleState { state -> [String: AgentStudioTraceValue] in
            var createdDelta = 0
            var releasedDelta = 0
            switch action {
            case .created:
                state.createdTotal &+= 1
                createdDelta = 1
            case .released:
                state.releasedTotal &+= 1
                releasedDelta = 1
            case .attached, .hidden, .closedForUndo, .undoRestored, .freed, .reconciled:
                break
            }
            state.activeCurrent = active
            state.hiddenCurrent = hidden
            state.closeUndoCurrent = closeUndo
            state.sampleSequence &+= 1
            var attributes = Self.rendererLifecycleAttributes(
                action: action,
                snapshot: state.snapshot,
                createdDelta: createdDelta,
                releasedDelta: releasedDelta,
                freedDelta: 0
            )
            if let windowFacts {
                Self.mergeRendererLifecycleWindowFacts(windowFacts, into: &attributes)
            }
            return attributes
        }
        record(.rendererLifecycle, attributes: attributes)
    }

    /// Records native deallocation from the surface's explicit retirement path
    /// after `ghostty_surface_free` returns. Carries no active/hidden/closeUndo update — by the
    /// time this fires the surface has already left every manager collection.
    package func recordRendererFreed(elapsed: Duration? = nil) {
        var attributes = withRendererLifecycleState { state -> [String: AgentStudioTraceValue] in
            state.freedTotal &+= 1
            state.sampleSequence &+= 1
            return Self.rendererLifecycleAttributes(
                action: .freed,
                snapshot: state.snapshot,
                createdDelta: 0,
                releasedDelta: 0,
                freedDelta: 1
            )
        }
        if let elapsed {
            attributes["agentstudio.performance.elapsed_ms"] = .double(Self.milliseconds(from: elapsed))
        }
        record(.rendererLifecycle, attributes: attributes)
    }

    /// Records one renderer visibility reconciliation pass. Emits only when at least one
    /// delivery was applied or missing (`applied + missing > 0`); an all-equal pass instead
    /// accumulates its `equal` count into `reconcile.equal_since_last_emit`, which rides along on
    /// the next emitted record so an idle window doesn't produce record noise while still
    /// exposing how many no-op passes happened between emissions.
    package func recordRendererVisibilityReconciliation(
        applied: Int,
        equal: Int,
        missing: Int,
        elapsed: Duration,
        windowFacts: RendererLifecycleWindowFacts?
    ) {
        let attributes = withRendererLifecycleState { state -> [String: AgentStudioTraceValue]? in
            guard applied + missing > 0 else {
                state.reconciliationEqualSinceLastEmit &+= equal
                return nil
            }
            let equalSinceLastEmit = state.reconciliationEqualSinceLastEmit
            state.reconciliationEqualSinceLastEmit = 0
            state.sampleSequence &+= 1
            var attributes = Self.rendererLifecycleAttributes(
                action: .reconciled,
                snapshot: state.snapshot,
                createdDelta: 0,
                releasedDelta: 0,
                freedDelta: 0
            )
            attributes["agentstudio.performance.renderer.reconcile.applied"] = .int(applied)
            attributes["agentstudio.performance.renderer.reconcile.equal"] = .int(equal)
            attributes["agentstudio.performance.renderer.reconcile.missing"] = .int(missing)
            attributes["agentstudio.performance.renderer.reconcile.equal_since_last_emit"] = .int(
                equalSinceLastEmit)
            attributes["agentstudio.performance.elapsed_ms"] = .double(Self.milliseconds(from: elapsed))
            if let windowFacts {
                Self.mergeRendererLifecycleWindowFacts(windowFacts, into: &attributes)
            }
            return attributes
        }
        guard let attributes else { return }
        record(.rendererLifecycle, attributes: attributes)
    }

    package func rendererLifecycleSnapshot() -> RendererLifecyclePerformanceSnapshot {
        withRendererLifecycleState { $0.snapshot }
    }

    private static func rendererLifecycleAttributes(
        action: RendererLifecycleAction,
        snapshot: RendererLifecyclePerformanceSnapshot,
        createdDelta: Int,
        releasedDelta: Int,
        freedDelta: Int
    ) -> [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.renderer.event.kind": .string(action.rawValue),
            "agentstudio.performance.renderer.created.total": .int(snapshot.createdTotal),
            "agentstudio.performance.renderer.released.total": .int(snapshot.releasedTotal),
            "agentstudio.performance.renderer.freed.total": .int(snapshot.freedTotal),
            "agentstudio.performance.renderer.active.current": .int(snapshot.activeCurrent),
            "agentstudio.performance.renderer.hidden.current": .int(snapshot.hiddenCurrent),
            "agentstudio.performance.renderer.close_undo.current": .int(snapshot.closeUndoCurrent),
            "agentstudio.performance.renderer.live.current": .int(snapshot.liveCurrent),
            "agentstudio.performance.renderer.manager_owned.current": .int(snapshot.managerOwnedCurrent),
            "agentstudio.performance.renderer.orphan_candidate.current": .int(
                snapshot.orphanCandidateCurrent),
            "agentstudio.performance.renderer.sample.sequence": .int(snapshot.sampleSequence),
            "agentstudio.performance.renderer.created.delta": .int(createdDelta),
            "agentstudio.performance.renderer.released.delta": .int(releasedDelta),
            "agentstudio.performance.renderer.freed.delta": .int(freedDelta),
            "agentstudio.performance.renderer.lifecycle.valid": .bool(snapshot.isValid),
        ]
    }

    private static func mergeRendererLifecycleWindowFacts(
        _ windowFacts: RendererLifecycleWindowFacts,
        into attributes: inout [String: AgentStudioTraceValue]
    ) {
        attributes["agentstudio.performance.renderer.window.visible"] = .bool(windowFacts.visible)
        attributes["agentstudio.performance.renderer.window.miniaturized"] = .bool(
            windowFacts.miniaturized)
        attributes["agentstudio.performance.renderer.window.occluded"] = .bool(windowFacts.occluded)
    }
}
