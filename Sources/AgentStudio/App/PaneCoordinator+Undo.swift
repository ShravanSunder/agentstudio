import Foundation

@MainActor
extension PaneCoordinator {
    /// Undo the last close operation (tab or pane).
    func undoCloseTab() {
        while let entry = popLastUndoEntry() {
            switch entry {
            case .tab(let snapshot):
                undoTabClose(snapshot)
                return

            case .pane(let snapshot):
                guard store.tab(snapshot.tabId) != nil else {
                    Self.logger.info("undoClose: tab \(snapshot.tabId) gone — skipping pane entry")
                    continue
                }
                if snapshot.pane.isDrawerChild,
                    let parentId = snapshot.anchorPaneId,
                    store.pane(parentId) == nil
                {
                    Self.logger.info("undoClose: parent pane \(parentId) gone — skipping drawer child entry")
                    continue
                }
                undoPaneClose(snapshot)
                return
            }
        }
        Self.logger.info("No entries to restore from undo stack")
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
            Self.logger.warning(
                "undoTabClose: removing broken pane \(paneId) from tab \(snapshot.tab.id)"
            )
            removeFailedRestoredPane(paneId, fromTab: snapshot.tab.id)
        }

        if !failedPaneIds.isEmpty {
            Self.logger.warning(
                "undoTabClose: tab \(snapshot.tab.id) restored with \(failedPaneIds.count) failed panes"
            )
        }

        // If the active arrangement was emptied by failure cleanup, prefer switching to
        // any remaining non-empty arrangement before deciding the tab is empty.
        recoverActiveArrangementIfNeeded(tabId: snapshot.tab.id)

        guard let restoredTab = store.tab(snapshot.tab.id), !restoredTab.panes.isEmpty else {
            Self.logger.error("undoTabClose: all panes failed for tab \(snapshot.tab.id); removing empty tab")
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
            Self.logger.warning(
                "undoPaneClose: removing broken pane \(paneId) in tab \(snapshot.tabId)"
            )
            removeFailedRestoredPane(paneId, fromTab: snapshot.tabId)
        }

        recoverActiveArrangementIfNeeded(tabId: snapshot.tabId)
        guard let restoredTab = store.tab(snapshot.tabId), !restoredTab.panes.isEmpty else {
            Self.logger.error(
                "undoPaneClose: no panes remain in tab \(snapshot.tabId) after restore cleanup; removing empty tab")
            store.removeTab(snapshot.tabId)
            return
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
                Self.logger.error("Failed to restore terminal pane \(pane.id)")
            } else if createViewForContent(pane: pane) != nil {
                return true
            } else {
                Self.logger.error("Failed to recreate terminal pane \(pane.id)")
            }
            return false

        case .webview, .codeViewer, .bridgePanel:
            if createViewForContent(pane: pane) != nil {
                return true
            }
            Self.logger.error("Failed to recreate \(label.lowercased()) pane \(pane.id)")
            return false

        case .unsupported:
            // Unsupported content has no renderer implementation in this build.
            // Keep the pane model restored so user state is preserved, but log that no view can be recreated.
            Self.logger.warning("Cannot restore unsupported pane \(pane.id)")
            return true
        }
    }

    private func recoverActiveArrangementIfNeeded(tabId: UUID) {
        guard let tab = store.tab(tabId) else {
            Self.logger.warning("recoverActiveArrangementIfNeeded: tab \(tabId) no longer exists")
            return
        }
        guard tab.activeArrangement.layout.paneIds.isEmpty else { return }
        guard let fallbackArrangement = tab.arrangements.first(where: { !$0.layout.paneIds.isEmpty }) else {
            Self.logger.error(
                "recoverActiveArrangementIfNeeded: tab \(tabId) has no non-empty arrangements after undo cleanup")
            return
        }
        Self.logger.warning(
            "recoverActiveArrangementIfNeeded: switched tab \(tabId) to non-empty arrangement \(fallbackArrangement.id)"
        )
        store.switchArrangement(to: fallbackArrangement.id, inTab: tabId)
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
