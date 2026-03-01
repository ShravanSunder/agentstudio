import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepoSidebarContentView")
struct RepoSidebarContentViewTests {
    @Test("branchStatus maps centralized local-git summary + PR count")
    func branchStatusMapsLocalSummaryAndPRCount() {
        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)")
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "feature/sidebar",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: rootPath,
                summary: GitWorkingTreeSummary(changed: 1, staged: 0, untracked: 2),
                branch: "feature/sidebar"
            )
        )

        let status = RepoSidebarContentView.branchStatus(
            enrichment: enrichment,
            pullRequestCount: 3
        )

        #expect(status.isDirty == true)
        #expect(status.prCount == 3)
        #expect(status.syncState == .unknown)
        #expect(status.linesAdded == 0)
        #expect(status.linesDeleted == 0)
    }

    @Test("branchStatus keeps unknown local state when snapshot missing")
    func branchStatusFallsBackToUnknownWithoutLocalSnapshot() {
        let status = RepoSidebarContentView.branchStatus(
            enrichment: nil,
            pullRequestCount: 7
        )

        #expect(status.isDirty == GitBranchStatus.unknown.isDirty)
        #expect(status.syncState == GitBranchStatus.unknown.syncState)
        #expect(status.prCount == 7)
    }

    @Test("mergeBranchStatuses merges local snapshots with independent PR counts")
    func mergeBranchStatusesMergesSources() {
        let localOnlyWorktreeId = UUID()
        let prOnlyWorktreeId = UUID()
        let repoId = UUID()

        let merged = RepoSidebarContentView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [
                localOnlyWorktreeId: WorktreeEnrichment(
                    worktreeId: localOnlyWorktreeId,
                    repoId: repoId,
                    branch: "",
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: localOnlyWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 0, staged: 1, untracked: 0),
                        branch: nil
                    )
                )
            ],
            pullRequestCountsByWorktreeId: [prOnlyWorktreeId: 2]
        )

        #expect(merged[localOnlyWorktreeId]?.isDirty == true)
        #expect(merged[localOnlyWorktreeId]?.prCount == nil)
        #expect(merged[prOnlyWorktreeId]?.prCount == 2)
        #expect(merged[prOnlyWorktreeId]?.syncState == .unknown)
    }

    @Test("sidebar branch status derives from worktree enrichment snapshots")
    func sidebarBranchStatusDerivesFromWorktreeEnrichmentSnapshots() {
        let worktreeId = UUID()
        let repoId = UUID()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "feature/sidebar-pipeline",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                branch: "feature/sidebar-pipeline"
            )
        )

        let merged = RepoSidebarContentView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [worktreeId: enrichment],
            pullRequestCountsByWorktreeId: [worktreeId: 5]
        )

        #expect(merged[worktreeId]?.isDirty == true)
        #expect(merged[worktreeId]?.prCount == 5)
        #expect(merged[worktreeId]?.syncState == .unknown)
    }

    @Test("primary grouping uses shared metadata group key")
    func primaryGroupingUsesSharedMetadataGroupKey() {
        let groupKey = "remote:askluna/agent-studio"
        let firstRepo = SidebarRepo(
            id: UUID(),
            name: "agent-studio-a",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio-a"),
            stableKey: "a",
            worktrees: [Worktree(name: "main", path: URL(fileURLWithPath: "/tmp/agent-studio-a"), branch: "main")]
        )
        let secondRepo = SidebarRepo(
            id: UUID(),
            name: "agent-studio-b",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio-b"),
            stableKey: "b",
            worktrees: [Worktree(name: "main", path: URL(fileURLWithPath: "/tmp/agent-studio-b"), branch: "main")]
        )
        let metadataByRepoId: [UUID: RepoIdentityMetadata] = [
            firstRepo.id: RepoIdentityMetadata(
                groupKey: groupKey,
                displayName: "agent-studio",
                repoName: "agent-studio",
                worktreeCommonDirectory: nil,
                folderCwd: firstRepo.repoPath.path,
                parentFolder: "tmp",
                organizationName: "askluna",
                originRemote: "git@github.com:askluna/agent-studio.git",
                upstreamRemote: nil,
                lastPathComponent: "agent-studio-a",
                worktreeCwds: firstRepo.worktrees.map(\.path.path),
                remoteFingerprint: "git@github.com:askluna/agent-studio.git",
                remoteSlug: "askluna/agent-studio"
            ),
            secondRepo.id: RepoIdentityMetadata(
                groupKey: groupKey,
                displayName: "agent-studio",
                repoName: "agent-studio",
                worktreeCommonDirectory: nil,
                folderCwd: secondRepo.repoPath.path,
                parentFolder: "tmp",
                organizationName: "askluna",
                originRemote: "https://github.com/askluna/agent-studio",
                upstreamRemote: nil,
                lastPathComponent: "agent-studio-b",
                worktreeCwds: secondRepo.worktrees.map(\.path.path),
                remoteFingerprint: "https://github.com/askluna/agent-studio",
                remoteSlug: "askluna/agent-studio"
            ),
        ]

        let groups = SidebarRepoGrouping.buildGroups(
            repos: [firstRepo, secondRepo],
            metadataByRepoId: metadataByRepoId
        )

        #expect(groups.count == 1)
        #expect(groups.first?.id == groupKey)
        #expect(groups.first?.repos.count == 2)
    }

    @Test("pending bucket grouping supports unresolved repos")
    func pendingBucketGroupingSupportsUnresolvedRepos() {
        let repo = SidebarRepo(
            id: UUID(),
            name: "pending-repo",
            repoPath: URL(fileURLWithPath: "/tmp/pending-repo"),
            stableKey: "pending",
            worktrees: [Worktree(name: "main", path: URL(fileURLWithPath: "/tmp/pending-repo"), branch: "main")]
        )
        let metadataByRepoId: [UUID: RepoIdentityMetadata] = [
            repo.id: RepoIdentityMetadata(
                groupKey: "pending:\(repo.id.uuidString)",
                displayName: "pending-repo",
                repoName: "pending-repo",
                worktreeCommonDirectory: nil,
                folderCwd: repo.repoPath.path,
                parentFolder: "tmp",
                organizationName: nil,
                originRemote: nil,
                upstreamRemote: nil,
                lastPathComponent: "pending-repo",
                worktreeCwds: repo.worktrees.map(\.path.path),
                remoteFingerprint: nil,
                remoteSlug: nil
            )
        ]

        let groups = SidebarRepoGrouping.buildGroups(
            repos: [repo],
            metadataByRepoId: metadataByRepoId
        )

        #expect(groups.count == 1)
        #expect(groups.first?.id == "pending:\(repo.id.uuidString)")
        #expect(groups.first?.repos.count == 1)
    }

    @Test("missing metadata falls back to path grouping key")
    func missingMetadataFallsBackToPathGroupingKey() {
        let repo = SidebarRepo(
            id: UUID(),
            name: "path-repo",
            repoPath: URL(fileURLWithPath: "/tmp/path-repo"),
            stableKey: "path",
            worktrees: [Worktree(name: "main", path: URL(fileURLWithPath: "/tmp/path-repo"), branch: "main")]
        )

        let groups = SidebarRepoGrouping.buildGroups(
            repos: [repo],
            metadataByRepoId: [:]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.id == "path:\(repo.repoPath.standardizedFileURL.path)")
    }
}
