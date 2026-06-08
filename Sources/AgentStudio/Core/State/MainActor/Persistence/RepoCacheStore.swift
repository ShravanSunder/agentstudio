import Foundation
import Observation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

@MainActor
final class RepoCacheStore {
    private let cacheAtom: RepoEnrichmentCacheAtom
    private let recentTargetAtom: RecentWorkspaceTargetAtom
    private let persistor: WorkspacePersistor
    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    private var lastPersistedProjection: PersistedProjection?
    private(set) var canArchiveLegacyCacheFile = true

    var isAutosaveObservationActive: Bool {
        isObservingCacheState
    }

    init(
        cacheAtom: RepoEnrichmentCacheAtom,
        recentTargetAtom: RecentWorkspaceTargetAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.cacheAtom = cacheAtom
        self.recentTargetAtom = recentTargetAtom
        self.persistor = persistor
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.recoveryReporter = recoveryReporter
    }

    convenience init(
        atom: RepoCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.init(
            cacheAtom: atom.enrichmentCacheAtom,
            recentTargetAtom: atom.recentTargetAtom,
            persistor: persistor,
            sqliteDatastore: sqliteDatastore,
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
        guard sqliteDatastore == nil else {
            preconditionFailure("Use await restoreAsync(for:) when SQLite datastore is enabled")
        }
        restoreFromLegacyFiles(workspaceId: workspaceId, legacyImportDecision: .allowImport)
    }

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        canArchiveLegacyCacheFile = true
        if let sqliteDatastore {
            switch await restoreFromSQLite(for: workspaceId, sqliteDatastore: sqliteDatastore) {
            case .restored:
                return
            case .missing(let legacyImportDecision, let recoveryEvents):
                reportRecoveryEvents(recoveryEvents)
                await restoreFromLegacyFilesAsync(workspaceId: workspaceId, legacyImportDecision: legacyImportDecision)
                return
            case .unavailable(let recoveryEvents):
                reportRecoveryEvents(recoveryEvents)
                cacheAtom.clear()
                recentTargetAtom.clear()
                canArchiveLegacyCacheFile = false
                recoveryReporter?(
                    .init(store: .repoCache, workspaceId: workspaceId, recovery: .resetToDefaults)
                )
                return
            }
        }
        restoreFromLegacyFiles(workspaceId: workspaceId, legacyImportDecision: .allowImport)
    }

    private func restoreFromLegacyFiles(
        workspaceId: UUID,
        legacyImportDecision: WorkspaceLocalSQLiteLegacyImportDecision
    ) {
        guard legacyImportDecision.allowsLegacyImport else {
            cacheAtom.clear()
            recentTargetAtom.clear()
            lastPersistedProjection = currentPersistedProjection()
            canArchiveLegacyCacheFile = !persistor.hasLegacyCacheFile(for: workspaceId)
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
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
            recentTargetAtom.hydrate(recentTargets: cacheState.recentTargets)
            isRestoringState = false
            if sqliteDatastore == nil {
                lastPersistedProjection = currentPersistedProjection()
            }
            canArchiveLegacyCacheFile = sqliteDatastore == nil
        case .missing:
            cacheAtom.clear()
            recentTargetAtom.clear()
            if sqliteDatastore == nil {
                lastPersistedProjection = currentPersistedProjection()
            }
        case .corrupt(let error):
            let quarantinedURL = persistor.quarantineCorruptRepoCacheFile(for: workspaceId)
            cacheAtom.clear()
            recentTargetAtom.clear()
            lastPersistedProjection = currentPersistedProjection()
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

    private func restoreFromLegacyFilesAsync(
        workspaceId: UUID,
        legacyImportDecision: WorkspaceLocalSQLiteLegacyImportDecision
    ) async {
        restoreFromLegacyFiles(workspaceId: workspaceId, legacyImportDecision: legacyImportDecision)
        guard legacyImportDecision.allowsLegacyImport, persistor.hasLegacyCacheFile(for: workspaceId) else {
            return
        }
        canArchiveLegacyCacheFile = await materializeSQLiteIfNeeded(for: workspaceId)
    }

    func flush(for workspaceId: UUID) throws {
        guard sqliteDatastore == nil else {
            preconditionFailure("Use await flushAsync(for:) when SQLite datastore is enabled")
        }
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try persistLegacyJSONNow(for: workspaceId)
        lastPersistedProjection = currentPersistedProjection()
    }

    func flushAsync(for workspaceId: UUID) async throws {
        activeWorkspaceId = workspaceId
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try await persistNow(for: workspaceId)
    }

    private func observeCacheState() {
        guard !isObservingCacheState else { return }
        isObservingCacheState = true
        withObservationTracking {
            _ = cacheAtom.repoEnrichmentByRepoId
            _ = cacheAtom.worktreeEnrichmentByWorktreeId
            _ = cacheAtom.pullRequestCountByWorktreeId
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
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        debouncedSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration, workspaceId] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try await self.persistNow(for: workspaceId, force: false)
            } catch {
                repoCacheStoreLogger.warning("Repo cache autosave failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistNow(for workspaceId: UUID, force: Bool = true) async throws {
        let persistedProjection = currentPersistedProjection()
        guard force || persistedProjection != lastPersistedProjection else { return }
        do {
            if let sqliteDatastore {
                try await sqliteDatastore.saveRepoCacheState(
                    cacheState: currentCacheStateRecord(),
                    recentTargets: recentTargetAtom.recentTargets,
                    workspaceId: workspaceId
                )
                lastPersistedProjection = persistedProjection
                return
            }
            try persistLegacyJSONNow(for: workspaceId)
            lastPersistedProjection = persistedProjection
        } catch {
            recoveryReporter?(
                .init(store: .repoCache, workspaceId: workspaceId, recovery: .saveFailed)
            )
            throw error
        }
    }

    private func persistLegacyJSONNow(for workspaceId: UUID) throws {
        guard persistor.ensureDirectory() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try persistor.saveCache(
            .init(
                workspaceId: workspaceId,
                repoEnrichmentByRepoId: cacheAtom.repoEnrichmentByRepoId,
                worktreeEnrichmentByWorktreeId: cacheAtom.worktreeEnrichmentByWorktreeId,
                pullRequestCountByWorktreeId: cacheAtom.pullRequestCountByWorktreeId,
                recentTargets: recentTargetAtom.recentTargets,
                sourceRevision: cacheAtom.sourceRevision,
                lastRebuiltAt: cacheAtom.lastRebuiltAt
            )
        )
    }

    private enum SQLiteRestoreOutcome {
        case restored
        case missing(WorkspaceLocalSQLiteLegacyImportDecision, recoveryEvents: [PersistenceRecoveryEvent])
        case unavailable(recoveryEvents: [PersistenceRecoveryEvent])
    }

    private func restoreFromSQLite(
        for workspaceId: UUID,
        sqliteDatastore: WorkspaceSQLiteDatastore
    ) async -> SQLiteRestoreOutcome {
        switch await sqliteDatastore.loadRepoCacheState(workspaceId: workspaceId) {
        case .loaded(let payload):
            guard let cacheState = payload.cacheState,
                let recentTargets = payload.recentTargets
            else {
                return .missing(
                    combinedLegacyDecision(
                        cacheDecision: payload.cacheLegacyDecision,
                        recentTargetDecision: payload.recentTargetLegacyDecision
                    ),
                    recoveryEvents: payload.recoveryEvents
                )
            }
            isRestoringState = true
            cacheAtom.hydrate(
                .init(
                    repoEnrichmentByRepoId: cacheState.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheState.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: cacheState.pullRequestCountByWorktreeId,
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
            recentTargetAtom.hydrate(recentTargets: recentTargets)
            isRestoringState = false
            lastPersistedProjection = currentPersistedProjection()
            return .restored
        case .unavailable(let failure, let recoveryEvents):
            isRestoringState = false
            repoCacheStoreLogger.warning("Repo cache SQLite restore failed: \(failure.description)")
            return .unavailable(recoveryEvents: recoveryEvents)
        }
    }

    private func combinedLegacyDecision(
        cacheDecision: WorkspaceLocalSQLiteLegacyImportDecision,
        recentTargetDecision: WorkspaceLocalSQLiteLegacyImportDecision
    ) -> WorkspaceLocalSQLiteLegacyImportDecision {
        if cacheDecision.allowsLegacyImport, recentTargetDecision.allowsLegacyImport {
            return .allowImport
        }
        if cacheDecision.canArchiveLegacyFile, recentTargetDecision.canArchiveLegacyFile {
            return .blockReplayAllowArchive
        }
        return .blockReplayBlockArchive
    }

    private func materializeSQLiteIfNeeded(for workspaceId: UUID) async -> Bool {
        guard sqliteDatastore != nil else { return true }
        do {
            try await persistNow(for: workspaceId, force: true)
            return true
        } catch {
            repoCacheStoreLogger.warning(
                "Repo cache legacy import materialization failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func currentCacheStateRecord() -> WorkspaceLocalRepository.CacheStateRecord {
        .init(
            repoEnrichmentByRepoId: cacheAtom.repoEnrichmentByRepoId,
            worktreeEnrichmentByWorktreeId: cacheAtom.worktreeEnrichmentByWorktreeId,
            pullRequestCountByWorktreeId: cacheAtom.pullRequestCountByWorktreeId,
            sourceRevision: cacheAtom.sourceRevision,
            lastRebuiltAt: cacheAtom.lastRebuiltAt
        )
    }

    private func currentPersistedProjection() -> PersistedProjection {
        .init(
            cacheState: currentCacheStateRecord(),
            recentTargets: recentTargetAtom.recentTargets
        )
    }

    private func reportRecoveryEvents(_ recoveryEvents: [PersistenceRecoveryEvent]) {
        for recoveryEvent in recoveryEvents {
            recoveryReporter?(recoveryEvent)
        }
    }

    private struct PersistedProjection: Equatable {
        let repoEnrichmentByRepoId: [UUID: RepoEnrichmentProjection]
        let worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichmentProjection]
        let pullRequestCountByWorktreeId: [UUID: Int]
        let sourceRevision: UInt64
        let lastRebuiltAt: Date?
        let recentTargets: [RecentWorkspaceTarget]

        init(
            cacheState: WorkspaceLocalRepository.CacheStateRecord,
            recentTargets: [RecentWorkspaceTarget]
        ) {
            repoEnrichmentByRepoId = cacheState.repoEnrichmentByRepoId.mapValues {
                RepoEnrichmentProjection(enrichment: $0)
            }
            worktreeEnrichmentByWorktreeId = cacheState.worktreeEnrichmentByWorktreeId.mapValues {
                WorktreeEnrichmentProjection(enrichment: $0)
            }
            pullRequestCountByWorktreeId = cacheState.pullRequestCountByWorktreeId
            sourceRevision = cacheState.sourceRevision
            lastRebuiltAt = cacheState.lastRebuiltAt
            self.recentTargets = recentTargets
        }
    }

    private enum RepoEnrichmentProjection: Equatable {
        case awaitingOrigin(repoId: UUID)
        case resolvedLocal(repoId: UUID, identity: RepoIdentity)
        case resolvedRemote(repoId: UUID, raw: RawRepoOrigin, identity: RepoIdentity)

        init(enrichment: RepoEnrichment) {
            switch enrichment {
            case .awaitingOrigin(let repoId):
                self = .awaitingOrigin(repoId: repoId)
            case .resolvedLocal(let repoId, let identity, _):
                self = .resolvedLocal(repoId: repoId, identity: identity)
            case .resolvedRemote(let repoId, let raw, let identity, _):
                self = .resolvedRemote(repoId: repoId, raw: raw, identity: identity)
            }
        }
    }

    private struct WorktreeEnrichmentProjection: Equatable {
        let worktreeId: UUID
        let repoId: UUID
        let branch: String
        let isMainWorktree: Bool

        init(enrichment: WorktreeEnrichment) {
            worktreeId = enrichment.worktreeId
            repoId = enrichment.repoId
            branch = enrichment.branch
            isMainWorktree = enrichment.isMainWorktree
        }
    }
}
