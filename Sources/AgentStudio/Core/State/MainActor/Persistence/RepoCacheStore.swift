import Foundation
import Observation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

@MainActor
final class RepoCacheStore {
    private let cacheAtom: RepoEnrichmentCacheAtom
    private let recentTargetAtom: RecentWorkspaceTargetAtom
    private let persistor: WorkspacePersistor
    private let sqliteBackend: WorkspaceLocalSQLiteStoreBackend?
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    private(set) var canArchiveLegacyCacheFile = true

    var isAutosaveObservationActive: Bool {
        isObservingCacheState
    }

    init(
        cacheAtom: RepoEnrichmentCacheAtom,
        recentTargetAtom: RecentWorkspaceTargetAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        sqliteBackend: WorkspaceLocalSQLiteStoreBackend? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.cacheAtom = cacheAtom
        self.recentTargetAtom = recentTargetAtom
        self.persistor = persistor
        self.sqliteBackend = sqliteBackend
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
        self.recoveryReporter = recoveryReporter
    }

    convenience init(
        atom: RepoCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        sqliteBackend: WorkspaceLocalSQLiteStoreBackend? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.init(
            cacheAtom: atom.enrichmentCacheAtom,
            recentTargetAtom: atom.recentTargetAtom,
            persistor: persistor,
            sqliteBackend: sqliteBackend,
            persistDebounceDuration: persistDebounceDuration,
            clock: clock,
            recoveryReporter: recoveryReporter
        )
    }

    /// Begin observing atom mutations for debounced autosave.
    ///
    /// Stores do not observe from `init`: the owner first restores cache state,
    /// replays boot topology, and prunes stale entries as an explicit boot
    /// transaction. Production arms this from `WorkspaceBootStep.armPersistenceObservation`;
    /// tests or future isolated owners must opt in once their initial mutations are done.
    func startObserving() {
        observeCacheState()
    }

    func restore(for workspaceId: UUID) {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        canArchiveLegacyCacheFile = true
        switch restoreFromSQLite(for: workspaceId) {
        case .restored:
            return
        case .missing:
            break
        case .unavailable:
            cacheAtom.clear()
            recentTargetAtom.clear()
            canArchiveLegacyCacheFile = false
            recoveryReporter?(
                .init(store: .repoCache, workspaceId: workspaceId, recovery: .resetToDefaults)
            )
            return
        }
        switch persistor.loadCache(for: workspaceId) {
        case .loaded(let cacheState):
            isRestoringState = true
            cacheAtom.hydrate(
                .init(
                    repoEnrichmentByRepoId: cacheState.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheState.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: cacheState.pullRequestCountByWorktreeId,
                    notificationCountByWorktreeId: cacheState.notificationCountByWorktreeId,
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
            recentTargetAtom.hydrate(recentTargets: cacheState.recentTargets)
            isRestoringState = false
            canArchiveLegacyCacheFile = materializeSQLiteIfNeeded(for: workspaceId)
        case .missing:
            cacheAtom.clear()
            recentTargetAtom.clear()
        case .corrupt(let error):
            let quarantinedURL = persistor.quarantineCorruptRepoCacheFile(for: workspaceId)
            cacheAtom.clear()
            recentTargetAtom.clear()
            repoCacheStoreLogger.warning(
                "Cache file corrupt; quarantined before resetting cache/local memory: \(error)"
            )
            recoveryReporter?(
                .init(
                    store: .repoCache,
                    workspaceId: workspaceId,
                    recovery: quarantinedURL == nil ? .quarantineFailed : .quarantinedAndReset,
                    quarantinedFilename: quarantinedURL?.lastPathComponent
                )
            )
        }
    }

    func flush(for workspaceId: UUID) throws {
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try persistNow(for: workspaceId)
    }

    private func observeCacheState() {
        guard !isObservingCacheState else { return }
        isObservingCacheState = true
        withObservationTracking {
            _ = cacheAtom.repoEnrichmentByRepoId
            _ = cacheAtom.worktreeEnrichmentByWorktreeId
            _ = cacheAtom.pullRequestCountByWorktreeId
            _ = cacheAtom.notificationCountByWorktreeId
            _ = recentTargetAtom.recentTargets
            _ = cacheAtom.sourceRevision
            _ = cacheAtom.lastRebuiltAt
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                // Repo cache write owners are @MainActor; this traps if ownership changes.
                guard let self else { return }
                let shouldIgnore = self.isRestoringState
                self.isObservingCacheState = false
                self.observeCacheState()
                guard !shouldIgnore else { return }
                self.schedulePersist()
            }
        }
    }

    private func schedulePersist() {
        guard let workspaceId = activeWorkspaceId else { return }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.persistDebounceDuration)
            guard !Task.isCancelled else { return }
            do {
                try self.persistNow(for: workspaceId)
            } catch {
                repoCacheStoreLogger.warning("Repo cache autosave failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistNow(for workspaceId: UUID) throws {
        do {
            if let sqliteBackend {
                let repository = try sqliteBackend.repository(for: workspaceId)
                try repository.replaceCacheState(
                    cacheState: .init(
                        repoEnrichmentByRepoId: cacheAtom.repoEnrichmentByRepoId,
                        worktreeEnrichmentByWorktreeId: cacheAtom.worktreeEnrichmentByWorktreeId,
                        pullRequestCountByWorktreeId: cacheAtom.pullRequestCountByWorktreeId,
                        notificationCountByWorktreeId: cacheAtom.notificationCountByWorktreeId,
                        sourceRevision: cacheAtom.sourceRevision,
                        lastRebuiltAt: cacheAtom.lastRebuiltAt
                    ),
                    updatedAt: Date()
                )
                try repository.replaceRecentTargets(recentTargetAtom.recentTargets, updatedAt: Date())
                return
            }
            guard persistor.ensureDirectory() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try persistor.saveCache(
                .init(
                    workspaceId: workspaceId,
                    repoEnrichmentByRepoId: cacheAtom.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheAtom.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: cacheAtom.pullRequestCountByWorktreeId,
                    notificationCountByWorktreeId: cacheAtom.notificationCountByWorktreeId,
                    recentTargets: recentTargetAtom.recentTargets,
                    sourceRevision: cacheAtom.sourceRevision,
                    lastRebuiltAt: cacheAtom.lastRebuiltAt
                )
            )
        } catch {
            recoveryReporter?(
                .init(store: .repoCache, workspaceId: workspaceId, recovery: .saveFailed)
            )
            throw error
        }
    }

    private func restoreFromSQLite(for workspaceId: UUID) -> LocalSQLiteRestoreOutcome {
        guard let sqliteBackend else { return .missing }
        do {
            let repository = try sqliteBackend.repository(for: workspaceId)
            guard try repository.hasCacheState(),
                try repository.hasRecentTargetsState()
            else {
                return .missing
            }
            let cacheState = try repository.fetchCacheState()
            let recentTargets = try repository.fetchRecentTargets()
            isRestoringState = true
            cacheAtom.hydrate(
                .init(
                    repoEnrichmentByRepoId: cacheState.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheState.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: cacheState.pullRequestCountByWorktreeId,
                    notificationCountByWorktreeId: cacheState.notificationCountByWorktreeId,
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
            recentTargetAtom.hydrate(recentTargets: recentTargets)
            isRestoringState = false
            return .restored
        } catch {
            isRestoringState = false
            repoCacheStoreLogger.warning("Repo cache SQLite restore failed: \(error.localizedDescription)")
            return .unavailable(error)
        }
    }

    private func materializeSQLiteIfNeeded(for workspaceId: UUID) -> Bool {
        guard sqliteBackend != nil else { return true }
        do {
            try persistNow(for: workspaceId)
            return true
        } catch {
            repoCacheStoreLogger.warning(
                "Repo cache legacy import materialization failed: \(error.localizedDescription)"
            )
            return false
        }
    }
}
