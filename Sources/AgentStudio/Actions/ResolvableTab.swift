import Foundation

/// Protocol exposing what ActionResolver needs from a tab.
/// Decouples resolution logic from concrete TabItem/SplitTree types,
/// enabling unit testing with lightweight mocks.
protocol ResolvableTab: Identifiable where ID == UUID {
    var id: UUID { get }
    var activePaneId: UUID? { get }
    var allPaneIds: [UUID] { get }
    var isSplit: Bool { get }

    /// Find the neighbor pane ID in the given direction.
    func neighborPaneId(of paneId: UUID, direction: SplitFocusDirection) -> UUID?

    /// Get the next pane ID in traversal order (wraps around).
    func nextPaneId(after paneId: UUID) -> UUID?

    /// Get the previous pane ID in traversal order (wraps around).
    func previousPaneId(before paneId: UUID) -> UUID?
}

// MARK: - TabItem Conformance

extension TabItem: ResolvableTab {
    func neighborPaneId(of paneId: UUID, direction: SplitFocusDirection) -> UUID? {
        splitTree.neighbor(of: paneId, direction: direction)?.id
    }

    func nextPaneId(after paneId: UUID) -> UUID? {
        splitTree.nextView(after: paneId)?.id
    }

    func previousPaneId(before paneId: UUID) -> UUID? {
        splitTree.previousView(before: paneId)?.id
    }
}
