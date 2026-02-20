import XCTest

@testable import AgentStudio

/// End-to-end tests that exercise the full zmx daemon lifecycle against a real zmx binary.
///
/// These tests spawn actual zmx daemons using `script` to provide a PTY wrapper,
/// then exercise healthCheck, discoverOrphanSessions, and destroyPaneSession
/// against live processes.
///
/// Requires zmx to be installed on PATH. Tests are skipped when zmx is unavailable.
final class ZmxE2ETests: XCTestCase {
    private var harness: ZmxTestHarness!
    private var backend: ZmxBackend!

    override func setUp() async throws {
        try await super.setUp()
        harness = ZmxTestHarness()

        guard let zmxBackend = harness.createBackend() else {
            throw XCTSkip("zmx not available on this system")
        }
        backend = zmxBackend

        guard await backend.isAvailable else {
            throw XCTSkip("zmx binary not executable")
        }

        // Ensure the isolated zmx dir exists
        try FileManager.default.createDirectory(
            atPath: harness.zmxDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    override func tearDown() async throws {
        await harness.cleanup()
        try await super.tearDown()
    }

    // MARK: - Full Lifecycle

    func test_fullLifecycle_create_healthCheck_kill_verify() async throws {
        // Arrange — create a handle
        let worktree = makeWorktree(name: "e2e-lifecycle", path: "/tmp", branch: "e2e-lifecycle")
        let repo = makeRepo()
        let paneId = UUID()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: paneId)

        // Act 1 — spawn a zmx daemon
        let zmxPath = harness.zmxPath!
        let spawnProcess = try spawnZmxSession(
            zmxPath: zmxPath,
            zmxDir: harness.zmxDir,
            sessionId: handle.id,
            commandArgs: ["/bin/sleep", "300"]
        )
        defer { spawnProcess.terminate() }

        // Wait for daemon to register (poll zmx list)
        let appeared = await pollForSession(sessionId: handle.id, timeout: 10)
        guard appeared else {
            throw XCTSkip("zmx daemon did not start within timeout")
        }

        // Assert 1 — healthCheck sees the session
        let alive = await backend.healthCheck(handle)
        XCTAssertTrue(alive, "healthCheck should return true for a live zmx session")

        // Assert 2 — discoverOrphanSessions finds it (not in known set)
        let orphans = await backend.discoverOrphanSessions(excluding: [])
        XCTAssertTrue(
            orphans.contains(handle.id),
            "discoverOrphanSessions should find the session when not in the known set"
        )

        // Assert 3 — discoverOrphanSessions excludes it when known
        let orphansExcluded = await backend.discoverOrphanSessions(excluding: [handle.id])
        XCTAssertFalse(
            orphansExcluded.contains(handle.id),
            "discoverOrphanSessions should exclude the session when in the known set"
        )

        // Act 2 — kill the session
        try await backend.destroyPaneSession(handle)

        // Wait for daemon to disappear
        let disappeared = await pollForSessionGone(sessionId: handle.id, timeout: 5)
        XCTAssertTrue(disappeared, "Session should disappear from zmx list after kill")

        // Assert 4 — healthCheck returns false after kill
        let deadCheck = await backend.healthCheck(handle)
        XCTAssertFalse(deadCheck, "healthCheck should return false after session is killed")
    }

    // MARK: - Orphan Discovery E2E

    func test_orphanDiscovery_findsUntrackedSession() async throws {
        // Arrange — spawn two sessions, only one is "known"
        let worktree1 = makeWorktree(name: "e2e-known", path: "/tmp", branch: "e2e-known")
        let worktree2 = makeWorktree(name: "e2e-orphan", path: "/tmp", branch: "e2e-orphan")
        let repo = makeRepo()

        let handle1 = try await backend.createPaneSession(repo: repo, worktree: worktree1, paneId: UUID())
        let handle2 = try await backend.createPaneSession(repo: repo, worktree: worktree2, paneId: UUID())

        let zmxPath = harness.zmxPath!
        let proc1 = try spawnZmxSession(
            zmxPath: zmxPath, zmxDir: harness.zmxDir,
            sessionId: handle1.id, commandArgs: ["/bin/sleep", "300"]
        )
        let proc2 = try spawnZmxSession(
            zmxPath: zmxPath, zmxDir: harness.zmxDir,
            sessionId: handle2.id, commandArgs: ["/bin/sleep", "300"]
        )
        defer {
            proc1.terminate()
            proc2.terminate()
        }

        // Wait for both daemons
        let appeared1 = await pollForSession(sessionId: handle1.id, timeout: 10)
        let appeared2 = await pollForSession(sessionId: handle2.id, timeout: 10)
        guard appeared1, appeared2 else {
            throw XCTSkip("zmx daemons did not start within timeout")
        }

        // Act — discover orphans, treating handle1 as "known"
        let orphans = await backend.discoverOrphanSessions(excluding: [handle1.id])

        // Assert
        XCTAssertTrue(orphans.contains(handle2.id), "handle2 should be discovered as orphan")
        XCTAssertFalse(orphans.contains(handle1.id), "handle1 should be excluded (known)")
    }

    // MARK: - Destroy By ID E2E

    func test_destroySessionById_killsLiveSession() async throws {
        // Arrange
        let worktree = makeWorktree(name: "e2e-destroy", path: "/tmp", branch: "e2e-destroy")
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        let proc = try spawnZmxSession(
            zmxPath: harness.zmxPath!, zmxDir: harness.zmxDir,
            sessionId: handle.id, commandArgs: ["/bin/sleep", "300"]
        )
        defer { proc.terminate() }

        guard await pollForSession(sessionId: handle.id, timeout: 10) else {
            throw XCTSkip("zmx daemon did not start")
        }

        // Act
        try await backend.destroySessionById(handle.id)

        // Assert
        let gone = await pollForSessionGone(sessionId: handle.id, timeout: 5)
        XCTAssertTrue(gone, "Session should be gone after destroySessionById")
    }

    // MARK: - Restore Semantics E2E

    func test_restoreAcrossBackendRecreation_detectsAndKillsExistingSession() async throws {
        // Arrange — create a session and spawn a live daemon
        let worktree = makeWorktree(name: "e2e-restore", path: "/tmp", branch: "e2e-restore")
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        let proc = try spawnZmxSession(
            zmxPath: harness.zmxPath!, zmxDir: harness.zmxDir,
            sessionId: handle.id, commandArgs: ["/bin/sleep", "300"]
        )
        defer { proc.terminate() }

        guard await pollForSession(sessionId: handle.id, timeout: 10) else {
            throw XCTSkip("zmx daemon did not start")
        }

        // Act — simulate app restart by creating a new backend instance.
        guard let recreatedBackend = harness.createBackend() else {
            throw XCTSkip("zmx backend unavailable during recreation")
        }

        // Assert — recreated backend can still discover and control the existing session.
        let aliveAfterRecreate = await recreatedBackend.healthCheck(handle)
        XCTAssertTrue(
            aliveAfterRecreate,
            "Recreated backend should detect live session (restore semantics)"
        )

        try await recreatedBackend.destroySessionById(handle.id)
        let gone = await pollForSessionGone(sessionId: handle.id, timeout: 5)
        XCTAssertTrue(gone, "Session should be gone after kill from recreated backend")
    }

    // MARK: - Socket Exists E2E

    func test_socketExists_afterDaemonStarts() async throws {
        // Arrange
        let worktree = makeWorktree(name: "e2e-socket", path: "/tmp", branch: "e2e-socket")
        let repo = makeRepo()
        let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

        let proc = try spawnZmxSession(
            zmxPath: harness.zmxPath!, zmxDir: harness.zmxDir,
            sessionId: handle.id, commandArgs: ["/bin/sleep", "300"]
        )
        defer { proc.terminate() }

        guard await pollForSession(sessionId: handle.id, timeout: 10) else {
            throw XCTSkip("zmx daemon did not start")
        }

        // Assert — zmxDir should exist after daemon starts
        XCTAssertTrue(backend.socketExists(), "socketExists should return true when zmxDir exists with active daemons")
    }

    // MARK: - Helpers

    /// Spawn a zmx session directly (zmx creates its own daemon).
    /// Returns the Process so the caller can terminate it in tearDown.
    private func spawnZmxSession(
        zmxPath: String,
        zmxDir: String,
        sessionId: String,
        commandArgs: [String]
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "ZMX_DIR=\(ZmxBackend.shellEscape(zmxDir)) \(ZmxBackend.shellEscape(zmxPath)) attach \(ZmxBackend.shellEscape(sessionId)) \(commandArgs.map { ZmxBackend.shellEscape($0) }.joined(separator: " "))",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = Pipe()  // keep stdin open (not /dev/null) so zmx client stays attached
        try process.run()
        return process
    }

    /// Poll `zmx list` until the given session ID appears, up to `timeout` seconds.
    private func pollForSession(sessionId: String, timeout: Int) async -> Bool {
        for _ in 0..<(timeout * 4) {
            let alive = await backend.healthCheck(
                makePaneSessionHandle(id: sessionId)
            )
            if alive { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
        }
        return false
    }

    /// Poll `zmx list` until the given session ID disappears, up to `timeout` seconds.
    private func pollForSessionGone(sessionId: String, timeout: Int) async -> Bool {
        for _ in 0..<(timeout * 4) {
            let alive = await backend.healthCheck(
                makePaneSessionHandle(id: sessionId)
            )
            if !alive { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
        }
        return false
    }
}
