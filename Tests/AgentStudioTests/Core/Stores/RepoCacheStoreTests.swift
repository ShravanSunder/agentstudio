import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct RepoCacheStoreTests {
    private let tempDir: URL
    private let persistor: WorkspacePersistor

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "repo-cache-store-tests-\(UUID().uuidString)")
        persistor = WorkspacePersistor(workspacesDir: tempDir)
        persistor.ensureDirectory()
    }

    @Test
    func flushAndRestore_roundTripsPersistedCacheState() throws {
        let workspaceId = UUID()
        let atom = RepoCacheAtom()
        let repo = CanonicalRepo(
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )
        let worktree = CanonicalWorktree(
            repoId: repo.id,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio/main"),
            isMainWorktree: true
        )
        let repoStore = RepoCacheStore(atom: atom, persistor: persistor)

        atom.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        atom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktree.id, repoId: repo.id, branch: "main")
        )
        atom.setPullRequestCount(3, for: worktree.id)
        atom.setNotificationCount(2, for: worktree.id)
        atom.recordRecentTarget(
            .forCwd(
                URL(fileURLWithPath: "/tmp/agent-studio/main"),
                title: "agent-studio",
                subtitle: "main",
                lastOpenedAt: Date(timeIntervalSince1970: 456)
            )
        )
        atom.markRebuilt(sourceRevision: 42, at: Date(timeIntervalSince1970: 123))

        try repoStore.flush(for: workspaceId)

        let restoredAtom = RepoCacheAtom()
        let restoredStore = RepoCacheStore(atom: restoredAtom, persistor: persistor)
        restoredStore.restore(for: workspaceId)

        #expect(restoredAtom.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
        #expect(restoredAtom.worktreeEnrichmentByWorktreeId[worktree.id]?.branch == "main")
        #expect(restoredAtom.pullRequestCountByWorktreeId[worktree.id] == 3)
        #expect(restoredAtom.notificationCountByWorktreeId[worktree.id] == 2)
        #expect(restoredAtom.recentTargets.map(\.id) == ["cwd:/tmp/agent-studio/main"])
        #expect(restoredAtom.sourceRevision == 42)
        #expect(restoredAtom.lastRebuiltAt == Date(timeIntervalSince1970: 123))
    }

    @Test
    func flushAndRestore_roundTripsCacheAndRecentTargetsThroughLocalSQLite() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let target = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/agent-studio"),
            title: "agent-studio",
            subtitle: "/tmp/agent-studio",
            lastOpenedAt: Date(timeIntervalSince1970: 456)
        )
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor,
            sqliteBackend: fixture.sqliteBackend
        )

        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")
        )
        cacheAtom.setPullRequestCount(3, for: worktreeId)
        cacheAtom.setNotificationCount(2, for: worktreeId)
        cacheAtom.markRebuilt(sourceRevision: 42, at: Date(timeIntervalSince1970: 123))
        recentTargetAtom.recordRecentTarget(target)

        try store.flush(for: workspaceId)

        let storedCache = try fixture.repository.fetchCacheState()
        #expect(storedCache.repoEnrichmentByRepoId[repoId] == .awaitingOrigin(repoId: repoId))
        #expect(storedCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(storedCache.pullRequestCountByWorktreeId[worktreeId] == 3)
        #expect(storedCache.notificationCountByWorktreeId[worktreeId] == 2)
        #expect(storedCache.sourceRevision == 42)
        #expect(storedCache.lastRebuiltAt == Date(timeIntervalSince1970: 123))
        #expect(try fixture.repository.fetchRecentTargets() == [target])
        guard case .missing = persistor.loadCache(for: workspaceId) else {
            Issue.record("SQLite-backed repo cache flush should not write the legacy JSON sidecar")
            return
        }

        let restoredCacheAtom = RepoEnrichmentCacheAtom()
        let restoredRecentTargetAtom = RecentWorkspaceTargetAtom()
        RepoCacheStore(
            cacheAtom: restoredCacheAtom,
            recentTargetAtom: restoredRecentTargetAtom,
            persistor: persistor,
            sqliteBackend: fixture.sqliteBackend
        ).restore(for: workspaceId)

        #expect(restoredCacheAtom.repoEnrichmentByRepoId[repoId] == .awaitingOrigin(repoId: repoId))
        #expect(restoredCacheAtom.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(restoredCacheAtom.pullRequestCountByWorktreeId[worktreeId] == 3)
        #expect(restoredCacheAtom.notificationCountByWorktreeId[worktreeId] == 2)
        #expect(restoredCacheAtom.sourceRevision == 42)
        #expect(restoredCacheAtom.lastRebuiltAt == Date(timeIntervalSince1970: 123))
        #expect(restoredRecentTargetAtom.recentTargets == [target])
    }

    @Test
    func restoreWithSQLiteBackendImportsLegacyJSONWhenLanesAreMissing() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let repoId = UUID()
        let target = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/legacy"),
            title: "legacy",
            subtitle: "/tmp/legacy",
            lastOpenedAt: Date(timeIntervalSince1970: 456)
        )
        try persistor.saveCache(
            .init(
                workspaceId: workspaceId,
                repoEnrichmentByRepoId: [repoId: .awaitingOrigin(repoId: repoId)],
                worktreeEnrichmentByWorktreeId: [:],
                pullRequestCountByWorktreeId: [:],
                notificationCountByWorktreeId: [:],
                recentTargets: [target],
                sourceRevision: 7,
                lastRebuiltAt: Date(timeIntervalSince1970: 123)
            )
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor,
            sqliteBackend: fixture.sqliteBackend
        )

        store.restore(for: workspaceId)

        #expect(cacheAtom.repoEnrichmentByRepoId[repoId] == .awaitingOrigin(repoId: repoId))
        #expect(cacheAtom.sourceRevision == 7)
        #expect(cacheAtom.lastRebuiltAt == Date(timeIntervalSince1970: 123))
        #expect(recentTargetAtom.recentTargets == [target])
        #expect(try fixture.repository.hasCacheState())
        #expect(try fixture.repository.hasRecentTargetsState())
    }

    @Test
    func unavailableSQLiteBackendResetsCacheAndBlocksLegacyArchiveReadiness() throws {
        let workspaceId = UUID()
        let repoId = UUID()
        try persistor.saveCache(
            .init(
                workspaceId: workspaceId,
                repoEnrichmentByRepoId: [repoId: .awaitingOrigin(repoId: repoId)],
                worktreeEnrichmentByWorktreeId: [:],
                pullRequestCountByWorktreeId: [:],
                notificationCountByWorktreeId: [:],
                recentTargets: [],
                sourceRevision: 7,
                lastRebuiltAt: nil
            )
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor,
            sqliteBackend: failingWorkspaceLocalSQLiteBackend()
        )

        store.restore(for: workspaceId)

        #expect(cacheAtom.repoEnrichmentByRepoId[repoId] == nil)
        #expect(cacheAtom.repoEnrichmentByRepoId.isEmpty)
        #expect(recentTargetAtom.recentTargets.isEmpty)
        #expect(!store.canArchiveLegacyCacheFile)
    }

    @Test
    func restoreWithSQLiteBackendDoesNotResurrectLegacyJSONAfterEmptyLaneFlush() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let repoId = UUID()
        let target = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/stale"),
            title: "stale",
            subtitle: "/tmp/stale",
            lastOpenedAt: Date(timeIntervalSince1970: 456)
        )
        try persistor.saveCache(
            .init(
                workspaceId: workspaceId,
                repoEnrichmentByRepoId: [repoId: .awaitingOrigin(repoId: repoId)],
                worktreeEnrichmentByWorktreeId: [:],
                pullRequestCountByWorktreeId: [:],
                notificationCountByWorktreeId: [:],
                recentTargets: [target],
                sourceRevision: 7,
                lastRebuiltAt: Date(timeIntervalSince1970: 123)
            )
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor,
            sqliteBackend: fixture.sqliteBackend
        )

        try store.flush(for: workspaceId)
        store.restore(for: workspaceId)

        #expect(cacheAtom.repoEnrichmentByRepoId.isEmpty)
        #expect(cacheAtom.sourceRevision == 0)
        #expect(recentTargetAtom.recentTargets.isEmpty)
        #expect(try fixture.repository.hasCacheState())
        #expect(try fixture.repository.hasRecentTargetsState())
    }

    @Test
    func missingSQLiteCacheLanesAfterImportResetInsteadOfReplayingLegacyJSON() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let sqliteRepoId = UUID()
        let staleRepoId = UUID()
        let staleTarget = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/stale-cache"),
            title: "stale",
            subtitle: "/tmp/stale-cache",
            lastOpenedAt: Date(timeIntervalSince1970: 456)
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor,
            sqliteBackend: fixture.sqliteBackend
        )
        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: sqliteRepoId))
        cacheAtom.markRebuilt(sourceRevision: 11, at: Date(timeIntervalSince1970: 789))
        recentTargetAtom.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/sqlite-cache")))
        try store.flush(for: workspaceId)
        try persistor.saveCache(
            .init(
                workspaceId: workspaceId,
                repoEnrichmentByRepoId: [staleRepoId: .awaitingOrigin(repoId: staleRepoId)],
                worktreeEnrichmentByWorktreeId: [:],
                pullRequestCountByWorktreeId: [:],
                notificationCountByWorktreeId: [:],
                recentTargets: [staleTarget],
                sourceRevision: 7,
                lastRebuiltAt: Date(timeIntervalSince1970: 123)
            )
        )
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: "DELETE FROM cache_metadata WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
            try database.execute(
                sql: """
                    DELETE FROM local_persistence_lane_marker
                    WHERE workspace_id = ? AND lane = 'recent_workspace_targets'
                    """,
                arguments: [workspaceId.uuidString]
            )
            try database.execute(
                sql: "DELETE FROM local_recent_workspace_target WHERE workspace_id = ?",
                arguments: [workspaceId.uuidString]
            )
        }
        let restoredCacheAtom = RepoEnrichmentCacheAtom()
        let restoredRecentTargetAtom = RecentWorkspaceTargetAtom()
        let restoredStore = RepoCacheStore(
            cacheAtom: restoredCacheAtom,
            recentTargetAtom: restoredRecentTargetAtom,
            persistor: persistor,
            sqliteBackend: workspaceLocalSQLiteBackendWithImportedLegacyLanes(repository: fixture.repository)
        )

        restoredStore.restore(for: workspaceId)

        #expect(restoredCacheAtom.repoEnrichmentByRepoId.isEmpty)
        #expect(restoredCacheAtom.repoEnrichmentByRepoId[staleRepoId] == nil)
        #expect(restoredCacheAtom.sourceRevision == 0)
        #expect(restoredRecentTargetAtom.recentTargets.isEmpty)
        #expect(!restoredStore.canArchiveLegacyCacheFile)
    }

    @Test
    func restoreWithSQLiteBackendResetsWhenSQLiteCacheLaneFailsInsteadOfReplayingLegacyJSON() throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let sqliteRepoId = UUID()
        let staleRepoId = UUID()
        let staleTarget = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/stale-cache"),
            title: "stale",
            subtitle: "/tmp/stale-cache",
            lastOpenedAt: Date(timeIntervalSince1970: 456)
        )
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor,
            sqliteBackend: fixture.sqliteBackend
        )
        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: sqliteRepoId))
        recentTargetAtom.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/sqlite-cache")))
        try store.flush(for: workspaceId)
        try persistor.saveCache(
            .init(
                workspaceId: workspaceId,
                repoEnrichmentByRepoId: [staleRepoId: .awaitingOrigin(repoId: staleRepoId)],
                worktreeEnrichmentByWorktreeId: [:],
                pullRequestCountByWorktreeId: [:],
                notificationCountByWorktreeId: [:],
                recentTargets: [staleTarget],
                sourceRevision: 7,
                lastRebuiltAt: Date(timeIntervalSince1970: 123)
            )
        )
        try fixture.databaseQueue.write { database in
            try database.drop(table: "cache_metadata")
        }

        let restoredCacheAtom = RepoEnrichmentCacheAtom()
        let restoredRecentTargetAtom = RecentWorkspaceTargetAtom()
        let restoredStore = RepoCacheStore(
            cacheAtom: restoredCacheAtom,
            recentTargetAtom: restoredRecentTargetAtom,
            persistor: persistor,
            sqliteBackend: fixture.sqliteBackend
        )
        restoredStore.restore(for: workspaceId)

        #expect(restoredCacheAtom.repoEnrichmentByRepoId.isEmpty)
        #expect(restoredCacheAtom.repoEnrichmentByRepoId[staleRepoId] == nil)
        #expect(restoredRecentTargetAtom.recentTargets.isEmpty)
        #expect(!restoredStore.canArchiveLegacyCacheFile)
    }

    @Test
    func flushAndRestore_operatesOnSplitCacheAndRecentTargetAtoms() throws {
        let workspaceId = UUID()
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor
        )
        let repoId = UUID()
        let target = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))

        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        recentTargetAtom.recordRecentTarget(target)

        try store.flush(for: workspaceId)

        let restoredCacheAtom = RepoEnrichmentCacheAtom()
        let restoredRecentTargetAtom = RecentWorkspaceTargetAtom()
        RepoCacheStore(
            cacheAtom: restoredCacheAtom,
            recentTargetAtom: restoredRecentTargetAtom,
            persistor: persistor
        ).restore(for: workspaceId)

        #expect(restoredCacheAtom.repoEnrichmentByRepoId[repoId] == .awaitingOrigin(repoId: repoId))
        #expect(restoredRecentTargetAtom.recentTargets == [target])
    }

    @Test
    func flush_operatesOnTheProvidedLiveAtomScope() throws {
        let workspaceId = UUID()
        let atom = RepoCacheAtom()
        let store = RepoCacheStore(atom: atom, persistor: persistor)
        let repo = CanonicalRepo(
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )

        atom.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))

        try store.flush(for: workspaceId)

        let restoredAtom = RepoCacheAtom()
        RepoCacheStore(atom: restoredAtom, persistor: persistor).restore(for: workspaceId)

        #expect(restoredAtom.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id))
    }

    @Test
    func observedCacheChange_autosavesRepoCache() async throws {
        let workspaceId = UUID()
        let atom = RepoCacheAtom()
        let clock = TestPushClock()
        let store = RepoCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        let repo = CanonicalRepo(
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )

        store.restore(for: workspaceId)
        store.startObserving()
        atom.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))

        await assertEventuallyMain("repo cache change should autosave") {
            switch persistor.loadCache(for: workspaceId) {
            case .loaded(let cache):
                return cache.repoEnrichmentByRepoId[repo.id] == .awaitingOrigin(repoId: repo.id)
            case .missing, .corrupt:
                return false
            }
        }
    }

    @Test
    func observedRecentTargetChange_autosavesRecentTargets() async throws {
        let workspaceId = UUID()
        let atom = RepoCacheAtom()
        let clock = TestPushClock()
        let store = RepoCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        let target = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))

        store.restore(for: workspaceId)
        store.startObserving()
        atom.recordRecentTarget(target)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))

        await assertEventuallyMain("recent target change should autosave") {
            switch persistor.loadCache(for: workspaceId) {
            case .loaded(let cache):
                return cache.recentTargets == [target]
            case .missing, .corrupt:
                return false
            }
        }
    }

    @Test
    func mutationBeforeStartObservingDoesNotScheduleAutosave() async throws {
        let workspaceId = UUID()
        let atom = RepoCacheAtom()
        let clock = TestPushClock()
        let store = RepoCacheStore(
            atom: atom,
            persistor: persistor,
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        let repo = CanonicalRepo(
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
        )

        store.restore(for: workspaceId)
        atom.setRepoEnrichment(.awaitingOrigin(repoId: repo.id))
        await Task.yield()

        #expect(clock.pendingSleepCount == 0)
        switch persistor.loadCache(for: workspaceId) {
        case .missing:
            break
        case .loaded, .corrupt:
            Issue.record("Cache mutation before startObserving() should not autosave")
        }
    }

    @Test
    func autosaveObservationStateIsExplicitlyArmed() {
        let workspaceId = UUID()
        let store = RepoCacheStore(atom: RepoCacheAtom(), persistor: persistor)

        #expect(store.isAutosaveObservationActive == false)
        store.restore(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive == true)
    }

    @Test
    func restore_missingCacheFile_clearsExistingSplitState() {
        let workspaceId = UUID()
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let repoId = UUID()
        let target = RecentWorkspaceTarget.forCwd(URL(fileURLWithPath: "/tmp/agent-studio"))
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            persistor: persistor
        )

        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        recentTargetAtom.recordRecentTarget(target)

        store.restore(for: workspaceId)

        #expect(cacheAtom.repoEnrichmentByRepoId.isEmpty)
        #expect(recentTargetAtom.recentTargets.isEmpty)
    }

    @Test
    func restore_corruptCacheFile_quarantinesAndResetsLocalMemory() throws {
        let workspaceId = UUID()
        let corruptURL = tempDir.appending(path: "\(workspaceId.uuidString).workspace.cache.json")
        try "not json".write(to: corruptURL, atomically: true, encoding: .utf8)

        let atom = RepoCacheAtom()
        atom.setRepoEnrichment(.awaitingOrigin(repoId: UUID()))
        atom.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/agent-studio")))
        var reportedRecovery: PersistenceRecoveryEvent?
        let repoStore = RepoCacheStore(
            atom: atom,
            persistor: persistor,
            recoveryReporter: { reportedRecovery = $0 }
        )

        repoStore.restore(for: workspaceId)

        #expect(atom.repoEnrichmentByRepoId.isEmpty)
        #expect(atom.worktreeEnrichmentByWorktreeId.isEmpty)
        #expect(atom.pullRequestCountByWorktreeId.isEmpty)
        #expect(atom.notificationCountByWorktreeId.isEmpty)
        #expect(atom.recentTargets.isEmpty)
        #expect(reportedRecovery?.store == .repoCache)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .quarantinedAndReset)
        #expect(reportedRecovery?.quarantinedFilename?.contains(".workspace.cache.corrupt-") == true)
        #expect(FileManager.default.fileExists(atPath: corruptURL.path) == false)
    }

    @Test
    func flushFailure_reportsSaveFailedRecovery() {
        let workspaceId = UUID()
        let blockedDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "repo-cache-blocked-\(UUID().uuidString)")
        try? Data("not-a-directory".utf8).write(to: blockedDirectoryURL, options: .atomic)
        var reportedRecovery: PersistenceRecoveryEvent?
        let store = RepoCacheStore(
            atom: RepoCacheAtom(),
            persistor: WorkspacePersistor(workspacesDir: blockedDirectoryURL),
            recoveryReporter: { reportedRecovery = $0 }
        )

        #expect(throws: Error.self) {
            try store.flush(for: workspaceId)
        }

        #expect(reportedRecovery?.store == .repoCache)
        #expect(reportedRecovery?.workspaceId == workspaceId)
        #expect(reportedRecovery?.recovery == .saveFailed)
    }
}
