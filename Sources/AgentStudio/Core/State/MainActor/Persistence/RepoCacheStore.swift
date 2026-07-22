import Foundation
import Observation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

@MainActor
final class RepoCacheStore {
    private let cacheAtom: RepoEnrichmentCacheAtom
    private let recentTargetAtom: RecentWorkspaceTargetAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    private var lastPersistedProjection: PersistedProjection?
    var isAutosaveObservationActive: Bool {
        isObservingCacheState
    }

    init(
        cacheAtom: RepoEnrichmentCacheAtom,
        recentTargetAtom: RecentWorkspaceTargetAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.cacheAtom = cacheAtom
        self.recentTargetAtom = recentTargetAtom
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.recoveryReporter = recoveryReporter
    }

    convenience init(
        atom: RepoCacheAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.init(
            cacheAtom: atom.enrichmentCacheAtom,
            recentTargetAtom: atom.recentTargetAtom,
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

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        switch await sqliteDatastore.loadRepoCacheState(workspaceId: workspaceId) {
        case .loaded(let payload):
            isRestoringState = true
            let cacheState = payload.cacheState
            cacheAtom.hydrate(
                .init(
                    repoEnrichmentByRepoId: cacheState.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheState.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: cacheState.pullRequestCountByWorktreeId,
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
            recentTargetAtom.hydrate(recentTargets: payload.recentTargets)
            isRestoringState = false
            reportRecoveryEvents(payload.recoveryEvents)
        case .unavailable(let failure, let recoveryEvents):
            isRestoringState = false
            cacheAtom.clear()
            recentTargetAtom.clear()
            reportRecoveryEvents(recoveryEvents)
            repoCacheStoreLogger.warning("Repo cache SQLite restore failed: \(failure.description)")
            recoveryReporter?(
                .init(
                    store: .repoCache,
                    workspaceId: workspaceId,
                    recovery: .resetToDefaults
                )
            )
        }
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
            _ = cacheAtom.cacheRevision
            _ = recentTargetAtom.recentTargets
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
            try await sqliteDatastore.saveRepoCacheState(
                cacheState: currentCacheStateRecord(),
                recentTargets: recentTargetAtom.recentTargets,
                workspaceId: workspaceId
            )
            lastPersistedProjection = persistedProjection
        } catch {
            recoveryReporter?(
                .init(store: .repoCache, workspaceId: workspaceId, recovery: .saveFailed)
            )
            throw error
        }
    }

    private func currentCacheStateRecord() -> WorkspaceLocalRepository.CacheStateRecord {
        .init(
            repoEnrichmentByRepoId: cacheAtom.repoEnrichmentSnapshot(),
            worktreeEnrichmentByWorktreeId: cacheAtom.worktreeEnrichmentSnapshot(),
            pullRequestCountByWorktreeId: cacheAtom.pullRequestCountSnapshot(),
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
