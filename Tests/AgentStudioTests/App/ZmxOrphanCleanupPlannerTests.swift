import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct ZmxOrphanCleanupPlannerTests {

    @Test("returns known session IDs without skip when candidates are resolvable")
    func test_plan_whenAllCandidatesResolvable_returnsKnownSessionIdsWithoutSkip() {
        // Arrange
        let parentPaneId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let drawerPaneId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let mainPaneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let drawerSessionId = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)
        let mainSessionId = ZmxBackend.sessionId(
            repoStableKey: "a1b2c3d4e5f6a7b8",
            worktreeStableKey: "00112233aabbccdd",
            paneId: mainPaneId
        )
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .drawer(
                parentPaneId: parentPaneId,
                paneId: drawerPaneId,
                storedSessionId: nil,
                derivedSessionId: drawerSessionId
            ),
            .main(
                paneId: mainPaneId,
                storedSessionId: nil,
                derivedSessionId: mainSessionId
            ),
        ]

        // Act
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(candidates: candidates, liveSessionIds: [])

        // Assert
        let plan = hydrationPlan.cleanupPlan
        #expect(!plan.shouldSkipCleanup)
        #expect(hydrationPlan.sessionIdsToPersistByPaneId.isEmpty)
        #expect(
            plan.knownSessionIds
                == Set([
                    drawerSessionId,
                    mainSessionId,
                ])
        )
    }

    @Test("marks cleanup skip when any main candidate is unresolvable")
    func test_plan_whenAnyMainCandidateUnresolvable_setsSkipCleanupTrue() {
        // Arrange
        let resolvablePaneId = UUID()
        let unresolvedPaneId = UUID()
        let resolvedSessionId = ZmxBackend.sessionId(
            repoStableKey: "abcdef0123456789",
            worktreeStableKey: "fedcba9876543210",
            paneId: resolvablePaneId
        )
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(
                paneId: resolvablePaneId,
                storedSessionId: nil,
                derivedSessionId: resolvedSessionId
            ),
            .main(
                paneId: unresolvedPaneId,
                storedSessionId: nil,
                derivedSessionId: nil
            ),
        ]

        // Act
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(candidates: candidates, liveSessionIds: [])

        // Assert
        let plan = hydrationPlan.cleanupPlan
        #expect(plan.shouldSkipCleanup)
        #expect(plan.knownSessionIds.contains(resolvedSessionId))
    }

    @Test("stored session IDs win over derived and live same-pane candidates")
    func test_plan_whenStoredSessionIdExists_usesStoredIdWithoutPersistenceUpdate() {
        // Arrange
        let paneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let storedSessionId = ZmxBackend.sessionId(
            repoStableKey: "1111111111111111",
            worktreeStableKey: "2222222222222222",
            paneId: paneId
        )
        let derivedSessionId = ZmxBackend.sessionId(
            repoStableKey: "3333333333333333",
            worktreeStableKey: "4444444444444444",
            paneId: paneId
        )
        let liveSessionId = ZmxBackend.sessionId(
            repoStableKey: "5555555555555555",
            worktreeStableKey: "6666666666666666",
            paneId: paneId
        )
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(paneId: paneId, storedSessionId: storedSessionId, derivedSessionId: derivedSessionId)
        ]

        // Act
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: [liveSessionId]
        )

        // Assert
        #expect(!hydrationPlan.cleanupPlan.shouldSkipCleanup)
        #expect(hydrationPlan.cleanupPlan.knownSessionIds == [storedSessionId])
        #expect(hydrationPlan.sessionIdsToPersistByPaneId.isEmpty)
    }

    @Test("adopts unique live main session by same-kind pane segment")
    func test_plan_whenLegacyMainPaneHasUniqueLiveMatch_adoptsLiveSessionId() {
        // Arrange
        let paneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let derivedRoamedSessionId = ZmxBackend.sessionId(
            repoStableKey: "3333333333333333",
            worktreeStableKey: "4444444444444444",
            paneId: paneId
        )
        let liveBirthSessionId = ZmxBackend.sessionId(
            repoStableKey: "1111111111111111",
            worktreeStableKey: "2222222222222222",
            paneId: paneId
        )
        let unrelatedLiveSessionId = ZmxBackend.sessionId(
            repoStableKey: "5555555555555555",
            worktreeStableKey: "6666666666666666",
            paneId: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        )
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(paneId: paneId, storedSessionId: nil, derivedSessionId: derivedRoamedSessionId)
        ]

        // Act
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: [liveBirthSessionId, unrelatedLiveSessionId]
        )

        // Assert
        #expect(!hydrationPlan.cleanupPlan.shouldSkipCleanup)
        #expect(hydrationPlan.cleanupPlan.knownSessionIds == [liveBirthSessionId])
        #expect(hydrationPlan.sessionIdsToPersistByPaneId == [paneId: liveBirthSessionId])
        #expect(
            hydrationPlan.cleanupPlan.destroyableOrphanSessionIds(
                from: [liveBirthSessionId, unrelatedLiveSessionId]
            ) == [unrelatedLiveSessionId]
        )
    }

    @Test("protects same-pane live sessions when adoption is ambiguous")
    func test_plan_whenLegacyMainPaneHasAmbiguousLiveMatches_protectsSamePaneSessionsFromCleanup() {
        // Arrange
        let paneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let derivedSessionId = ZmxBackend.sessionId(
            repoStableKey: "3333333333333333",
            worktreeStableKey: "4444444444444444",
            paneId: paneId
        )
        let firstLiveMatch = ZmxBackend.sessionId(
            repoStableKey: "1111111111111111",
            worktreeStableKey: "2222222222222222",
            paneId: paneId
        )
        let secondLiveMatch = ZmxBackend.sessionId(
            repoStableKey: "5555555555555555",
            worktreeStableKey: "6666666666666666",
            paneId: paneId
        )
        let unrelatedLiveSessionId = ZmxBackend.sessionId(
            repoStableKey: "7777777777777777",
            worktreeStableKey: "8888888888888888",
            paneId: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        )
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(paneId: paneId, storedSessionId: nil, derivedSessionId: derivedSessionId)
        ]

        // Act
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: [firstLiveMatch, secondLiveMatch, unrelatedLiveSessionId]
        )

        // Assert
        #expect(!hydrationPlan.cleanupPlan.shouldSkipCleanup)
        #expect(hydrationPlan.cleanupPlan.knownSessionIds == [derivedSessionId])
        #expect(hydrationPlan.sessionIdsToPersistByPaneId.isEmpty)
        #expect(
            hydrationPlan.cleanupPlan.destroyableOrphanSessionIds(
                from: [firstLiveMatch, secondLiveMatch, unrelatedLiveSessionId]
            ) == [unrelatedLiveSessionId]
        )
    }

    @Test("does not cross-adopt drawer sessions into main pane anchors")
    func test_plan_whenOnlyDrawerLiveSessionSharesPaneSegment_doesNotAdoptForMainPane() {
        // Arrange
        let parentPaneId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let paneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let derivedMainSessionId = ZmxBackend.sessionId(
            repoStableKey: "3333333333333333",
            worktreeStableKey: "4444444444444444",
            paneId: paneId
        )
        let liveDrawerSessionId = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: paneId)
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(paneId: paneId, storedSessionId: nil, derivedSessionId: derivedMainSessionId)
        ]

        // Act
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: [liveDrawerSessionId]
        )

        // Assert
        #expect(hydrationPlan.cleanupPlan.knownSessionIds == [derivedMainSessionId])
        #expect(hydrationPlan.sessionIdsToPersistByPaneId.isEmpty)
        #expect(
            hydrationPlan.cleanupPlan.destroyableOrphanSessionIds(from: [liveDrawerSessionId]) == [
                liveDrawerSessionId
            ])
    }

    @Test("does not persist ambiguous legacy main matches but adopts when ambiguity clears")
    func test_plan_whenAmbiguousMatchClears_adoptsOnLaterPlan() {
        // Arrange
        let paneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let derivedSessionId = ZmxBackend.sessionId(
            repoStableKey: "3333333333333333",
            worktreeStableKey: "4444444444444444",
            paneId: paneId
        )
        let firstLiveMatch = ZmxBackend.sessionId(
            repoStableKey: "1111111111111111",
            worktreeStableKey: "2222222222222222",
            paneId: paneId
        )
        let secondLiveMatch = ZmxBackend.sessionId(
            repoStableKey: "5555555555555555",
            worktreeStableKey: "6666666666666666",
            paneId: paneId
        )
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(paneId: paneId, storedSessionId: nil, derivedSessionId: derivedSessionId)
        ]

        // Act
        let ambiguousPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: [firstLiveMatch, secondLiveMatch]
        )
        let laterUnambiguousPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: [firstLiveMatch]
        )

        // Assert
        #expect(ambiguousPlan.sessionIdsToPersistByPaneId.isEmpty)
        #expect(
            ambiguousPlan.cleanupPlan.destroyableOrphanSessionIds(
                from: [firstLiveMatch, secondLiveMatch]
            ).isEmpty
        )
        #expect(laterUnambiguousPlan.sessionIdsToPersistByPaneId == [paneId: firstLiveMatch])
    }

    @Test("invalid stored session IDs are ignored during cleanup planning")
    func test_plan_whenStoredSessionIdDoesNotMatchPane_ignoresStoredIdAndAdoptsLiveMatch() {
        // Arrange
        let paneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let foreignPaneId = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let invalidStoredSessionId = ZmxBackend.sessionId(
            repoStableKey: "1111111111111111",
            worktreeStableKey: "2222222222222222",
            paneId: foreignPaneId
        )
        let derivedSessionId = ZmxBackend.sessionId(
            repoStableKey: "3333333333333333",
            worktreeStableKey: "4444444444444444",
            paneId: paneId
        )
        let liveSessionId = ZmxBackend.sessionId(
            repoStableKey: "5555555555555555",
            worktreeStableKey: "6666666666666666",
            paneId: paneId
        )
        let candidates: [ZmxOrphanCleanupCandidate] = [
            .main(paneId: paneId, storedSessionId: invalidStoredSessionId, derivedSessionId: derivedSessionId)
        ]

        // Act
        let hydrationPlan = ZmxOrphanCleanupPlanner.plan(
            candidates: candidates,
            liveSessionIds: [liveSessionId]
        )

        // Assert
        #expect(hydrationPlan.cleanupPlan.knownSessionIds == [liveSessionId])
        #expect(hydrationPlan.sessionIdsToPersistByPaneId == [paneId: liveSessionId])
    }

    @MainActor
    @Test("startup cleanup hydrates legacy roamed pane anchor before destroying unrelated sessions")
    func test_runOrphanCleanup_whenLegacyRoamedPaneHasLiveBirthSession_persistsAdoptedAnchor() async throws {
        // Arrange
        let workspaceId = UUID()
        let fixture = try makeZmxCleanupSQLiteFixture(workspaceId: workspaceId)
        let identityAtom = WorkspaceIdentityAtom()
        identityAtom.hydrate(
            workspaceId: workspaceId,
            workspaceName: "Legacy zmx Cleanup",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        var recoveryEvents: [PersistenceRecoveryEvent] = []
        let store = WorkspaceStore(
            identityAtom: identityAtom,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ),
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend),
            recoveryReporter: { event in recoveryEvents.append(event) }
        )
        let delegate = AppDelegate()
        delegate.store = store

        let birthRepo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-zmx-cleanup-birth"))
        let birthWorktree = try #require(birthRepo.worktrees.first)
        let roamedRepo = store.addRepo(at: URL(filePath: "/tmp/agent-studio-zmx-cleanup-roamed"))
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
            )
        )
        let legacyPane = try #require(store.paneAtom.pane(legacyPaneState.id))
        store.appendTab(Tab(paneId: legacyPane.id, name: "Legacy"))

        let birthSessionId = ZmxBackend.sessionId(
            repoStableKey: birthRepo.stableKey,
            worktreeStableKey: birthWorktree.stableKey,
            paneId: legacyPane.id
        )
        let roamedDerivedSessionId = ZmxBackend.sessionId(
            repoStableKey: roamedRepo.stableKey,
            worktreeStableKey: roamedWorktree.stableKey,
            paneId: legacyPane.id
        )
        let unrelatedSessionId = ZmxBackend.sessionId(
            repoStableKey: "1111111111111111",
            worktreeStableKey: "2222222222222222",
            paneId: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        )
        let backend = RecordingZmxCleanupBackend(liveSessionIds: [birthSessionId, unrelatedSessionId])
        let terminalRestoreRuntime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: true,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        // Act
        try await delegate.runOrphanZmxCleanup(
            backend: backend,
            terminalRestoreRuntime: terminalRestoreRuntime
        )

        // Assert
        #expect(store.pane(legacyPane.id)?.terminalState?.zmxSessionId == birthSessionId)
        #expect(store.pane(legacyPane.id)?.terminalState?.zmxSessionId != roamedDerivedSessionId)
        #expect(Set(backend.destroyedSessionIds) == [unrelatedSessionId])
        #expect(recoveryEvents.isEmpty)

        let storedPanes = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId).panes
        let storedPane = try #require(storedPanes.first { $0.id == legacyPane.id })
        guard case .terminal(_, _, let storedSessionId) = storedPane.content else {
            Issue.record("Expected terminal content for legacy pane")
            return
        }
        #expect(storedSessionId == birthSessionId)
    }
}

private struct ZmxCleanupSQLiteFixture {
    let coreQueue: DatabaseQueue
    let localQueue: DatabaseQueue
    let coreRepository: WorkspaceCoreRepository
    let backend: WorkspaceSQLiteStoreBackend
}

@MainActor
private func makeZmxCleanupSQLiteFixture(workspaceId: UUID) throws -> ZmxCleanupSQLiteFixture {
    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.zmx.cleanup.core")
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(label: "AgentStudio.zmx.cleanup.local")
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

private final class RecordingZmxCleanupBackend: SessionBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let liveSessionIds: [String]
    private var destroyedIds: [String] = []

    init(liveSessionIds: [String]) {
        self.liveSessionIds = liveSessionIds
    }

    var destroyedSessionIds: [String] {
        lock.withLock { destroyedIds }
    }

    var isAvailable: Bool {
        get async { true }
    }

    func createPaneSession(repo: Repo, worktree: Worktree, paneId: UUID) async throws -> PaneSessionHandle {
        throw SessionBackendError.operationFailed("unused in cleanup tests")
    }

    func attachCommand(for handle: PaneSessionHandle) -> String {
        "unused"
    }

    func destroyPaneSession(_ handle: PaneSessionHandle) async throws {}

    func healthCheck(_ handle: PaneSessionHandle) async -> Bool {
        false
    }

    func socketExists() -> Bool {
        true
    }

    func sessionExists(_ handle: PaneSessionHandle) async -> Bool {
        false
    }

    func discoverOrphanSessions(excluding knownIds: Set<String>) async -> [String] {
        liveSessionIds.filter { $0.hasPrefix(ZmxBackend.sessionPrefix) && !knownIds.contains($0) }
    }

    func destroySessionById(_ sessionId: String) async throws {
        lock.withLock {
            destroyedIds.append(sessionId)
        }
    }
}
