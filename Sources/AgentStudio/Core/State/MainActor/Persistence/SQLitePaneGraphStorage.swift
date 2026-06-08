import Foundation

enum SQLitePaneGraphStorage {
    struct ResidencyStorageValues {
        let kind: String
        let pendingUndoExpiresAt: Double?
        let orphanReasonKind: String?
        let orphanWorktreePath: String?
    }

    static let sourceKindWorktree = "worktree"
    static let sourceKindFloating = "floating"

    static let residencyKindActive = "active"
    static let residencyKindBackgrounded = "backgrounded"
    static let residencyKindPendingUndo = "pendingUndo"
    static let residencyKindOrphaned = "orphaned"

    static let orphanReasonWorktreeNotFound = "worktreeNotFound"

    static let placementKindLayout = "layout"
    static let placementKindDrawerChild = "drawerChild"

    static func sourceKind(_ source: WorkspaceCoreRepository.PaneSourceRecord) -> String {
        switch source {
        case .worktree:
            sourceKindWorktree
        case .floating:
            sourceKindFloating
        }
    }

    static func sourceIds(
        pane: WorkspaceCoreRepository.PaneRecord
    ) -> (repoId: UUID?, worktreeId: UUID?) {
        switch pane.metadata.source {
        case .worktree(let repoId, let worktreeId, _):
            return (repoId, worktreeId)
        case .floating:
            return (pane.metadata.durableFacets.repoId, pane.metadata.durableFacets.worktreeId)
        }
    }

    static func residency(
        _ residency: WorkspaceCoreRepository.PaneResidencyRecord
    ) -> ResidencyStorageValues {
        switch residency {
        case .active:
            return .init(
                kind: residencyKindActive,
                pendingUndoExpiresAt: nil,
                orphanReasonKind: nil,
                orphanWorktreePath: nil
            )
        case .backgrounded:
            return .init(
                kind: residencyKindBackgrounded,
                pendingUndoExpiresAt: nil,
                orphanReasonKind: nil,
                orphanWorktreePath: nil
            )
        case .pendingUndo(let expiresAt):
            return .init(
                kind: residencyKindPendingUndo,
                pendingUndoExpiresAt: expiresAt.timeIntervalSince1970,
                orphanReasonKind: nil,
                orphanWorktreePath: nil
            )
        case .orphaned(let worktreePath):
            return .init(
                kind: residencyKindOrphaned,
                pendingUndoExpiresAt: nil,
                orphanReasonKind: orphanReasonWorktreeNotFound,
                orphanWorktreePath: worktreePath
            )
        }
    }

    static func placement(
        _ placement: WorkspaceCoreRepository.PanePlacementRecord
    ) -> (kind: String, parentPaneId: UUID?) {
        switch placement {
        case .layout:
            return (placementKindLayout, nil)
        case .drawerChild(let parentPaneId):
            return (placementKindDrawerChild, parentPaneId)
        }
    }
}
