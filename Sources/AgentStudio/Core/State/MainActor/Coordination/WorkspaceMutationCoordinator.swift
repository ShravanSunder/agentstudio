import Foundation
import os.log

@MainActor
package final class WorkspaceMutationCoordinator {
    package enum RestorePaneResult: Equatable {
        case restored
        case failedMissingDrawerParent(UUID?)
        case failedLayoutInsertion(tabId: UUID, anchorPaneId: UUID?)
    }

    package enum CloseEntry {
        case tab(TabCloseSnapshot)
        case pane(PaneCloseSnapshot)
    }

    package struct TabCloseSnapshot {
        package let tab: Tab
        package let panes: [Pane]
        package let tabIndex: Int
    }

    package struct PaneCloseSnapshot {
        package let pane: Pane
        package let drawerChildPanes: [Pane]
        package let drawerViewsByArrangementId: [UUID: DrawerView]
        package let tabId: UUID
        package let anchorPaneId: UUID?
        package let direction: Layout.SplitDirection

        package init(
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

    let repositoryTopologyAtom: RepositoryTopologyAtom
    private let workspacePaneAtom: WorkspacePaneAtom
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabArrangementAtom: WorkspaceTabArrangementAtom

    private var workspaceTab: WorkspaceTabLayoutDerived {
        WorkspaceTabLayoutDerived(
            shellAtom: workspaceTabShellAtom,
            arrangementAtom: workspaceTabArrangementAtom
        )
    }

    package init(
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
    package func removePane(_ paneId: UUID) -> Bool {
        let removedPane = workspacePaneAtom.pane(paneId)
        let removedDrawerIds = Set([removedPane?.drawer?.drawerId].compactMap(\.self))
        let removedPaneIds = Set([paneId] + (removedPane?.drawer?.paneIds ?? []))
        guard workspacePaneAtom.deletePaneAndOwnedDrawerChildren(paneId) else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("removePane: pane \(paneId) not found")
            return false
        }
        for removedPaneId in removedPaneIds {
            workspaceTabArrangementAtom.presentationAtom.removeZoomSourcePane(removedPaneId)
        }
        workspaceTabArrangementAtom.removePaneReferences(removedPaneIds, removingDrawerIds: removedDrawerIds)
        removeEmptyTabs()
        return true
    }

    @discardableResult
    package func backgroundPane(_ paneId: UUID) -> Bool {
        guard let backgroundedPane = workspacePaneAtom.pane(paneId) else {
            Logger(subsystem: "com.agentstudio", category: "WorkspaceMutationCoordinator")
                .warning("backgroundPane: pane \(paneId) not found")
            return false
        }
        workspacePaneAtom.setResidency(.backgrounded, for: paneId)
        for drawerPaneId in backgroundedPane.drawer?.paneIds ?? [] {
            workspacePaneAtom.setResidency(.backgrounded, for: drawerPaneId)
        }
        return true
    }

    @discardableResult
    package func reactivatePane(
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

        if workspaceTab.tabContaining(paneId: paneId) != nil {
            workspacePaneAtom.setResidency(.active, for: paneId)
            for drawerPaneId in pane.drawer?.paneIds ?? [] {
                workspacePaneAtom.setResidency(.active, for: drawerPaneId)
            }
            return true
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
            workspaceTabArrangementAtom.restoreDrawerPaneViews(
                drawerId: drawer.drawerId,
                parentPaneId: paneId,
                drawerPaneIds: drawer.paneIds,
                drawerViewsByArrangementId: [:],
                inTab: tabId
            )
        }
        return true
    }

    func applyRepoReassociation(
        _ result: RepositoryReassociationResult
    ) -> RepositoryReassociationResult {
        result
    }

    @discardableResult
    package func orphanPanesForRemovedWorktreeIfUnmatched(
        _ removedWorktree: RemovedWorktreeEntry
    ) -> [UUID] {
        let currentWorktreeIDs = Set(repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id))
        let affectedPaneIDs = workspacePaneAtom.paneSnapshot().values.compactMap { pane -> UUID? in
            guard pane.residency == .active || pane.residency == .backgrounded else { return nil }
            guard let cwd = pane.metadata.cwd?.standardizedFileURL else { return nil }
            guard Self.path(removedWorktree.path, contains: cwd) else { return nil }
            guard
                repositoryTopologyAtom.repoAndWorktree(
                    containing: cwd,
                    among: currentWorktreeIDs
                ) == nil
            else { return nil }
            return pane.id
        }
        for paneID in affectedPaneIDs {
            workspacePaneAtom.setResidency(
                .orphaned(reason: .worktreeNotFound(path: removedWorktree.path.path)),
                for: paneID
            )
        }
        return affectedPaneIDs
    }

    @discardableResult
    package func clearPaneAssociations(forRemovedWorktreeID removedWorktreeID: UUID) -> [UUID] {
        let affectedPaneIDs = workspacePaneAtom.graphAtom.paneStateSnapshot().values.compactMap { state in
            state.durableContextFacets.worktreeId == removedWorktreeID ? state.id : nil
        }
        for paneID in affectedPaneIDs {
            guard
                let state = workspacePaneAtom.graphAtom.paneState(paneID),
                let revision = workspacePaneAtom.graphAtom.reservePaneAssociationRevision(paneID)
            else { continue }
            _ = workspacePaneAtom.graphAtom.applyPaneAssociationUpdate(
                paneID,
                cwd: state.durableContextFacets.cwd,
                resolution: .confidentNoMatch,
                revision: revision
            )
        }
        return affectedPaneIDs
    }

    @discardableResult
    package func reconcilePaneAssociationsForCurrentTopology(
        affectedWorktreeIDs: Set<UUID>
    ) -> [UUID] {
        guard !affectedWorktreeIDs.isEmpty else { return [] }
        let topologySnapshot = repositoryTopologyAtom.captureReadSnapshot()
        let reconciliationCandidates: [(paneID: UUID, cwd: URL?, resolution: PaneAssociationResolution)] =
            workspacePaneAtom.graphAtom.paneStateSnapshot().values.compactMap { state in
                let facets = state.durableContextFacets
                let resolvedContext = topologySnapshot.repoAndWorktree(containing: facets.cwd)
                let currentAssociationIsAffected = facets.worktreeId.map(affectedWorktreeIDs.contains) ?? false
                let resolvedAssociationIsAffected =
                    resolvedContext.map { affectedWorktreeIDs.contains($0.worktree.id) } ?? false
                guard currentAssociationIsAffected || resolvedAssociationIsAffected else { return nil }

                let resolution: PaneAssociationResolution
                if let resolvedContext {
                    resolution = .matched(
                        repoId: resolvedContext.repo.id,
                        worktreeId: resolvedContext.worktree.id
                    )
                } else if topologySnapshot.hasUnavailableWorktree(containing: facets.cwd) {
                    resolution = .uncertain
                } else {
                    resolution = .confidentNoMatch
                }
                return (state.id, facets.cwd, resolution)
            }
        var changedPaneIDs: [UUID] = []
        for (paneID, cwd, resolution) in reconciliationCandidates {
            guard let revision = workspacePaneAtom.graphAtom.reservePaneAssociationRevision(paneID) else {
                continue
            }
            let updateResult = workspacePaneAtom.graphAtom.applyPaneAssociationUpdate(
                paneID,
                cwd: cwd,
                resolution: resolution,
                revision: revision
            )
            if updateResult == .applied {
                changedPaneIDs.append(paneID)
            }
        }
        return changedPaneIDs
    }

    @discardableResult
    package func restoreOrphanedPaneResidencyForCurrentTopology() -> Bool {
        let activeLayoutPaneIDs = workspaceTab.allPaneIds
        let currentWorktreeIDs = Set(repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id))
        let restorablePaneIDs = workspacePaneAtom.paneSnapshot().values.compactMap { pane -> UUID? in
            guard pane.residency.isOrphaned else { return nil }
            guard let cwd = pane.metadata.cwd else { return nil }
            guard
                repositoryTopologyAtom.repoAndWorktree(
                    containing: cwd,
                    among: currentWorktreeIDs
                ) != nil
            else { return nil }
            return pane.id
        }
        for paneID in restorablePaneIDs {
            workspacePaneAtom.setResidency(
                activeLayoutPaneIDs.contains(paneID) ? .active : .backgrounded,
                for: paneID
            )
        }
        return !restorablePaneIDs.isEmpty
    }

    private nonisolated static func path(_ root: URL, contains candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.starts(with: rootComponents)
    }

    package func snapshotForClose(tabId: UUID) -> TabCloseSnapshot? {
        let tabs = workspaceTab.tabs
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabId }) else { return nil }
        let tab = tabs[tabIndex]
        var allPanes: [Pane] = []
        var seenPaneIds = Set<UUID>()
        for paneId in tab.allPaneIds {
            guard let layoutPane = workspacePaneAtom.pane(paneId) else { continue }
            if seenPaneIds.insert(layoutPane.id).inserted {
                allPanes.append(layoutPane)
            }
            if let drawer = layoutPane.drawer {
                for drawerPane in workspacePaneAtom.snapshotPanes(with: drawer.paneIds)
                where seenPaneIds.insert(drawerPane.id).inserted {
                    allPanes.append(drawerPane)
                }
            }
        }
        return TabCloseSnapshot(tab: tab, panes: allPanes, tabIndex: tabIndex)
    }

    package func snapshotForPaneClose(paneId: UUID, inTab tabId: UUID) -> PaneCloseSnapshot? {
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

    package func restoreFromSnapshot(_ snapshot: TabCloseSnapshot) {
        for pane in snapshot.panes {
            _ = workspacePaneAtom.insertRestoredPane(pane)
        }
        workspaceTabShellAtom.insertTabShell(
            TabShell(id: snapshot.tab.id, name: snapshot.tab.name, colorHex: snapshot.tab.colorHex),
            at: snapshot.tabIndex
        )
        workspaceTabArrangementAtom.insertState(
            Self.arrangementState(from: snapshot.tab),
            at: snapshot.tabIndex
        )
        for pane in snapshot.panes {
            workspacePaneAtom.setResidency(pane.residency, for: pane.id)
        }
        workspaceTabShellAtom.setActiveTab(snapshot.tab.id)
    }

    @discardableResult
    package func restoreFromPaneSnapshot(_ snapshot: PaneCloseSnapshot) -> RestorePaneResult {
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
            activeArrangementId: tab.activeArrangementId
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
