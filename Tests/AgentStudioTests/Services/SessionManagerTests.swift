import XCTest
@testable import AgentStudio

final class SessionManagerTests: XCTestCase {

    // MARK: - Test Data

    private var worktreeA: Worktree!
    private var worktreeB: Worktree!
    private var repo: Repo!
    private var repos: [Repo]!

    override func setUp() {
        super.setUp()
        worktreeA = makeWorktree(name: "main", path: "/tmp/repo/main", branch: "main")
        worktreeB = makeWorktree(name: "feature", path: "/tmp/repo/feature", branch: "feature")
        repo = makeRepo(worktrees: [worktreeA, worktreeB])
        repos = [repo]
    }

    // MARK: - findWorktree(for:in:)

    func test_findWorktree_matchingTab_returnsWorktree() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: repo.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: repos)

        // Assert
        XCTAssertEqual(result?.id, worktreeA.id)
    }

    func test_findWorktree_wrongRepoId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: UUID())

        // Act
        let result = SessionManager.findWorktree(for: tab, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    func test_findWorktree_wrongWorktreeId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: UUID(), repoId: repo.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    func test_findWorktree_emptyRepos_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: repo.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: [])

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - findRepo(for:in:)

    func test_findRepo_matchingTab_returnsRepo() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: repo.id)

        // Act
        let result = SessionManager.findRepo(for: tab, in: repos)

        // Assert
        XCTAssertEqual(result?.id, repo.id)
    }

    func test_findRepo_wrongRepoId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, repoId: UUID())

        // Act
        let result = SessionManager.findRepo(for: tab, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - findRepo(containing:in:)

    func test_findRepoContaining_existingWorktree_returnsRepo() {
        // Act
        let result = SessionManager.findRepo(containing: worktreeA, in: repos)

        // Assert
        XCTAssertEqual(result?.id, repo.id)
    }

    func test_findRepoContaining_orphanWorktree_returnsNil() {
        // Arrange
        let orphan = makeWorktree(name: "orphan")

        // Act
        let result = SessionManager.findRepo(containing: orphan, in: repos)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - mergeWorktrees (static via instance for now)

    func test_mergeWorktrees_newDiscovered_returnedAsIs() {
        // Arrange
        let existing: [Worktree] = []
        let discovered = [makeWorktree(name: "new-feature", path: "/tmp/repo/new", branch: "new")]

        // Act
        let result = SessionManager.mergeWorktrees(existing: existing, discovered: discovered)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isOpen)
        XCTAssertNil(result[0].agent)
        XCTAssertEqual(result[0].status, .idle)
    }

    func test_mergeWorktrees_matchingPath_preservesExistingState() {
        // Arrange
        let sharedPath = "/tmp/repo/feature"
        let existing = [makeWorktree(
            name: "feature",
            path: sharedPath,
            branch: "feature",
            agent: .claude,
            status: .running,
            isOpen: true,
            lastOpened: Date(timeIntervalSince1970: 999)
        )]
        let discovered = [makeWorktree(
            name: "feature-renamed",
            path: sharedPath,
            branch: "feature-v2"
        )]

        // Act
        let result = SessionManager.mergeWorktrees(existing: existing, discovered: discovered)

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].agent, .claude)
        XCTAssertEqual(result[0].status, .running)
        XCTAssertTrue(result[0].isOpen)
        XCTAssertEqual(result[0].lastOpened, Date(timeIntervalSince1970: 999))
        XCTAssertEqual(result[0].name, "feature-renamed")
        XCTAssertEqual(result[0].branch, "feature-v2")
    }

    func test_mergeWorktrees_existingRemovedFromDisk_notInResult() {
        // Arrange
        let existing = [
            makeWorktree(name: "old", path: "/tmp/repo/old", branch: "old", isOpen: true),
        ]
        let discovered: [Worktree] = []

        // Act
        let result = SessionManager.mergeWorktrees(existing: existing, discovered: discovered)

        // Assert
        XCTAssertTrue(result.isEmpty)
    }
}
