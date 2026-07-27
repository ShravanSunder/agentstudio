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
        let panes = workspacePane.panes
        let tabs = workspaceTab.tabs
        var locationsByWorktreeId: [UUID: [WorkspacePaneLocation]] = [:]
        var seenPaneIds = Set<UUID>()

        for (tabIndex, tab) in tabs.enumerated() {
            for paneId in tab.allPaneIds {
                guard seenPaneIds.insert(paneId).inserted else { continue }
                guard let pane = panes[paneId], pane.residency == .active else { continue }
                guard let worktreeId = pane.worktreeId else { continue }

                let paneIndexInTab =
                    tab.activePaneIds.firstIndex(of: pane.id)
                    ?? tab.allPaneIds.firstIndex(of: pane.id)
                    ?? 0

                locationsByWorktreeId[worktreeId, default: []].append(
                    WorkspacePaneLocation(
                        paneId: pane.id,
                        tabId: tab.id,
                        tabIndex: tabIndex,
                        paneIndexInTab: paneIndexInTab,
                        isActiveInTab: tab.activePaneId == pane.id
                    )
                )
            }
        }

        for pane in panes.values where pane.residency == .active {
            guard !seenPaneIds.contains(pane.id), let worktreeId = pane.worktreeId else { continue }
            workspaceLookupLogger.warning(
                "paneLocationsByWorktreeId: active pane \(pane.id.uuidString, privacy: .public) for worktree \(worktreeId.uuidString, privacy: .public) has no owning tab"
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
