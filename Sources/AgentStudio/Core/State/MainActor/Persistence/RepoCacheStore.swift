import Foundation
import Observation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

struct RepoCacheSaveCapture: Sendable {
    let repoEnrichmentByRepoID: [UUID: RepoEnrichment]
    let worktreeEnrichmentByWorktreeID: [UUID: WorktreeEnrichment]
    let pullRequestCountByWorktreeID: [UUID: Int]
    let sourceRevision: UInt64
    let lastRebuiltAt: Date?
    let recentTargets: [RecentWorkspaceTarget]
}

struct RepoCachePersistedProjection: Equatable, Sendable {
    let repoEnrichmentByRepoID: [UUID: RepoCacheRepoEnrichmentProjection]
    let worktreeEnrichmentByWorktreeID: [UUID: RepoCacheWorktreeEnrichmentProjection]
    let pullRequestCountByWorktreeID: [UUID: Int]
    let sourceRevision: UInt64
    let lastRebuiltAt: Date?
    let recentTargets: [RecentWorkspaceTarget]
}

enum RepoCacheRepoEnrichmentProjection: Equatable, Sendable {
    case awaitingOrigin(repoID: UUID)
    case resolvedLocal(repoID: UUID, identity: RepoIdentity)
    case resolvedRemote(repoID: UUID, raw: RawRepoOrigin, identity: RepoIdentity)

    init(enrichment: RepoEnrichment) {
        switch enrichment {
        case .awaitingOrigin(let repoID):
            self = .awaitingOrigin(repoID: repoID)
        case .resolvedLocal(let repoID, let identity, _):
            self = .resolvedLocal(repoID: repoID, identity: identity)
        case .resolvedRemote(let repoID, let raw, let identity, _):
            self = .resolvedRemote(repoID: repoID, raw: raw, identity: identity)
        }
    }
}

struct RepoCacheWorktreeEnrichmentProjection: Equatable, Sendable {
    let worktreeID: UUID
    let repoID: UUID
    let branch: String
    let isMainWorktree: Bool

    init(enrichment: WorktreeEnrichment) {
        worktreeID = enrichment.worktreeId
        repoID = enrichment.repoId
        branch = enrichment.branch
        isMainWorktree = enrichment.isMainWorktree
    }
}

struct PreparedRepoCacheSave: Sendable {
    let cacheState: WorkspaceLocalRepository.CacheStateRecord
    let recentTargets: [RecentWorkspaceTarget]
    let projection: RepoCachePersistedProjection
    let shouldPersist: Bool
}

enum RepoCacheSavePreparer {
    @concurrent nonisolated static func prepareOffMain(
        capture: RepoCacheSaveCapture,
        previousProjection: RepoCachePersistedProjection?,
        force: Bool
    ) async -> PreparedRepoCacheSave {
        let cacheState = WorkspaceLocalRepository.CacheStateRecord(
            repoEnrichmentByRepoId: capture.repoEnrichmentByRepoID,
            worktreeEnrichmentByWorktreeId: capture.worktreeEnrichmentByWorktreeID,
            pullRequestCountByWorktreeId: capture.pullRequestCountByWorktreeID,
            sourceRevision: capture.sourceRevision,
            lastRebuiltAt: capture.lastRebuiltAt
        )
        let projection = RepoCachePersistedProjection(
            repoEnrichmentByRepoID: capture.repoEnrichmentByRepoID.mapValues {
                RepoCacheRepoEnrichmentProjection(enrichment: $0)
            },
            worktreeEnrichmentByWorktreeID: capture.worktreeEnrichmentByWorktreeID.mapValues {
                RepoCacheWorktreeEnrichmentProjection(enrichment: $0)
            },
            pullRequestCountByWorktreeID: capture.pullRequestCountByWorktreeID,
            sourceRevision: capture.sourceRevision,
            lastRebuiltAt: capture.lastRebuiltAt,
            recentTargets: capture.recentTargets
        )
        return PreparedRepoCacheSave(
            cacheState: cacheState,
            recentTargets: capture.recentTargets,
            projection: projection,
            shouldPersist: force || projection != previousProjection
        )
    }
}

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
    private var lastPersistedProjection: RepoCachePersistedProjection?
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
        let capture = captureCurrentSaveState()
        lastPersistedProjection = await RepoCacheSavePreparer.prepareOffMain(
            capture: capture,
            previousProjection: nil,
            force: true
        ).projection
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
        let capture = captureCurrentSaveState()
        let preparedSave = await RepoCacheSavePreparer.prepareOffMain(
            capture: capture,
            previousProjection: lastPersistedProjection,
            force: force
        )
        guard preparedSave.shouldPersist else { return }
        do {
            try await sqliteDatastore.saveRepoCacheState(
                cacheState: preparedSave.cacheState,
                recentTargets: preparedSave.recentTargets,
                workspaceId: workspaceId
            )
            lastPersistedProjection = preparedSave.projection
        } catch {
            recoveryReporter?(
                .init(store: .repoCache, workspaceId: workspaceId, recovery: .saveFailed)
            )
            throw error
        }
    }

    func captureCurrentSaveState() -> RepoCacheSaveCapture {
        RepoCacheSaveCapture(
            repoEnrichmentByRepoID: cacheAtom.repoEnrichmentSnapshot(),
            worktreeEnrichmentByWorktreeID: cacheAtom.worktreeEnrichmentSnapshot(),
            pullRequestCountByWorktreeID: cacheAtom.pullRequestCountSnapshot(),
            sourceRevision: cacheAtom.sourceRevision,
            lastRebuiltAt: cacheAtom.lastRebuiltAt,
            recentTargets: recentTargetAtom.recentTargets
        )
    }

    private func reportRecoveryEvents(_ recoveryEvents: [PersistenceRecoveryEvent]) {
        for recoveryEvent in recoveryEvents {
            recoveryReporter?(recoveryEvent)
        }
    }
}
