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
        let repo = makeRepo()

        // Act
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Assert — session should be alive
        let exists = await backend.sessionExists(handle)
        XCTAssertTrue(exists, "Session should exist after creation")
        XCTAssertTrue(handle.id.hasPrefix("agentstudio--"))
        XCTAssertEqual(handle.id.count, 65)
    }

    // MARK: - Health Check

    func test_healthCheck_trueForLiveSession() async throws {
        // Arrange
        let worktree = makeWorktree(name: "health-test", path: "/tmp", branch: "health-test")
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertTrue(alive, "Health check should return true for a live session")
    }

    // MARK: - Destroy

    func test_destroyPaneSession_removesSession() async throws {
        // Arrange
        let worktree = makeWorktree(name: "destroy-test", path: "/tmp", branch: "destroy-test")
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

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
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

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
        let repo = makeRepo()

        let handle1 = try await backend.createPaneSession(repo: repo, worktree: worktree1, paneId: UUID())
        let handle2 = try await backend.createPaneSession(repo: repo, worktree: worktree2, paneId: UUID())

        // Act — exclude handle1, so handle2 should appear as orphan
        let orphans = await backend.discoverOrphanSessions(excluding: [handle1.id])

        // Assert
        XCTAssertTrue(orphans.contains(handle2.id), "Untracked session should be discovered as orphan")
        XCTAssertFalse(orphans.contains(handle1.id), "Tracked session should be excluded")
    }

    // MARK: - Session Survival (regression: tmux sessions must persist after client disconnect)

    func test_detachedSession_survivesWithDestroyUnattachedOff() async throws {
        // This is the core session persistence guarantee: a detached tmux session
        // must remain alive (ghost.conf sets `destroy-unattached off`).
        // Regression: if ghost.conf is not loaded or settings are wrong,
        // sessions die when the last client detaches (i.e., when the app quits).

        // Arrange — create a detached session (no client attached)
        let worktree = makeWorktree(name: "survival-detach", path: "/tmp", branch: "survival-detach")
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Sanity — session exists right after creation
        let existsAfterCreate = await backend.sessionExists(handle)
        XCTAssertTrue(existsAfterCreate, "Session should exist right after creation")

        // Act — wait a beat (detached session with no client should survive)
        try await Task.sleep(for: .seconds(2))

        // Assert — session still alive
        let existsAfterWait = await backend.sessionExists(handle)
        XCTAssertTrue(existsAfterWait, "Detached session must survive — destroy-unattached off should be in effect")
    }

    func test_ghostConfig_loadedByServer_destroyUnattachedOff() async throws {
        // Verify that the test tmux server actually loaded ghost.conf by querying
        // the server's destroy-unattached option. If this is "on", sessions will
        // die when clients disconnect (breaking session persistence).

        // Arrange — create a session to start the server
        let worktree = makeWorktree(name: "config-check", path: "/tmp", branch: "config-check")
        let repo = makeRepo()
        _ = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Act — query the server's global options
        let executor = DefaultProcessExecutor()
        let result = try await executor.execute(
            command: "tmux",
            args: ["-L", harness.socketName, "show-options", "-g"],
            cwd: nil,
            environment: nil
        )

        // Assert
        XCTAssertTrue(result.succeeded, "show-options should succeed")
        XCTAssertTrue(
            result.stdout.contains("destroy-unattached off"),
            "tmux server must have destroy-unattached off for session persistence. "
            + "Got options: \(result.stdout)"
        )
    }

    func test_configPath_inTmuxCommand_doesNotContainAgentStudio() async throws {
        // Regression: the ghost.conf path passed via -f to tmux ends up in the
        // server's command line. If it contains "AgentStudio" (mixed case),
        // `pkill -f "AgentStudio"` will kill the tmux server along with the app.

        // Arrange
        let config = SessionConfiguration.detect()

        // Assert — the config path should not contain "AgentStudio"
        XCTAssertFalse(
            config.ghostConfigPath.contains("AgentStudio"),
            "ghostConfigPath must not contain 'AgentStudio' — this would cause "
            + "pkill -f 'AgentStudio' to kill the tmux server. "
            + "Got: \(config.ghostConfigPath)"
        )
    }

    func test_tmuxBinaryPath_resolved() {
        // Regression: hardcoding "tmux" in the command breaks on macOS GUI apps
        // where PATH doesn't include /opt/homebrew/bin.

        // Act
        let config = SessionConfiguration.detect()

        // Assert — tmuxPath should be resolved to an absolute path
        XCTAssertNotNil(config.tmuxPath, "tmuxPath should be resolved (tmux is installed)")
        if let path = config.tmuxPath {
            XCTAssertTrue(
                path.hasPrefix("/"),
                "tmuxPath should be an absolute path, got: \(path)"
            )
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: path),
                "tmuxPath should point to an executable, got: \(path)"
            )
        }
    }
}
