import AgentStudioInfrastructure
import Foundation
import Observation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

struct RepoCacheSaveCapture: Sendable {
    let repoEnrichmentByRepoID: [UUID: RepoEnrichment]
    let worktreeEnrichmentByWorktreeID: [UUID: WorktreeEnrichment]
    let sourceRevision: UInt64
    let lastRebuiltAt: Date?
}

struct RepoCachePersistedProjection: Equatable, Sendable {
    let repoEnrichmentByRepoID: [UUID: RepoCacheRepoEnrichmentProjection]
    let worktreeEnrichmentByWorktreeID: [UUID: RepoCacheWorktreeEnrichmentProjection]
    let sourceRevision: UInt64
    let lastRebuiltAt: Date?
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
            sourceRevision: capture.sourceRevision,
            lastRebuiltAt: capture.lastRebuiltAt
        )
        return PreparedRepoCacheSave(
            cacheState: cacheState,
            projection: projection,
            shouldPersist: force || projection != previousProjection
        )
    }
}

@MainActor
package final class RepoCacheStore {
    private let cacheAtom: RepoEnrichmentCacheAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    private var lastPersistedProjection: RepoCachePersistedProjection?
    package var isAutosaveObservationActive: Bool {
        isObservingCacheState
    }

    package init(
        cacheAtom: RepoEnrichmentCacheAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.cacheAtom = cacheAtom
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
    package func startObserving() {
        observeCacheState()
    }

    package func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        switch await sqliteDatastore.loadRepoCacheState() {
        case .loaded(let cacheState):
            isRestoringState = true
            cacheAtom.hydrate(
                .init(
                    repoEnrichmentByRepoId: cacheState.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheState.worktreeEnrichmentByWorktreeId,
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
            isRestoringState = false
        case .unavailable(let failure):
            isRestoringState = false
            cacheAtom.clear()
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

    package func flushAsync(for workspaceId: UUID) async throws {
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
                cacheState: preparedSave.cacheState
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
            sourceRevision: cacheAtom.sourceRevision,
            lastRebuiltAt: cacheAtom.lastRebuiltAt
        )
    }

}
