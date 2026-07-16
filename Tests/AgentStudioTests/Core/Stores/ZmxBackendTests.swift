import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class ZmxBackendTests {
    private var executor: MockProcessExecutor!
    private var backend: ZmxBackend!

    init() {
        executor = MockProcessExecutor()
        backend = ZmxBackend(
            executor: executor,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: "/tmp/zmx-test",
            retryPolicy: .singleAttempt
        )
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

    // MARK: - createPaneSession

    @Test

    func test_createPaneSession_returnsHandleWithoutCLICall() async throws {
        // Arrange
        let sessionID = ZmxSessionID.generateUUIDv7()
        // Use a real temp dir so createDirectory succeeds
        let tempZmxDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zmx-test-\(UUID().uuidString.prefix(8))").path
        let tempBackend = ZmxBackend(
            executor: executor,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: tempZmxDir
        )
        // Act
        let handle = try await tempBackend.createPaneSession(sessionID: sessionID)

        // Assert — no CLI calls (zmx auto-creates on attach)
        #expect(executor.calls.isEmpty)
        #expect(handle.id == sessionID)
        #expect(UUIDv7.isV7(try #require(UUID(uuidString: handle.id.rawValue))))
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
            id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344"
        )

        // Act
        let cmd = backend.attachCommand(for: handle)

        // Assert
        #expect(!(cmd.contains("ZMX_DIR=")))
        #expect(cmd.hasPrefix("\"/usr/local/bin/zmx\""))
        #expect(cmd.contains("attach"))
        #expect(cmd.contains("\"as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344\""))
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
            id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344"
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
            sessionID: restoredSessionID("as-abc-def-ghi"),
            shell: "/bin/zsh"
        )

        // Assert
        #expect(cmd == "'/opt/homebrew/bin/zmx' attach 'as-abc-def-ghi' '/bin/zsh' -i -l")
    }

    // MARK: - Shell Escape

    @Test

    func test_shellEscape_simplePath() {
        #expect(ZmxBackend.shellEscape("/usr/bin/zmx") == "'/usr/bin/zmx'")
    }

    @Test

    func test_shellEscape_pathWithSpaces() {
        #expect(ZmxBackend.shellEscape("/Users/test user/bin/zmx") == "'/Users/test user/bin/zmx'")
    }

    @Test

    func test_shellEscape_pathWithSingleQuote() {
        #expect(ZmxBackend.shellEscape("/tmp/it's") == "'/tmp/it'\\''s'")
    }

    @Test

    func test_shellEscape_escapesDollar() {
        #expect(ZmxBackend.shellEscape("/tmp/$HOME") == "'/tmp/$HOME'")
    }

    @Test

    func test_shellEscape_escapesBacktick() {
        #expect(ZmxBackend.shellEscape("/tmp/`pwd`") == "'/tmp/`pwd`'")
    }

    @Test

    func test_shellEscape_escapesDoubleQuote() {
        #expect(ZmxBackend.shellEscape("/tmp/\"quoted\"") == "'/tmp/\"quoted\"'")
    }

    @Test

    func test_shellEscape_escapesBackslash() {
        #expect(ZmxBackend.shellEscape("/tmp/foo\\bar") == "'/tmp/foo\\bar'")
    }

    @Test

    func test_shellEscape_escapesHistoryBang() {
        #expect(ZmxBackend.shellEscape("/tmp/bang!") == "'/tmp/bang!'")
    }

    @Test
    func test_shellEscape_roundTripsOpaqueArgumentsThroughZsh() throws {
        // Arrange
        let opaqueArguments = [
            "legacy!id",
            "single'quote",
            "double\"quote",
            "back\\slash",
            "white space",
            "$HOME",
            "`pwd`",
        ]
        let command = "printf '%s\\n' \(opaqueArguments.map(ZmxBackend.shellEscape).joined(separator: " "))"
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = outputPipe

        // Act
        try process.run()
        process.waitUntilExit()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let decodedArguments = try #require(String(data: output, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast()
            .map(String.init)

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(decodedArguments == opaqueArguments)
    }

    // MARK: - healthCheck

    @Test

    func test_healthCheck_returnsTrue_whenSessionInList() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
        executor.enqueueSuccess("as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344\trunning\t123")

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
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
        executor.enqueueSuccess("some-other-session\trunning\t456")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        #expect(!(alive))
    }

    @Test

    func test_healthCheck_returnsFalse_onCommandFailure() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
        executor.enqueueFailure("zmx: error")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        #expect(!(alive))
    }

    @Test

    func test_healthCheck_returnsFalse_onEmptyOutput() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
        executor.enqueueSuccess("")

        // Act
        let alive = await backend.healthCheck(handle)

        // Assert
        #expect(!(alive))
    }

    @Test
    func test_healthCheck_retriesThreeAttempts_thenSucceeds() async {
        // Arrange
        let localExecutor = MockProcessExecutor()
        let retryBackend = ZmxBackend(
            executor: localExecutor,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: "/tmp/zmx-test",
            retryPolicy: .init(maxAttempts: 3, backoffs: [])
        )
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
        localExecutor.enqueueFailure("temporary zmx list failure")
        localExecutor.enqueueFailure("temporary zmx list failure")
        localExecutor.enqueueSuccess("as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344\trunning\t123")

        // Act
        let alive = await retryBackend.healthCheck(handle)

        // Assert
        #expect(alive)
        #expect(localExecutor.calls.count == 3)
    }

    // MARK: - destroyPaneSession

    @Test

    func test_destroyPaneSession_sendsKillCommand() async throws {
        // Arrange
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
        executor.enqueueSuccess()

        // Act
        try await backend.destroyPaneSession(handle)

        // Assert
        let call = executor.calls.first!
        #expect(call.command == "/usr/local/bin/zmx")
        #expect(call.args == ["kill", handle.id.rawValue])
    }

    @Test

    func test_destroyPaneSession_throwsOnFailure() async {
        // Arrange
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
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
                    "as-abc-111-222\trunning\nas-def-333-444\trunning\nuser-session\trunning\nas-ghi-555-666\trunning",
                stderr: ""
            ))

        // Act
        let orphans = await backend.discoverOrphanSessions(
            excluding: [restoredSessionID("as-abc-111-222")]
        )

        // Assert
        #expect(orphans.count == 2)
        #expect(orphans.contains(restoredSessionID("as-def-333-444")))
        #expect(orphans.contains(restoredSessionID("as-ghi-555-666")))
        #expect(!orphans.contains(restoredSessionID("user-session")))
    }

    @Test
    func test_discoverOrphanSessions_parsesZmx042KeyValueFormat() async {
        // Arrange
        executor.enqueue(
            ProcessResult(
                exitCode: 0,
                stdout:
                    "name=as-abc-111-222\tpid=123\tclients=0\tcreated=1774059493\tstart_dir=/tmp\tcmd=/bin/sleep 300\nname=as-d--aabb--ccdd\tpid=456\tclients=0\tcreated=1774059494\tstart_dir=/tmp\tcmd=/bin/sleep 300\nname=user-session\tpid=789\tclients=0",
                stderr: ""
            ))

        // Act
        let orphans = await backend.discoverOrphanSessions(
            excluding: [restoredSessionID("as-abc-111-222")]
        )

        // Assert
        #expect(orphans.count == 1)
        #expect(orphans.contains(restoredSessionID("as-d--aabb--ccdd")))
        #expect(!orphans.contains(restoredSessionID("user-session")))
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
                    "as-abc-111-222\trunning\nas-d--aabb--ccdd\trunning\nuser-session\trunning",
                stderr: ""
            ))

        // Act — exclude the main session, drawer should appear as orphan
        let orphans = await backend.discoverOrphanSessions(
            excluding: [restoredSessionID("as-abc-111-222")]
        )

        // Assert
        #expect(orphans.count == 1)
        #expect(orphans.contains(restoredSessionID("as-d--aabb--ccdd")))
        #expect(!orphans.contains(restoredSessionID("user-session")))
    }

    // MARK: - destroySessionByID

    @Test

    func test_destroySessionById_sendsKillCommand() async throws {
        // Arrange
        executor.enqueueSuccess()

        // Act
        try await backend.destroySessionByID(restoredSessionID("as-abc-def-ghi"))

        // Assert
        let call = executor.calls.first!
        #expect(call.command == "/usr/local/bin/zmx")
        #expect(call.args == ["kill", "as-abc-def-ghi"])
    }

    @Test

    func test_destroySessionById_throwsOnFailure() async {
        // Arrange
        executor.enqueueFailure("session not found")

        // Act & Assert
        do {
            try await backend.destroySessionByID(restoredSessionID("as-abc-def-ghi"))
            Issue.record("Expected error")
        } catch {
            #expect(error is SessionBackendError)
        }
    }

    @Test
    func test_destroySessionById_retriesThreeAttempts_thenSucceeds() async throws {
        // Arrange
        let localExecutor = MockProcessExecutor()
        let retryBackend = ZmxBackend(
            executor: localExecutor,
            zmxPath: "/usr/local/bin/zmx",
            zmxDir: "/tmp/zmx-test",
            retryPolicy: .init(maxAttempts: 3, backoffs: [])
        )
        localExecutor.enqueueFailure("temporary kill failure")
        localExecutor.enqueueFailure("temporary kill failure")
        localExecutor.enqueueSuccess()

        // Act
        try await retryBackend.destroySessionByID(restoredSessionID("as-abc-def-ghi"))

        // Assert
        #expect(localExecutor.calls.count == 3)
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
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
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
        let handle = makePaneSessionHandle(id: "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-aabbccdd11223344")
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
        try await backend.destroySessionByID(restoredSessionID("as-abc-def-ghi"))

        // Assert
        let call = executor.calls.first!
        #expect(call.environment?["ZMX_DIR"] == "/tmp/zmx-test")
    }

    private func makePaneSessionHandle(id: String) -> PaneSessionHandle {
        PaneSessionHandle(id: restoredSessionID(id))
    }

    private func restoredSessionID(_ storedText: String) -> ZmxSessionID {
        guard let sessionID = ZmxSessionID(restoring: storedText) else {
            preconditionFailure("test fixture zmx identity must be nonblank")
        }
        return sessionID
    }
}
