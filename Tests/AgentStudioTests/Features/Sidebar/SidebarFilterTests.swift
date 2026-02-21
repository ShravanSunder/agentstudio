import Testing
import Foundation

@testable import AgentStudio

/// Tests for SidebarFilter — the extracted filter algorithm
/// used by SidebarContentView for sidebar search.
@Suite(.serialized)
struct SidebarFilterTests {

    // MARK: - Empty Query

    @Test
    func test_filter_emptyQuery_returnsAllRepos() {
        // Arrange
        let repos = [
            makeRepo(name: "alpha", worktrees: [makeWorktree(name: "main")]),
            makeRepo(name: "beta", worktrees: [makeWorktree(name: "develop")]),
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "")

        // Assert
        #expect(result.count == 2)
    }

    // MARK: - Repo Name Match

    @Test
    func test_filter_repoNameMatch_returnsAllWorktrees() {
        // Arrange
        let repos = [
            makeRepo(
                name: "my-project",
                worktrees: [
                    makeWorktree(name: "main"),
                    makeWorktree(name: "feature-x"),
                    makeWorktree(name: "bugfix-y"),
                ]),
            makeRepo(
                name: "other-repo",
                worktrees: [
                    makeWorktree(name: "main")
                ]),
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "my-project")

        // Assert
        #expect(result.count == 1)
        #expect(result[0].name == "my-project")
        #expect(result[0].worktrees.count == 3)
    }

    @Test
    func test_filter_repoNameMatch_caseInsensitive() {
        // Arrange
        let repos = [
            makeRepo(name: "AgentStudio", worktrees: [makeWorktree(name: "main")])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "agentstudio")

        // Assert
        #expect(result.count == 1)
        #expect(result[0].name == "AgentStudio")
    }

    // MARK: - Worktree Name Match

    @Test
    func test_filter_worktreeNameMatch_returnsOnlyMatchingWorktrees() {
        // Arrange
        let repos = [
            makeRepo(
                name: "my-repo",
                worktrees: [
                    makeWorktree(name: "main"),
                    makeWorktree(name: "feature-auth"),
                    makeWorktree(name: "feature-payment"),
                ])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "auth")

        // Assert
        #expect(result.count == 1)
        #expect(result[0].worktrees.count == 1)
        #expect(result[0].worktrees[0].name == "feature-auth")
    }

    @Test
    func test_filter_worktreeNameMatch_caseInsensitive() {
        // Arrange
        let repos = [
            makeRepo(
                name: "repo",
                worktrees: [
                    makeWorktree(name: "Feature-Auth")
                ])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "feature-auth")

        // Assert
        #expect(result.count == 1)
        #expect(result[0].worktrees[0].name == "Feature-Auth")
    }

    @Test
    func test_filter_multipleWorktreesMatch_returnsAllMatching() {
        // Arrange
        let repos = [
            makeRepo(
                name: "repo",
                worktrees: [
                    makeWorktree(name: "feature-login"),
                    makeWorktree(name: "feature-logout"),
                    makeWorktree(name: "bugfix-crash"),
                ])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "feature")

        // Assert
        #expect(result.count == 1)
        #expect(result[0].worktrees.count == 2)
    }

    // MARK: - No Match

    @Test
    func test_filter_noMatch_returnsEmpty() {
        // Arrange
        let repos = [
            makeRepo(name: "alpha", worktrees: [makeWorktree(name: "main")]),
            makeRepo(name: "beta", worktrees: [makeWorktree(name: "develop")]),
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "zzz-nonexistent")

        // Assert
        #expect(result.isEmpty)
    }

    // MARK: - Mixed Matches Across Repos

    @Test
    func test_filter_mixedMatches_repoAndWorktree() {
        // Arrange
        let repos = [
            makeRepo(
                name: "auth-service",
                worktrees: [
                    makeWorktree(name: "main"),
                    makeWorktree(name: "develop"),
                ]),
            makeRepo(
                name: "payment-service",
                worktrees: [
                    makeWorktree(name: "auth-migration"),
                    makeWorktree(name: "main"),
                ]),
            makeRepo(
                name: "frontend",
                worktrees: [
                    makeWorktree(name: "main")
                ]),
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "auth")

        // Assert
        #expect(result.count == 2)

        // auth-service: repo name matches → all worktrees
        let authService = result.first { $0.name == "auth-service" }
        #expect(authService != nil)
        #expect(authService?.worktrees.count == 2)

        // payment-service: worktree matches → only matching
        let paymentService = result.first { $0.name == "payment-service" }
        #expect(paymentService != nil)
        #expect(paymentService?.worktrees.count == 1)
        #expect(paymentService?.worktrees[0].name == "auth-migration")
    }

    // MARK: - Substring Match

    @Test
    func test_filter_substringMatch_works() {
        // Arrange
        let repos = [
            makeRepo(name: "my-cool-repo", worktrees: [makeWorktree(name: "main")])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "cool")

        // Assert
        #expect(result.count == 1)
    }

    // MARK: - Empty Repos

    @Test
    func test_filter_emptyRepoList_returnsEmpty() {
        // Act
        let result = SidebarFilter.filter(repos: [], query: "anything")

        // Assert
        #expect(result.isEmpty)
    }

    @Test
    func test_filter_repoWithNoWorktrees_noMatch() {
        // Arrange
        let repos = [
            makeRepo(name: "empty-repo", worktrees: [])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "feature")

        // Assert
        #expect(result.isEmpty)
    }

    @Test
    func test_filter_repoWithNoWorktrees_repoNameMatch() {
        // Arrange
        let repos = [
            makeRepo(name: "empty-repo", worktrees: [])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "empty")

        // Assert
        #expect(result.count == 1)
    }
}
