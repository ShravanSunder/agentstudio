import XCTest
@testable import AgentStudio

final class ZmxBackendTests: XCTestCase {
    private var executor: MockProcessExecutor!
    private var backend: ZmxBackend!

    override func setUp() {
        super.setUp()
        executor = MockProcessExecutor()
        backend = ZmxBackend(executor: executor, zmxPath: "/usr/local/bin/zmx", zmxDir: "/tmp/zmx-test")
    }

    // MARK: - isAvailable

    func test_isAvailable_whenBinaryExists() async {
        // Arrange — use a path that exists (/usr/bin/env)
        let backendWithRealPath = ZmxBackend(executor: executor, zmxPath: "/usr/bin/env", zmxDir: "/tmp/zmx-test")

        // Act
        let available = await backendWithRealPath.isAvailable

        // Assert — checks FileManager.isExecutableFile, no CLI call
        XCTAssertTrue(available)
        XCTAssertTrue(executor.calls.isEmpty, "isAvailable should not make any CLI calls")
    }

    func test_isAvailable_whenBinaryMissing() async {
        // Arrange — path that doesn't exist
        let backendWithBadPath = ZmxBackend(executor: executor, zmxPath: "/nonexistent/zmx", zmxDir: "/tmp/zmx-test")

        // Act
        let available = await backendWithBadPath.isAvailable

        // Assert
        XCTAssertFalse(available)
        XCTAssertTrue(executor.calls.isEmpty, "isAvailable should not make any CLI calls")
    }

    // MARK: - Session ID Generation

    func test_sessionId_format_uses16HexSegments() {
        // Arrange — stable keys are 16 hex chars from SHA-256
        let repoKey = "a1b2c3d4e5f6a7b8"
        let wtKey = "00112233aabbccdd"
        let paneId = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899001122")!

        // Act
        let id = ZmxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

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
        let id1 = ZmxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)
        let id2 = ZmxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

        // Assert
        XCTAssertEqual(id1, id2)
    }

    func test_sessionId_allSegmentsAreLowercaseHex() {
        // Arrange
        let repoKey = "abcdef0123456789"
        let wtKey = "fedcba9876543210"
        let paneId = UUID()

        // Act
        let id = ZmxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

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

    // MARK: - Drawer Session ID Generation

    func test_drawerSessionId_format() {
        // Arrange
        let parentPaneId = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899001122")!
        let drawerPaneId = UUID(uuidString: "11223344-5566-7788-99AA-BBCCDDEEFF00")!

        // Act
        let id = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)

        // Assert — format: agentstudio-d--<parent16>--<drawer16>
        XCTAssertTrue(id.hasPrefix("agentstudio-d--"))
        XCTAssertEqual(id, "agentstudio-d--aabbccdd11223344--1122334455667788")
    }

    func test_drawerSessionId_isDeterministic() {
        // Arrange
        let parentPaneId = UUID()
        let drawerPaneId = UUID()

        // Act
        let id1 = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)
        let id2 = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)

        // Assert
        XCTAssertEqual(id1, id2)
    }

    func test_drawerSessionId_allSegmentsAreLowercaseHex() {
        // Arrange
        let parentPaneId = UUID()
        let drawerPaneId = UUID()

        // Act
        let id = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)

        // Assert — prefix is "agentstudio-d--", then two 16-char hex segments
        let suffix = String(id.dropFirst("agentstudio-d--".count))
        let segments = suffix.components(separatedBy: "--")
        XCTAssertEqual(segments.count, 2)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for segment in segments {
            XCTAssertEqual(segment.count, 16)
            XCTAssertTrue(segment.unicodeScalars.allSatisfy { hexChars.contains($0) })
        }
    }

    // MARK: - PaneSessionHandle Validation

    func test_paneSessionHandle_hasValidId_validFormat() {
        // Arrange
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        )

        // Assert
        XCTAssertTrue(handle.hasValidId)
    }

    func test_paneSessionHandle_hasValidId_invalidPrefix() {
        // Arrange
        let handle = makePaneSessionHandle(id: "wrong--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_paneSessionHandle_hasValidId_wrongSegmentCount() {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd")

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    func test_paneSessionHandle_hasValidId_nonHexChars() {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--gggggggggggggggg--00112233aabbccdd--aabbccdd11223344")

        // Assert
        XCTAssertFalse(handle.hasValidId)
    }

    // MARK: - createPaneSession

    func test_createPaneSession_returnsHandleWithoutCLICall() async throws {
        // Arrange
        let worktree = makeWorktree(name: "feature-x", path: "/tmp/feature-x", branch: "feature-x")
        let repo = makeRepo()
        // Use a real temp dir so createDirectory succeeds
        let tempZmxDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmx-test-\(UUID().uuidString.prefix(8))").path
        let tempBackend = ZmxBackend(
            executor: executor,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: tempZmxDir
        )

        // Act
        let handle = try await tempBackend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        // Assert — no CLI calls (zmx auto-creates on attach)
        XCTAssertTrue(executor.calls.isEmpty, "createPaneSession should make zero CLI calls")
        XCTAssertTrue(handle.id.hasPrefix("agentstudio--"))
        XCTAssertEqual(handle.id.count, 65)
        XCTAssertEqual(handle.projectId, repo.id)
        XCTAssertEqual(handle.worktreeId, worktree.id)
        XCTAssertEqual(handle.displayName, "feature-x")
        XCTAssertEqual(handle.repoPath, repo.repoPath)
        XCTAssertEqual(handle.worktreePath, worktree.path)
        // Verify zmxDir was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempZmxDir))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempZmxDir)
    }

    // MARK: - attachCommand

    func test_attachCommand_format() {
        // Arrange
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        )

        // Act
        let cmd = backend.attachCommand(for: handle)

        // Assert
        XCTAssertFalse(cmd.contains("ZMX_DIR="))
        XCTAssertTrue(cmd.hasPrefix("\"/usr/local/bin/zmx\""))
        XCTAssertTrue(cmd.contains("attach"))
        XCTAssertTrue(cmd.contains("\"agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344\""))
        XCTAssertTrue(cmd.contains("-i -l"))
        // No ghost.conf, no mouse-off, no unbind-key
        XCTAssertFalse(cmd.contains("ghost.conf"))
        XCTAssertFalse(cmd.contains("mouse"))
        XCTAssertFalse(cmd.contains("unbind"))
    }

    func test_attachCommand_escapesPathsWithSpaces() {
        // Arrange
        let spacedBackend = ZmxBackend(
            executor: executor,
            zmxPath: "/Users/test user/bin/zmx",
            zmxDir: "/Users/test user/.agentstudio/zmx"
        )
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        )

        // Act
        let cmd = spacedBackend.attachCommand(for: handle)

        // Assert
        XCTAssertFalse(cmd.contains("/Users/test user/.agentstudio/zmx"))
        XCTAssertTrue(cmd.contains("\"/Users/test user/bin/zmx\""))
    }

    func test_buildAttachCommand_staticMethod() {
        // Act
        let cmd = ZmxBackend.buildAttachCommand(
            zmxPath: "/opt/homebrew/bin/zmx",
            zmxDir: "/home/user/.agentstudio/zmx",
            sessionId: "agentstudio--abc--def--ghi",
            shell: "/bin/zsh"
        )

        // Assert
        XCTAssertEqual(
            cmd,
            "\"/opt/homebrew/bin/zmx\" attach \"agentstudio--abc--def--ghi\" \"/bin/zsh\" -i -l"
        )
    }

    // MARK: - Shell Escape

    func test_shellEscape_simplePath() {
        XCTAssertEqual(ZmxBackend.shellEscape("/usr/bin/zmx"), "\"/usr/bin/zmx\"")
    }

    func test_shellEscape_pathWithSpaces() {
        XCTAssertEqual(ZmxBackend.shellEscape("/Users/test user/bin/zmx"), "\"/Users/test user/bin/zmx\"")
    }

    func test_shellEscape_pathWithSingleQuote() {
        XCTAssertEqual(ZmxBackend.shellEscape("/tmp/it's"), "\"/tmp/it's\"")
    }

    // MARK: - healthCheck

    func test_healthCheck_returnsTrue_whenSessionInList() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344\trunning\t123")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertTrue(alive)
        let call = executor.calls.first!
        XCTAssertEqual(call.command, "/usr/local/bin/zmx")
        XCTAssertEqual(call.args, ["list"])
    }

    func test_healthCheck_returnsFalse_whenSessionNotInList() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("some-other-session\trunning\t456")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertFalse(alive)
    }

    func test_healthCheck_returnsFalse_onCommandFailure() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueFailure("zmx: error")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        XCTAssertFalse(alive)
    }

    func test_healthCheck_returnsFalse_onEmptyOutput() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("")

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
        XCTAssertEqual(call.command, "/usr/local/bin/zmx")
        XCTAssertEqual(call.args, ["kill", handle.id])
    }

    func test_destroyPaneSession_throwsOnFailure() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueFailure("session not found")

        // Act & Assert
        do {
            try await backend.destroyPaneSession(handle)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SessionBackendError)
        }
    }

    // MARK: - discoverOrphanSessions

    func test_discoverOrphanSessions_filtersCorrectly() async {
        // Arrange
        executor.enqueue(ProcessResult(
            exitCode: 0,
            stdout: "agentstudio--abc--111--222\trunning\nagentstudio--def--333--444\trunning\nuser-session\trunning\nagentstudio--ghi--555--666\trunning",
            stderr: ""
        ))

        // Act
        let orphans = await backend.discoverOrphanSessions(excluding: ["agentstudio--abc--111--222"])

        // Assert
        XCTAssertEqual(orphans.count, 2)
        XCTAssertTrue(orphans.contains("agentstudio--def--333--444"))
        XCTAssertTrue(orphans.contains("agentstudio--ghi--555--666"))
        XCTAssertFalse(orphans.contains("user-session"))
    }

    func test_discoverOrphanSessions_passesZmxDirEnv() async {
        // Arrange
        executor.enqueueSuccess("")

        // Act
        _ = await backend.discoverOrphanSessions(excluding: [])

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.command, "/usr/local/bin/zmx")
        XCTAssertEqual(call.args, ["list"])
    }

    func test_discoverOrphanSessions_returnsEmpty_onFailure() async {
        // Arrange
        executor.enqueueFailure("zmx error")

        // Act
        let orphans = await backend.discoverOrphanSessions(excluding: [])

        // Assert
        XCTAssertTrue(orphans.isEmpty)
    }

    func test_discoverOrphanSessions_includesDrawerSessions() async {
        // Arrange — mix of main and drawer sessions
        executor.enqueue(ProcessResult(
            exitCode: 0,
            stdout: "agentstudio--abc--111--222\trunning\nagentstudio-d--aabb--ccdd\trunning\nuser-session\trunning",
            stderr: ""
        ))

        // Act — exclude the main session, drawer should appear as orphan
        let orphans = await backend.discoverOrphanSessions(excluding: ["agentstudio--abc--111--222"])

        // Assert
        XCTAssertEqual(orphans.count, 1)
        XCTAssertTrue(orphans.contains("agentstudio-d--aabb--ccdd"))
        XCTAssertFalse(orphans.contains("user-session"))
    }

    // MARK: - destroySessionById

    func test_destroySessionById_sendsKillCommand() async throws {
        // Arrange
        executor.enqueueSuccess()

        // Act
        try await backend.destroySessionById("agentstudio--abc--def--ghi")

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.command, "/usr/local/bin/zmx")
        XCTAssertEqual(call.args, ["kill", "agentstudio--abc--def--ghi"])
    }

    func test_destroySessionById_throwsOnFailure() async {
        // Arrange
        executor.enqueueFailure("session not found")

        // Act & Assert
        do {
            try await backend.destroySessionById("agentstudio--abc--def--ghi")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is SessionBackendError)
        }
    }

    // MARK: - socketExists

    func test_socketExists_returnsTrueWhenDirExists() {
        // Arrange — use a backend pointed at an existing temp dir
        let tempDir = FileManager.default.temporaryDirectory.path
        let tempBackend = ZmxBackend(executor: executor, zmxPath: "/usr/local/bin/zmx", zmxDir: tempDir)

        // Assert
        XCTAssertTrue(tempBackend.socketExists())
    }

    func test_socketExists_returnsFalseWhenDirMissing() {
        // Arrange
        let badBackend = ZmxBackend(executor: executor, zmxPath: "/usr/local/bin/zmx", zmxDir: "/nonexistent/\(UUID())")

        // Assert
        XCTAssertFalse(badBackend.socketExists())
    }

    // MARK: - ZMX_DIR Environment Propagation

    func test_healthCheck_passesZmxDirEnv() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("")

        // Act
        _ = await backend.healthCheck(handle)

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.environment?["ZMX_DIR"], "/tmp/zmx-test")
    }

    func test_destroyPaneSession_passesZmxDirEnv() async throws {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess()

        // Act
        try await backend.destroyPaneSession(handle)

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.environment?["ZMX_DIR"], "/tmp/zmx-test")
    }

    func test_destroySessionById_passesZmxDirEnv() async throws {
        // Arrange
        executor.enqueueSuccess()

        // Act
        try await backend.destroySessionById("agentstudio--abc--def--ghi")

        // Assert
        let call = executor.calls.first!
        XCTAssertEqual(call.environment?["ZMX_DIR"], "/tmp/zmx-test")
    }
}
