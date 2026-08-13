import AgentStudioCore
import Foundation

@MainActor
final class CommandBarRepoScopeItemCache {
    private struct ArtifactIdentity: Equatable {
        let repository: Repo
        let worktreePresence: [WorktreePresence]
        let group: String
        let groupPriority: Int
    }

    private struct CachedArtifact {
        let identity: ArtifactIdentity
        let item: CommandBarItem
    }

    private var artifactsByRepositoryID: [UUID: CachedArtifact] = [:]
    private(set) var buildCount = 0

    func items(
        store: WorkspaceStore,
        group: String,
        groupPriority: Int,
        dispatcher: any AppCommandDispatching
    ) -> [CommandBarItem] {
        let repositoryIDs = store.repositoryTopologyAtom.repositoryIdsInOrder
        let repositories = repositoryIDs.compactMap { repositoryID in
            store.repositoryTopologyAtom.repo(repositoryID)
        }
        let presenceByWorktreeID = CommandBarDataSource.buildWorktreePresenceByWorktreeId(
            repos: repositories,
            locationsByWorktreeId: CommandBarDataSource.worktreeLocationsByWorktreeId(store: store)
        )
        let liveRepositoryIDs = Set(repositoryIDs)
        artifactsByRepositoryID = artifactsByRepositoryID.filter { liveRepositoryIDs.contains($0.key) }

        return
            repositories
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { repository in
                let identity = ArtifactIdentity(
                    repository: repository,
                    worktreePresence: repository.worktrees.map { worktree in
                        presenceByWorktreeID[worktree.id]
                            ?? CommandBarDataSource.emptyWorktreePresence(
                                worktree: worktree,
                                repo: repository
                            )
                    },
                    group: group,
                    groupPriority: groupPriority
                )
                if let cachedArtifact = artifactsByRepositoryID[repository.id],
                    cachedArtifact.identity == identity
                {
                    return cachedArtifact.item
                }

                let item = CommandBarDataSource.repoRootItem(
                    repo: repository,
                    presenceByWorktreeId: presenceByWorktreeID,
                    group: group,
                    groupPriority: groupPriority
                )
                artifactsByRepositoryID[repository.id] = CachedArtifact(
                    identity: identity,
                    item: item
                )
                buildCount += 1
                return item
            }
    }
}
