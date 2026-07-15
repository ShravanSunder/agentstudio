import CoreGraphics
import Foundation

struct WorkspaceLegacyHydrationSnapshot: Sendable {
    let id: UUID
    let name: String
    let repos: [CanonicalRepo]
    let worktrees: [CanonicalWorktree]
    let unavailableRepoIds: Set<UUID>
    let panes: [Pane]
    let tabs: [Tab]
    let activeTabId: UUID?
    let sidebarWidth: CGFloat
    let windowFrame: CGRect?
    let watchedPaths: [WatchedPath]
    let createdAt: Date

    init(_ state: WorkspacePersistor.PersistableState) {
        id = state.id
        name = state.name
        repos = state.repos
        worktrees = state.worktrees
        unavailableRepoIds = state.unavailableRepoIds
        panes = state.panes
        tabs = state.tabs
        activeTabId = state.activeTabId
        sidebarWidth = state.sidebarWidth
        windowFrame = state.windowFrame
        watchedPaths = state.watchedPaths
        createdAt = state.createdAt
    }
}

enum WorkspaceHydrationSource: Sendable {
    case legacy(WorkspaceLegacyHydrationSnapshot)
    case sqlite(
        workspace: WorkspaceSQLiteSnapshot,
        repositoryTopology: RepositoryTopologySQLiteSnapshot
    )

    static func legacy(_ state: WorkspacePersistor.PersistableState) -> Self {
        .legacy(WorkspaceLegacyHydrationSnapshot(state))
    }
}

enum WorkspaceHydrationPreparationRejection: Error, Equatable, Sendable {
    case sqliteWorkspaceIDMismatch(workspaceID: UUID, repositoryTopologyID: UUID)
    case repositoryTopology(RepositoryTopologyIdentityRejection)
    case duplicatePaneID(UUID)
    case duplicateDrawerID(UUID)
    case duplicateTabID(UUID)
    case duplicateArrangementID(UUID)
    case tabHasNoArrangements(UUID)
}

enum WorkspaceHydrationPreparationResult: Equatable, Sendable {
    case prepared(PreparedWorkspaceHydration)
    case rejected(WorkspaceHydrationPreparationRejection)
}

struct PreparedWorkspaceHydrationIdentity: Equatable, Sendable {
    let workspaceId: UUID
    let workspaceName: String
    let createdAt: Date
}

struct PreparedWorkspaceHydrationWindowMemory: Equatable, Sendable {
    let sidebarWidth: CGFloat
    let windowFrame: CGRect?
}

struct PreparedWorkspaceHydration: Equatable, Sendable {
    let identity: PreparedWorkspaceHydrationIdentity
    let windowMemory: PreparedWorkspaceHydrationWindowMemory
    let runtimeRepos: [Repo]
    let watchedPaths: [WatchedPath]
    let unavailableRepoIds: Set<UUID>
    let panes: [Pane]
    let tabs: [Tab]
    let activeTabId: UUID?
    let repairReport: WorkspaceTabMembershipRepairReport
    let validWorktreeIds: Set<UUID>
    let drawerParentPaneIdByDrawerId: [UUID: UUID]
}

enum WorkspaceHydrationPreparation {
    static func prepare(_ source: WorkspaceHydrationSource) -> WorkspaceHydrationPreparationResult {
        let payload: WorkspaceHydrationPayload
        switch source {
        case .legacy(let state):
            payload = WorkspaceHydrationPayload(
                workspaceId: state.id,
                workspaceName: state.name,
                createdAt: state.createdAt,
                sidebarWidth: state.sidebarWidth,
                windowFrame: state.windowFrame,
                canonicalRepos: state.repos,
                canonicalWorktrees: state.worktrees,
                watchedPaths: state.watchedPaths,
                unavailableRepoIds: state.unavailableRepoIds,
                panes: state.panes,
                tabs: state.tabs,
                activeTabId: state.activeTabId
            )
        case .sqlite(let workspace, let repositoryTopology):
            guard workspace.id == repositoryTopology.id else {
                return .rejected(
                    .sqliteWorkspaceIDMismatch(
                        workspaceID: workspace.id,
                        repositoryTopologyID: repositoryTopology.id
                    )
                )
            }
            payload = WorkspaceHydrationPayload(
                workspaceId: workspace.id,
                workspaceName: workspace.name,
                createdAt: workspace.createdAt,
                sidebarWidth: workspace.sidebarWidth,
                windowFrame: workspace.windowFrame,
                canonicalRepos: repositoryTopology.repos,
                canonicalWorktrees: repositoryTopology.worktrees,
                watchedPaths: repositoryTopology.watchedPaths,
                unavailableRepoIds: repositoryTopology.unavailableRepoIds,
                panes: workspace.panes,
                tabs: workspace.tabs,
                activeTabId: workspace.activeTabId
            )
        }

        if let rejection = validateIdentities(in: payload) {
            return .rejected(rejection)
        }

        let runtimeRepos = makeRuntimeRepos(
            canonicalRepos: payload.canonicalRepos,
            canonicalWorktrees: payload.canonicalWorktrees
        )
        let validWorktreeIds = Set(payload.canonicalWorktrees.map(\.id))
        let filteredPanes = filterAndNormalizePanes(
            payload.panes,
            validWorktreeIds: validWorktreeIds
        )
        let validPaneIds = Set(filteredPanes.map(\.id))
        let drawerParentPaneIdByDrawerId = makeDrawerParentPaneIdsByDrawerId(from: filteredPanes)
        let normalizedTabs = WorkspaceTabMembershipNormalizer.normalize(
            tabs: payload.tabs,
            validPaneIds: validPaneIds,
            activeTabId: payload.activeTabId,
            drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
        )

        return .prepared(
            PreparedWorkspaceHydration(
                identity: PreparedWorkspaceHydrationIdentity(
                    workspaceId: payload.workspaceId,
                    workspaceName: payload.workspaceName,
                    createdAt: payload.createdAt
                ),
                windowMemory: PreparedWorkspaceHydrationWindowMemory(
                    sidebarWidth: payload.sidebarWidth,
                    windowFrame: payload.windowFrame
                ),
                runtimeRepos: runtimeRepos,
                watchedPaths: payload.watchedPaths,
                unavailableRepoIds: payload.unavailableRepoIds,
                panes: filteredPanes,
                tabs: normalizedTabs.tabs,
                activeTabId: normalizedTabs.activeTabId,
                repairReport: normalizedTabs.repairReport,
                validWorktreeIds: validWorktreeIds,
                drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
            )
        )
    }

    private static func validateIdentities(
        in payload: WorkspaceHydrationPayload
    ) -> WorkspaceHydrationPreparationRejection? {
        var repositoryIds = Set<UUID>()
        for repository in payload.canonicalRepos {
            guard repositoryIds.insert(repository.id).inserted else {
                return .repositoryTopology(.duplicateRepositoryID(repository.id))
            }
        }

        var worktreeIds = Set<UUID>()
        for worktree in payload.canonicalWorktrees {
            guard worktreeIds.insert(worktree.id).inserted else {
                return .repositoryTopology(.duplicateWorktreeID(worktree.id))
            }
            guard repositoryIds.contains(worktree.repoId) else {
                return .repositoryTopology(
                    .worktreeRepositoryMissing(
                        worktreeID: worktree.id,
                        repositoryID: worktree.repoId
                    )
                )
            }
        }

        var watchedPathIds = Set<UUID>()
        for watchedPath in payload.watchedPaths {
            guard watchedPathIds.insert(watchedPath.id).inserted else {
                return .repositoryTopology(.duplicateWatchedPathID(watchedPath.id))
            }
        }

        if let missingRepositoryId = payload.unavailableRepoIds.first(where: {
            !repositoryIds.contains($0)
        }) {
            return .repositoryTopology(.unavailableRepositoryMissing(missingRepositoryId))
        }

        var paneIds = Set<UUID>()
        var drawerIds = Set<UUID>()
        for pane in payload.panes {
            guard paneIds.insert(pane.id).inserted else {
                return .duplicatePaneID(pane.id)
            }
            if let drawer = pane.drawer, !drawerIds.insert(drawer.drawerId).inserted {
                return .duplicateDrawerID(drawer.drawerId)
            }
        }

        var tabIds = Set<UUID>()
        var arrangementIds = Set<UUID>()
        for tab in payload.tabs {
            guard tabIds.insert(tab.id).inserted else {
                return .duplicateTabID(tab.id)
            }
            guard !tab.arrangements.isEmpty else {
                return .tabHasNoArrangements(tab.id)
            }
            for arrangement in tab.arrangements where !arrangementIds.insert(arrangement.id).inserted {
                return .duplicateArrangementID(arrangement.id)
            }
        }

        return nil
    }

    private static func makeRuntimeRepos(
        canonicalRepos: [CanonicalRepo],
        canonicalWorktrees: [CanonicalWorktree]
    ) -> [Repo] {
        let canonicalWorktreesByRepoId = Dictionary(grouping: canonicalWorktrees, by: \.repoId)
        return canonicalRepos.map { canonicalRepo in
            let runtimeWorktrees = (canonicalWorktreesByRepoId[canonicalRepo.id] ?? [])
                .map { canonicalWorktree in
                    Worktree(
                        id: canonicalWorktree.id,
                        repoId: canonicalWorktree.repoId,
                        name: canonicalWorktree.name,
                        path: canonicalWorktree.path,
                        isMainWorktree: canonicalWorktree.isMainWorktree,
                        tags: canonicalWorktree.tags
                    )
                }
            return Repo(
                id: canonicalRepo.id,
                name: canonicalRepo.name,
                repoPath: canonicalRepo.repoPath,
                worktrees: runtimeWorktrees,
                createdAt: canonicalRepo.createdAt,
                tags: canonicalRepo.tags
            )
        }
    }

    private static func filterAndNormalizePanes(
        _ panes: [Pane],
        validWorktreeIds: Set<UUID>
    ) -> [Pane] {
        var filteredPanes = panes.filter { pane in
            guard let worktreeId = pane.worktreeId else { return true }
            return validWorktreeIds.contains(worktreeId)
        }
        let validPaneIds = Set(filteredPanes.map(\.id))
        for paneIndex in filteredPanes.indices {
            filteredPanes[paneIndex].withDrawer { drawer in
                drawer.paneIds.removeAll { !validPaneIds.contains($0) }
            }
        }
        return filteredPanes
    }

    private static func makeDrawerParentPaneIdsByDrawerId(from panes: [Pane]) -> [UUID: UUID] {
        var parentPaneIdsByDrawerId: [UUID: UUID] = [:]
        for pane in panes {
            guard let drawer = pane.drawer else { continue }
            parentPaneIdsByDrawerId[drawer.drawerId] = pane.id
        }
        return parentPaneIdsByDrawerId
    }
}

private struct WorkspaceHydrationPayload: Sendable {
    let workspaceId: UUID
    let workspaceName: String
    let createdAt: Date
    let sidebarWidth: CGFloat
    let windowFrame: CGRect?
    let canonicalRepos: [CanonicalRepo]
    let canonicalWorktrees: [CanonicalWorktree]
    let watchedPaths: [WatchedPath]
    let unavailableRepoIds: Set<UUID>
    let panes: [Pane]
    let tabs: [Tab]
    let activeTabId: UUID?
}
