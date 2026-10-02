import AgentStudioCore
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
    case commandFinished
    case surfaceClosed
    /// SR6b, the surface route: the cold `GhosttySurfaceView` latch recorded
    /// person input under `TerminalLocalActionAccumulator`'s lock, which
    /// detached the pre-input aggregate ahead of this control (Program
    /// Design item 13). Gating on `restorePhaseByPane` is Panes' consumer.
    case restorePhaseEnded(RestoreGeneration)
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
    /// SR6b: terminal activation arms a cold pane's restore phase before
    /// `createSurface` (Program Design item 13). Pane-keyed, not
    /// surface-keyed: no surface exists yet at arm time.
    case restorePhaseArmed(
        paneID: UUID, restoreGeneration: RestoreGeneration, resumeInvocation: ResumeInvocation? = nil)
    /// SR6b, the no-surface route: a resumed agent's SessionStart fact can
    /// end the phase (R3) without going through a surface's ordered ingress.
    /// Always unused in R1, which never auto-resumes; the case exists now so
    /// the vocabulary is complete ahead of R3.
    case restorePhaseEnded(paneID: UUID, restoreGeneration: RestoreGeneration)
    /// SR6b: permanent pane retirement — `WorkspaceSurfaceCoordinator
    /// .retirePanesPermanently`, "the shared final-retirement edge for undo
    /// expiry and committed direct discards" — is pane-keyed and distinct
    /// from `.surfaceClosed`, which also fires on ordinary surface
    /// replacement (`consumeAggregateState`'s `replacedSurfaceID` branch).
    /// Only this input clears `restorePhaseByPane`; a replaced surface keeps
    /// the pane's restore phase (Panes' consumer, requested via Main
    /// 2026-09-30).
    case paneRetiredPermanently(paneID: UUID)
}
