import Foundation
import Testing

@testable import AgentStudio

/// End-to-end tests that exercise the full zmx daemon lifecycle against a real zmx binary.
///
/// These tests spawn actual zmx daemons using `/bin/sh` to provide a process wrapper,
/// then exercise healthCheck, discoverOrphanSessions, and destroyPaneSession
/// against live processes.
///
/// Requires zmx to be installed on PATH. Tests are skipped when zmx is unavailable.
@Suite(.serialized)
struct ZmxE2ETests {
    @Test("full lifecycle create healthCheck kill verify")
    func test_fullLifecycle_create_healthCheck_kill_verify() async throws {
        try await withRealBackend { harness, backend in
            // Arrange — create a handle
            let worktree = makeWorktree(name: "e2e-lifecycle", path: "/tmp", branch: "e2e-lifecycle")
            let repo = makeRepo()
            let paneId = UUID()
            let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: paneId)

            // Act 1 — spawn a zmx daemon
            guard let zmxPath = harness.zmxPath else {
                return
            }
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: handle.id,
                commandArgs: ["/bin/sleep", "300"]
            )

            // Wait for daemon to register (poll zmx list)
            let appeared = await pollForSession(
                backend: backend,
                sessionId: handle.id,
                timeout: 10
            )
            #expect(appeared, "zmx daemon should start within timeout")

            // Assert 1 — healthCheck sees the session
            #expect(
                await backend.healthCheck(handle),
                "healthCheck should return true for a live zmx session"
            )

            // Assert 2 — discoverOrphanSessions finds it (not in known set)
            let orphans = await backend.discoverOrphanSessions(excluding: [])
            #expect(
                orphans.contains(handle.id),
                "discoverOrphanSessions should find the session when not in the known set"
            )

            // Assert 3 — discoverOrphanSessions excludes it when known
            let orphansExcluded = await backend.discoverOrphanSessions(excluding: [handle.id])
            #expect(
                !orphansExcluded.contains(handle.id),
                "discoverOrphanSessions should exclude the session when in the known set"
            )

            // Act 2 — kill the session
            try await backend.destroyPaneSession(handle)

            // Wait for daemon to disappear
            let disappeared = await pollForSessionGone(
                backend: backend,
                sessionId: handle.id,
                timeout: 5
            )
            #expect(disappeared, "Session should disappear from zmx list after kill")

            // Assert 4 — healthCheck returns false after kill
            #expect(
                await backend.healthCheck(handle) == false,
                "healthCheck should return false after session is killed"
            )
        }
    }

    // MARK: - Orphan Discovery E2E

    @Test("orphan discovery finds untracked session")
    func test_orphanDiscovery_findsUntrackedSession() async throws {
        try await withRealBackend { harness, backend in
            // Arrange — spawn two sessions, only one is "known"
            let worktree1 = makeWorktree(name: "e2e-known", path: "/tmp", branch: "e2e-known")
            let worktree2 = makeWorktree(name: "e2e-orphan", path: "/tmp", branch: "e2e-orphan")
            let repo = makeRepo()

            let handle1 = try await backend.createPaneSession(repo: repo, worktree: worktree1, paneId: UUID())
            let handle2 = try await backend.createPaneSession(repo: repo, worktree: worktree2, paneId: UUID())

            guard let zmxPath = harness.zmxPath else {
                return
            }
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: handle1.id,
                commandArgs: ["/bin/sleep", "300"]
            )
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: handle2.id,
                commandArgs: ["/bin/sleep", "300"]
            )

            // Wait for both daemons
            let appeared1 = await pollForSession(
                backend: backend,
                sessionId: handle1.id,
                timeout: 10
            )
            let appeared2 = await pollForSession(
                backend: backend,
                sessionId: handle2.id,
                timeout: 10
            )
            #expect(appeared1, "zmx daemon 1 should start within timeout")
            #expect(appeared2, "zmx daemon 2 should start within timeout")

            // Act — discover orphans, treating handle1 as "known"
            let orphans = await backend.discoverOrphanSessions(excluding: [handle1.id])

            // Assert
            #expect(orphans.contains(handle2.id), "handle2 should be discovered as orphan")
            #expect(!orphans.contains(handle1.id), "handle1 should be excluded (known)")
        }
    }

    // MARK: - Destroy By ID E2E

    @Test("destroy session by id kills live session")
    func test_destroySessionById_killsLiveSession() async throws {
        try await withRealBackend { harness, backend in
            // Arrange
            let worktree = makeWorktree(name: "e2e-destroy", path: "/tmp", branch: "e2e-destroy")
            let repo = makeRepo()
            let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

            guard let zmxPath = harness.zmxPath else {
                return
            }
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: handle.id,
                commandArgs: ["/bin/sleep", "300"]
            )

            let appeared = await pollForSession(
                backend: backend,
                sessionId: handle.id,
                timeout: 10
            )
            #expect(appeared, "zmx daemon should start before destroy")

            // Act
            try await backend.destroySessionById(handle.id)

            // Assert
            let gone = await pollForSessionGone(
                backend: backend,
                sessionId: handle.id,
                timeout: 5
            )
            #expect(gone, "Session should be gone after destroySessionById")
        }
    }

    // MARK: - Restore Semantics E2E

    @Test("restore across backend recreation detects and kills existing session")
    func test_restoreAcrossBackendRecreation_detectsAndKillsExistingSession() async throws {
        try await withRealBackend { harness, backend in
            // Arrange — create a session and spawn a live daemon
            let worktree = makeWorktree(name: "e2e-restore", path: "/tmp", branch: "e2e-restore")
            let repo = makeRepo()
            let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

            guard let zmxPath = harness.zmxPath else {
                return
            }
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: handle.id,
                commandArgs: ["/bin/sleep", "300"]
            )

            let appeared = await pollForSession(
                backend: backend,
                sessionId: handle.id,
                timeout: 10
            )
            #expect(appeared, "zmx daemon should start before recreation checks")

            // Act — simulate app restart by creating a new backend instance.
            guard let recreatedBackend = harness.createBackend() else {
                return
            }

            // Assert — recreated backend can still discover and control the existing session.
            #expect(
                await recreatedBackend.healthCheck(handle),
                "Recreated backend should detect live session (restore semantics)"
            )

            try await recreatedBackend.destroySessionById(handle.id)
            let gone = await pollForSessionGone(
                backend: recreatedBackend,
                sessionId: handle.id,
                timeout: 5
            )
            #expect(gone, "Session should be gone after kill from recreated backend")
        }
    }

    // MARK: - Socket Exists E2E

    @Test("socket exists after daemon starts")
    func test_socketExists_afterDaemonStarts() async throws {
        try await withRealBackend { harness, backend in
            // Arrange
            let worktree = makeWorktree(name: "e2e-socket", path: "/tmp", branch: "e2e-socket")
            let repo = makeRepo()
            let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())

            guard let zmxPath = harness.zmxPath else {
                return
            }
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: handle.id,
                commandArgs: ["/bin/sleep", "300"]
            )

            let appeared = await pollForSession(
                backend: backend,
                sessionId: handle.id,
                timeout: 10
            )
            #expect(appeared, "zmx daemon should start before checking socket")

            // Assert — zmxDir should exist after daemon starts
            #expect(
                backend.socketExists(),
                "socketExists should return true when zmxDir exists with active daemons"
            )
        }
    }

    // MARK: - Helpers

    /// Run backend setup and guaranteed cleanup for each zmx E2E case.
    private func withRealBackend(
        _ test: @escaping (ZmxTestHarness, ZmxBackend) async throws -> Void
    ) async throws {
        let harness = ZmxTestHarness()
        guard let backend = harness.createBackend(),
            await backend.isAvailable
        else {
            return
        }

        try FileManager.default.createDirectory(
            atPath: harness.zmxDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        do {
            try await withTimeout(seconds: 30) {
                try await test(harness, backend)
            }
            await harness.cleanup()
        } catch {
            await harness.cleanup()
            throw error
        }
    }

    private enum TimeoutError: Error {
        case exceeded
    }

    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Double(seconds)))
                throw TimeoutError.exceeded
            }

            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func pollForSession(
        backend: ZmxBackend,
        sessionId: String,
        timeout: Int
    ) async -> Bool {
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
    private func pollForSessionGone(
        backend: ZmxBackend,
        sessionId: String,
        timeout: Int
    ) async -> Bool {
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
