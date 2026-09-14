import AgentStudioCore
import Foundation
import Observation

/// The transient state of one Space-held pane preview in a window.
@MainActor
@Observable
final class HeldPanePreviewState {
    enum Lifecycle: Equatable {
        case idle(nextGeneration: UInt64)
        case held(generation: UInt64, requestedTarget: ValidatedPanePreviewTarget?)
        case suppressedUntilSpaceRelease(generation: UInt64)
    }

    private(set) var lifecycle: Lifecycle = .idle(nextGeneration: 1)
    private(set) var presentedTarget: ValidatedPanePreviewTarget?

    var requestedTarget: ValidatedPanePreviewTarget? {
        guard case .held(_, let target) = lifecycle else { return nil }
        return target
    }

    var generation: UInt64? {
        switch lifecycle {
        case .idle:
            nil
        case .held(let generation, _), .suppressedUntilSpaceRelease(let generation):
            generation
        }
    }

    var isHeld: Bool {
        if case .held = lifecycle { return true }
        return false
    }

    @discardableResult
    func beginSpaceHold(
        requestedTarget: ValidatedPanePreviewTarget?,
        isRepeat: Bool = false
    ) -> Bool {
        guard !isRepeat, case .idle(let nextGeneration) = lifecycle else { return false }
        let generation = nextGeneration
        presentedTarget = nil
        lifecycle = .held(generation: generation, requestedTarget: requestedTarget)
        return true
    }

    /// Follows the selected row without minting a new hold generation.
    func updateRequestedTarget(_ target: ValidatedPanePreviewTarget?) {
        guard case .held(let generation, _) = lifecycle else { return }
        guard requestedTarget != target else { return }
        presentedTarget = nil
        lifecycle = .held(generation: generation, requestedTarget: target)
    }

    /// Publishes a target only when it still belongs to this held generation.
    @discardableResult
    func acceptPresentedTarget(
        _ target: ValidatedPanePreviewTarget,
        generation: UInt64
    ) -> Bool {
        guard case .held(let currentGeneration, _) = lifecycle,
            currentGeneration == generation,
            requestedTarget == target
        else { return false }
        presentedTarget = target
        return true
    }

    /// Keeps the request current while an existing owner prepares its mount.
    @discardableResult
    func markPresentationUnavailable(
        generation: UInt64,
        target: ValidatedPanePreviewTarget
    ) -> Bool {
        guard case .held(let currentGeneration, _) = lifecycle,
            currentGeneration == generation,
            requestedTarget == target
        else { return false }
        presentedTarget = nil
        return true
    }

    /// Removes a stale target without selecting a replacement pane.
    @discardableResult
    func invalidateTarget(
        generation: UInt64,
        target: ValidatedPanePreviewTarget
    ) -> Bool {
        guard case .held(let currentGeneration, _) = lifecycle,
            currentGeneration == generation,
            requestedTarget == target
        else { return false }
        presentedTarget = nil
        lifecycle = .held(generation: generation, requestedTarget: nil)
        return true
    }

    /// Enter and digit activation take ownership before the matching Space up.
    func commitBeforeActivation() {
        guard case .held(let generation, _) = lifecycle else { return }
        presentedTarget = nil
        lifecycle = .suppressedUntilSpaceRelease(generation: generation)
    }

    /// Ends a held or committed gesture and returns to canonical presentation.
    func endSpaceHold() {
        guard generation != nil else { return }
        presentedTarget = nil
        lifecycle = .idle(nextGeneration: generationForNextHold &+ 1)
    }

    private var generationForNextHold: UInt64 {
        switch lifecycle {
        case .idle(let nextGeneration):
            nextGeneration
        case .held(let generation, _), .suppressedUntilSpaceRelease(let generation):
            generation
        }
    }

    /// Shared cancellation ingress for focus, demand, routing, and window loss.
    func cancelIfHeld() {
        guard generation != nil else { return }
        endSpaceHold()
    }
}

/// Identity captured at selection time and compared by every later callback.
struct ValidatedPanePreviewTarget: Equatable, Sendable {
    let paneID: UUID
    let owningTabID: UUID
    let provider: SessionProvider?
    let sessionID: ZmxSessionID?
}
