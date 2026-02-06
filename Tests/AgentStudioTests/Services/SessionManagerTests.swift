import XCTest
@testable import AgentStudio

final class SessionManagerTests: XCTestCase {

    // MARK: - Test Data

    private var worktreeA: Worktree!
    private var worktreeB: Worktree!
    private var project: Project!
    private var projects: [Project]!

    override func setUp() {
        super.setUp()
        worktreeA = makeWorktree(name: "main", path: "/tmp/repo/main", branch: "main")
        worktreeB = makeWorktree(name: "feature", path: "/tmp/repo/feature", branch: "feature")
        project = makeProject(worktrees: [worktreeA, worktreeB])
        projects = [project]
    }

    // MARK: - findWorktree(for:in:)

    func test_findWorktree_matchingTab_returnsWorktree() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, projectId: project.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: projects)

        // Assert
        XCTAssertEqual(result?.id, worktreeA.id)
    }

    func test_findWorktree_wrongProjectId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, projectId: UUID())

        // Act
        let result = SessionManager.findWorktree(for: tab, in: projects)

        // Assert
        XCTAssertNil(result)
    }

    func test_findWorktree_wrongWorktreeId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: UUID(), projectId: project.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: projects)

        // Assert
        XCTAssertNil(result)
    }

    func test_findWorktree_emptyProjects_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, projectId: project.id)

        // Act
        let result = SessionManager.findWorktree(for: tab, in: [])

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - findProject(for:in:)

    func test_findProject_matchingTab_returnsProject() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, projectId: project.id)

        // Act
        let result = SessionManager.findProject(for: tab, in: projects)

        // Assert
        XCTAssertEqual(result?.id, project.id)
    }

    func test_findProject_wrongProjectId_returnsNil() {
        // Arrange
        let tab = makeOpenTab(worktreeId: worktreeA.id, projectId: UUID())

        // Act
        let result = SessionManager.findProject(for: tab, in: projects)

        // Assert
        XCTAssertNil(result)
    }

    // MARK: - findProject(containing:in:)

    func test_findProjectContaining_existingWorktree_returnsProject() {
        // Act
        let result = SessionManager.findProject(containing: worktreeA, in: projects)

        // Assert
        XCTAssertEqual(result?.id, project.id)
    }

    func test_findProjectContaining_orphanWorktree_returnsNil() {
        // Arrange
        let orphan = makeWorktree(name: "orphan")

        // Act
        let result = SessionManager.findProject(containing: orphan, in: projects)

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
