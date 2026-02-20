import XCTest

@testable import AgentStudio

/// Tests for SidebarFilter — the extracted filter algorithm
/// used by SidebarContentView for sidebar search.
final class SidebarFilterTests: XCTestCase {

    // MARK: - Empty Query

    func test_filter_emptyQuery_returnsAllRepos() {
        // Arrange
        let repos = [
            makeRepo(name: "alpha", worktrees: [makeWorktree(name: "main")]),
            makeRepo(name: "beta", worktrees: [makeWorktree(name: "develop")]),
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "")

        // Assert
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Repo Name Match

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
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "my-project")
        XCTAssertEqual(result[0].worktrees.count, 3, "All worktrees should be included when repo name matches")
    }

    func test_filter_repoNameMatch_caseInsensitive() {
        // Arrange
        let repos = [
            makeRepo(name: "AgentStudio", worktrees: [makeWorktree(name: "main")])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "agentstudio")

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "AgentStudio")
    }

    // MARK: - Worktree Name Match

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
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].worktrees.count, 1, "Only matching worktrees should appear")
        XCTAssertEqual(result[0].worktrees[0].name, "feature-auth")
    }

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
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].worktrees[0].name, "Feature-Auth")
    }

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
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].worktrees.count, 2)
    }

    // MARK: - No Match

    func test_filter_noMatch_returnsEmpty() {
        // Arrange
        let repos = [
            makeRepo(name: "alpha", worktrees: [makeWorktree(name: "main")]),
            makeRepo(name: "beta", worktrees: [makeWorktree(name: "develop")]),
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "zzz-nonexistent")

        // Assert
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Mixed Matches Across Repos

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
        XCTAssertEqual(result.count, 2)

        // auth-service: repo name matches → all worktrees
        let authService = result.first { $0.name == "auth-service" }
        XCTAssertNotNil(authService)
        XCTAssertEqual(authService?.worktrees.count, 2)

        // payment-service: worktree matches → only matching
        let paymentService = result.first { $0.name == "payment-service" }
        XCTAssertNotNil(paymentService)
        XCTAssertEqual(paymentService?.worktrees.count, 1)
        XCTAssertEqual(paymentService?.worktrees[0].name, "auth-migration")
    }

    // MARK: - Substring Match

    func test_filter_substringMatch_works() {
        // Arrange
        let repos = [
            makeRepo(name: "my-cool-repo", worktrees: [makeWorktree(name: "main")])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "cool")

        // Assert
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Empty Repos

    func test_filter_emptyRepoList_returnsEmpty() {
        // Act
        let result = SidebarFilter.filter(repos: [], query: "anything")

        // Assert
        XCTAssertTrue(result.isEmpty)
    }

    func test_filter_repoWithNoWorktrees_noMatch() {
        // Arrange
        let repos = [
            makeRepo(name: "empty-repo", worktrees: [])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "feature")

        // Assert
        XCTAssertTrue(result.isEmpty, "Repo with no worktrees should not match on worktree query")
    }

    func test_filter_repoWithNoWorktrees_repoNameMatch() {
        // Arrange
        let repos = [
            makeRepo(name: "empty-repo", worktrees: [])
        ]

        // Act
        let result = SidebarFilter.filter(repos: repos, query: "empty")

        // Assert
        XCTAssertEqual(result.count, 1, "Repo should match on name even with no worktrees")
    }
}
