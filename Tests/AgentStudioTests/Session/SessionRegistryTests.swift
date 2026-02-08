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
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"

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
        let badId = "agentstudio--A1B2C3D4--E5F6A7B8--00001111"

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
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"
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
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"
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
        registry.unregisterPaneSession(id: "agentstudio--00000000--00000000--44444444")

        // Assert
        XCTAssertTrue(registry.entries.isEmpty)
    }

    // MARK: - attachCommand

    func test_attachCommand_returnsNil_withoutEntry() {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()

        // Act
        let cmd = registry.attachCommand(for: worktree, in: repo, paneId: UUID())

        // Assert
        XCTAssertNil(cmd)
    }

    func test_attachCommand_returnsCommand_forRegisteredSession() {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()
        let paneId = UUID()
        let sessionId = TmuxBackend.sessionId(projectId: repo.id, worktreeId: worktree.id, paneId: paneId)

        registry.registerPaneSession(
            id: sessionId,
            projectId: repo.id,
            worktreeId: worktree.id,
            displayName: worktree.name,
            workingDirectory: worktree.path
        )

        // Act
        let cmd = registry.attachCommand(for: worktree, in: repo, paneId: paneId)

        // Assert
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd?.contains(sessionId) ?? false)
    }

    // MARK: - destroyAll

    func test_destroyAll_clearsAllEntries() async {
        // Arrange
        registry.registerPaneSession(
            id: "agentstudio--a1b2c3d4--e5f6a7b8--00001111",
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
            id: "agentstudio--a1b2c3d4--e5f6a7b8--00001111",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Assert
        XCTAssertTrue(handle.hasValidId)
    }

    func test_hasValidId_acceptsLegacy2SegmentFormat() {
        // Arrange — 2-segment (31-char) legacy format should still be accepted
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

    // MARK: - getOrCreatePaneSession

    func test_getOrCreatePaneSession_returnsExistingAliveEntry() async throws {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()
        let paneId = UUID()
        let sessionId = TmuxBackend.sessionId(projectId: repo.id, worktreeId: worktree.id, paneId: paneId)

        registry.registerPaneSession(
            id: sessionId,
            projectId: repo.id,
            worktreeId: worktree.id,
            displayName: worktree.name,
            workingDirectory: worktree.path
        )

        // Act
        let entry = try await registry.getOrCreatePaneSession(for: worktree, in: repo, paneId: paneId)

        // Assert — should return existing, not create new
        XCTAssertEqual(entry.handle.id, sessionId)
        XCTAssertTrue(mockBackend.createCalls.isEmpty, "Should not call backend.create for existing alive entry")
    }

    func test_getOrCreatePaneSession_throwsWhenNoBackend() async {
        // Arrange — reset with nil backend
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
            backend: nil
        )

        let worktree = makeWorktree()
        let repo = makeRepo()

        // Act & Assert
        do {
            _ = try await registry.getOrCreatePaneSession(for: worktree, in: repo, paneId: UUID())
            XCTFail("Expected SessionBackendError.notAvailable")
        } catch let error as SessionBackendError {
            if case .notAvailable = error {
                // Expected
            } else {
                XCTFail("Expected .notAvailable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_getOrCreatePaneSession_createsViaBackend() async throws {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()
        let paneId = UUID()
        let expectedId = TmuxBackend.sessionId(projectId: repo.id, worktreeId: worktree.id, paneId: paneId)
        let handle = PaneSessionHandle(
            id: expectedId,
            projectId: repo.id,
            worktreeId: worktree.id,
            displayName: worktree.name,
            workingDirectory: worktree.path
        )
        mockBackend.createResult = .success(handle)

        // Act
        let entry = try await registry.getOrCreatePaneSession(for: worktree, in: repo, paneId: paneId)

        // Assert
        XCTAssertEqual(entry.handle.id, expectedId)
        XCTAssertEqual(mockBackend.createCalls.count, 1)
        XCTAssertNotNil(registry.entries[expectedId])
    }

    // MARK: - destroyAll Error Handling

    func test_destroyAll_continuesOnPerSessionFailure() async {
        // Arrange — register two sessions, mock throws on destroy
        registry.registerPaneSession(
            id: "agentstudio--a1b2c3d4--e5f6a7b8--00001111",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "first",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        registry.registerPaneSession(
            id: "agentstudio--11111111--22222222--33333333",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "second",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        mockBackend.throwOnDestroy = true

        // Act — should not crash despite backend throwing
        await registry.destroyAll()

        // Assert — entries should be cleared regardless
        XCTAssertTrue(registry.entries.isEmpty)
        XCTAssertEqual(mockBackend.destroyCalls.count, 2)
    }

    // MARK: - saveCheckpoint Round-Trip

    func test_saveCheckpoint_roundTripsEntries() {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"
        let projectId = UUID()
        let worktreeId = UUID()

        registry.registerPaneSession(
            id: sessionId,
            projectId: projectId,
            worktreeId: worktreeId,
            displayName: "test-roundtrip",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Act
        registry.saveCheckpoint()

        // Assert — load checkpoint and verify contents
        let loaded = SessionCheckpoint.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessions.count, 1)
        XCTAssertEqual(loaded?.sessions.first?.sessionId, sessionId)
        XCTAssertEqual(loaded?.sessions.first?.displayName, "test-roundtrip")
    }

    // MARK: - Restore from Checkpoint (via initialize)

    func test_restoreFromCheckpoint_populatesAliveEntries() async {
        // Arrange — create a checkpoint with one session
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"
        let projectId = UUID()
        let worktreeId = UUID()
        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: sessionId,
                projectId: projectId,
                worktreeId: worktreeId,
                displayName: "surviving",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                lastKnownAlive: Date()
            ),
        ])

        // Mock: session is alive in tmux
        mockBackend.sessionExistsResult = true

        // Act
        await registry.restoreFromCheckpoint(checkpoint)

        // Assert
        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertNotNil(registry.entries[sessionId])
        XCTAssertEqual(registry.entries[sessionId]?.machine.state, .alive)
    }

    func test_restoreFromCheckpoint_skipsDeadSessions() async {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"
        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: sessionId,
                projectId: UUID(),
                worktreeId: UUID(),
                displayName: "dead-session",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                lastKnownAlive: Date()
            ),
        ])

        // Mock: session is NOT alive in tmux
        mockBackend.sessionExistsResult = false

        // Act
        await registry.restoreFromCheckpoint(checkpoint)

        // Assert — dead session should not be restored
        XCTAssertTrue(registry.entries.isEmpty)
    }

    func test_restoreFromCheckpoint_destroysLegacy2SegmentSessions() async {
        // Arrange — legacy 2-segment ID (31 chars) should be destroyed, not restored
        let legacyId = "agentstudio--a1b2c3d4--e5f6a7b8"
        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: legacyId,
                projectId: UUID(),
                worktreeId: UUID(),
                displayName: "legacy-session",
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                lastKnownAlive: Date()
            ),
        ])

        mockBackend.sessionExistsResult = true

        // Act
        await registry.restoreFromCheckpoint(checkpoint)

        // Assert — legacy session destroyed, not restored
        XCTAssertTrue(registry.entries.isEmpty, "Legacy session should not be restored")
        XCTAssertEqual(mockBackend.destroyByIdCalls, [legacyId], "Legacy session should be destroyed")
    }

    // MARK: - Effect Handler: Recovery

    func test_effectHandler_attemptRecovery_succeeds() async {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"
        registry.registerPaneSession(
            id: sessionId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        guard let entry = registry.entries[sessionId] else {
            XCTFail("Entry not found"); return
        }

        // Move to dead state
        await entry.machine.send(.healthCheckFailed)
        XCTAssertEqual(entry.machine.state, .dead)

        // Mock: healthCheck returns true (session recovered)
        mockBackend.healthCheckResult = true

        // Act
        await entry.machine.send(.attemptRecovery)

        // Allow effects to execute
        try? await Task.sleep(for: .milliseconds(100))

        // Assert — should have transitioned through recovering → alive
        XCTAssertEqual(entry.machine.state, .alive)
    }

    func test_effectHandler_attemptRecovery_fails() async {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4--e5f6a7b8--00001111"
        registry.registerPaneSession(
            id: sessionId,
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        guard let entry = registry.entries[sessionId] else {
            XCTFail("Entry not found"); return
        }

        // Move to dead state
        await entry.machine.send(.healthCheckFailed)
        XCTAssertEqual(entry.machine.state, .dead)

        // Mock: healthCheck returns false (session did not recover)
        mockBackend.healthCheckResult = false

        // Act
        await entry.machine.send(.attemptRecovery)

        // Allow effects to execute
        try? await Task.sleep(for: .milliseconds(100))

        // Assert — should have transitioned to failed
        if case .failed = entry.machine.state {
            // Expected
        } else {
            XCTFail("Expected .failed state, got \(entry.machine.state)")
        }
    }
}
