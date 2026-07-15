import Foundation
import GRDB
import Testing

@testable import AgentStudio

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
        @Test("full lifecycle create healthCheck kill verify")
        func test_fullLifecycle_create_healthCheck_kill_verify() async throws {
            try await withRealBackend { harness, backend in
                // Arrange — create a handle
                let worktree = makeWorktree(name: "e2e-lifecycle", path: "/tmp")
                let repo = makeRepo()
                let paneId = UUID()
                let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: paneId)
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id,
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
                    sessionId: handle.id,
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
                let worktree1 = makeWorktree(name: "e2e-known", path: "/tmp")
                let worktree2 = makeWorktree(name: "e2e-orphan", path: "/tmp")
                let repo = makeRepo()
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                let handle1 = try await backend.createPaneSession(repo: repo, worktree: worktree1, paneId: UUID())
                let handle2 = try await backend.createPaneSession(repo: repo, worktree: worktree2, paneId: UUID())
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
                let appeared1 = await harness.waitForSessionSocket(
                    sessionId: handle1.id,
                    exists: true
                )
                let appeared2 = await harness.waitForSessionSocket(
                    sessionId: handle2.id,
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
                let worktree = makeWorktree(name: "e2e-destroy", path: "/tmp")
                let repo = makeRepo()
                let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id,
                    exists: true
                )
                #expect(appeared, "zmx daemon should start before destroy")

                // Act
                try await backend.destroySessionById(handle.id)

                // Assert
                let gone = await harness.waitForSessionSocket(
                    sessionId: handle.id,
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
                let worktree = makeWorktree(name: "e2e-restore", path: "/tmp")
                let repo = makeRepo()
                let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id,
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

                try await recreatedBackend.destroySessionById(handle.id)
                let gone = await harness.waitForSessionSocket(
                    sessionId: handle.id,
                    exists: false,
                    timeout: .seconds(5)
                )
                #expect(gone, "Session should be gone after kill from recreated backend")
            }
        }

        // MARK: - Phase-A Smoke

        @MainActor
        @Test("phase A smoke hydrates roamed legacy pane without killing live zmx session")
        func test_phaseASmoke_hydratesLegacyRoamedPaneBeforeCleanup() async throws {
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

            do {
                _ = try await runPhaseASmoke(harness: harness, backend: backend)
                await harness.cleanup()
            } catch {
                await harness.cleanup()
                throw error
            }
        }

        @MainActor
        @Test("startup reconciliation preserves two workspaces sharing one zmx dir")
        func test_startupReconciliation_whenTwoWorkspacesShareZmxDir_preservesAllSessions() async throws {
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

            do {
                let firstWorkspaceSessions = try await runPhaseASmoke(harness: harness, backend: backend)
                let secondWorkspaceSessions = try await runPhaseASmoke(harness: harness, backend: backend)

                for sessionId in [
                    firstWorkspaceSessions.birthHandle.id,
                    firstWorkspaceSessions.unrelatedSessionId,
                    secondWorkspaceSessions.birthHandle.id,
                    secondWorkspaceSessions.unrelatedSessionId,
                ] {
                    #expect(
                        await harness.waitForSessionSocket(
                            sessionId: sessionId,
                            exists: true,
                            timeout: .seconds(5)
                        ),
                        "startup reconciliation must not destroy live session \(sessionId)"
                    )
                }

                let firstHistory = try await harness.sessionHistory(sessionId: firstWorkspaceSessions.birthHandle.id)
                let secondHistory = try await harness.sessionHistory(sessionId: secondWorkspaceSessions.birthHandle.id)
                #expect(firstHistory.contains(firstWorkspaceSessions.scrollbackMarker))
                #expect(secondHistory.contains(secondWorkspaceSessions.scrollbackMarker))

                await harness.cleanup()
            } catch {
                await harness.cleanup()
                throw error
            }
        }

        @MainActor
        @discardableResult
        private func runPhaseASmoke(
            harness: ZmxTestHarness,
            backend: ZmxBackend
        ) async throws -> ZmxPhaseASmokeSessions {
            // Arrange — a legacy pre-anchor pane was born in worktree A, roamed to
            // worktree B, and still has a live zmx daemon under its birth id.
            let workspaceId = UUID()
            let fixture = try makeZmxE2ESQLiteFixture(workspaceId: workspaceId)
            let identityAtom = WorkspaceIdentityAtom()
            identityAtom.hydrate(
                workspaceId: workspaceId,
                workspaceName: "zmx Phase A Smoke",
                createdAt: Date(timeIntervalSince1970: 1_700_000_300)
            )
            var recoveryEvents: [PersistenceRecoveryEvent] = []
            let store = WorkspaceStore(
                workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner(),
                identityAtom: identityAtom,
                persistor: WorkspacePersistor(
                    workspacesDir: URL(filePath: harness.zmxDir).appending(path: "workspaces")
                ),
                sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend),
                recoveryReporter: { event in recoveryEvents.append(event) }
            )
            let delegate = AppDelegate()
            delegate.store = store

            let birthURL = URL(filePath: harness.zmxDir).appending(path: "birth")
            let roamedURL = URL(filePath: harness.zmxDir).appending(path: "roamed")
            try FileManager.default.createDirectory(at: birthURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: roamedURL, withIntermediateDirectories: true)

            let birthRepo = store.addRepo(at: birthURL)
            let birthWorktree = try #require(birthRepo.worktrees.first)
            let roamedRepo = store.addRepo(at: roamedURL)
            let roamedWorktree = try #require(roamedRepo.worktrees.first)
            let legacyPaneState = store.paneAtom.createPane(
                content: .terminal(.init(provider: .zmx, lifetime: .persistent, zmxSessionId: nil)),
                metadata: PaneMetadata(
                    launchDirectory: birthWorktree.path,
                    title: "Legacy Roamed",
                    facets: PaneContextFacets(
                        repoId: roamedRepo.id,
                        worktreeId: roamedWorktree.id,
                        cwd: roamedWorktree.path
                    )
                ),
                anchorZmxSessionIfNeeded: false
            )
            let legacyPane = try #require(store.paneAtom.pane(legacyPaneState.id))
            store.appendTab(Tab(paneId: legacyPane.id, name: "Legacy"))

            let sessions = try await startPhaseASmokeSessions(
                harness: harness,
                backend: backend,
                paneContext: ZmxPhaseASmokePaneContext(
                    birthRepo: birthRepo,
                    birthWorktree: birthWorktree,
                    roamedRepo: roamedRepo,
                    roamedWorktree: roamedWorktree,
                    legacyPane: legacyPane
                )
            )

            // Act — simulate boot reconciliation on the next launch with the real backend.
            _ = try await delegate.runZmxStartupSessionReconciliation(
                inventory: backend,
                terminalRestoreRuntime: TerminalRestoreRuntime(
                    sessionConfiguration: SessionConfiguration(
                        isEnabled: true,
                        zmxPath: sessions.zmxPath,
                        zmxDir: harness.zmxDir,
                        healthCheckInterval: 30,
                        maxCheckpointAge: 60
                    )
                )
            )

            // Assert — the live birth daemon is adopted and protected; the
            // unrelated zmx session is not destroyed during boot reconciliation.
            #expect(store.pane(legacyPane.id)?.terminalState?.zmxSessionId == sessions.birthHandle.id)
            #expect(store.pane(legacyPane.id)?.terminalState?.zmxSessionId != sessions.roamedDerivedSessionId)
            #expect(await backend.healthCheck(sessions.birthHandle))
            let birthHistory = try await harness.sessionHistory(sessionId: sessions.birthHandle.id)
            #expect(birthHistory.contains(sessions.scrollbackMarker))
            #expect(
                await harness.waitForSessionSocket(
                    sessionId: sessions.unrelatedSessionId,
                    exists: true,
                    timeout: .seconds(5)
                )
            )
            #expect(recoveryEvents.isEmpty)

            try assertPersistedZmxSessionId(
                fixture: fixture,
                workspaceId: workspaceId,
                paneId: legacyPane.id,
                expectedSessionId: sessions.birthHandle.id
            )
            return sessions
        }

        private func startPhaseASmokeSessions(
            harness: ZmxTestHarness,
            backend: ZmxBackend,
            paneContext: ZmxPhaseASmokePaneContext
        ) async throws -> ZmxPhaseASmokeSessions {
            let birthHandle = try await backend.createPaneSession(
                repo: paneContext.birthRepo,
                worktree: paneContext.birthWorktree,
                paneId: paneContext.legacyPane.id
            )
            let roamedDerivedSessionId = ZmxBackend.sessionId(
                repoStableKey: paneContext.roamedRepo.stableKey,
                worktreeStableKey: paneContext.roamedWorktree.stableKey,
                paneId: paneContext.legacyPane.id
            )
            let unrelatedSessionId = ZmxBackend.sessionId(
                repoStableKey: "1111111111111111",
                worktreeStableKey: "2222222222222222",
                paneId: UUID()
            )
            let scrollbackMarker = "agentstudio-zmx-scrollback-\(paneContext.legacyPane.id.uuidString)"

            let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: birthHandle.id,
                commandArgs: ["/bin/sh", "-lc", "printf '%s\\n' '\(scrollbackMarker)'; sleep 300"]
            )
            _ = try harness.spawnZmxSession(
                zmxPath: zmxPath,
                sessionId: unrelatedSessionId,
                commandArgs: ["/bin/sleep", "300"]
            )
            #expect(await harness.waitForSessionSocket(sessionId: birthHandle.id, exists: true))
            #expect(await harness.waitForSessionSocket(sessionId: unrelatedSessionId, exists: true))
            #expect(
                await harness.waitForSessionHistory(
                    sessionId: birthHandle.id,
                    containing: scrollbackMarker
                )
            )
            return .init(
                birthHandle: birthHandle,
                roamedDerivedSessionId: roamedDerivedSessionId,
                unrelatedSessionId: unrelatedSessionId,
                scrollbackMarker: scrollbackMarker,
                zmxPath: zmxPath
            )
        }

        private func assertPersistedZmxSessionId(
            fixture: ZmxE2ESQLiteFixture,
            workspaceId: UUID,
            paneId: UUID,
            expectedSessionId: String
        ) throws {
            let storedPanes = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId).panes
            let storedPane = try #require(storedPanes.first { $0.id == paneId })
            guard case .terminal(_, _, let storedSessionId) = storedPane.content else {
                Issue.record("Expected terminal content for legacy pane")
                return
            }
            #expect(storedSessionId == expectedSessionId)
        }

        // MARK: - Socket Exists E2E

        @Test("socket exists after daemon starts")
        func test_socketExists_afterDaemonStarts() async throws {
            try await withRealBackend { harness, backend in
                // Arrange
                let worktree = makeWorktree(name: "e2e-socket", path: "/tmp")
                let repo = makeRepo()
                let handle = try await backend.createPaneSession(repo: repo, worktree: worktree, paneId: UUID())
                let zmxPath = try #require(harness.zmxPath, "Expected zmx path to be available")

                _ = try harness.spawnZmxSession(
                    zmxPath: zmxPath,
                    sessionId: handle.id,
                    commandArgs: ["/bin/sleep", "300"]
                )

                let appeared = await harness.waitForSessionSocket(
                    sessionId: handle.id,
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

            do {
                try await test(harness, backend)
                await harness.cleanup()
            } catch {
                await harness.cleanup()
                throw error
            }
        }
    }
}

private struct ZmxE2ESQLiteFixture {
    let coreQueue: DatabaseQueue
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let backend: WorkspaceSQLiteStoreBackend
}

private struct ZmxPhaseASmokePaneContext {
    let birthRepo: Repo
    let birthWorktree: Worktree
    let roamedRepo: Repo
    let roamedWorktree: Worktree
    let legacyPane: Pane
}

private struct ZmxPhaseASmokeSessions {
    let birthHandle: PaneSessionHandle
    let roamedDerivedSessionId: String
    let unrelatedSessionId: String
    let scrollbackMarker: String
    let zmxPath: String
}

@MainActor
private func makeZmxE2ESQLiteFixture(workspaceId: UUID) throws -> ZmxE2ESQLiteFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.zmx.e2e.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.zmx.e2e.local")
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    let coreRepository = WorkspaceCoreRepository(databaseWriter: coreQueue)
    let backend = WorkspaceSQLiteStoreBackend(
        coreRepository: coreRepository,
        makeLocalRepository: { workspaceId in
            WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: localQueue)
        }
    )
    return .init(coreQueue: coreQueue, localQueue: localQueue, coreRepository: coreRepository, backend: backend)
}
