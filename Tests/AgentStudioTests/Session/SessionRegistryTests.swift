import XCTest
@testable import AgentStudio

@MainActor
final class SessionRegistryTests: XCTestCase {
    private var registry: SessionRegistry!
    private var mockBackend: MockSessionBackend!

    override func setUp() {
        super.setUp()
        mockBackend = MockSessionBackend()
        registry = SessionRegistry.shared
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
    }

    override func tearDown() {
        registry._resetForTesting()
        super.tearDown()
    }

    // MARK: - registerPaneSession

    func test_registerPaneSession_createsEntry() {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8"

        // Act
        registry.registerPaneSession(
            id: sessionId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertNotNil(registry.entries[sessionId])
        XCTAssertEqual(registry.entries[sessionId]?.machine.state, .alive)
    }

    func test_registerPaneSession_rejectsInvalidId() {
        // Arrange
        let badId = "not-a-valid-session-id"

        // Act
        registry.registerPaneSession(
            id: badId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertNil(registry.entries[badId])
    }

    func test_registerPaneSession_rejectsUppercaseHex() {
        // Arrange — uppercase hex should be rejected
        let badId = "agentstudio--A1B2C3D4--E5F6A7B8"

        // Act
        registry.registerPaneSession(
            id: badId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertNil(registry.entries[badId])
    }

    func test_registerPaneSession_doesNotDuplicateExisting() {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8"
        registry.registerPaneSession(
            id: sessionId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "first",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Act — register again with different displayName
        registry.registerPaneSession(
            id: sessionId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "second",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert — original entry preserved
        XCTAssertEqual(registry.entries[sessionId]?.handle.displayName, "first")
    }

    // MARK: - unregisterPaneSession

    func test_unregisterPaneSession_removesEntry() {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8"
        registry.registerPaneSession(
            id: sessionId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Act
        registry.unregisterPaneSession(id: sessionId)

        // Assert
        XCTAssertNil(registry.entries[sessionId])
    }

    func test_unregisterPaneSession_noOpForUnknownId() {
        // Act — should not crash
        registry.unregisterPaneSession(id: "agentstudio--00000000--00000000")

        // Assert
        XCTAssertTrue(registry.entries.isEmpty)
    }

    // MARK: - attachCommand

    func test_attachCommand_returnsNil_withoutEntry() {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()

        // Act
        let cmd = registry.attachCommand(for: worktree, in: repo)

        // Assert
        XCTAssertNil(cmd)
    }

    func test_attachCommand_returnsCommand_forRegisteredSession() {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()
        let sessionId = TmuxBackend.sessionId(projectId: repo.id, worktreeId: worktree.id)

        registry.registerPaneSession(
            id: sessionId,
            projectId: repo.id,
            worktreeId: worktree.id,
            displayName: worktree.name,
            workingDirectory: worktree.path
        )

        // Act
        let cmd = registry.attachCommand(for: worktree, in: repo)

        // Assert
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd?.contains(sessionId) ?? false)
    }

    // MARK: - destroyAll

    func test_destroyAll_clearsAllEntries() async {
        // Arrange
        registry.registerPaneSession(
            id: "agentstudio--a1b2c3d4--e5f6a7b8",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Act
        await registry.destroyAll()

        // Assert
        XCTAssertTrue(registry.entries.isEmpty)
        XCTAssertEqual(mockBackend.destroyCalls.count, 1)
    }

    // MARK: - saveCheckpoint

    func test_saveCheckpoint_doesNotCrashWithNoEntries() {
        // Act — should not crash
        registry.saveCheckpoint()
    }

    // MARK: - PaneSessionHandle.hasValidId

    func test_hasValidId_acceptsValidFormat() {
        // Arrange
        let handle = PaneSessionHandle(
            id: "agentstudio--a1b2c3d4--e5f6a7b8",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertTrue(handle.hasValidId)
    }

    func test_hasValidId_rejectsWrongPrefix() {
        // Arrange
        let handle = PaneSessionHandle(
            id: "wrongprefix--a1b2c3d4--e5f6a7b8",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_hasValidId_rejectsNonHexChars() {
        // Arrange
        let handle = PaneSessionHandle(
            id: "agentstudio--zzzzzzzz--e5f6a7b8",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_hasValidId_rejectsTooShort() {
        // Arrange
        let handle = PaneSessionHandle(
            id: "agentstudio--abc--def",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_hasValidId_rejectsEmptyString() {
        // Arrange
        let handle = PaneSessionHandle(
            id: "",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }
}
