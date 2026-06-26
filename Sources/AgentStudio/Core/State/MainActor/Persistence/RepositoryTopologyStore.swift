import Foundation
import Observation
import os.log

private let repositoryTopologyStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepositoryTopologyStore")

/// Main-actor persistence boundary for repository topology.
///
/// Live topology mutations remain owned by `RepositoryTopologyAtom`; this store
/// owns restore/observe/flush participation for that atom.
@MainActor
final class RepositoryTopologyStore {
    let repositoryTopologyAtom: RepositoryTopologyAtom

    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingPersistedState = false
    private var isRestoringState = false
    private(set) var isDirty: Bool = false
    private var canonicalFlushHandler: (@MainActor @Sendable () async -> Bool)?
    private var canonicalDirtyHandler: (@MainActor @Sendable () -> Void)?
    private var canonicalCleanHandler: (@MainActor @Sendable () -> Void)?

    var isAutosaveObservationActive: Bool {
        isObservingPersistedState
    }

    init(
        repositoryTopologyAtom: RepositoryTopologyAtom = RepositoryTopologyAtom(),
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil
    ) {
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        self.delay = clock.map(AsyncDelay.clock) ?? .taskSleep
    }

    func startObserving() {
        guard !isObservingPersistedState else { return }
        isObservingPersistedState = true
        withObservationTracking {
            _ = repositoryTopologyAtom.repos
            _ = repositoryTopologyAtom.watchedPaths
            _ = repositoryTopologyAtom.unavailableRepoIds
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shouldIgnore = self.isRestoringState
                self.isObservingPersistedState = false
                self.startObserving()
                guard !shouldIgnore else { return }
                self.markDirtyObserved()
            }
        }
    }

    func markRestoring(_ isRestoring: Bool) {
        isRestoringState = isRestoring
    }

    func setCanonicalFlushHandler(_ handler: @escaping @MainActor @Sendable () async -> Bool) {
        canonicalFlushHandler = handler
    }

    func setCanonicalDirtyStateHandlers(
        markDirty: @escaping @MainActor @Sendable () -> Void,
        markClean: @escaping @MainActor @Sendable () -> Void
    ) {
        canonicalDirtyHandler = markDirty
        canonicalCleanHandler = markClean
    }

    func restoreTopology(from context: WorkspaceSQLiteDatastore.ResolvedWorkspaceRestoreContext) {
        hydrateTopologyProjection(RepositoryTopologyPersistenceBridge.runtimeTopology(from: context.topology))
    }

    @discardableResult
    func flushAsync() async -> Bool {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        guard let canonicalFlushHandler else {
            repositoryTopologyStoreLogger.debug(
                "Skipping topology flush because canonical flush handler is unavailable")
            return false
        }
        let succeeded = await canonicalFlushHandler()
        if succeeded {
            markCanonicalPersistenceSucceeded()
        }
        return succeeded
    }

    func restoreTopology(workspaceId: UUID) async -> Bool {
        guard let sqliteDatastore else {
            repositoryTopologyStoreLogger.debug("Skipping topology restore because SQLite datastore is unavailable")
            return false
        }
        switch await sqliteDatastore.loadRepositoryTopology(workspaceId: workspaceId) {
        case .loaded(let topology):
            hydrateTopologyProjection(RepositoryTopologyPersistenceBridge.runtimeTopology(from: topology))
            return true
        case .uninitialized:
            return false
        case .unavailable(let failure, _):
            repositoryTopologyStoreLogger.error("Failed to restore topology: \(failure.description, privacy: .public)")
            return false
        }
    }

    private func markDirtyObserved() {
        if !isDirty {
            isDirty = true
            canonicalDirtyHandler?()
        }

        debouncedSaveTask?.cancel()
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        debouncedSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.persistDebouncedAutosave()
        }
    }

    private func persistDebouncedAutosave() async {
        guard sqliteDatastore != nil else {
            repositoryTopologyStoreLogger.debug("Skipping topology autosave because SQLite datastore is unavailable")
            return
        }
        await flushAsync()
    }

    private func hydrateTopologyProjection(
        _ projection: RepositoryTopologyPersistenceBridge.RuntimeTopologyProjection
    ) {
        markRestoring(true)
        defer { markRestoring(false) }
        repositoryTopologyAtom.hydrate(
            runtimeRepos: projection.repos,
            watchedPaths: projection.watchedPaths,
            unavailableRepoIds: projection.unavailableRepoIds
        )
    }

    func markCanonicalPersistenceSucceeded() {
        if isDirty {
            isDirty = false
            canonicalCleanHandler?()
        }
    }
}
