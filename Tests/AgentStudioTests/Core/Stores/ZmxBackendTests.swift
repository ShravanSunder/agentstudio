import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class ZmxBackendTests {
    private var executor: MockProcessExecutor!
    private var backend: ZmxBackend!

        init() {
        executor = MockProcessExecutor()
        backend = ZmxBackend(executor: executor, zmxPath: "/usr/local/bin/zmx", zmxDir: "/tmp/zmx-test")
    }

    // MARK: - isAvailable

    @Test

    func test_isAvailable_whenBinaryExists() async {
        // Arrange — use a path that exists (/usr/bin/env)
        let backendWithRealPath = ZmxBackend(executor: executor, zmxPath: "/usr/bin/env", zmxDir: "/tmp/zmx-test")

        // Act
        let available = await backendWithRealPath.isAvailable

        // Assert — checks FileManager.isExecutableFile, no CLI call
        #expect(available)
        #expect(executor.calls.isEmpty)
    }

    @Test

    func test_isAvailable_whenBinaryMissing() async {
        // Arrange — path that doesn't exist
        let backendWithBadPath = ZmxBackend(executor: executor, zmxPath: "/nonexistent/zmx", zmxDir: "/tmp/zmx-test")

        // Act
        let available = await backendWithBadPath.isAvailable

        // Assert
        #expect(!(available))
        #expect(executor.calls.isEmpty)
    }

    // MARK: - Session ID Generation

    @Test

    func test_sessionId_format_uses16HexSegments() {
        // Arrange — stable keys are 16 hex chars from SHA-256
        let repoKey = "a1b2c3d4e5f6a7b8"
        let wtKey = "00112233aabbccdd"
        let paneId = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899001122")!

        // Act
        let id = ZmxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

        // Assert — format: agentstudio--<repo16>--<wt16>--<pane16>
        #expect(id.hasPrefix("agentstudio--"))
        #expect(id == "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        #expect(id.count == 65)
    }

    @Test

    func test_sessionId_isDeterministic() {
        // Arrange
        let repoKey = "abcdef0123456789"
        let wtKey = "1234567890abcdef"
        let paneId = UUID()

        // Act
        let id1 = ZmxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)
        let id2 = ZmxBackend.sessionId(repoStableKey: repoKey, worktreeStableKey: wtKey, paneId: paneId)

        // Assert
        #expect(id1 == id2)
    }

    @Test

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
        #expect(segments.count == 3)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for segment in segments {
            #expect(segment.count == 16)
            #expect(segment.unicodeScalars.allSatisfy { hexChars.contains($0) })
        }
    }

    // MARK: - Drawer Session ID Generation

    @Test

    func test_drawerSessionId_format() {
        // Arrange
        let parentPaneId = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899001122")!
        let drawerPaneId = UUID(uuidString: "11223344-5566-7788-99AA-BBCCDDEEFF00")!

        // Act
        let id = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)

        // Assert — format: agentstudio-d--<parent16>--<drawer16>
        #expect(id.hasPrefix("agentstudio-d--"))
        #expect(id == "agentstudio-d--aabbccdd11223344--1122334455667788")
    }

    @Test

    func test_drawerSessionId_isDeterministic() {
        // Arrange
        let parentPaneId = UUID()
        let drawerPaneId = UUID()

        // Act
        let id1 = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)
        let id2 = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)

        // Assert
        #expect(id1 == id2)
    }

    @Test

    func test_drawerSessionId_allSegmentsAreLowercaseHex() {
        // Arrange
        let parentPaneId = UUID()
        let drawerPaneId = UUID()

        // Act
        let id = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)

        // Assert — prefix is "agentstudio-d--", then two 16-char hex segments
        let suffix = String(id.dropFirst("agentstudio-d--".count))
        let segments = suffix.components(separatedBy: "--")
        #expect(segments.count == 2)
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        for segment in segments {
            #expect(segment.count == 16)
            #expect(segment.unicodeScalars.allSatisfy { hexChars.contains($0) })
        }
    }

    // MARK: - PaneSessionHandle Validation

    @Test

    func test_paneSessionHandle_hasValidId_validFormat() {
        // Arrange
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        )

        // Assert
        #expect(handle.hasValidId)
    }

    @Test

    func test_paneSessionHandle_hasValidId_invalidPrefix() {
        // Arrange
        let handle = makePaneSessionHandle(id: "wrong--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")

        // Assert
        #expect(!(handle.hasValidId))
    }

    @Test

    func test_paneSessionHandle_hasValidId_wrongSegmentCount() {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd")

        // Assert
        #expect(!(handle.hasValidId))
    }

    @Test

    func test_paneSessionHandle_hasValidId_nonHexChars() {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--gggggggggggggggg--00112233aabbccdd--aabbccdd11223344")

        // Assert
        #expect(!(handle.hasValidId))
    }

    // MARK: - createPaneSession

    @Test

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
        #expect(executor.calls.isEmpty)
        #expect(handle.id.hasPrefix("agentstudio--"))
        #expect(handle.id.count == 65)
        #expect(handle.projectId == repo.id)
        #expect(handle.worktreeId == worktree.id)
        #expect(handle.displayName == "feature-x")
        #expect(handle.repoPath == repo.repoPath)
        #expect(handle.worktreePath == worktree.path)
        // Verify zmxDir was created
        #expect(FileManager.default.fileExists(atPath: tempZmxDir))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tempZmxDir)
    }

    // MARK: - attachCommand

    @Test

    func test_attachCommand_format() {
        // Arrange
        let handle = makePaneSessionHandle(
            id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344"
        )

        // Act
        let cmd = backend.attachCommand(for: handle)

        // Assert
        #expect(!(cmd.contains("ZMX_DIR=")))
        #expect(cmd.hasPrefix("\"/usr/local/bin/zmx\""))
        #expect(cmd.contains("attach"))
        #expect(cmd.contains("\"agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344\""))
        #expect(cmd.contains("-i -l"))
        // No ghost.conf, no mouse-off, no unbind-key
        #expect(!(cmd.contains("ghost.conf")))
        #expect(!(cmd.contains("mouse")))
        #expect(!(cmd.contains("unbind")))
    }

    @Test

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
        #expect(!(cmd.contains("/Users/test user/.agentstudio/zmx")))
        #expect(cmd.contains("\"/Users/test user/bin/zmx\""))
    }

    @Test

    func test_buildAttachCommand_staticMethod() {
        // Act
        let cmd = ZmxBackend.buildAttachCommand(
            zmxPath: "/opt/homebrew/bin/zmx",
            sessionId: "agentstudio--abc--def--ghi",
            shell: "/bin/zsh"
        )

        // Assert
        #expect(cmd == "\"/opt/homebrew/bin/zmx\" attach \"agentstudio--abc--def--ghi\" \"/bin/zsh\" -i -l")
    }

    // MARK: - Shell Escape

    @Test

    func test_shellEscape_simplePath() {
        #expect(ZmxBackend.shellEscape("/usr/bin/zmx") == "\"/usr/bin/zmx\"")
    }

    @Test

    func test_shellEscape_pathWithSpaces() {
        #expect(ZmxBackend.shellEscape("/Users/test user/bin/zmx") == "\"/Users/test user/bin/zmx\"")
    }

    @Test

    func test_shellEscape_pathWithSingleQuote() {
        #expect(ZmxBackend.shellEscape("/tmp/it's") == "\"/tmp/it's\"")
    }

    @Test

    func test_shellEscape_escapesDollar() {
        #expect(ZmxBackend.shellEscape("/tmp/$HOME") == "\"/tmp/\\$HOME\"")
    }

    @Test

    func test_shellEscape_escapesBacktick() {
        #expect(ZmxBackend.shellEscape("/tmp/`pwd`") == "\"/tmp/\\`pwd\\`\"")
    }

    @Test

    func test_shellEscape_escapesDoubleQuote() {
        #expect(ZmxBackend.shellEscape("/tmp/\"quoted\"") == "\"/tmp/\\\"quoted\\\"\"")
    }

    @Test

    func test_shellEscape_escapesBackslash() {
        #expect(ZmxBackend.shellEscape("/tmp/foo\\bar") == "\"/tmp/foo\\\\bar\"")
    }

    @Test

    func test_shellEscape_escapesHistoryBang() {
        #expect(ZmxBackend.shellEscape("/tmp/bang!") == "\"/tmp/bang\\!\"")
    }

    // MARK: - healthCheck

    @Test

    func test_healthCheck_returnsTrue_whenSessionInList() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344\trunning\t123")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        #expect(alive)
        let call = executor.calls.first!
        #expect(call.command == "/usr/local/bin/zmx")
        #expect(call.args == ["list"])
    }

    @Test

    func test_healthCheck_returnsFalse_whenSessionNotInList() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("some-other-session\trunning\t456")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        #expect(!(alive))
    }

    @Test

    func test_healthCheck_returnsFalse_onCommandFailure() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueFailure("zmx: error")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        #expect(!(alive))
    }

    @Test

    func test_healthCheck_returnsFalse_onEmptyOutput() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        #expect(!(alive))
    }

    // MARK: - destroyPaneSession

    @Test

    func test_destroyPaneSession_sendsKillCommand() async throws {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess()

        // Act
        try await backend.destroyPaneSession(handle)

        // Assert
        let call = executor.calls.first!
        #expect(call.command == "/usr/local/bin/zmx")
        #expect(call.args == ["kill", handle.id])
    }

    @Test

    func test_destroyPaneSession_throwsOnFailure() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueFailure("session not found")

        // Act & Assert
        do {
            try await backend.destroyPaneSession(handle)
            Issue.record("Expected error")
        } catch {
            #expect(error is SessionBackendError)
        }
    }

    // MARK: - discoverOrphanSessions

    @Test

    func test_discoverOrphanSessions_filtersCorrectly() async {
        // Arrange
        executor.enqueue(
            ProcessResult(
                exitCode: 0,
                stdout:
                    "agentstudio--abc--111--222\trunning\nagentstudio--def--333--444\trunning\nuser-session\trunning\nagentstudio--ghi--555--666\trunning",
                stderr: ""
            ))

        // Act
        let orphans = await backend.discoverOrphanSessions(excluding: ["agentstudio--abc--111--222"])

        // Assert
        #expect(orphans.count == 2)
        #expect(orphans.contains("agentstudio--def--333--444"))
        #expect(orphans.contains("agentstudio--ghi--555--666"))
        #expect(!(orphans.contains("user-session")))
    }

    @Test

    func test_discoverOrphanSessions_passesZmxDirEnv() async {
        // Arrange
        executor.enqueueSuccess("")

        // Act
        _ = await backend.discoverOrphanSessions(excluding: [])

        // Assert
        let call = executor.calls.first!
        #expect(call.command == "/usr/local/bin/zmx")
        #expect(call.args == ["list"])
    }

    @Test

    func test_discoverOrphanSessions_returnsEmpty_onFailure() async {
        // Arrange
        executor.enqueueFailure("zmx error")

        // Act
        let orphans = await backend.discoverOrphanSessions(excluding: [])

        // Assert
        #expect(orphans.isEmpty)
    }

    @Test

    func test_discoverOrphanSessions_includesDrawerSessions() async {
        // Arrange — mix of main and drawer sessions
        executor.enqueue(
            ProcessResult(
                exitCode: 0,
                stdout:
                    "agentstudio--abc--111--222\trunning\nagentstudio-d--aabb--ccdd\trunning\nuser-session\trunning",
                stderr: ""
            ))

        // Act — exclude the main session, drawer should appear as orphan
        let orphans = await backend.discoverOrphanSessions(excluding: ["agentstudio--abc--111--222"])

        // Assert
        #expect(orphans.count == 1)
        #expect(orphans.contains("agentstudio-d--aabb--ccdd"))
        #expect(!(orphans.contains("user-session")))
    }

    // MARK: - destroySessionById

    @Test

    func test_destroySessionById_sendsKillCommand() async throws {
        // Arrange
        executor.enqueueSuccess()

        // Act
        try await backend.destroySessionById("agentstudio--abc--def--ghi")

        // Assert
        let call = executor.calls.first!
        #expect(call.command == "/usr/local/bin/zmx")
        #expect(call.args == ["kill", "agentstudio--abc--def--ghi"])
    }

    @Test

    func test_destroySessionById_throwsOnFailure() async {
        // Arrange
        executor.enqueueFailure("session not found")

        // Act & Assert
        do {
            try await backend.destroySessionById("agentstudio--abc--def--ghi")
            Issue.record("Expected error")
        } catch {
            #expect(error is SessionBackendError)
        }
    }

    // MARK: - socketExists

    @Test

    func test_socketExists_returnsTrueWhenDirExists() {
        // Arrange — use a backend pointed at an existing temp dir
        let tempDir = FileManager.default.temporaryDirectory.path
        let tempBackend = ZmxBackend(executor: executor, zmxPath: "/usr/local/bin/zmx", zmxDir: tempDir)

        // Assert
        #expect(tempBackend.socketExists())
    }

    @Test

    func test_socketExists_returnsFalseWhenDirMissing() {
        // Arrange
        let badBackend = ZmxBackend(executor: executor, zmxPath: "/usr/local/bin/zmx", zmxDir: "/nonexistent/\(UUID())")

        // Assert
        #expect(!(badBackend.socketExists()))
    }

    // MARK: - ZMX_DIR Environment Propagation

    @Test

    func test_healthCheck_passesZmxDirEnv() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess("")

        // Act
        _ = await backend.healthCheck(handle)

        // Assert
        let call = executor.calls.first!
        #expect(call.environment?["ZMX_DIR"] == "/tmp/zmx-test")
    }

    @Test

    func test_destroyPaneSession_passesZmxDirEnv() async throws {
        // Arrange
        let handle = makePaneSessionHandle(id: "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--aabbccdd11223344")
        executor.enqueueSuccess()

        // Act
        try await backend.destroyPaneSession(handle)

        // Assert
        let call = executor.calls.first!
        #expect(call.environment?["ZMX_DIR"] == "/tmp/zmx-test")
    }

    @Test

    func test_destroySessionById_passesZmxDirEnv() async throws {
        // Arrange
        executor.enqueueSuccess()

        // Act
        try await backend.destroySessionById("agentstudio--abc--def--ghi")

        // Assert
        let call = executor.calls.first!
        #expect(call.environment?["ZMX_DIR"] == "/tmp/zmx-test")
    }
}
