import Foundation
import os.log

private let workspaceLookupLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceLookupDerived")

struct WorkspacePaneLocation: Equatable, Sendable {
    let paneId: UUID
    let tabId: UUID
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool
}

@MainActor
struct WorkspaceLookupDerived {
    func tabContaining(paneId: UUID) -> Tab? {
        atom(\.workspaceTab).tabContaining(paneId: paneId)
    }

    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        atom(\.repositoryTopology).repoAndWorktree(containing: cwd)
    }

    func paneLocations(
        for worktreeId: UUID,
        workspacePane: WorkspacePaneAtom,
        workspaceTab: WorkspaceTabLayoutDerived
    ) -> [WorkspacePaneLocation] {
        paneLocationsByWorktreeId(workspacePane: workspacePane, workspaceTab: workspaceTab)[worktreeId] ?? []
    }

    func paneLocations(for worktreeId: UUID) -> [WorkspacePaneLocation] {
        paneLocations(
            for: worktreeId,
            workspacePane: atom(\.workspacePane),
            workspaceTab: atom(\.workspaceTab)
        )
    }

    func paneLocationsByWorktreeId(
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
