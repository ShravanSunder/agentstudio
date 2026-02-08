import XCTest
@testable import AgentStudio

/// Integration tests that exercise TmuxBackend against a real tmux binary.
/// Each test uses an isolated socket via TmuxTestHarness to prevent cross-test interference.
///
/// Requires tmux to be installed (homebrew or system).
final class TmuxBackendIntegrationTests: XCTestCase {
    private var harness: TmuxTestHarness!
    private var backend: TmuxBackend!

    override func setUp() async throws {
        try await super.setUp()
        harness = TmuxTestHarness()
        backend = harness.createBackend()

        // Skip if tmux is not available
        guard await backend.isAvailable else {
            throw XCTSkip("tmux not available on this system")
        }
    }

    override func tearDown() async throws {
        await harness.cleanup()
        try await super.tearDown()
    }

    // MARK: - Create + Verify

    func test_createSession_thenSessionExists() async throws {
        // Arrange
        let worktree = makeWorktree(
            name: "integ-test",
            path: "/tmp",
            branch: "integ-test"
        )
        let projectId = UUID()

        // Act
        let handle = try await backend.createPaneSession(projectId: projectId, worktree: worktree)

        // Assert — session should be alive
        let exists = await backend.sessionExists(handle)
        XCTAssertTrue(exists, "Session should exist after creation")
        XCTAssertTrue(handle.id.hasPrefix("agentstudio--"))
    }

    // MARK: - Health Check

    func test_healthCheck_trueForLiveSession() async throws {
        // Arrange
        let worktree = makeWorktree(name: "health-test", path: "/tmp", branch: "health-test")
        let handle = try await backend.createPaneSession(projectId: UUID(), worktree: worktree)

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertTrue(alive, "Health check should return true for a live session")
    }

    // MARK: - Destroy

    func test_destroyPaneSession_removesSession() async throws {
        // Arrange
        let worktree = makeWorktree(name: "destroy-test", path: "/tmp", branch: "destroy-test")
        let handle = try await backend.createPaneSession(projectId: UUID(), worktree: worktree)

        // Sanity — session exists before destroy
        let beforeDestroy = await backend.sessionExists(handle)
        XCTAssertTrue(beforeDestroy)

        // Act
        try await backend.destroyPaneSession(handle)

        // Assert
        let afterDestroy = await backend.sessionExists(handle)
        XCTAssertFalse(afterDestroy, "Session should not exist after destroy")
    }

    func test_destroySessionById_removesSession() async throws {
        // Arrange
        let worktree = makeWorktree(name: "destroy-id-test", path: "/tmp", branch: "destroy-id-test")
        let handle = try await backend.createPaneSession(projectId: UUID(), worktree: worktree)

        // Act
        try await backend.destroySessionById(handle.id)

        // Assert
        let exists = await backend.sessionExists(handle)
        XCTAssertFalse(exists, "Session should not exist after destroySessionById")
    }

    // MARK: - Orphan Discovery

    func test_discoverOrphanSessions_findsUntracked() async throws {
        // Arrange — create two sessions
        let worktree1 = makeWorktree(name: "orphan-tracked", path: "/tmp", branch: "orphan-tracked")
        let worktree2 = makeWorktree(name: "orphan-untracked", path: "/tmp", branch: "orphan-untracked")

        let handle1 = try await backend.createPaneSession(projectId: UUID(), worktree: worktree1)
        let handle2 = try await backend.createPaneSession(projectId: UUID(), worktree: worktree2)

        // Act — exclude handle1, so handle2 should appear as orphan
        let orphans = await backend.discoverOrphanSessions(excluding: [handle1.id])

        // Assert
        XCTAssertTrue(orphans.contains(handle2.id), "Untracked session should be discovered as orphan")
        XCTAssertFalse(orphans.contains(handle1.id), "Tracked session should be excluded")
    }
}
