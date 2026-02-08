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
        let sessionId = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        let paneId = UUID()

        // Act
        registry.registerPaneSession(
            id: sessionId,
            paneId: paneId,
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test"
        )

        // Assert
        XCTAssertNotNil(registry.entries[sessionId])
        XCTAssertEqual(registry.entries[sessionId]?.machine.state, .alive)
        XCTAssertEqual(registry.entries[sessionId]?.handle.paneId, paneId)
    }

    func test_registerPaneSession_rejectsInvalidId() {
        // Arrange
        let badId = "not-a-valid-session-id"

        // Act
        registry.registerPaneSession(
            id: badId,
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test"
        )

        // Assert
        XCTAssertNil(registry.entries[badId])
    }

    func test_registerPaneSession_rejectsUppercaseHex() {
        // Arrange — uppercase hex should be rejected
        let badId = "agentstudio--A1B2C3D4E5F6A7B8--00112233AABBCCDD--AABBCCDD11223344"

        // Act
        registry.registerPaneSession(
            id: badId,
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test"
        )

        // Assert
        XCTAssertNil(registry.entries[badId])
    }

    func test_registerPaneSession_doesNotDuplicateExisting() {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        registry.registerPaneSession(
            id: sessionId,
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "first"
        )

        // Act — register again with different displayName
        registry.registerPaneSession(
            id: sessionId,
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "second"
        )

        // Assert — original entry preserved
        XCTAssertEqual(registry.entries[sessionId]?.handle.displayName, "first")
    }

    // MARK: - unregisterPaneSession

    func test_unregisterPaneSession_removesEntry() {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        registry.registerPaneSession(
            id: sessionId,
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test"
        )

        // Act
        registry.unregisterPaneSession(id: sessionId)

        // Assert
        XCTAssertNil(registry.entries[sessionId])
    }

    func test_unregisterPaneSession_noOpForUnknownId() {
        // Act — should not crash
        registry.unregisterPaneSession(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")

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
        let sessionId = TmuxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: paneId
        )

        registry.registerPaneSession(
            id: sessionId,
            paneId: paneId,
            projectId: repo.id,
            worktreeId: worktree.id,
            repoPath: repo.repoPath,
            worktreePath: worktree.path,
            displayName: worktree.name
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
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344",
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test"
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
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        )

        // Assert
        XCTAssertTrue(handle.hasValidId)
    }

    func test_hasValidId_rejects2SegmentFormat() {
        // Arrange — 2-segment format should be rejected
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4--e5f6a7b8"
        )

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_hasValidId_rejectsWrongPrefix() {
        // Arrange
        let handle = makePaneSessionHandle(
            id: "wrongprefix--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        )

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_hasValidId_rejectsNonHexChars() {
        // Arrange
        let handle = makePaneSessionHandle(
            id: "agentstudio--zzzzzzzzzzzzzzzz--00112233aabbccdd--aabbccdd11223344"
        )

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_hasValidId_rejectsTooShort() {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--abc--def--ghi")

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_hasValidId_rejectsEmptyString() {
        // Arrange
        let handle = makePaneSessionHandle(id: "")

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    // MARK: - getOrCreatePaneSession

    func test_getOrCreatePaneSession_returnsExistingAliveEntry() async throws {
        // Arrange
        let worktree = makeWorktree()
        let repo = makeRepo()
        let paneId = UUID()
        let sessionId = TmuxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: paneId
        )

        registry.registerPaneSession(
            id: sessionId,
            paneId: paneId,
            projectId: repo.id,
            worktreeId: worktree.id,
            repoPath: repo.repoPath,
            worktreePath: worktree.path,
            displayName: worktree.name
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
        let expectedId = TmuxBackend.sessionId(
            repoStableKey: repo.stableKey,
            worktreeStableKey: worktree.stableKey,
            paneId: paneId
        )
        let handle = makePaneSessionHandle(
            id: expectedId,
            paneId: paneId,
            projectId: repo.id,
            worktreeId: worktree.id,
            repoPath: repo.repoPath.path,
            worktreePath: worktree.path.path,
            displayName: worktree.name,
            workingDirectory: worktree.path.path
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
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344",
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "first"
        )
        registry.registerPaneSession(
            id: "agentstudio--1111111111111111--2222222222222222--3333333333333333",
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "second"
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
        let sessionId = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        let paneId = UUID()
        let projectId = UUID()
        let worktreeId = UUID()

        registry.registerPaneSession(
            id: sessionId,
            paneId: paneId,
            projectId: projectId,
            worktreeId: worktreeId,
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test-roundtrip"
        )

        // Act
        registry.saveCheckpoint()

        // Assert — load checkpoint and verify contents
        let loaded = SessionCheckpoint.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessions.count, 1)
        XCTAssertEqual(loaded?.sessions.first?.sessionId, sessionId)
        XCTAssertEqual(loaded?.sessions.first?.displayName, "test-roundtrip")
        XCTAssertEqual(loaded?.sessions.first?.paneId, paneId)
    }

    // MARK: - Restore from Checkpoint

    func test_restoreFromCheckpoint_populatesAliveEntries() async {
        // Arrange — create repo + worktree, compute deterministic session ID
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
                displayName: "surviving",
                workingDirectory: worktree.path,
                lastKnownAlive: Date()
            ),
        ])

        // Mock: session is alive in tmux
        mockBackend.sessionExistsResult = true

        // Act — provide repoLookup that returns the test repo
        await registry.restoreFromCheckpoint(checkpoint) { id, _ in
            id == repoWithWt.id ? repoWithWt : nil
        }

        // Assert
        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertNotNil(registry.entries[sessionId])
        XCTAssertEqual(registry.entries[sessionId]?.machine.state, .alive)
    }

    func test_restoreFromCheckpoint_skipsDeadSessions() async {
        // Arrange
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
                displayName: "dead-session",
                workingDirectory: worktree.path,
                lastKnownAlive: Date()
            ),
        ])

        // Mock: session is NOT alive in tmux
        mockBackend.sessionExistsResult = false

        // Act
        await registry.restoreFromCheckpoint(checkpoint) { id, _ in
            id == repoWithWt.id ? repoWithWt : nil
        }

        // Assert — dead session should not be restored
        XCTAssertTrue(registry.entries.isEmpty)
    }

    func test_restoreFromCheckpoint_destroysMismatchedSessionIds() async {
        // Arrange — repo exists but has moved to a new path, so stableKey changed
        let paneId = UUID()
        let worktreeId = UUID()
        let staleSessionId = "agentstudio--0000000000000000--1111111111111111--2222222222222222"

        // Current repo is at a different path than what produced the stale session ID
        let repo = makeRepo(repoPath: "/tmp/test-repo")
        let worktree = makeWorktree(id: worktreeId, path: "/tmp/test-repo/main")
        let repoWithWt = makeRepo(id: repo.id, repoPath: "/tmp/test-repo", worktrees: [worktree])

        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: staleSessionId,
                paneId: paneId,
                projectId: repo.id,
                worktreeId: worktreeId,
                repoPath: URL(fileURLWithPath: "/old/path/repo"),
                worktreePath: URL(fileURLWithPath: "/old/path/repo/main"),
                displayName: "stale-session",
                workingDirectory: URL(fileURLWithPath: "/old/path/repo/main"),
                lastKnownAlive: Date()
            ),
        ])

        mockBackend.sessionExistsResult = true

        // Act — repoLookup returns repo at new path → recomputed ID won't match stale
        await registry.restoreFromCheckpoint(checkpoint) { id, _ in
            id == repoWithWt.id ? repoWithWt : nil
        }

        // Assert — stale session destroyed, not restored
        XCTAssertTrue(registry.entries.isEmpty, "Mismatched session should not be restored")
        XCTAssertEqual(mockBackend.destroyByIdCalls, [staleSessionId], "Stale session should be destroyed")
    }

    func test_restoreFromCheckpoint_destroysStaleWhenRepoNotFound() async {
        // Arrange — checkpoint references a repo that no longer exists
        let paneId = UUID()
        let staleSessionId = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"

        let checkpoint = SessionCheckpoint(sessions: [
            .init(
                sessionId: staleSessionId,
                paneId: paneId,
                projectId: UUID(),
                worktreeId: UUID(),
                repoPath: URL(fileURLWithPath: "/tmp/deleted-repo"),
                worktreePath: URL(fileURLWithPath: "/tmp/deleted-repo/main"),
                displayName: "orphan-session",
                workingDirectory: URL(fileURLWithPath: "/tmp/deleted-repo/main"),
                lastKnownAlive: Date()
            ),
        ])

        mockBackend.sessionExistsResult = true

        // Act — repoLookup returns nil (repo removed)
        await registry.restoreFromCheckpoint(checkpoint) { _, _ in nil }

        // Assert — session destroyed because repo no longer exists
        XCTAssertTrue(registry.entries.isEmpty, "Session for missing repo should not be restored")
        XCTAssertEqual(mockBackend.destroyByIdCalls, [staleSessionId], "Stale session should be destroyed")
    }

    func test_restoreFromCheckpoint_fallsBackToPathMatching() async {
        // Arrange — checkpoint has stale UUIDs but valid paths that still match
        let paneId = UUID()
        let staleProjectId = UUID()  // UUID from old workspace
        let staleWorktreeId = UUID()  // UUID from old workspace

        let repo = makeRepo(repoPath: "/tmp/test-repo")
        let worktree = makeWorktree(path: "/tmp/test-repo/main")
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
                projectId: staleProjectId,
                worktreeId: staleWorktreeId,
                repoPath: repo.repoPath,
                worktreePath: worktree.path,
                displayName: "path-fallback",
                workingDirectory: worktree.path,
                lastKnownAlive: Date()
            ),
        ])

        mockBackend.sessionExistsResult = true

        // Act — UUID lookup fails (staleProjectId doesn't match), but path fallback succeeds
        await registry.restoreFromCheckpoint(checkpoint) { id, path in
            // UUID won't match, but path will
            if id == repoWithWt.id { return repoWithWt }
            if path == repoWithWt.repoPath { return repoWithWt }
            return nil
        }

        // Assert — should restore via path fallback
        XCTAssertEqual(registry.entries.count, 1)
        XCTAssertNotNil(registry.entries[sessionId])
        XCTAssertEqual(registry.entries[sessionId]?.machine.state, .alive)
        // Handle should have the CURRENT repo/worktree IDs, not the stale ones
        XCTAssertEqual(registry.entries[sessionId]?.handle.projectId, repo.id)
        XCTAssertEqual(registry.entries[sessionId]?.handle.worktreeId, worktree.id)
    }

    // MARK: - Effect Handler: Recovery

    func test_effectHandler_attemptRecovery_succeeds() async {
        // Arrange
        let sessionId = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        registry.registerPaneSession(
            id: sessionId,
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test"
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
        let sessionId = "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        registry.registerPaneSession(
            id: sessionId,
            paneId: UUID(),
            projectId: UUID(),
            worktreeId: UUID(),
            repoPath: URL(fileURLWithPath: "/tmp/test-repo"),
            worktreePath: URL(fileURLWithPath: "/tmp"),
            displayName: "test"
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
