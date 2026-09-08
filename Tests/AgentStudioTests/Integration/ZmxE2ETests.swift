import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

/// End-to-end tests that exercise the full zmx daemon lifecycle against a real zmx binary.
///
/// These tests spawn actual zmx daemons using `/bin/sh` to provide a process wrapper,
/// then exercise healthCheck, discoverOrphanSessions, and destroyPaneSession
/// against live processes.
///
/// Requires zmx to be installed on PATH. Tests are skipped when zmx is unavailable.
extension E2ESerializedTests {
    @Suite(.serialized)
    struct ZmxE2ETests {
        @Test("inspection failures are not reported as absence", arguments: [false, true])
        func inspectionFailureIsNotAbsence(permissionDenied: Bool) async throws {
            try await withRealBackend { harness, backend in
                let sessionID = ZmxSessionID.generateUUIDv7()
                defer {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: harness.zmxDir)
                }
                if permissionDenied {
                    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: harness.zmxDir)
                } else {
                    try Data().write(to: URL(fileURLWithPath: "\(harness.zmxDir)/\(sessionID.rawValue)"))
                }
                await #expect(throws: ZmxSessionControlFailure.unavailable) {
                    try await backend.observeSessionIdentity(sessionID)
                }
            }
        }

        @Test("an already absent session needs no kill", arguments: [false, true])
        func absentSessionNeedsNoKill(wasRunning: Bool) async throws {
            try await withRealBackend { harness, backend in
                let sessionID = ZmxSessionID.generateUUIDv7()
                if wasRunning {
                    _ = try harness.spawnZmxSession(
                        zmxPath: try #require(harness.zmxPath), sessionId: sessionID.rawValue,
                        commandArgs: ["/bin/sleep", "300"])
                    try #require(await harness.waitForSessionSocket(sessionId: sessionID.rawValue, exists: true))
                    try await backend.destroySessionByID(sessionID)
                    try #require(await harness.waitForSessionSocket(sessionId: sessionID.rawValue, exists: false))
                }
                let evidence: Data? = try await backend.observeSessionIdentity(sessionID)
                #expect(evidence == nil)
            }
        }

        @Test("observed identity addresses one real daemon and rejects a mismatched cleanup")
        func observedIdentityProtectsTheRunningSession() async throws {
            try await withRealBackend { harness, backend in
                let sessionID = ZmxSessionID.generateUUIDv7()
                _ = try harness.spawnZmxSession(
                    zmxPath: try #require(harness.zmxPath), sessionId: sessionID.rawValue,
                    commandArgs: ["/bin/sleep", "300"])
                try #require(await harness.waitForSessionSocket(sessionId: sessionID.rawValue, exists: true))

                let encoded = try #require(try await backend.observeSessionIdentity(sessionID))
                let identity = try ZmxSessionIdentity.decode(encoded)
                #expect(identity.daemon.pid != identity.terminalLeader.pid)
                #expect(identity.processGroupID == identity.terminalLeader.pid)
                let mismatch = ZmxSessionIdentity(
                    version: identity.version, bootID: identity.bootID, daemon: identity.daemon,
                    terminalLeader: identity.terminalLeader, processGroupID: identity.processGroupID,
                    sessionCreatedAt: identity.sessionCreatedAt + 1)
                await #expect(throws: ZmxSessionControlFailure.identityMismatch) {
                    try await backend.retireVerifiedSession(sessionID, expectedIdentity: mismatch.encoded())
                }
                #expect(await backend.sessionExists(.init(id: sessionID)))
            }
        }

        @Test("verified cleanup ends the exact real session and reconciles a repeated attempt")
        func verifiedCleanupEndsTheOriginalSession() async throws {
            try await withRealBackend { harness, backend in
                let sessionID = ZmxSessionID.generateUUIDv7()
                _ = try harness.spawnZmxSession(
                    zmxPath: try #require(harness.zmxPath), sessionId: sessionID.rawValue,
                    commandArgs: ["/bin/sleep", "300"])
                try #require(await harness.waitForSessionSocket(sessionId: sessionID.rawValue, exists: true))
                let identity = try #require(try await backend.observeSessionIdentity(sessionID))

                _ = try await backend.retireVerifiedSession(sessionID, expectedIdentity: identity)
                try #require(await harness.waitForSessionSocket(sessionId: sessionID.rawValue, exists: false))
                // Socket removal precedes final process reaping. Wait for the stronger
                // completion observation, rather than treating unlink as termination.
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                var completed = false
                while ContinuousClock.now < deadline {
                    do {
                        completed =
                            try await backend.retireVerifiedSession(sessionID, expectedIdentity: identity) == .completed
                        if completed { break }
                    } catch ZmxSessionControlFailure.processUnverifiable {
                        // Kernel inspection can race final process reaping.
                    } catch ZmxSessionControlFailure.unavailable {
                        // The endpoint can disappear between inspection and connection.
                    }
                    await Task.yield()
                }
                #expect(completed, "Original processes and process group must exit, not just remove their socket")
            }
        }

        @Test("full lifecycle create healthCheck kill verify")
        func test_fullLifecycle_create_healthCheck_kill_verify() async throws {
            try await withRealBackend { harness, backend in
                // Arrange — create a handle
                let handle = try await backend.createPaneSession(sessionID: .generateUUIDv7())
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id.rawValue,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id.rawValue,
                    exists: true
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

                let disappeared = await harness.waitForSessionSocket(
                    sessionId: handle.id.rawValue,
                    exists: false,
                    timeout: .seconds(5)
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
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                let handle1 = try await backend.createPaneSession(sessionID: .generateUUIDv7())
                let handle2 = try await backend.createPaneSession(sessionID: .generateUUIDv7())
                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle1.id.rawValue,
                    commandArgs: ["/bin/sleep", "300"]
                )
                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle2.id.rawValue,
                    commandArgs: ["/bin/sleep", "300"]
                )

                // Wait for both daemons
                let appeared1 = await harness.waitForSessionSocket(
                    sessionId: handle1.id.rawValue,
                    exists: true
                )
                let appeared2 = await harness.waitForSessionSocket(
                    sessionId: handle2.id.rawValue,
                    exists: true
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
                let handle = try await backend.createPaneSession(sessionID: .generateUUIDv7())
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id.rawValue,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id.rawValue,
                    exists: true
                )
                #expect(appeared, "zmx daemon should start before destroy")

                // Act
                try await backend.destroySessionByID(handle.id)

                // Assert
                let gone = await harness.waitForSessionSocket(
                    sessionId: handle.id.rawValue,
                    exists: false,
                    timeout: .seconds(5)
                )
                #expect(gone, "Session should be gone after destroySessionById")
            }
        }

        // MARK: - Restore Semantics E2E

        @Test("restore across backend recreation detects and kills existing session")
        func test_restoreAcrossBackendRecreation_detectsAndKillsExistingSession() async throws {
            try await withRealBackend { harness, backend in
                // Arrange — create a session and spawn a live daemon
                let handle = try await backend.createPaneSession(sessionID: .generateUUIDv7())
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id.rawValue,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id.rawValue,
                    exists: true
                )
                #expect(appeared, "zmx daemon should start before recreation checks")

                // Act — simulate app restart by creating a new backend instance.
                let recreatedBackend = try #require(
                    harness.createBackend(),
                    "Expected recreated backend for restore semantics test"
                )

                // Assert — recreated backend can still discover and control the existing session.
                #expect(
                    await recreatedBackend.healthCheck(handle),
                    "Recreated backend should detect live session (restore semantics)"
                )

                try await recreatedBackend.destroySessionByID(handle.id)
                let gone = await harness.waitForSessionSocket(
                    sessionId: handle.id.rawValue,
                    exists: false,
                    timeout: .seconds(5)
                )
                #expect(gone, "Session should be gone after kill from recreated backend")
            }
        }

        // MARK: - Socket Exists E2E

        @Test("socket exists after daemon starts")
        func test_socketExists_afterDaemonStarts() async throws {
            try await withRealBackend { harness, backend in
                // Arrange
                let handle = try await backend.createPaneSession(sessionID: .generateUUIDv7())
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id.rawValue,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id.rawValue,
                    exists: true
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
            _ test: @escaping @Sendable (ZmxTestHarness, ZmxBackend) async throws -> Void
        ) async throws {
            let harness = ZmxTestHarness()
            let backend = try #require(
                harness.createBackend(),
                "ZmxTestHarness failed to resolve zmx path; integration test requires zmx"
            )
            try #require(await backend.isAvailable, "zmx is unavailable in this environment")

            try FileManager.default.createDirectory(
                atPath: harness.zmxDir,
                withIntermediateDirectories: true,
                attributes: nil
            )

            var bodyError: (any Error)?
            do {
                try await test(harness, backend)
            } catch {
                bodyError = error
            }
            let cleanupOutcome = await harness.cleanup()
            if let bodyError {
                if !cleanupOutcome.succeeded {
                    Issue.record("zmx cleanup also failed: \(cleanupOutcome.diagnostics)")
                }
                throw bodyError
            }
            if !cleanupOutcome.succeeded {
                throw ZmxTestHarness.CleanupError(outcome: cleanupOutcome)
            }
        }
    }
}
