import Foundation

/// Direction for inserting a new pane into a split.
/// Standalone type decoupled from SplitTree's generic parameter.
enum SplitNewDirection: Equatable, Codable, Hashable {
    case left, right, up, down
}

/// Identifies where a pane being inserted comes from.
enum PaneSource: Equatable, Hashable {
    /// Moving an existing pane from its current location
    case existingPane(paneId: UUID, sourceTabId: UUID)
    /// Creating a new terminal
    case newTerminal
}

/// Fully resolved action with all target IDs explicit.
/// Every action that modifies tab/pane state flows through this type.
///
/// "Resolved" means no "active tab" or "current pane" references —
/// all targets are concrete UUIDs computed during the resolution step.
enum PaneAction: Equatable, Hashable {
    // Tab lifecycle
    case selectTab(tabId: UUID)
    case closeTab(tabId: UUID)
    case breakUpTab(tabId: UUID)

    // Pane lifecycle
    case closePane(tabId: UUID, paneId: UUID)
    case extractPaneToTab(tabId: UUID, paneId: UUID)

    // Pane focus
    case focusPane(tabId: UUID, paneId: UUID)

    // Split operations
    case insertPane(source: PaneSource, targetTabId: UUID,
                    targetPaneId: UUID, direction: SplitNewDirection)
    case resizePane(tabId: UUID, paneId: UUID, ratio: CGFloat)
    case equalizePanes(tabId: UUID)

    /// Move ALL panes from sourceTab into targetTab at targetPaneId position.
    /// Source tab is removed after merge.
    case mergeTab(sourceTabId: UUID, targetTabId: UUID,
                  targetPaneId: UUID, direction: SplitNewDirection)
}
