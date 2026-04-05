import Foundation
import os.log

@MainActor
final class WorkspaceMutationCoordinator {
    enum RestorePaneResult: Equatable {
        case restored
        case failedMissingDrawerParent(UUID?)
        case failedLayoutInsertion(tabId: UUID, anchorPaneId: UUID?)
    }

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

    private let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    private let workspacePaneAtom: WorkspacePaneAtom
    private let workspaceTabLayoutAtom: WorkspaceTabLayoutAtom

    init(
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    ) {
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.workspacePaneAtom = workspacePaneAtom
        self.workspaceTabLayoutAtom = workspaceTabLayoutAtom
    }

    @discardableResult
    func removePane(_ paneId: UUID) -> Bool {
        guard workspacePaneAtom.deletePaneAndOwnedDrawerChildren(paneId) else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("removePane: pane \(paneId) not found")
            return false
        }
        workspaceTabLayoutAtom.removePaneReferences(paneId)
        return true
    }

    @discardableResult
    func backgroundPane(_ paneId: UUID) -> Bool {
        guard workspacePaneAtom.pane(paneId) != nil else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("backgroundPane: pane \(paneId) not found")
            return false
        }
        workspaceTabLayoutAtom.removePaneReferences(paneId)
        workspacePaneAtom.setResidency(.backgrounded, for: paneId)
        return true
    }

    @discardableResult
    func reactivatePane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) -> Bool {
        guard
            let pane = workspacePaneAtom.pane(paneId),
            pane.residency == .backgrounded
        else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("reactivatePane: pane \(paneId) not found or not backgrounded")
            return false
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
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("reactivatePane: failed inserting pane \(paneId) into tab \(tabId) at anchor \(targetPaneId)")
            return false
        }
        workspacePaneAtom.setResidency(.active, for: paneId)
        return true
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
        for paneId in tab.allPaneIds {
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
            anchorPaneId = tab.activePaneIds.first { $0 != paneId }
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

    @discardableResult
    func restoreFromPaneSnapshot(_ snapshot: PaneCloseSnapshot) -> RestorePaneResult {
        _ = workspacePaneAtom.insertRestoredPane(snapshot.pane)
        for child in snapshot.drawerChildPanes {
            _ = workspacePaneAtom.insertRestoredPane(child)
        }

        if snapshot.pane.isDrawerChild {
            if let parentId = snapshot.anchorPaneId {
                guard workspacePaneAtom.restoreDrawerPane(snapshot.pane, to: parentId) else {
                    _ = workspacePaneAtom.deletePaneAndOwnedDrawerChildren(snapshot.pane.id)
                    return .failedMissingDrawerParent(parentId)
                }
                return .restored
            }
            _ = workspacePaneAtom.deletePaneAndOwnedDrawerChildren(snapshot.pane.id)
            return .failedMissingDrawerParent(nil)
        } else if let anchor = snapshot.anchorPaneId {
            guard
                workspaceTabLayoutAtom.insertPane(
                    snapshot.pane.id,
                    inTab: snapshot.tabId,
                    at: anchor,
                    direction: snapshot.direction,
                    position: .after
                )
            else {
                _ = workspacePaneAtom.deletePaneAndOwnedDrawerChildren(snapshot.pane.id)
                return .failedLayoutInsertion(tabId: snapshot.tabId, anchorPaneId: anchor)
            }
            workspaceTabLayoutAtom.setActivePane(snapshot.pane.id, inTab: snapshot.tabId)
            return .restored
        }
        _ = workspacePaneAtom.deletePaneAndOwnedDrawerChildren(snapshot.pane.id)
        return .failedLayoutInsertion(tabId: snapshot.tabId, anchorPaneId: snapshot.anchorPaneId)
    }
}
