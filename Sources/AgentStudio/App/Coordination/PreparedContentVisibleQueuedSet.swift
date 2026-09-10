import AgentStudioCore

/// The complete current visible pane set signaled to the prepared content
/// mount lane, together with which of those panes the store's visibility
/// resolver currently reports as active.
///
/// `visiblePaneIDs` order carries no meaning and is not a contract: a caller
/// must never infer which pane is active from list position. `activePaneIDs`
/// is the only signal for that — the active main pane of the visible tab
/// and, if a drawer is expanded, its active drawer pane, exactly as
/// `StoreVisibilityTierResolver.isActive(_:)` decides it.
struct PreparedContentVisibleQueuedSet: Equatable, Sendable {
    let visiblePaneIDs: [PaneId]
    let activePaneIDs: Set<PaneId>
}
