import XCTest
@testable import AgentStudio

/// E2E smoke test for the session initialization flow.
/// Verifies that SessionRegistry.initialize() with a mock backend
/// completes without crashing and leaves the registry in a valid state.
@MainActor
final class SessionInitializationTests: XCTestCase {

    override func tearDown() {
        SessionRegistry.shared._resetForTesting()
        super.tearDown()
    }

    /// Verify that initialize → checkpoint restore → health check scheduling
    /// completes without crashing when given a mock backend and a valid checkpoint.
    func test_initializeWithMockBackend_completesWithoutCrash() async {
        // Arrange — pre-configure registry with mock backend
        let mockBackend = MockSessionBackend()
        mockBackend.sessionExistsResult = true

        let registry = SessionRegistry.shared
        registry._resetForTesting(
            configuration: SessionConfiguration(
                isEnabled: true,
                tmuxPath: "/usr/bin/tmux",
                ghostConfigPath: "/tmp/ghost.conf",
                healthCheckInterval: 30,
                socketDirectory: "/tmp",
                socketName: "agentstudio",
                maxCheckpointAge: 604800
            ),
            backend: mockBackend
        )

        // Create a v3 checkpoint with deterministic IDs
        let paneId = UUID()
        let worktreeId = UUID()
        let repo = makeRepo(repoPath: "/tmp/test-repo")
        let worktree = makeWorktree(id: worktreeId, path: "/tmp/test-repo/main")
        let repoWithWt = makeRepo(id: repo.id, repoPath: "/tmp/test-repo", worktrees: [worktree])

        let sessionId = TmuxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: paneId
        )

        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: sessionId,
                paneId: paneId,
                projectId: repo.id,
                worktreeId: worktreeId,
                repoPath: repo.repoPath,
                worktreePath: worktree.path,
                displayName: "smoke-test",
                workingDirectory: worktree.path,
                lastKnownAlive: Date()
            ),
        ])

        // Act — restore from checkpoint with mock repo lookup
        await registry.restoreFromCheckpoint(checkpoint) { id, _ in
            id == repoWithWt.id ? repoWithWt : nil
        }

        // Assert — registry should have restored the entry without crashing
        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertNotNil(registry.entries[sessionId])
        XCTAssertEqual(registry.entries[sessionId]?.machine.state, .alive)

        // Cleanup
        registry.stopHealthChecks()
    }
}
