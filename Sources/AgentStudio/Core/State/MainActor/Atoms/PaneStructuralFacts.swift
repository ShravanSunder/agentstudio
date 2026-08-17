import Foundation

package struct PaneStructuralFacts: Equatable, Sendable {
    package enum Placement: Equatable, Sendable {
        case layout
        case drawerChild(parentPaneID: UUID)
    }

    package let paneID: UUID
    package let residency: SessionResidency
    package let contentType: PaneContentType
    package let isBridgeEligible: Bool
    package let repoID: UUID?
    package let worktreeID: UUID?
    package let cwd: URL?
    package let placement: Placement
    package let ownedDrawerID: UUID?
    package let ownedDrawerPaneIDs: [UUID]

    package var parentPaneID: UUID? {
        guard case .drawerChild(let parentPaneID) = placement else { return nil }
        return parentPaneID
    }

    package var isDrawerChild: Bool {
        parentPaneID != nil
    }

    init(state: PaneGraphState) {
        self.paneID = state.id
        self.residency = state.residency
        self.contentType = state.metadata.contentType
        self.isBridgeEligible = if case .bridgePanel = state.content { true } else { false }
        self.repoID = state.metadata.facets.repoId
        self.worktreeID = state.metadata.facets.worktreeId
        self.cwd = state.metadata.facets.cwd
        self.placement = state.parentPaneId.map(Placement.drawerChild(parentPaneID:)) ?? .layout
        self.ownedDrawerID = state.drawer?.drawerId
        self.ownedDrawerPaneIDs = state.drawer?.paneIds ?? []
    }
}
