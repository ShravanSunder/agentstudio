import Foundation

package struct WorkspaceUndoRestoreProposal: Sendable {
    let bundle: WorkspaceSQLiteSaveBundle
    package let close: WorkspaceUndoCloseRecord
    package let tabID: UUID
}

extension WorkspaceUndoComposition {
    @concurrent nonisolated static func prepareRestoreOffMain(
        in source: WorkspaceSQLiteSaveBundle, close: WorkspaceUndoCloseRecord, time: WorkspaceUndoJournalTime
    ) async throws -> WorkspaceUndoRestoreProposal {
        try prepareRestore(in: source, close: close, time: time)
    }

    static func prepareRestore(
        in source: WorkspaceSQLiteSaveBundle, close: WorkspaceUndoCloseRecord, time: WorkspaceUndoJournalTime
    ) throws -> WorkspaceUndoRestoreProposal {
        try validateUndoJournalTime(time)
        guard source.id == close.workspaceID else { throw WorkspaceUndoCloseWriteFailure.workspaceMismatch }
        guard close.deadlineBootID == time.bootID else { throw WorkspaceUndoJournalFailure.deadlineNeedsRecovery }
        guard time.uptimeNanoseconds < close.deadlineUptimeNanoseconds else {
            throw WorkspaceUndoJournalFailure.undoExpired
        }
        let existingIDs = Set(source.workspace.panes.map(\.id))
        let restoredIDs = close.snapshot.panes.map(\.id)
        guard Set(restoredIDs).count == restoredIDs.count,
            existingIDs.isDisjoint(with: restoredIDs)
        else { throw WorkspaceUndoCompositionFailure.invalidComposition }
        var updated = source.workspace
        let tabID: UUID
        switch close.snapshot {
        case .tab(let tab, _, let tabIndex):
            guard !updated.tabs.contains(where: { $0.id == tab.id }) else {
                throw WorkspaceUndoCompositionFailure.invalidComposition
            }
            updated.tabs.insert(tab, at: min(max(0, tabIndex), updated.tabs.count))
            tabID = tab.id
        case .pane(let snapshot):
            guard let index = updated.tabs.firstIndex(where: { $0.id == snapshot.tabID }) else {
                throw WorkspaceUndoCompositionFailure.missingTarget
            }
            updated.tabs[index] = try restorePane(snapshot, in: updated.tabs[index], workspace: &updated)
            tabID = snapshot.tabID
        }
        updated.panes.append(contentsOf: close.snapshot.panes)
        updated.activeTabId = tabID
        updated.updatedAt = time.utc
        guard case .prepared = WorkspaceCompositionPreparer.prepare(updated) else {
            throw WorkspaceUndoCompositionFailure.invalidComposition
        }
        return .init(
            bundle: .init(workspace: updated, captureRevision: source.captureRevision), close: close, tabID: tabID)
    }

    private static func restorePane(
        _ snapshot: WorkspaceUndoCloseSnapshot.PaneSnapshot, in tab: Tab,
        workspace: inout WorkspaceSQLiteSnapshot
    ) throws -> Tab {
        var state = TabArrangementState(
            tabId: tab.id, allPaneIds: tab.allPaneIds, arrangements: tab.arrangements,
            activeArrangementId: tab.activeArrangementId
        )
        guard let anchorID = snapshot.anchorPaneID else { throw WorkspaceUndoCompositionFailure.missingTarget }
        if snapshot.pane.isDrawerChild {
            guard snapshot.pane.parentPaneId == anchorID, tab.allPaneIds.contains(anchorID),
                let parentIndex = workspace.panes.firstIndex(where: { $0.id == anchorID }),
                let drawerID = workspace.panes[parentIndex].drawer?.drawerId
            else { throw WorkspaceUndoCompositionFailure.missingTarget }
            workspace.panes[parentIndex].withDrawer { $0.paneIds.append(snapshot.pane.id) }
            var placed = false
            for index in state.arrangements.indices where state.arrangements[index].layout.contains(anchorID) {
                var view = state.arrangements[index].drawerViews[drawerID] ?? DrawerView(layout: DrawerGridLayout())
                if let lastID = view.layout.paneIds.last {
                    guard
                        let layout = view.layout.inserting(
                            paneId: snapshot.pane.id, at: lastID, direction: .right, sizingMode: .halveTarget
                        )
                    else { throw WorkspaceUndoCompositionFailure.invalidComposition }
                    view.layout = layout
                } else {
                    view.layout = DrawerGridLayout(topRow: Layout(paneId: snapshot.pane.id))
                }
                view.activeChildId = snapshot.pane.id
                state.arrangements[index].drawerViews[drawerID] = view
                placed = true
            }
            guard placed else { throw WorkspaceUndoCompositionFailure.missingTarget }
            state.allPaneIds.append(snapshot.pane.id)
        } else {
            guard
                let inserted = TabArrangementMutationRules.insertingPane(
                    snapshot.pane.id, in: state, at: anchorID, direction: snapshot.direction,
                    position: .after, sizingMode: .halveTarget
                )
            else { throw WorkspaceUndoCompositionFailure.missingTarget }
            state = inserted
            if let drawerID = snapshot.pane.drawer?.drawerId, !snapshot.drawerChildPanes.isEmpty {
                let childIDs = snapshot.drawerChildPanes.map(\.id)
                let fallback = DrawerView(
                    layout: DrawerGridLayout(topRow: Layout.autoTiled(childIDs)), activeChildId: childIDs.first)
                for index in state.arrangements.indices
                where state.arrangements[index].layout.contains(snapshot.pane.id) {
                    let source = snapshot.drawerViewsByArrangementID[state.arrangements[index].id] ?? fallback
                    state.arrangements[index].drawerViews[drawerID] =
                        TabArrangementRepairRules.pruningInvalidDrawerViewPaneIds(
                            validPaneIds: Set(childIDs), from: [drawerID: source]
                        )[drawerID]
                }
                state.allPaneIds.append(contentsOf: childIDs.filter { !state.allPaneIds.contains($0) })
            }
        }
        return Tab(
            id: tab.id, name: tab.name, allPaneIds: state.allPaneIds, arrangements: state.arrangements,
            activeArrangementId: state.activeArrangementId, colorHex: tab.colorHex)
    }
}
