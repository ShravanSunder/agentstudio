import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("RepoSidebarContentView")
struct RepoSidebarContentViewTests {
    @Test("flat list entries expand a resolved group into header and child rows")
    func flatListEntriesExpandResolvedGroupIntoHeaderAndChildRows() {
        let repoId = UUID()
        let worktree = Worktree(
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio"),
            isMainWorktree: true
        )
        let repo = SidebarRepo(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [worktree]
        )
        let group = SidebarRepoGroup(
            id: "remote:askluna/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "askluna",
            repos: [repo]
        )

        let entries = RepoSidebarContentView.buildListEntries(
            groups: [group],
            expandedGroupIds: [group.id],
            isFiltering: false
        )

        #expect(entries.count == 2)
        guard
            case .resolvedGroupHeader(let headerGroup) = entries[0],
            case .resolvedWorktreeRow(let childGroupId, let childRepoId, let childWorktreeId) = entries[1]
        else {
            Issue.record("Expected flat resolved header followed by child row")
            return
        }

        #expect(headerGroup.id == group.id)
        #expect(childGroupId == group.id)
        #expect(childRepoId == repo.id)
        #expect(childWorktreeId == worktree.id)
    }

    @Test("flat list entries keep collapsed groups flat with header only")
    func flatListEntriesKeepCollapsedGroupsFlatWithHeaderOnly() {
        let repoId = UUID()
        let repo = SidebarRepo(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [Worktree(repoId: repoId, name: "main", path: URL(fileURLWithPath: "/tmp/agent-studio"))]
        )
        let group = SidebarRepoGroup(
            id: "remote:askluna/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "askluna",
            repos: [repo]
        )

        let entries = RepoSidebarContentView.buildListEntries(
            groups: [group],
            expandedGroupIds: [],
            isFiltering: false
        )

        #expect(entries.count == 1)
        guard case .resolvedGroupHeader(let headerGroup) = entries[0] else {
            Issue.record("Expected collapsed group to render header only")
            return
        }
        #expect(headerGroup.id == group.id)
    }

    @Test("flat list entries only include resolved headers and worktree rows")
    func flatListEntriesOnlyIncludeResolvedHeadersAndWorktreeRows() {
        let resolvedRepoId = UUID()
        let resolvedGroup = SidebarRepoGroup(
            id: "remote:askluna/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "askluna",
            repos: [
                SidebarRepo(
                    id: resolvedRepoId,
                    name: "agent-studio",
                    repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                    stableKey: "agent-studio",
                    worktrees: [
                        Worktree(
                            repoId: resolvedRepoId,
                            name: "main",
                            path: URL(fileURLWithPath: "/tmp/agent-studio")
                        )
                    ]
                )
            ]
        )

        let entries = RepoSidebarContentView.buildListEntries(
            groups: [resolvedGroup],
            expandedGroupIds: [],
            isFiltering: false
        )

        #expect(entries.count == 1)
        guard case .resolvedGroupHeader = entries[0] else {
            Issue.record("Expected only the resolved header entry")
            return
        }
    }

    @Test("sidebar projection separates resolved groups from loading repos")
    func sidebarProjectionSeparatesResolvedGroupsFromLoadingRepos() {
        let resolvedId = UUID()
        let unresolvedId = UUID()
        let missingId = UUID()

        let resolvedRepo = SidebarRepo(
            id: resolvedId,
            name: "resolved-repo",
            repoPath: URL(fileURLWithPath: "/tmp/resolved-repo"),
            stableKey: "resolved-repo",
            worktrees: [Worktree(repoId: resolvedId, name: "main", path: URL(fileURLWithPath: "/tmp/resolved-repo"))]
        )
        let unresolvedRepo = SidebarRepo(
            id: unresolvedId,
            name: "loading-repo",
            repoPath: URL(fileURLWithPath: "/tmp/loading-repo"),
            stableKey: "loading-repo",
            worktrees: [Worktree(repoId: unresolvedId, name: "main", path: URL(fileURLWithPath: "/tmp/loading-repo"))]
        )
        let missingRepo = SidebarRepo(
            id: missingId,
            name: "missing-repo",
            repoPath: URL(fileURLWithPath: "/tmp/missing-repo"),
            stableKey: "missing-repo",
            worktrees: [Worktree(repoId: missingId, name: "main", path: URL(fileURLWithPath: "/tmp/missing-repo"))]
        )

        let projection = RepoSidebarContentView.projectSidebar(
            repos: [resolvedRepo, unresolvedRepo, missingRepo],
            repoEnrichmentByRepoId: [
                resolvedId: .resolvedRemote(
                    repoId: resolvedId,
                    raw: RawRepoOrigin(origin: "git@github.com:org/resolved-repo.git", upstream: nil),
                    identity: RepoIdentity(
                        groupKey: "remote:org/resolved-repo",
                        remoteSlug: "org/resolved-repo",
                        organizationName: "org",
                        displayName: "resolved-repo"
                    ),
                    updatedAt: Date()
                ),
                unresolvedId: .awaitingOrigin(repoId: unresolvedId),
            ],
            query: ""
        )

        #expect(projection.resolvedGroups.count == 1)
        #expect(projection.resolvedGroups.first?.repos.map(\.id) == [resolvedId])
        #expect(Set(projection.loadingRepos.map(\.id)) == Set([unresolvedId, missingId]))
        #expect(projection.showsNoResults == false)
    }

    @Test("sidebar projection keeps loading matches visible during filtering")
    func sidebarProjectionKeepsLoadingMatchesVisibleDuringFiltering() {
        let loadingRepo = SidebarRepo(
            id: UUID(),
            name: "loading-target",
            repoPath: URL(fileURLWithPath: "/tmp/loading-target"),
            stableKey: "loading-target",
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/loading-target"))]
        )

        let projection = RepoSidebarContentView.projectSidebar(
            repos: [loadingRepo],
            repoEnrichmentByRepoId: [:],
            query: "loading"
        )

        #expect(projection.resolvedGroups.isEmpty)
        #expect(projection.loadingRepos.map(\.id) == [loadingRepo.id])
        #expect(projection.showsNoResults == false)
    }

    @Test("sidebar projection shows no results only when both sections are empty for a query")
    func sidebarProjectionShowsNoResultsOnlyWhenBothSectionsAreEmpty() {
        let loadingRepo = SidebarRepo(
            id: UUID(),
            name: "loading-target",
            repoPath: URL(fileURLWithPath: "/tmp/loading-target"),
            stableKey: "loading-target",
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/loading-target"))]
        )

        let projection = RepoSidebarContentView.projectSidebar(
            repos: [loadingRepo],
            repoEnrichmentByRepoId: [:],
            query: "no-match"
        )

        #expect(projection.resolvedGroups.isEmpty)
        #expect(projection.loadingRepos.isEmpty)
        #expect(projection.showsNoResults)
    }

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

    @Test("branchStatus maps sync and line diff values from snapshot summary")
    func branchStatusMapsSnapshotSyncAndLineDiff() {
        let worktreeId = UUID()
        let repoId = UUID()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                summary: GitWorkingTreeSummary(
                    changed: 2,
                    staged: 1,
                    untracked: 0,
                    linesAdded: 12,
                    linesDeleted: 3,
                    aheadCount: 1,
                    behindCount: 0,
                    hasUpstream: true
                ),
                branch: "main"
            )
        )

        let status = RepoSidebarContentView.branchStatus(
            enrichment: enrichment,
            pullRequestCount: 1
        )

        #expect(status.isDirty)
        #expect(status.linesAdded == 12)
        #expect(status.linesDeleted == 3)
        #expect(status.syncState == .ahead(1))
        #expect(status.prCount == 1)
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
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/agent-studio-a"))]
        )
        let secondRepo = SidebarRepo(
            id: UUID(),
            name: "agent-studio-b",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio-b"),
            stableKey: "b",
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/agent-studio-b"))]
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

    @Test("projection fingerprint changes when repo graduates from loading to resolved")
    func projectionFingerprintChangesWhenTopologyChanges() {
        let repo = SidebarRepo(
            id: UUID(),
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/agent-studio"))]
        )

        let loadingProjection = RepoSidebarContentView.projectSidebar(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repo.id: .awaitingOrigin(repoId: repo.id)
            ],
            query: ""
        )
        let resolvedProjection = RepoSidebarContentView.projectSidebar(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repo.id: .resolvedRemote(
                    repoId: repo.id,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: RepoIdentity(
                        groupKey: "remote:askluna/agent-studio",
                        remoteSlug: "askluna/agent-studio",
                        organizationName: "askluna",
                        displayName: "agent-studio"
                    ),
                    updatedAt: Date()
                )
            ],
            query: ""
        )

        let loadingFingerprint = RepoSidebarContentView.projectionFingerprint(for: loadingProjection)
        let resolvedFingerprint = RepoSidebarContentView.projectionFingerprint(for: resolvedProjection)

        #expect(loadingFingerprint != resolvedFingerprint)
        #expect(loadingProjection.loadingRepos.map(\.id) == [repo.id])
        #expect(resolvedProjection.resolvedGroups.first?.repos.map(\.id) == [repo.id])
    }

    @Test("repo metadata builder uses resolved local identity when available")
    func repoMetadataBuilderUsesResolvedLocalIdentity() {
        let repo = SidebarRepo(
            id: UUID(),
            name: "MyProject",
            repoPath: URL(fileURLWithPath: "/tmp/MyProject"),
            stableKey: "my-project",
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/MyProject"))]
        )

        let metadata = RepoSidebarContentView.buildRepoMetadata(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repo.id: .resolvedLocal(
                    repoId: repo.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: "MyProject"),
                    updatedAt: Date()
                )
            ]
        )

        #expect(metadata[repo.id]?.groupKey == "local:MyProject")
        #expect(metadata[repo.id]?.organizationName == nil)
    }

    @Test("missing metadata falls back to path grouping key")
    func missingMetadataFallsBackToPathGroupingKey() {
        let repo = SidebarRepo(
            id: UUID(),
            name: "path-repo",
            repoPath: URL(fileURLWithPath: "/tmp/path-repo"),
            stableKey: "path",
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/path-repo"))]
        )

        let groups = SidebarRepoGrouping.buildGroups(
            repos: [repo],
            metadataByRepoId: [:]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.id == "path:\(repo.repoPath.standardizedFileURL.path)")
    }

    @Test("branch label prefers enrichment branch over canonical fallback")
    func branchLabelPrefersEnrichmentBranch() {
        let worktree = Worktree(
            repoId: UUID(),
            name: "feature-a",
            path: URL(fileURLWithPath: "/tmp/feature-a"),
            isMainWorktree: false
        )
        let enrichment = WorktreeEnrichment(
            worktreeId: worktree.id,
            repoId: UUID(),
            branch: "feature/fix-primary-sidebar",
            snapshot: nil
        )

        let label = PaneDisplayProjector.resolvedBranchName(
            worktree: worktree,
            enrichment: enrichment
        )

        #expect(label == "feature/fix-primary-sidebar")
    }

    @Test("branch label falls back to detached head only when both sources are empty")
    func branchLabelDetachedHeadFallback() {
        let worktree = Worktree(
            repoId: UUID(),
            name: "unknown",
            path: URL(fileURLWithPath: "/tmp/unknown"),
            isMainWorktree: false
        )

        let label = PaneDisplayProjector.resolvedBranchName(
            worktree: worktree,
            enrichment: nil
        )

        #expect(label == "detached HEAD")
    }

    @Test("repo metadata builder uses resolved remote identity when available")
    func repoMetadataBuilderUsesResolvedIdentity() {
        let repo = SidebarRepo(
            id: UUID(),
            name: "agent-studio-local",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio-local"),
            stableKey: "agent-studio-local",
            worktrees: [Worktree(repoId: UUID(), name: "main", path: URL(fileURLWithPath: "/tmp/agent-studio-local"))]
        )

        let metadata = RepoSidebarContentView.buildRepoMetadata(
            repos: [repo],
            repoEnrichmentByRepoId: [
                repo.id: .resolvedRemote(
                    repoId: repo.id,
                    raw: RawRepoOrigin(origin: "git@github.com:askluna/agent-studio.git", upstream: nil),
                    identity: RepoIdentity(
                        groupKey: "remote:askluna/agent-studio",
                        remoteSlug: "askluna/agent-studio",
                        organizationName: "askluna",
                        displayName: "agent-studio"
                    ),
                    updatedAt: Date()
                )
            ]
        )

        #expect(metadata[repo.id]?.groupKey == "remote:askluna/agent-studio")
        #expect(metadata[repo.id]?.organizationName == "askluna")
    }

    @Test("primaryRepoForGroup prefers repo whose repoPath matches one of its worktrees")
    func primaryRepoForGroupPrefersRepoPathMatch() {
        let repoA = SidebarRepo(
            id: UUID(),
            name: "askluna-finance-rlvr-forking",
            repoPath: URL(fileURLWithPath: "/tmp/askluna-finance-rlvr-forking"),
            stableKey: "a",
            worktrees: [
                Worktree(
                    repoId: UUID(),
                    name: "rlvr-forking",
                    path: URL(fileURLWithPath: "/tmp/askluna-finance-rlvr-forking")
                )
            ]
        )
        let repoB = SidebarRepo(
            id: UUID(),
            name: "askluna-finance",
            repoPath: URL(fileURLWithPath: "/tmp/askluna-finance"),
            stableKey: "b",
            worktrees: [
                Worktree(
                    repoId: UUID(),
                    name: "transaction-table-3", path: URL(fileURLWithPath: "/tmp/transaction-table-3")
                )
            ]
        )
        let group = SidebarRepoGroup(
            id: "remote:askluna/askluna-finance",
            repoTitle: "askluna-finance",
            organizationName: "askluna",
            repos: [repoA, repoB]
        )

        let primaryRepo = RepoSidebarContentView.primaryRepoForGroup(group)
        #expect(primaryRepo?.id == repoA.id)
    }

    @Test("primaryRepoForGroup falls back deterministically when no repo has a main-path match")
    func primaryRepoForGroupFallsBackDeterministically() {
        let repoA = SidebarRepo(
            id: UUID(),
            name: "b-repo",
            repoPath: URL(fileURLWithPath: "/tmp/b-repo"),
            stableKey: "b",
            worktrees: [Worktree(repoId: UUID(), name: "feat-b", path: URL(fileURLWithPath: "/tmp/feat-b"))]
        )
        let repoB = SidebarRepo(
            id: UUID(),
            name: "a-repo",
            repoPath: URL(fileURLWithPath: "/tmp/a-repo"),
            stableKey: "a",
            worktrees: [Worktree(repoId: UUID(), name: "feat-a", path: URL(fileURLWithPath: "/tmp/feat-a"))]
        )
        let group = SidebarRepoGroup(
            id: "remote:org/repo",
            repoTitle: "repo",
            organizationName: "org",
            repos: [repoA, repoB]
        )

        let primaryRepo = RepoSidebarContentView.primaryRepoForGroup(group)
        #expect(primaryRepo?.name == "a-repo")
    }
}
