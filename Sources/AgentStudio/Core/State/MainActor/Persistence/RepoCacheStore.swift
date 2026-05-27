import Foundation
import Observation
import os.log

private let repoCacheStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepoCacheStore")

@MainActor
final class RepoCacheStore {
    private let atom: RepoCacheAtom
    private let persistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingCacheState = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?

    init(
        atom: RepoCacheAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock(),
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.persistor = persistor
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
        self.recoveryReporter = recoveryReporter
    }

    /// Begin observing atom mutations for debounced autosave. Must be called by the
    /// owner (AppDelegate in production, individual tests in unit tests) after all
    /// boot-time mutations have settled. Installing observation inside `init` causes
    /// every boot-time atom mutation (pruneStaleCache, replayBootTopology) to spawn
    /// a debounce `Task` that races with other boot Tasks and trips the Swift 6.2
    /// task-allocator LIFO check on macOS 26.4 (swift#84793, firebase#15994).
    func startObserving() {
        observeCacheState()
    }

    func restore(for workspaceId: UUID) {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        switch persistor.loadCache(for: workspaceId) {
        case .loaded(let cacheState):
            isRestoringState = true
            atom.hydrate(
                .init(
                    repoEnrichmentByRepoId: cacheState.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: cacheState.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: cacheState.pullRequestCountByWorktreeId,
                    notificationCountByWorktreeId: cacheState.notificationCountByWorktreeId,
                    recentTargets: cacheState.recentTargets,
                    sourceRevision: cacheState.sourceRevision,
                    lastRebuiltAt: cacheState.lastRebuiltAt
                )
            )
            isRestoringState = false
        case .missing:
            break
        case .corrupt(let error):
            repoCacheStoreLogger.warning("Cache file corrupt, will rebuild from events: \(error)")
            recoveryReporter?(
                .init(
                    store: .repoCache,
                    workspaceId: workspaceId,
                    recovery: .rebuiltFromEvents
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
            _ = atom.repoEnrichmentByRepoId
            _ = atom.worktreeEnrichmentByWorktreeId
            _ = atom.pullRequestCountByWorktreeId
            _ = atom.notificationCountByWorktreeId
            _ = atom.recentTargets
            _ = atom.sourceRevision
            _ = atom.lastRebuiltAt
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                // RepoCacheAtom is @MainActor; this traps if that ownership changes.
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
            guard persistor.ensureDirectory() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try persistor.saveCache(
                .init(
                    workspaceId: workspaceId,
                    repoEnrichmentByRepoId: atom.repoEnrichmentByRepoId,
                    worktreeEnrichmentByWorktreeId: atom.worktreeEnrichmentByWorktreeId,
                    pullRequestCountByWorktreeId: atom.pullRequestCountByWorktreeId,
                    notificationCountByWorktreeId: atom.notificationCountByWorktreeId,
                    recentTargets: atom.recentTargets,
                    sourceRevision: atom.sourceRevision,
                    lastRebuiltAt: atom.lastRebuiltAt
                )
            )
        } catch {
            recoveryReporter?(
                .init(store: .repoCache, workspaceId: workspaceId, recovery: .saveFailed)
            )
            throw error
        }
    }
}
