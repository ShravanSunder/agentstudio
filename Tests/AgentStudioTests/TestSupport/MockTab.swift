import AgentStudioCore
import Foundation

/// Lightweight `ResolvableTab` mock for testing `WorkspaceCommandResolver.resolve(command:)`.
/// Uses pure UUIDs with configurable navigation results — no NSViews required.
package struct MockTab: ResolvableTab {
    package let id: UUID
    package var activePaneId: UUID?
    package var visiblePaneIds: [UUID]
    package var ownedPaneIds: [UUID]
    package var minimizedPaneIdsForValidation: Set<UUID>
    package var validationActiveArrangementId: UUID?
    package var arrangementSnapshots: [ArrangementSnapshot]
    package var isSplit: Bool { visiblePaneIds.count > 1 }

    package var neighbors: [UUID: [SplitFocusDirection: UUID]] = [:]
    package var nextPanes: [UUID: UUID] = [:]
    package var previousPanes: [UUID: UUID] = [:]

    package init(
        id: UUID,
        activePaneId: UUID?,
        allPaneIds: [UUID],
        ownedPaneIds: [UUID]? = nil,
        minimizedPaneIds: Set<UUID> = [],
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
        self.minimizedPaneIdsForValidation = minimizedPaneIds
        self.validationActiveArrangementId = defaultArrangementId
        self.arrangementSnapshots =
            arrangementSnapshots ?? [
                ArrangementSnapshot(id: defaultArrangementId, isDefault: true)
            ]
        self.neighbors = neighbors
        self.nextPanes = nextPanes
        self.previousPanes = previousPanes
    }

    package func neighborPaneId(of paneId: UUID, direction: SplitFocusDirection) -> UUID? {
        neighbors[paneId]?[direction]
    }

    package func nextPaneId(after paneId: UUID) -> UUID? {
        nextPanes[paneId]
    }

    package func previousPaneId(before paneId: UUID) -> UUID? {
        previousPanes[paneId]
    }
}
