import Foundation

/// Direction for inserting a new pane into a split.
/// Standalone type decoupled from SplitTree's generic parameter.
enum SplitNewDirection: Equatable, Codable, Hashable {
    case left, right, up, down
}

/// Direction for keyboard-driven pane resize.
enum SplitResizeDirection: Equatable, Hashable, CustomStringConvertible {
    case up, down, left, right

    /// The Layout.SplitDirection axis this resize acts on.
    var axis: Layout.SplitDirection {
        switch self {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }

    var description: String {
        switch self {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        }
    }
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
    case resizePane(tabId: UUID, splitId: UUID, ratio: Double)
    case equalizePanes(tabId: UUID)

    /// Toggle zoom on a pane (display-only, transient).
    case toggleSplitZoom(tabId: UUID, paneId: UUID)

    /// Move a tab by a relative delta (positive=right, negative=left).
    case moveTab(tabId: UUID, delta: Int)

    /// Resize a pane by keyboard delta (Ghostty's resize_split action).
    case resizePaneByDelta(tabId: UUID, paneId: UUID,
                           direction: SplitResizeDirection, amount: UInt16)

    /// Move ALL panes from sourceTab into targetTab at targetPaneId position.
    /// Source tab is removed after merge.
    case mergeTab(sourceTabId: UUID, targetTabId: UUID,
                  targetPaneId: UUID, direction: SplitNewDirection)

    // System actions — dispatched by Reconciler and undo timers, not by user input.

    /// Undo TTL expired — remove session from store, kill tmux, destroy surface.
    case expireUndoEntry(sessionId: UUID)

    /// Reconciler-generated repair action.
    case repair(RepairAction)
}

/// System-generated repair actions from the Reconciler.
/// Flow through ActionExecutor like user actions — one-way data flow never bypassed.
enum RepairAction: Equatable, Hashable {
    /// tmux died — create new tmux session, send reattach command to existing surface.
    case reattachTmux(sessionId: UUID)
    /// Surface died — full view + surface recreation. tmux reattaches.
    case recreateSurface(sessionId: UUID)
    /// Session is in layout but has no view in ViewRegistry.
    case createMissingView(sessionId: UUID)
    /// Unrecoverable failure — mark session as failed.
    case markSessionFailed(sessionId: UUID, reason: String)
    /// Session exists in runtime but not in store (and not pending undo) — clean up.
    case cleanupOrphan(sessionId: UUID)
}
