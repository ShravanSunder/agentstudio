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
        atom(\.workspaceRepositoryTopology).repoAndWorktree(containing: cwd)
    }

    func paneLocations(
        for worktreeId: UUID,
        workspacePane: WorkspacePaneAtom,
        workspaceTab: WorkspaceTabLayoutDerived
    ) -> [WorkspacePaneLocation] {
        workspacePane.panes(for: worktreeId)
            .compactMap { pane in
                guard pane.residency == .active else { return nil }
                guard let tab = workspaceTab.tabContaining(paneId: pane.id) else {
                    workspaceLookupLogger.warning(
                        "paneLocations: active pane \(pane.id.uuidString, privacy: .public) for worktree \(worktreeId.uuidString, privacy: .public) has no owning tab"
                    )
                    return nil
                }
                guard let tabIndex = workspaceTab.tabs.firstIndex(where: { $0.id == tab.id }) else {
                    workspaceLookupLogger.warning(
                        "paneLocations: active pane \(pane.id.uuidString, privacy: .public) for worktree \(worktreeId.uuidString, privacy: .public) has tab \(tab.id.uuidString, privacy: .public) missing from tab order"
                    )
                    return nil
                }

                let paneIndexInTab =
                    tab.activePaneIds.firstIndex(of: pane.id)
                    ?? tab.allPaneIds.firstIndex(of: pane.id)
                    ?? 0

                return WorkspacePaneLocation(
                    paneId: pane.id,
                    tabId: tab.id,
                    tabIndex: tabIndex,
                    paneIndexInTab: paneIndexInTab,
                    isActiveInTab: tab.activePaneId == pane.id
                )
            }
            .sorted { lhs, rhs in
                if lhs.tabIndex != rhs.tabIndex {
                    return lhs.tabIndex < rhs.tabIndex
                }
                if lhs.paneIndexInTab != rhs.paneIndexInTab {
                    return lhs.paneIndexInTab < rhs.paneIndexInTab
                }
                return lhs.paneId.uuidString < rhs.paneId.uuidString
            }
    }

    func paneLocations(for worktreeId: UUID) -> [WorkspacePaneLocation] {
        paneLocations(
            for: worktreeId,
            workspacePane: atom(\.workspacePane),
            workspaceTab: atom(\.workspaceTab)
        )
    }
}
