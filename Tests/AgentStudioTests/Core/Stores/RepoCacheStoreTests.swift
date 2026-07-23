import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct RepoCacheStoreTests {
    @Test
    func flushAndRestoreRoundTripsSQLiteStateAcrossSplitAtoms() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let datastore = try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        let repoId = UUID()
        let worktreeId = UUID()
        let recentTarget = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/agent-studio"),
            lastOpenedAt: Date(timeIntervalSince1970: 456)
        )
        let store = RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            sqliteDatastore: datastore
        )

        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        cacheAtom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")
        )
        cacheAtom.setPullRequestCount(3, for: worktreeId)
        cacheAtom.markRebuilt(sourceRevision: 42, at: Date(timeIntervalSince1970: 123))
        recentTargetAtom.recordRecentTarget(recentTarget)
        try await store.flushAsync(for: workspaceId)

        let restoredCacheAtom = RepoEnrichmentCacheAtom()
        let restoredRecentTargetAtom = RecentWorkspaceTargetAtom()
        await RepoCacheStore(
            cacheAtom: restoredCacheAtom,
            recentTargetAtom: restoredRecentTargetAtom,
            sqliteDatastore: datastore
        ).restoreAsync(for: workspaceId)

        #expect(restoredCacheAtom.repoEnrichmentByRepoId[repoId] == .awaitingOrigin(repoId: repoId))
        #expect(restoredCacheAtom.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "main")
        #expect(restoredCacheAtom.pullRequestCountByWorktreeId[worktreeId] == 3)
        #expect(restoredCacheAtom.sourceRevision == 42)
        #expect(restoredCacheAtom.lastRebuiltAt == Date(timeIntervalSince1970: 123))
        #expect(restoredRecentTargetAtom.recentTargets == [recentTarget])
    }

    @Test
    func missingSQLiteRowsResetExistingStateToTypedDefaults() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: UUID()))
        recentTargetAtom.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/stale")))

        await RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        ).restoreAsync(for: workspaceId)

        #expect(cacheAtom.repoEnrichmentByRepoId.isEmpty)
        #expect(cacheAtom.worktreeEnrichmentByWorktreeId.isEmpty)
        #expect(cacheAtom.pullRequestCountByWorktreeId.isEmpty)
        #expect(cacheAtom.sourceRevision == 0)
        #expect(recentTargetAtom.recentTargets.isEmpty)
    }

    @Test
    func unavailableSQLiteResetsDefaultsAndReportsRecovery() async throws {
        let workspaceId = UUID()
        let cacheAtom = RepoEnrichmentCacheAtom()
        let recentTargetAtom = RecentWorkspaceTargetAtom()
        cacheAtom.setRepoEnrichment(.awaitingOrigin(repoId: UUID()))
        recentTargetAtom.recordRecentTarget(.forCwd(URL(fileURLWithPath: "/tmp/stale")))
        var reportedRecoveries: [PersistenceRecoveryEvent] = []

        await RepoCacheStore(
            cacheAtom: cacheAtom,
            recentTargetAtom: recentTargetAtom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: failingWorkspaceLocalSQLiteBackend()),
            recoveryReporter: { reportedRecoveries.append($0) }
        ).restoreAsync(for: workspaceId)

        #expect(cacheAtom.repoEnrichmentByRepoId.isEmpty)
        #expect(recentTargetAtom.recentTargets.isEmpty)
        #expect(
            reportedRecoveries.contains { recovery in
                recovery.store == .repoCache
                    && recovery.workspaceId == workspaceId
                    && recovery.recovery == .resetToDefaults
            })
    }

    @Test
    func observedPersistedChangeAutosavesSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = RepoCacheAtom()
        let clock = TestPushClock()
        let repoId = UUID()
        let store = RepoCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        atom.setRepoEnrichment(.awaitingOrigin(repoId: repoId))
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))

        await assertEventuallyMain("repo cache change should autosave") {
            (try? fixture.repository.fetchCacheState().repoEnrichmentByRepoId[repoId])
                == .awaitingOrigin(repoId: repoId)
        }
    }

    @Test
    func observedRecentTargetChangeAutosavesSQLite() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = RepoCacheAtom()
        let clock = TestPushClock()
        let target = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/agent-studio"),
            lastOpenedAt: Date(timeIntervalSince1970: 456)
        )
        let store = RepoCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        store.startObserving()

        atom.recordRecentTarget(target)
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))

        await assertEventuallyMain("recent target change should autosave") {
            (try? fixture.repository.fetchRecentTargets()) == [target]
        }
    }

    @Test
    func snapshotOnlyWorktreeChangeDoesNotRewritePersistedCache() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = RepoCacheAtom()
        let clock = TestPushClock()
        let repoId = UUID()
        let worktreeId = UUID()
        let store = RepoCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)
        atom.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: worktreeId, repoId: repoId, branch: "main")
        )
        try await store.flushAsync(for: workspaceId)
        let originalUpdatedAt = try await fixture.databaseQueue.read { database in
            let updatedAt = try Double.fetchOne(
                database,
                sql: "SELECT updated_at FROM cache_worktree_enrichment WHERE worktree_id = ?",
                arguments: [worktreeId.uuidString]
            )
            return try #require(updatedAt)
        }
        store.startObserving()

        atom.setWorktreeEnrichment(
            WorktreeEnrichment(
                worktreeId: worktreeId,
                repoId: repoId,
                branch: "main",
                snapshot: GitWorkingTreeSnapshot(
                    worktreeId: worktreeId,
                    repoId: repoId,
                    rootPath: URL(fileURLWithPath: "/tmp/agent-studio"),
                    summary: GitWorkingTreeSummary(changed: 2, staged: 0, untracked: 1),
                    branch: "main"
                )
            )
        )
        await clock.waitForPendingSleepCount()
        clock.advance(by: .milliseconds(10))
        await Task.yield()

        let currentUpdatedAt = try await fixture.databaseQueue.read { database in
            let updatedAt = try Double.fetchOne(
                database,
                sql: "SELECT updated_at FROM cache_worktree_enrichment WHERE worktree_id = ?",
                arguments: [worktreeId.uuidString]
            )
            return try #require(updatedAt)
        }
        #expect(currentUpdatedAt == originalUpdatedAt)
    }

    @Test
    func mutationBeforeObservationDoesNotAutosave() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let atom = RepoCacheAtom()
        let clock = TestPushClock()
        let store = RepoCacheStore(
            atom: atom,
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend),
            persistDebounceDuration: .milliseconds(10),
            clock: clock
        )
        await store.restoreAsync(for: workspaceId)

        atom.setRepoEnrichment(.awaitingOrigin(repoId: UUID()))
        await Task.yield()

        #expect(clock.pendingSleepCount == 0)
        #expect(try fixture.repository.hasCacheState() == false)
    }

    @Test
    func observationIsExplicitlyArmed() async throws {
        let workspaceId = UUID()
        let fixture = try makeWorkspaceLocalSQLiteStoreFixture(workspaceId: workspaceId)
        let store = RepoCacheStore(
            atom: RepoCacheAtom(),
            sqliteDatastore: try workspaceSQLiteDatastore(from: fixture.sqliteBackend)
        )

        #expect(store.isAutosaveObservationActive == false)
        await store.restoreAsync(for: workspaceId)
        #expect(store.isAutosaveObservationActive == false)
        store.startObserving()
        #expect(store.isAutosaveObservationActive)
    }
}
