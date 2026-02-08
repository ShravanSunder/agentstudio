import Foundation
@testable import AgentStudio

/// Lightweight `ResolvableTab` mock for testing `ActionResolver.resolve(command:)`.
/// Uses pure UUIDs with configurable navigation results — no NSViews required.
struct MockTab: ResolvableTab {
    let id: UUID
    var activePaneId: UUID?
    var allPaneIds: [UUID]
    var isSplit: Bool { allPaneIds.count > 1 }

    var neighbors: [UUID: [SplitFocusDirection: UUID]] = [:]
    var nextPanes: [UUID: UUID] = [:]
    var previousPanes: [UUID: UUID] = [:]

    func neighborPaneId(of paneId: UUID, direction: SplitFocusDirection) -> UUID? {
        neighbors[paneId]?[direction]
    }

    func nextPaneId(after paneId: UUID) -> UUID? {
        nextPanes[paneId]
    }

    func previousPaneId(before paneId: UUID) -> UUID? {
        previousPanes[paneId]
    }
}
