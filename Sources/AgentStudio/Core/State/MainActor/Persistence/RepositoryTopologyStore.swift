import Foundation
import Observation
import os.log

private let repositoryTopologyStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepositoryTopologyStore")

@MainActor
final class RepositoryTopologyStore {
    private let atom: RepositoryTopologyAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingTopology = false
    private(set) var isDirty = false

    var isAutosaveObservationActive: Bool {
        isObservingTopology
    }

    init(
        atom: RepositoryTopologyAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil
    ) {
        self.atom = atom
        self.sqliteDatastore = sqliteDatastore
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
    }

    func startObserving() {
        observeTopology()
    }

    func flushAsync() async throws {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        try await persistNow()
    }

    private func observeTopology() {
        guard !isObservingTopology else { return }
        isObservingTopology = true
        withObservationTracking {
            _ = atom.repos
            _ = atom.watchedPaths
            _ = atom.unavailableRepoIds
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isObservingTopology = false
                self.observeTopology()
                self.schedulePersist()
            }
        }
    }

    private func schedulePersist() {
        isDirty = true
        debouncedSaveTask?.cancel()
        let delay = self.delay
        let persistDebounceDuration = self.persistDebounceDuration
        debouncedSaveTask = Task { @MainActor [weak self, delay, persistDebounceDuration] in
            try? await delay.wait(persistDebounceDuration)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try await self.persistNow()
            } catch {
                repositoryTopologyStoreLogger.warning(
                    "Repository topology autosave failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func persistNow() async throws {
        guard let sqliteDatastore else { return }
        let repositories = atom.repos
        let unavailableRepositoryIDs = atom.unavailableRepoIds
        let watchedPaths = atom.watchedPaths
        let snapshot = await WorkspacePersistenceTransformer.makeRepositoryTopologySQLiteSnapshotOffMain(
            repositories: repositories,
            unavailableRepositoryIDs: unavailableRepositoryIDs,
            watchedPaths: watchedPaths,
            persistedAt: Date()
        )
        try await sqliteDatastore.saveRepositoryTopologySnapshot(snapshot)
        isDirty = false
    }
}
