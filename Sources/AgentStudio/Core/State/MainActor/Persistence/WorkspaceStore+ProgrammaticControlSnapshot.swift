import Foundation

package enum ProgrammaticControlPaneContentKind: Equatable, Sendable {
    case terminal
    case webview
    case bridgePanel
    case codeViewer
    case unsupported
}

package enum ProgrammaticControlPaneResidency: Equatable, Sendable {
    case active
    case pendingUndo
    case backgrounded
    case orphaned
}

package struct ProgrammaticControlWorkspaceSnapshot: Equatable, Sendable {
    package let id: UUID
    package let name: String
    package let tabs: [ProgrammaticControlTabSnapshot]
    package let panes: [ProgrammaticControlPaneSnapshot]
    package let repositories: [ProgrammaticControlRepositorySnapshot]
    package let activeTabId: UUID?

    package var activeTab: ProgrammaticControlTabSnapshot? {
        activeTabId.flatMap { tabId in tabs.first { $0.id == tabId } }
    }
}

package struct ProgrammaticControlTabSnapshot: Equatable, Sendable {
    package let id: UUID
    package let name: String
    package let paneIds: [UUID]
    package let activePaneId: UUID?
    package let isActive: Bool
}

package struct ProgrammaticControlPaneSnapshot: Equatable, Sendable {
    package let id: UUID
    package let title: String
    package let contentKind: ProgrammaticControlPaneContentKind
    package let residency: ProgrammaticControlPaneResidency
    package let tabId: UUID?
    package let repoId: UUID?
    package let worktreeId: UUID?
    package let isActive: Bool
    package let isDrawerChild: Bool
}

package struct ProgrammaticControlRepositorySnapshot: Equatable, Sendable {
    package let id: UUID
    package let name: String
    package let path: String
    package let worktrees: [ProgrammaticControlWorktreeSnapshot]
}

package struct ProgrammaticControlWorktreeSnapshot: Equatable, Sendable {
    package let id: UUID
    package let repoId: UUID
    package let name: String
    package let path: String
    package let isMainWorktree: Bool
}

@MainActor
extension WorkspaceStore {
    package func programmaticControlSnapshot() -> ProgrammaticControlWorkspaceSnapshot {
        let tabs = tabLayoutAtom.tabs
        let tabIdByPaneId = tabIdByPaneId(tabs: tabs)

        let paneSnapshots = sortedPanesForProgrammaticControl(tabs: tabs).map { pane in
            let tabId = tabIdByPaneId[pane.id]
            let tab = tabId.flatMap(tabLayoutAtom.tab)
            return ProgrammaticControlPaneSnapshot(
                id: pane.id,
                title: pane.title,
                contentKind: ProgrammaticControlPaneContentKind(content: pane.content),
                residency: ProgrammaticControlPaneResidency(residency: pane.residency),
                tabId: tabId,
                repoId: pane.repoId,
                worktreeId: pane.worktreeId,
                isActive: tab?.activePaneId == pane.id,
                isDrawerChild: pane.isDrawerChild
            )
        }

        let tabSnapshots = tabs.map { tab in
            ProgrammaticControlTabSnapshot(
                id: tab.id,
                name: tab.name,
                paneIds: tab.activePaneIds,
                activePaneId: tab.activePaneId,
                isActive: tab.id == tabLayoutAtom.activeTabId
            )
        }

        let repositorySnapshots = repositoryTopologyAtom.repos.map { repo in
            ProgrammaticControlRepositorySnapshot(
                id: repo.id,
                name: repo.name,
                path: repo.repoPath.path,
                worktrees: repo.worktrees.map { worktree in
                    ProgrammaticControlWorktreeSnapshot(
                        id: worktree.id,
                        repoId: worktree.repoId,
                        name: worktree.name,
                        path: worktree.path.path,
                        isMainWorktree: worktree.isMainWorktree
                    )
                }
            )
        }

        return ProgrammaticControlWorkspaceSnapshot(
            id: identityAtom.workspaceId,
            name: identityAtom.workspaceName,
            tabs: tabSnapshots,
            panes: paneSnapshots,
            repositories: repositorySnapshots,
            activeTabId: tabLayoutAtom.activeTabId
        )
    }

    private func sortedPanesForProgrammaticControl(tabs: [Tab]) -> [Pane] {
        var visitedPaneIds = Set<UUID>()
        var orderedPanes: [Pane] = []

        for paneId in tabs.flatMap(\.activePaneIds) {
            guard !visitedPaneIds.contains(paneId), let pane = paneAtom.pane(paneId) else { continue }
            visitedPaneIds.insert(paneId)
            orderedPanes.append(pane)
        }

        let remainingPanes = paneAtom.paneSnapshot().values
            .filter { !visitedPaneIds.contains($0.id) }
            .sorted { lhs, rhs in lhs.id.uuidString < rhs.id.uuidString }

        return orderedPanes + remainingPanes
    }

    private func tabIdByPaneId(tabs: [Tab]) -> [UUID: UUID] {
        var tabIdByPaneId: [UUID: UUID] = [:]
        for tab in tabs {
            for paneId in tab.allPaneIds {
                tabIdByPaneId[paneId] = tab.id
            }
        }
        return tabIdByPaneId
    }
}

extension ProgrammaticControlPaneContentKind {
    fileprivate init(content: PaneContent) {
        switch content {
        case .terminal:
            self = .terminal
        case .webview:
            self = .webview
        case .bridgePanel:
            self = .bridgePanel
        case .codeViewer:
            self = .codeViewer
        case .unsupported:
            self = .unsupported
        }
    }
}

extension ProgrammaticControlPaneResidency {
    fileprivate init(residency: SessionResidency) {
        switch residency {
        case .active:
            self = .active
        case .pendingUndo:
            self = .pendingUndo
        case .backgrounded:
            self = .backgrounded
        case .orphaned:
            self = .orphaned
        }
    }
}
