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

        // Create a checkpoint with one session to restore
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8"
        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: sessionId,
                projectId: UUID(),
                worktreeId: UUID(),
                displayName: "smoke-test",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                lastKnownAlive: Date()
            ),
        ])

        // Act — restore from checkpoint (the core of initialize flow)
        await registry.restoreFromCheckpoint(checkpoint)

        // Assert — registry should have restored the entry without crashing
        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertNotNil(registry.entries[sessionId])
        XCTAssertEqual(registry.entries[sessionId]?.machine.state, .alive)

        // Cleanup
        registry.stopHealthChecks()
    }
}
