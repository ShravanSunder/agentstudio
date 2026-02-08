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

    func test_sessionId_format_uses16HexSegments() {
        // Arrange — stable keys are 16 hex chars from SHA-256
        let repoKey = "a1b2c3d4e5f6a7b8"
        let wtKey = "00112233aabbccdd"
        let paneId = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899001122")!

        // Act
        let id = TmuxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

        // Assert — format: agentstudio--<repo16>--<wt16>--<pane16>
        XCTAssertTrue(id.hasPrefix("agentstudio--"))
        XCTAssertEqual(id, "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        XCTAssertEqual(id.count, 65)
    }

    func test_sessionId_isDeterministic() {
        // Arrange
        let repoKey = "abcdef0123456789"
        let wtKey = "1234567890abcdef"
        let paneId = UUID()

        // Act
        let id1 = TmuxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)
        let id2 = TmuxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

        // Assert
        XCTAssertEqual(id1, id2)
    }

    func test_sessionId_allSegmentsAreLowercaseHex() {
        // Arrange
        let repoKey = "abcdef0123456789"
        let wtKey = "fedcba9876543210"
        let paneId = UUID()

        // Act
        let id = TmuxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

        // Assert — all segments should be 16 lowercase hex chars
        let suffix = String(id.dropFirst(13))
        let segments = suffix.components(separatedBy: "--")
        XCTAssertEqual(segments.count, 3)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for segment in segments {
            XCTAssertEqual(segment.count, 16)
            XCTAssertTrue(segment.unicodeScalars.allSatisfy { hexChars.contains($0) })
        }
    }

    // MARK: - createPaneSession

    func test_createPaneSession_generatesCorrectCommand() async throws {
        // Arrange
        let worktree = makeWorktree(name: "feature-x", path: "/tmp/feature-x", branch: "feature-x")
        let repo = makeRepo()
        executor.enqueueSuccess()

        // Act
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Assert
        XCTAssertTrue(handle.id.hasPrefix("agentstudio--"))
        XCTAssertEqual(handle.id.count, 65)
        XCTAssertEqual(handle.projectId, repo.id)
        XCTAssertEqual(handle.worktreeId, worktree.id)
        XCTAssertEqual(handle.displayName, "feature-x")
        XCTAssertEqual(handle.repoPath, repo.repoPath)
        XCTAssertEqual(handle.worktreePath, worktree.path)

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
        let repo = makeRepo()
        executor.enqueueSuccess()

        // Act
        _ = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

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
        let repo = makeRepo()
        executor.enqueueFailure("session exists")

        // Act & Assert
        do {
            _ = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SessionBackendError)
        }
    }

    // MARK: - attachCommand

    func test_attachCommand_usesNewSessionA() {
        // Arrange
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344",
            workingDirectory: "/tmp"
        )

        // Act
        let cmd = backend.attachCommand(for: handle)

        // Assert
        XCTAssertEqual(
            cmd,
            "tmux -L agentstudio -f '/tmp/ghost.conf' new-session -A -s 'agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344' -c '/tmp'"
        )
    }

    func test_attachCommand_escapesPathsWithSpaces() {
        // Arrange
        let spacedBackend = TmuxBackend(
            executor: executor,
            ghostConfigPath: "/Users/test user/config path/ghost.conf"
        )
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344",
            workingDirectory: "/Users/test user/my project"
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
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess()

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertTrue(alive)
        let call = executor.calls.first!
        XCTAssertEqual(call.args, ["-L", "agentstudio", "has-session", "-t", handle.id])
    }

    func test_healthCheck_returnsFalse_onFailure() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueFailure()

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertFalse(alive)
    }

    // MARK: - destroyPaneSession

    func test_destroyPaneSession_sendsKillCommand() async throws {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess()

        // Act
        try await backend.destroyPaneSession(handle)

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.args, ["-L", "agentstudio", "kill-session", "-t", handle.id])
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
