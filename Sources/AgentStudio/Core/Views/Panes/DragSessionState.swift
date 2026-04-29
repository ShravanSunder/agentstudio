import Foundation

/// Shared drag session state for pane/tab/split drop interactions.
/// This keeps preview, commit, and teardown transitions explicit.
enum DragSessionState: Equatable {
    case idle
    case previewing(payload: SplitDropPayload)
    case armed(candidate: DragSessionCandidate)
    case committing(candidate: DragSessionCandidate)
    case teardown
}

/// A validated drag candidate selected during preview.
struct DragSessionCandidate: Equatable {
    let payload: SplitDropPayload
    let target: PaneDropTarget
}
