import Foundation

@MainActor
extension PaneCoordinator {
    /// Undo the last close operation (tab or pane).
    func undoCloseTab() {
        while let entry = undoStack.popLast() {
            switch entry {
            case .tab(let snapshot):
                undoTabClose(snapshot)
                return

            case .pane(let snapshot):
                guard store.tab(snapshot.tabId) != nil else {
                    paneCoordinatorLogger.info("undoClose: tab \(snapshot.tabId) gone — skipping pane entry")
                    continue
                }
                if snapshot.pane.isDrawerChild,
                    let parentId = snapshot.anchorPaneId,
                    store.pane(parentId) == nil
                {
                    paneCoordinatorLogger.info("undoClose: parent pane \(parentId) gone — skipping drawer child entry")
                    continue
                }
                undoPaneClose(snapshot)
                return
            }
        }
        paneCoordinatorLogger.info("No entries to restore from undo stack")
    }

    private func undoTabClose(_ snapshot: WorkspaceStore.TabCloseSnapshot) {
        store.restoreFromSnapshot(snapshot)
        var failedPaneIds: [UUID] = []

        // Restore views via lifecycle layer — iterate in reverse to match the LIFO
        // order of SurfaceManager's undo stack (panes were pushed in forward
        // order during close, so the last pane is on top of the stack).
        for pane in snapshot.panes.reversed() {
            let restored = restoreUndoPane(
                pane,
                worktree: nil,
                repo: nil,
                label: "Tab"
            )
            if !restored {
                failedPaneIds.append(pane.id)
            }
        }

        for paneId in failedPaneIds {
            paneCoordinatorLogger.warning(
                "undoTabClose: removing broken pane \(paneId) from tab \(snapshot.tab.id)"
            )
            removeFailedRestoredPane(paneId, fromTab: snapshot.tab.id)
        }

        if !failedPaneIds.isEmpty {
            paneCoordinatorLogger.warning(
                "undoTabClose: tab \(snapshot.tab.id) restored with \(failedPaneIds.count) failed panes"
            )
        }

        guard let restoredTab = store.tab(snapshot.tab.id), !restoredTab.paneIds.isEmpty else {
            paneCoordinatorLogger.error("undoTabClose: all panes failed for tab \(snapshot.tab.id); removing empty tab")
            store.removeTab(snapshot.tab.id)
            return
        }

        store.setActiveTab(snapshot.tab.id)
    }

    private func undoPaneClose(_ snapshot: WorkspaceStore.PaneCloseSnapshot) {
        store.restoreFromPaneSnapshot(snapshot)
        var failedPaneIds: [UUID] = []

        // Restore views for the pane and its drawer children.
        // Use the same restoration path as undoTabClose: attempt surface undo
        // via SurfaceManager to preserve scrollback, fall back to fresh creation.
        let allPanes = [snapshot.pane] + snapshot.drawerChildPanes
        for pane in allPanes.reversed() {
            guard viewRegistry.view(for: pane.id) == nil else { continue }
            let worktree = pane.worktreeId.flatMap(store.worktree)
            let repo = pane.repoId.flatMap { store.repo($0) }
            let restored = restoreUndoPane(
                pane,
                worktree: worktree,
                repo: repo,
                label: "Pane"
            )
            if !restored {
                failedPaneIds.append(pane.id)
            }
        }

        for paneId in failedPaneIds {
            paneCoordinatorLogger.warning(
                "undoPaneClose: removing broken pane \(paneId) in tab \(snapshot.tabId)"
            )
            removeFailedRestoredPane(paneId, fromTab: snapshot.tabId)
        }

        store.setActiveTab(snapshot.tabId)
    }

    private func restoreUndoPane(
        _ pane: Pane,
        worktree: Worktree?,
        repo: Repo?,
        label: String
    ) -> Bool {
        switch pane.content {
        case .terminal:
            if let worktree, let repo {
                if restoreView(for: pane, worktree: worktree, repo: repo) != nil {
                    return true
                }
                paneCoordinatorLogger.error("Failed to restore terminal pane \(pane.id)")
            } else if createViewForContent(pane: pane) != nil {
                return true
            } else {
                paneCoordinatorLogger.error("Failed to recreate terminal pane \(pane.id)")
            }
            return false

        case .webview, .codeViewer, .bridgePanel:
            if createViewForContent(pane: pane) != nil {
                return true
            }
            paneCoordinatorLogger.error("Failed to recreate \(label.lowercased()) pane \(pane.id)")
            return false

        case .unsupported:
            paneCoordinatorLogger.warning("Cannot restore unsupported pane \(pane.id)")
            return true
        }
    }

    private func removeFailedRestoredPane(_ paneId: UUID, fromTab tabId: UUID) {
        guard let pane = store.pane(paneId) else {
            teardownView(for: paneId)
            return
        }

        if pane.isDrawerChild, let parentPaneId = pane.parentPaneId {
            teardownView(for: paneId)
            store.removeDrawerPane(paneId, from: parentPaneId)
            return
        }

        teardownDrawerPanes(for: paneId)
        teardownView(for: paneId)
        _ = store.removePaneFromLayout(paneId, inTab: tabId)
        store.removePane(paneId)
    }
}
