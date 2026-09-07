import Foundation

struct WorkspacePaneDiscardProposal: Sendable {
    let bundle: WorkspaceSQLiteSaveBundle
    let paneID: UUID
    let parentPaneID: UUID?
    let removedPaneIDs: Set<UUID>
}

enum WorkspacePaneDiscardComposition {
    @concurrent nonisolated static func prepareBackgroundedPaneOffMain(
        in source: WorkspaceSQLiteSaveBundle, paneID: UUID
    ) async throws -> WorkspacePaneDiscardProposal {
        guard let pane = source.workspace.panes.first(where: { $0.id == paneID }),
            pane.residency == .backgrounded
        else { throw WorkspaceUndoCompositionFailure.missingTarget }
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
