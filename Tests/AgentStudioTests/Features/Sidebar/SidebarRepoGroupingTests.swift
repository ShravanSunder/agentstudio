import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct SidebarRepoGroupingTests {

    @Test("T1: Duplicate checkout path collapses to one row and prefers larger family")
    func duplicateCheckoutPath_prefersRepoWithMoreWorktrees() {
        let sharedPath = "/tmp/acme/feature-x"

        let ownerRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "acme-main",
            repoPath: "/tmp/acme/main",
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                    name: "main",
                    path: "/tmp/acme/main",
                    branch: "main",
                    isMainWorktree: true
                ),
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                    name: "feature-x",
                    path: sharedPath,
                    branch: "feature-x"
                ),
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                    name: "hotfix",
                    path: "/tmp/acme/hotfix",
                    branch: "hotfix"
                ),
            ]
        )

        let duplicateRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            name: "acme-feature-x-standalone",
            repoPath: sharedPath,
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
                    name: "feature-x",
                    path: sharedPath,
                    branch: "feature-x"
                )
            ]
        )

        let repos = [ownerRepo, duplicateRepo]
        let groups = SidebarRepoGrouping.buildGroups(
            repos: repos,
            metadataByRepoId: SidebarRepoGroupingMocks.metadata(for: repos)
        )

        #expect(groups.count == 1)
        #expect(groups[0].repos.count == 1)
        #expect(groups[0].repos[0].id == ownerRepo.id)

        let normalizedPaths = SidebarRepoGroupingMocks.normalizedWorktreePaths(in: groups[0])
        #expect(Set(normalizedPaths).count == 3)
        #expect(normalizedPaths.filter { $0 == URL(fileURLWithPath: sharedPath).standardizedFileURL.path }.count == 1)
    }

    @Test("T2: Tie-break prefers repo whose repoPath matches checkout path")
    func duplicateCheckoutPath_tiePrefersRepoPathMatch() {
        let sharedPath = "/tmp/team/feature-y"

        let repoA = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            name: "team-base",
            repoPath: "/tmp/team/base",
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000211")!,
                    name: "feature-y",
                    path: sharedPath,
                    branch: "feature-y"
                )
            ]
        )

        let repoB = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000112")!,
            name: "feature-y-standalone",
            repoPath: sharedPath,
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000212")!,
                    name: "feature-y",
                    path: sharedPath,
                    branch: "feature-y"
                )
            ]
        )

        let repos = [repoA, repoB]
        let groups = SidebarRepoGrouping.buildGroups(
            repos: repos,
            metadataByRepoId: SidebarRepoGroupingMocks.metadata(for: repos)
        )

        #expect(groups.count == 1)
        #expect(groups[0].repos.count == 1)
        #expect(groups[0].repos[0].id == repoB.id)
    }

    @Test("T3: Path normalization dedupes equivalent CWD values")
    func equivalentPaths_areDedupedAfterNormalization() {
        let canonical = "/tmp/normalize/worktree-a"
        let variant = "/tmp/normalize/./worktree-a/"

        let repoA = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000121")!,
            name: "normalize-a",
            repoPath: "/tmp/normalize/a",
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000221")!,
                    name: "worktree-a",
                    path: canonical,
                    branch: "worktree-a"
                )
            ]
        )

        let repoB = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000122")!,
            name: "normalize-b",
            repoPath: canonical,
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000222")!,
                    name: "worktree-a",
                    path: variant,
                    branch: "worktree-a"
                )
            ]
        )

        let repos = [repoA, repoB]
        let groups = SidebarRepoGrouping.buildGroups(
            repos: repos,
            metadataByRepoId: SidebarRepoGroupingMocks.metadata(for: repos)
        )

        let paths = SidebarRepoGroupingMocks.normalizedWorktreePaths(in: groups[0])
        #expect(groups[0].repos.count == 1)
        #expect(Set(paths).count == 1)
    }

    @Test("T4: Empty repos are omitted from group projection")
    func emptyRepos_areNotProjected() {
        let emptyRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000131")!,
            name: "empty-repo",
            repoPath: "/tmp/empty-repo",
            worktrees: []
        )

        let activeRepo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000132")!,
            name: "active-repo",
            repoPath: "/tmp/active-repo",
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000231")!,
                    name: "main",
                    path: "/tmp/active-repo",
                    branch: "main",
                    isMainWorktree: true
                )
            ]
        )

        let repos = [emptyRepo, activeRepo]
        let groups = SidebarRepoGrouping.buildGroups(
            repos: repos,
            metadataByRepoId: SidebarRepoGroupingMocks.metadata(for: repos)
        )

        #expect(groups.count == 1)
        #expect(groups[0].repos.count == 1)
        #expect(groups[0].repos[0].id == activeRepo.id)
    }

    @Test("T5: Checkout count equals number of rendered checkout rows")
    func checkoutCount_matchesProjectedWorktreeRows() {
        let repo = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000141")!,
            name: "count-repo",
            repoPath: "/tmp/count-repo",
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000241")!,
                    name: "main",
                    path: "/tmp/count-repo",
                    branch: "main",
                    isMainWorktree: true
                ),
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000242")!,
                    name: "feature-z",
                    path: "/tmp/count-repo-feature-z",
                    branch: "feature-z"
                ),
            ]
        )

        let groups = SidebarRepoGrouping.buildGroups(
            repos: [repo],
            metadataByRepoId: SidebarRepoGroupingMocks.metadata(for: [repo])
        )

        let renderedRows = groups[0].repos.flatMap(\.worktrees).count
        #expect(groups[0].checkoutCount == renderedRows)
        #expect(groups[0].checkoutCount == 2)
    }

    @Test("T6: Distinct checkout paths are preserved")
    func distinctCheckoutPaths_arePreserved() {
        let repoA = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000151")!,
            name: "repo-a",
            repoPath: "/tmp/repo-a",
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000251")!,
                    name: "a-main",
                    path: "/tmp/repo-a",
                    branch: "main",
                    isMainWorktree: true
                )
            ]
        )

        let repoB = makeRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000152")!,
            name: "repo-b",
            repoPath: "/tmp/repo-b",
            worktrees: [
                makeWorktree(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000252")!,
                    name: "b-main",
                    path: "/tmp/repo-b",
                    branch: "main",
                    isMainWorktree: true
                )
            ]
        )

        let repos = [repoA, repoB]
        let groups = SidebarRepoGrouping.buildGroups(
            repos: repos,
            metadataByRepoId: SidebarRepoGroupingMocks.metadata(for: repos)
        )

        let paths = Set(SidebarRepoGroupingMocks.normalizedWorktreePaths(in: groups[0]))
        #expect(paths.count == 2)
        #expect(paths.contains(URL(fileURLWithPath: "/tmp/repo-a").standardizedFileURL.path))
        #expect(paths.contains(URL(fileURLWithPath: "/tmp/repo-b").standardizedFileURL.path))
    }
}
