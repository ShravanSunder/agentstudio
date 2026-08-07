import Foundation
import os.log

private let workspaceLookupLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceLookupDerived")

package struct WorkspacePaneLocation: Equatable, Sendable {
    package let paneId: UUID
    package let tabId: UUID
    package let tabIndex: Int
    package let paneIndexInTab: Int
    package let isActiveInTab: Bool

    package init(
        paneId: UUID,
        tabId: UUID,
        tabIndex: Int,
        paneIndexInTab: Int,
        isActiveInTab: Bool
    ) {
        self.paneId = paneId
        self.tabId = tabId
        self.tabIndex = tabIndex
        self.paneIndexInTab = paneIndexInTab
        self.isActiveInTab = isActiveInTab
    }
}

@MainActor
package struct WorkspaceLookupDerived {
    package init() {}

    package func tabContaining(paneId: UUID) -> Tab? {
        atom(\.workspaceTab).tabContaining(paneId: paneId)
    }

    package func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        atom(\.workspaceRepositoryTopology).repoAndWorktree(containing: cwd)
    }

    package func paneLocations(
        for worktreeId: UUID,
        workspacePane: WorkspacePaneAtom,
        workspaceTab: WorkspaceTabLayoutDerived
    ) -> [WorkspacePaneLocation] {
        paneLocationsByWorktreeId(workspacePane: workspacePane, workspaceTab: workspaceTab)[worktreeId] ?? []
    }

    package func paneLocations(for worktreeId: UUID) -> [WorkspacePaneLocation] {
        paneLocations(
            for: worktreeId,
            workspacePane: atom(\.workspacePane),
            workspaceTab: atom(\.workspaceTab)
        )
    }

    package func paneLocationsByWorktreeId(
        workspacePane: WorkspacePaneAtom,
        workspaceTab: WorkspaceTabLayoutDerived
    ) -> [UUID: [WorkspacePaneLocation]] {
        let paneGraph = workspacePane.graphAtom
        let repositoryTopology = atom(\.workspaceRepositoryTopology)
        let tabs = workspaceTab.tabs
        var locationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:]
        var seenPaneIds = Set<UUID>()

        for (tabIndex, tab) in tabs.enumerated() {
            for paneId in tab.allPaneIds {
                guard seenPaneIds.insert(paneId).inserted else { continue }
                guard let paneFacts = paneGraph.paneStructuralFacts(paneId), paneFacts.residency == .active else {
                    continue
                }
                guard let worktreeId = repositoryTopology.repoAndWorktree(containing: paneFacts.cwd)?.worktree.id else {
                    continue
                }

                let paneIndexInTab =
                    tab.activePaneIds.firstIndex(of: paneFacts.paneID)
                    ?? tab.allPaneIds.firstIndex(of: paneFacts.paneID)
                    ?? 0

                locationsByWorktreeId[worktreeId, default: []].append(
                    WorkspacePaneLocation(
                        paneId: paneFacts.paneID,
                        tabId: tab.id,
                        tabIndex: tabIndex,
                        paneIndexInTab: paneIndexInTab,
                        isActiveInTab: tab.activePaneId == paneFacts.paneID
                    )
                )
            }
        }

        for paneID in paneGraph.paneIDs {
            guard let paneFacts = paneGraph.paneStructuralFacts(paneID), paneFacts.residency == .active else {
                continue
            }
            guard !seenPaneIds.contains(paneID),
                let worktreeId = repositoryTopology.repoAndWorktree(containing: paneFacts.cwd)?.worktree.id
            else {
                continue
            }
            workspaceLookupLogger.warning(
                "paneLocationsByWorktreeId: active pane \(paneID.uuidString, privacy: .public) for worktree \(worktreeId.uuidString, privacy: .public) has no owning tab"
            )
        }

        return locationsByWorktreeId.mapValues { locations in
            locations.sorted { lhs, rhs in
                if lhs.tabIndex != rhs.tabIndex {
                    return lhs.tabIndex < rhs.tabIndex
                }
                if lhs.paneIndexInTab != rhs.paneIndexInTab {
                    return lhs.paneIndexInTab < rhs.paneIndexInTab
                }
                return lhs.paneId.uuidString < rhs.paneId.uuidString
            }
        }
    }
}
