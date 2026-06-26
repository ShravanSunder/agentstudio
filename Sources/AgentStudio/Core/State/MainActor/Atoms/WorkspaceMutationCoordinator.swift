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
        let drawerViewsByArrangementId: [UUID: DrawerView]
        let tabId: UUID
        let anchorPaneId: UUID?
        let direction: Layout.SplitDirection

        init(
            pane: Pane,
            drawerChildPanes: [Pane],
            drawerViewsByArrangementId: [UUID: DrawerView] = [:],
            tabId: UUID,
            anchorPaneId: UUID?,
            direction: Layout.SplitDirection
        ) {
            self.pane = pane
            self.drawerChildPanes = drawerChildPanes
            self.drawerViewsByArrangementId = drawerViewsByArrangementId
            self.tabId = tabId
            self.anchorPaneId = anchorPaneId
            self.direction = direction
        }
    }

    private struct BackgroundedDrawerPayload {
        let drawerViewsByArrangementId: [UUID: DrawerView]
    }

    private let repositoryTopologyAtom: RepositoryTopologyAtom
    private let workspacePaneAtom: WorkspacePaneAtom
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabArrangementAtom: WorkspaceTabArrangementAtom
    private var backgroundedDrawerPayloadsByPaneId: [UUID: BackgroundedDrawerPayload] = [:]

    private var workspaceTab: WorkspaceTabLayoutDerived {
        WorkspaceTabLayoutDerived(
            shellAtom: workspaceTabShellAtom,
            arrangementAtom: workspaceTabArrangementAtom
        )
    }

    init(
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabArrangementAtom: WorkspaceTabArrangementAtom
    ) {
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.workspacePaneAtom = workspacePaneAtom
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabArrangementAtom = workspaceTabArrangementAtom
    }

    @discardableResult
    func removePane(_ paneId: UUID) -> Bool {
        let removedPane = workspacePaneAtom.pane(paneId)
        let removedDrawerIds = Set([removedPane?.drawer?.drawerId].compactMap(\.self))
        let removedPaneIds = Set([paneId] + (removedPane?.drawer?.paneIds ?? []))
        guard workspacePaneAtom.deletePaneAndOwnedDrawerChildren(paneId) else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("removePane: pane \(paneId) not found")
            return false
        }
        workspaceTabArrangementAtom.removePaneReferences(removedPaneIds, removingDrawerIds: removedDrawerIds)
        removeEmptyTabs()
        return true
    }

    @discardableResult
    func backgroundPane(_ paneId: UUID) -> Bool {
        guard let backgroundedPane = workspacePaneAtom.pane(paneId) else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("backgroundPane: pane \(paneId) not found")
            return false
        }
        let removedDrawerIds = Set([backgroundedPane.drawer?.drawerId].compactMap(\.self))
        let removedPaneIds = Set([paneId] + (backgroundedPane.drawer?.paneIds ?? []))
        if let drawer = backgroundedPane.drawer, !drawer.paneIds.isEmpty {
            backgroundedDrawerPayloadsByPaneId[paneId] = BackgroundedDrawerPayload(
                drawerViewsByArrangementId: drawerViewsByArrangementId(
                    drawerId: drawer.drawerId,
                    parentPaneId: paneId
                )
            )
        } else {
            backgroundedDrawerPayloadsByPaneId.removeValue(forKey: paneId)
        }
        workspaceTabArrangementAtom.removePaneReferences(removedPaneIds, removingDrawerIds: removedDrawerIds)
        removeEmptyTabs()
        workspacePaneAtom.setResidency(.backgrounded, for: paneId)
        for drawerPaneId in backgroundedPane.drawer?.paneIds ?? [] {
            workspacePaneAtom.setResidency(.backgrounded, for: drawerPaneId)
        }
        return true
    }

    @discardableResult
    func reactivatePane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        sizingMode: DropSizingMode
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
            workspaceTabArrangementAtom.insertPane(
                paneId,
                inTab: tabId,
                at: targetPaneId,
                direction: direction,
                position: position,
                sizingMode: sizingMode
            )
        else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("reactivatePane: failed inserting pane \(paneId) into tab \(tabId) at anchor \(targetPaneId)")
            return false
        }
        workspacePaneAtom.setResidency(.active, for: paneId)
        if let drawer = pane.drawer, !drawer.paneIds.isEmpty {
            for drawerPaneId in drawer.paneIds {
                workspacePaneAtom.setResidency(.active, for: drawerPaneId)
            }
            let payload = backgroundedDrawerPayloadsByPaneId.removeValue(forKey: paneId)
            workspaceTabArrangementAtom.restoreDrawerPaneViews(
                drawerId: drawer.drawerId,
                parentPaneId: paneId,
                drawerPaneIds: drawer.paneIds,
                drawerViewsByArrangementId: payload?.drawerViewsByArrangementId ?? [:],
                inTab: tabId
            )
        } else {
            backgroundedDrawerPayloadsByPaneId.removeValue(forKey: paneId)
        }
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
            activeLayoutPaneIds: workspaceTab.allPaneIds
        )
    }

    func snapshotForClose(tabId: UUID) -> TabCloseSnapshot? {
        let tabs = workspaceTab.tabs
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return nil }
        let tab = tabs[tabIndex]
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
        guard let closedPane = workspacePaneAtom.pane(paneId), let tab = workspaceTab.tab(tabId) else {
            return nil
        }

        let drawerChildPanes = closedPane.drawer.map { workspacePaneAtom.snapshotPanes(with: $0.paneIds) } ?? []
        let drawerViewsByArrangementId: [UUID: DrawerView]
        if let drawerId = closedPane.drawer?.drawerId {
            drawerViewsByArrangementId = Dictionary(
                uniqueKeysWithValues: tab.arrangements.compactMap { arrangement in
                    arrangement.drawerViews[drawerId].map { (arrangement.id, $0) }
                }
            )
        } else {
            drawerViewsByArrangementId = [:]
        }
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
            drawerViewsByArrangementId: drawerViewsByArrangementId,
            tabId: tabId,
            anchorPaneId: anchorPaneId,
            direction: direction
        )
    }

    private func drawerViewsByArrangementId(drawerId: UUID, parentPaneId: UUID) -> [UUID: DrawerView] {
        guard let tab = workspaceTab.tabContaining(paneId: parentPaneId) else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: tab.arrangements.compactMap { arrangement in
                arrangement.drawerViews[drawerId].map { (arrangement.id, $0) }
            }
        )
    }

    func restoreFromSnapshot(_ snapshot: TabCloseSnapshot) {
        for pane in snapshot.panes {
            _ = workspacePaneAtom.insertRestoredPane(pane)
        }
        workspaceTabShellAtom.insertTabShell(
            TabShell(id: snapshot.tab.id, name: snapshot.tab.name),
            at: snapshot.tabIndex
        )
        workspaceTabArrangementAtom.insertState(
            Self.arrangementState(from: snapshot.tab),
            at: snapshot.tabIndex
        )
        workspaceTabShellAtom.setActiveTab(snapshot.tab.id)
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
                workspaceTabArrangementAtom.insertPane(
                    snapshot.pane.id,
                    inTab: snapshot.tabId,
                    at: anchor,
                    direction: snapshot.direction,
                    position: .after,
                    sizingMode: .halveTarget
                )
            else {
                _ = workspacePaneAtom.deletePaneAndOwnedDrawerChildren(snapshot.pane.id)
                return .failedLayoutInsertion(tabId: snapshot.tabId, anchorPaneId: anchor)
            }
            workspaceTabArrangementAtom.setActivePane(snapshot.pane.id, inTab: snapshot.tabId)
            if let drawerId = snapshot.pane.drawer?.drawerId, !snapshot.drawerChildPanes.isEmpty {
                workspaceTabArrangementAtom.restoreDrawerPaneViews(
                    drawerId: drawerId,
                    parentPaneId: snapshot.pane.id,
                    drawerPaneIds: snapshot.drawerChildPanes.map(\.id),
                    drawerViewsByArrangementId: snapshot.drawerViewsByArrangementId,
                    inTab: snapshot.tabId
                )
            }
            return .restored
        }
        _ = workspacePaneAtom.deletePaneAndOwnedDrawerChildren(snapshot.pane.id)
        return .failedLayoutInsertion(tabId: snapshot.tabId, anchorPaneId: snapshot.anchorPaneId)
    }

    private static func arrangementState(from tab: Tab) -> TabArrangementState {
        TabArrangementState(
            tabId: tab.id,
            allPaneIds: tab.allPaneIds,
            arrangements: tab.arrangements,
            activeArrangementId: tab.activeArrangementId,
            zoomedPaneId: tab.zoomedPaneId
        )
    }

    private func removeEmptyTabs() {
        let emptyTabIds = workspaceTabArrangementAtom.arrangementStates.compactMap { state -> UUID? in
            !TabArrangementRepairRules.hasLivePaneReferences(in: state.arrangements) ? state.tabId : nil
        }

        for tabId in emptyTabIds {
            workspaceTabShellAtom.removeTabShell(tabId)
            workspaceTabArrangementAtom.removeState(tabId)
        }
    }
}
