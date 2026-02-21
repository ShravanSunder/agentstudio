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

// MARK: - Tab Conformance

extension Tab: ResolvableTab {
    var allPaneIds: [UUID] { paneIds }

    func neighborPaneId(of paneId: UUID, direction: SplitFocusDirection) -> UUID? {
        layout.neighbor(of: paneId, direction: direction.toFocusDirection)
    }

    func nextPaneId(after paneId: UUID) -> UUID? {
        layout.next(after: paneId)
    }

    func previousPaneId(before paneId: UUID) -> UUID? {
        layout.previous(before: paneId)
    }
}

// MARK: - Direction Bridging

extension SplitFocusDirection {
    /// Bridge SplitFocusDirection → Layout.FocusDirection
    var toFocusDirection: FocusDirection {
        switch self {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        }
    }
}
