import XCTest
@testable import AgentStudio

final class TmuxBackendTests: XCTestCase {
    private var executor: MockProcessExecutor!
    private var backend: TmuxBackend!

    override func setUp() {
        super.setUp()
        executor = MockProcessExecutor()
        backend = TmuxBackend(executor: executor, ghostConfigPath: "/tmp/ghost.conf")
    }

    // MARK: - isAvailable

    func test_isAvailable_whenTmuxExists() async {
        // Arrange
        executor.enqueueSuccess("tmux 3.4")

        // Act
        let available = await backend.isAvailable

        // Assert
        XCTAssertTrue(available)
        XCTAssertEqual(executor.calls.first?.command, "tmux")
        XCTAssertEqual(executor.calls.first?.args, ["-V"])
    }

    func test_isAvailable_whenTmuxMissing() async {
        // Arrange
        executor.enqueueFailure("not found")

        // Act
        let available = await backend.isAvailable

        // Assert
        XCTAssertFalse(available)
    }

    // MARK: - Session ID Generation

    func test_sessionId_format() {
        // Arrange
        let projectId = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000000")!
        let worktreeId = UUID(uuidString: "E5F6A7B8-0000-0000-0000-000000000000")!

        let paneId = UUID(uuidString: "00001111-0000-0000-0000-000000000000")!

        // Act
        let id = TmuxBackend.sessionId(projectId: projectId, worktreeId: worktreeId, paneId: paneId)

        // Assert
        XCTAssertEqual(id, "agentstudio--a1b2c3d4--e5f6a7b8--00001111")
    }

    func test_sessionId_isDeterministic() {
        // Arrange
        let projectId = UUID()
        let worktreeId = UUID()

        let paneId = UUID()

        // Act
        let id1 = TmuxBackend.sessionId(projectId: projectId, worktreeId: worktreeId, paneId: paneId)
        let id2 = TmuxBackend.sessionId(projectId: projectId, worktreeId: worktreeId, paneId: paneId)

        // Assert
        XCTAssertEqual(id1, id2)
    }

    // MARK: - createPaneSession

    func test_createPaneSession_generatesCorrectCommand() async throws {
        // Arrange
        let worktree = makeWorktree(name: "feature-x", path: "/tmp/feature-x", branch: "feature-x")
        let projectId = UUID()
        executor.enqueueSuccess()

        // Act
        let handle = try await backend.createPaneSession(projectId: projectId, worktree: worktree, paneId: UUID())

        // Assert
        XCTAssertTrue(handle.id.hasPrefix("agentstudio--"))
        XCTAssertEqual(handle.projectId, projectId)
        XCTAssertEqual(handle.worktreeId, worktree.id)
        XCTAssertEqual(handle.displayName, "feature-x")

        let call = executor.calls.first
        XCTAssertEqual(call?.command, "tmux")
        XCTAssertTrue(call?.args.contains("-L") ?? false)
        XCTAssertTrue(call?.args.contains("agentstudio") ?? false)
        XCTAssertTrue(call?.args.contains("-f") ?? false)
        XCTAssertTrue(call?.args.contains("/tmp/ghost.conf") ?? false)
        XCTAssertTrue(call?.args.contains("new-session") ?? false)
        XCTAssertTrue(call?.args.contains("-d") ?? false)
    }

    func test_createPaneSession_usesCustomSocket() async throws {
        // Arrange
        let worktree = makeWorktree()
        executor.enqueueSuccess()

        // Act
        _ = try await backend.createPaneSession(projectId: UUID(), worktree: worktree, paneId: UUID())

        // Assert
        let call = executor.calls.first!
        // Verify -L agentstudio appears in args
        if let lIndex = call.args.firstIndex(of: "-L") {
            XCTAssertEqual(call.args[call.args.index(after: lIndex)], "agentstudio")
        } else {
            XCTFail("Expected -L flag in tmux command")
        }
    }

    func test_createPaneSession_throwsOnFailure() async {
        // Arrange
        let worktree = makeWorktree()
        executor.enqueueFailure("session exists")

        // Act & Assert
        do {
            _ = try await backend.createPaneSession(projectId: UUID(), worktree: worktree, paneId: UUID())
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SessionBackendError)
        }
    }

    // MARK: - attachCommand

    func test_attachCommand_usesNewSessionA() {
        // Arrange
        let handle = PaneSessionHandle(
            id: "agentstudio--abc12345--def67890",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Act
        let cmd = backend.attachCommand(for: handle)

        // Assert
        XCTAssertEqual(
            cmd,
            "tmux -L agentstudio -f '/tmp/ghost.conf' new-session -A -s 'agentstudio--abc12345--def67890' -c '/tmp'"
        )
    }

    func test_attachCommand_escapesPathsWithSpaces() {
        // Arrange
        let spacedBackend = TmuxBackend(
            executor: executor,
            ghostConfigPath: "/Users/test user/config path/ghost.conf"
        )
        let handle = PaneSessionHandle(
            id: "agentstudio--abc12345--def67890",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/Users/test user/my project")
        )

        // Act
        let cmd = spacedBackend.attachCommand(for: handle)

        // Assert
        XCTAssertTrue(cmd.contains("'/Users/test user/config path/ghost.conf'"))
        XCTAssertTrue(cmd.contains("'/Users/test user/my project'"))
    }

    // MARK: - healthCheck

    func test_healthCheck_returnsTrue_onSuccess() async {
        // Arrange
        let handle = PaneSessionHandle(
            id: "agentstudio--abc--def",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        executor.enqueueSuccess()

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertTrue(alive)
        let call = executor.calls.first!
        XCTAssertEqual(call.args, ["-L", "agentstudio", "has-session", "-t", "agentstudio--abc--def"])
    }

    func test_healthCheck_returnsFalse_onFailure() async {
        // Arrange
        let handle = PaneSessionHandle(
            id: "agentstudio--abc--def",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        executor.enqueueFailure()

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertFalse(alive)
    }

    // MARK: - destroyPaneSession

    func test_destroyPaneSession_sendsKillCommand() async throws {
        // Arrange
        let handle = PaneSessionHandle(
            id: "agentstudio--abc--def",
            projectId: UUID(),
            worktreeId: UUID(),
            displayName: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        executor.enqueueSuccess()

        // Act
        try await backend.destroyPaneSession(handle)

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.args, ["-L", "agentstudio", "kill-session", "-t", "agentstudio--abc--def"])
    }

    // MARK: - discoverOrphanSessions

    func test_discoverOrphanSessions_filtersCorrectly() async {
        // Arrange
        executor.enqueue(ProcessResult(
            exitCode: 0,
            stdout: "agentstudio--abc--111\nagentstudio--def--222\nuser-session\nagentstudio--ghi--333",
            stderr: ""
        ))

        // Act
        let orphans = await backend.discoverOrphanSessions(excluding: ["agentstudio--abc--111"])

        // Assert
        XCTAssertEqual(orphans, ["agentstudio--def--222", "agentstudio--ghi--333"])
    }

    func test_discoverOrphanSessions_usesCustomSocket() async {
        // Arrange
        executor.enqueueSuccess("")

        // Act
        _ = await backend.discoverOrphanSessions(excluding: [])

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.args.prefix(2), ["-L", "agentstudio"])
    }

    // MARK: - destroySessionById

    func test_destroySessionById_sendsKillCommand() async throws {
        // Arrange
        executor.enqueueSuccess()

        // Act
        try await backend.destroySessionById("agentstudio--abc--def")

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.args, ["-L", "agentstudio", "kill-session", "-t", "agentstudio--abc--def"])
    }
}
