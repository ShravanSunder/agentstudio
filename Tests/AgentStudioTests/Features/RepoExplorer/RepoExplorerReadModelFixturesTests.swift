import AgentStudioCore
import Foundation

@testable import AgentStudioRepoExplorer

extension RepoExplorerReadModelTests {
    func repo(
        id: UUID,
        name: String,
        isPinned: Bool = false,
        worktrees: [Worktree]
    ) -> RepoPresentationItem {
        RepoPresentationItem(
            id: id,
            name: name,
            repoPath: URL(fileURLWithPath: "/tmp/\(name)"),
            stableKey: name,
            isPinned: isPinned,
            worktrees: worktrees
        )
    }

    func repoWithTabWorktrees(
        id: UUID,
        name: String,
        isPinned: Bool = false
    ) -> RepoPresentationItem {
        repo(
            id: id,
            name: name,
            isPinned: isPinned,
            worktrees: [
                worktree(repoId: id, name: "\(name)-earlier"),
                worktree(repoId: id, name: "\(name)-later"),
            ]
        )
    }

    func worktree(repoId: UUID, name: String = "main", isMain: Bool = false) -> Worktree {
        Worktree(
            repoId: repoId,
            name: name,
            path: URL(fileURLWithPath: "/tmp/\(name)"),
            isMainWorktree: isMain
        )
    }

    func resolvedRemote(repoId: UUID, displayName: String = "agent-studio") -> RepoEnrichment {
        .resolvedRemote(
            repoId: repoId,
            raw: RawRepoOrigin(origin: "git@github.com:askluna/\(displayName).git", upstream: nil),
            identity: RepoIdentity(
                groupKey: "remote:askluna/\(displayName)",
                remoteSlug: "askluna/\(displayName)",
                organizationName: "askluna",
                displayName: displayName
            ),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
