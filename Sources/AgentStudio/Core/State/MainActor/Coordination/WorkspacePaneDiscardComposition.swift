import Foundation

package enum WorkspacePaneDiscardTarget: Sendable {
    case backgroundedPane(paneID: UUID)
    case drawerPane(parentID: UUID, paneID: UUID)

    var paneID: UUID {
        switch self {
        case .backgroundedPane(let paneID), .drawerPane(_, let paneID): paneID
        }
    }
}

struct WorkspacePaneDiscardProposal: Sendable {
    let bundle: WorkspaceSQLiteSaveBundle
    let paneID: UUID
    let parentPaneID: UUID?
    let removedPaneIDs: Set<UUID>
}

enum WorkspacePaneDiscardComposition {
    @concurrent nonisolated static func prepareOffMain(
        in source: WorkspaceSQLiteSaveBundle, target: WorkspacePaneDiscardTarget
    ) async throws -> WorkspacePaneDiscardProposal {
        let paneID = target.paneID
        guard let pane = source.workspace.panes.first(where: { $0.id == paneID })
        else { throw WorkspaceUndoCompositionFailure.missingTarget }
        switch target {
        case .backgroundedPane:
            guard pane.residency == .backgrounded else { throw WorkspaceUndoCompositionFailure.missingTarget }
        case .drawerPane(let parentID, _):
            guard pane.parentPaneId == parentID else { throw WorkspaceUndoCompositionFailure.missingTarget }
        }
        let removedIDs = Set([paneID] + (pane.drawer?.paneIds ?? []))
        let drawerIDs = Set([pane.drawer?.drawerId].compactMap { $0 })
        var updated = source.workspace
        updated.panes.removeAll { removedIDs.contains($0.id) }
        if let parentID = pane.parentPaneId {
            guard let parentIndex = updated.panes.firstIndex(where: { $0.id == parentID }),
                updated.panes[parentIndex].drawer?.paneIds.contains(paneID) == true
            else { throw WorkspaceUndoCompositionFailure.invalidComposition }
            updated.panes[parentIndex].withDrawer { $0.paneIds.removeAll { $0 == paneID } }
        }
        updated.tabs = updated.tabs.compactMap { tab in
            let arrangements = TabArrangementRepairRules.removingPanes(
                removedIDs, removingDrawerIds: drawerIDs, from: tab.arrangements)
            guard TabArrangementRepairRules.hasLivePaneReferences(in: arrangements) else { return nil }
            return Tab(
                id: tab.id, name: tab.name,
                allPaneIds: tab.allPaneIds.filter { !removedIDs.contains($0) },
                arrangements: arrangements, activeArrangementId: tab.activeArrangementId,
                colorHex: tab.colorHex)
        }
        if let activeID = updated.activeTabId, !updated.tabs.contains(where: { $0.id == activeID }) {
            updated.activeTabId = updated.tabs.last?.id
        }
        return .init(
            bundle: .init(workspace: updated, captureRevision: source.captureRevision),
            paneID: paneID, parentPaneID: pane.parentPaneId, removedPaneIDs: removedIDs)
    }
}
