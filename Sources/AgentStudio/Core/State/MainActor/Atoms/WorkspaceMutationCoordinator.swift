import Foundation

@MainActor
final class WorkspaceMutationCoordinator {
    enum CloseEntry {
        case tab(TabCloseSnapshot)
        case pane(PaneCloseSnapshot)
    }

    struct TabCloseSnapshot {
        let tab: Tab
        let panes: [Pane]
        let tabIndex: Int
    }

    struct PaneCloseSnapshot {
        let pane: Pane
        let drawerChildPanes: [Pane]
        let tabId: UUID
        let anchorPaneId: UUID?
        let direction: Layout.SplitDirection
    }

    let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    let workspacePaneAtom: WorkspacePaneAtom
    let workspaceTabLayoutAtom: WorkspaceTabLayoutAtom

    init(
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    ) {
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.workspacePaneAtom = workspacePaneAtom
        self.workspaceTabLayoutAtom = workspaceTabLayoutAtom
    }

    func removePane(_ paneId: UUID) {
        guard workspacePaneAtom.deletePaneAndOwnedDrawerChildren(paneId) else { return }
        workspaceTabLayoutAtom.removePaneReferences(paneId)
    }

    func backgroundPane(_ paneId: UUID) {
        guard workspacePaneAtom.pane(paneId) != nil else { return }
        workspaceTabLayoutAtom.removePaneReferences(paneId)
        workspacePaneAtom.setResidency(.backgrounded, for: paneId)
    }

    func reactivatePane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard
            let pane = workspacePaneAtom.pane(paneId),
            pane.residency == .backgrounded
        else {
            return
        }

        guard
            workspaceTabLayoutAtom.insertPane(
                paneId,
                inTab: tabId,
                at: targetPaneId,
                direction: direction,
                position: position
            )
        else {
            return
        }
        workspacePaneAtom.setResidency(.active, for: paneId)
    }

    @discardableResult
    func reassociateRepo(_ repoId: UUID, to newPath: URL, discoveredWorktrees: [Worktree]) -> Bool {
        let worktreeIds = repositoryTopologyAtom.reassociateRepo(
            repoId,
            to: newPath,
            discoveredWorktrees: discoveredWorktrees
        )
        guard !worktreeIds.isEmpty else { return false }
        _ = restoreOrphanedPaneResidency(forWorktreeIds: worktreeIds)
        return true
    }

    @discardableResult
    func restoreOrphanedPaneResidency(forWorktreeIds worktreeIds: Set<UUID>) -> Bool {
        workspacePaneAtom.restoreOrphanedPaneResidency(
            forWorktreeIds: worktreeIds,
            activeLayoutPaneIds: workspaceTabLayoutAtom.allPaneIds
        )
    }

    func snapshotForClose(tabId: UUID) -> TabCloseSnapshot? {
        guard let tabIndex = workspaceTabLayoutAtom.tabs.firstIndex(where: { $0.id == tabId }) else { return nil }
        let tab = workspaceTabLayoutAtom.tabs[tabIndex]
        var allPanes: [Pane] = []
        for paneId in tab.panes {
            guard let layoutPane = workspacePaneAtom.pane(paneId) else { continue }
            allPanes.append(layoutPane)
            if let drawer = layoutPane.drawer {
                allPanes.append(contentsOf: workspacePaneAtom.snapshotPanes(with: drawer.paneIds))
            }
        }
        return TabCloseSnapshot(tab: tab, panes: allPanes, tabIndex: tabIndex)
    }

    func snapshotForPaneClose(paneId: UUID, inTab tabId: UUID) -> PaneCloseSnapshot? {
        guard let closedPane = workspacePaneAtom.pane(paneId), let tab = workspaceTabLayoutAtom.tab(tabId) else {
            return nil
        }

        let drawerChildPanes = closedPane.drawer.map { workspacePaneAtom.snapshotPanes(with: $0.paneIds) } ?? []
        let anchorPaneId: UUID?
        let direction: Layout.SplitDirection

        if closedPane.isDrawerChild {
            anchorPaneId = closedPane.parentPaneId
            direction = .horizontal
        } else {
            anchorPaneId = tab.paneIds.first { $0 != paneId }
            direction = .horizontal
        }

        return PaneCloseSnapshot(
            pane: closedPane,
            drawerChildPanes: drawerChildPanes,
            tabId: tabId,
            anchorPaneId: anchorPaneId,
            direction: direction
        )
    }

    func restoreFromSnapshot(_ snapshot: TabCloseSnapshot) {
        for pane in snapshot.panes {
            _ = workspacePaneAtom.insertRestoredPane(pane)
        }
        workspaceTabLayoutAtom.insertTab(snapshot.tab, at: snapshot.tabIndex)
        workspaceTabLayoutAtom.setActiveTab(snapshot.tab.id)
    }

    func restoreFromPaneSnapshot(_ snapshot: PaneCloseSnapshot) {
        _ = workspacePaneAtom.insertRestoredPane(snapshot.pane)
        for child in snapshot.drawerChildPanes {
            _ = workspacePaneAtom.insertRestoredPane(child)
        }

        if snapshot.pane.isDrawerChild {
            if let parentId = snapshot.anchorPaneId {
                workspacePaneAtom.restoreDrawerPane(snapshot.pane, to: parentId)
            }
        } else if let anchor = snapshot.anchorPaneId {
            _ = workspaceTabLayoutAtom.insertPane(
                snapshot.pane.id,
                inTab: snapshot.tabId,
                at: anchor,
                direction: snapshot.direction,
                position: .after
            )
            workspaceTabLayoutAtom.setActivePane(snapshot.pane.id, inTab: snapshot.tabId)
        }
    }
}
