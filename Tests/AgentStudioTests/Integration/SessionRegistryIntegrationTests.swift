import XCTest
@testable import AgentStudio

/// Integration tests that exercise SessionRegistry with a real TmuxBackend.
/// Uses an isolated socket via TmuxTestHarness to prevent cross-test interference.
@MainActor
final class SessionRegistryIntegrationTests: XCTestCase {
    private var harness: TmuxTestHarness!
    private var registry: SessionRegistry!
    private var backend: TmuxBackend!

    override func setUp() async throws {
        try await super.setUp()
        harness = TmuxTestHarness()
        backend = harness.createBackend()

        // Skip if tmux is not available
        guard await backend.isAvailable else {
            throw XCTSkip("tmux not available on this system")
        }

        registry = SessionRegistry.shared
        registry._resetForTesting(
            configuration: SessionConfiguration(
                isEnabled: true,
                tmuxPath: "/opt/homebrew/bin/tmux",
                ghostConfigPath: harness.ghostConfigPath,
                healthCheckInterval: 30,
                socketDirectory: "/tmp",
                socketName: harness.socketName,
                maxCheckpointAge: 604800
            ),
            backend: backend
        )
    }

    override func tearDown() async throws {
        await registry.destroyAll()
        registry._resetForTesting()
        await harness.cleanup()
        try await super.tearDown()
    }

    // MARK: - Full Lifecycle

    func test_getOrCreate_createsUsableSession() async throws {
        // Arrange
        let worktree = makeWorktree(name: "integ-lifecycle", path: "/tmp", branch: "integ-lifecycle")
        let repo = makeRepo()

        // Act
        let entry = try await registry.getOrCreatePaneSession(for: worktree, in: repo)

        // Assert — entry exists and session is alive in tmux
        XCTAssertEqual(entry.machine.state, .alive)
        XCTAssertNotNil(registry.entries[entry.handle.id])

        let alive = await backend.healthCheck(entry.handle)
        XCTAssertTrue(alive, "Backend should confirm session is alive")
    }

    // MARK: - Attach Command

    func test_registerAndAttach_producesValidCommand() async throws {
        // Arrange
        let worktree = makeWorktree(name: "integ-attach", path: "/tmp", branch: "integ-attach")
        let repo = makeRepo()

        // Create session so it exists in tmux
        let entry = try await registry.getOrCreatePaneSession(for: worktree, in: repo)

        // Act
        let cmd = registry.attachCommand(for: worktree, in: repo)

        // Assert
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd?.contains("new-session") ?? false, "Attach command should use new-session")
        XCTAssertTrue(cmd?.contains("-A") ?? false, "Attach command should use -A flag")
        XCTAssertTrue(cmd?.contains(entry.handle.id) ?? false, "Attach command should reference session ID")
        XCTAssertTrue(cmd?.contains(harness.socketName) ?? false, "Attach command should use test socket")
    }
}
