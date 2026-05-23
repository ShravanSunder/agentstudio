import Foundation

@testable import AgentStudio

/// Lightweight `ResolvableTab` mock for testing `WorkspaceCommandResolver.resolve(command:)`.
/// Uses pure UUIDs with configurable navigation results — no NSViews required.
struct MockTab: ResolvableTab {
    let id: UUID
    var activePaneId: UUID?
    var visiblePaneIds: [UUID]
    var ownedPaneIds: [UUID]
    var validationActiveArrangementId: UUID?
    var arrangementSnapshots: [ArrangementSnapshot]
    var isSplit: Bool { visiblePaneIds.count > 1 }

    var neighbors: [UUID: [SplitFocusDirection: UUID]] = [:]
    var nextPanes: [UUID: UUID] = [:]
    var previousPanes: [UUID: UUID] = [:]

    init(
        id: UUID,
        activePaneId: UUID?,
        allPaneIds: [UUID],
        ownedPaneIds: [UUID]? = nil,
        validationActiveArrangementId: UUID? = nil,
        arrangementSnapshots: [ArrangementSnapshot]? = nil,
        neighbors: [UUID: [SplitFocusDirection: UUID]] = [:],
        nextPanes: [UUID: UUID] = [:],
        previousPanes: [UUID: UUID] = [:]
    ) {
        let defaultArrangementId = validationActiveArrangementId ?? arrangementSnapshots?.first?.id ?? UUID()
        self.id = id
        self.activePaneId = activePaneId
        self.visiblePaneIds = allPaneIds
        self.ownedPaneIds = ownedPaneIds ?? allPaneIds
        self.validationActiveArrangementId = defaultArrangementId
        self.arrangementSnapshots =
            arrangementSnapshots ?? [
                ArrangementSnapshot(id: defaultArrangementId, isDefault: true)
            ]
        self.neighbors = neighbors
        self.nextPanes = nextPanes
        self.previousPanes = previousPanes
    }

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
