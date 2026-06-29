import Foundation
import Observation
import os.log

private let repositoryTopologyStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepositoryTopologyStore")

@MainActor
final class RepositoryTopologyStore {
    private let atom: RepositoryTopologyAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let saveCoordinator: WorkspaceSQLiteSaveCoordinator?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private let recoveryReporter: PersistenceRecoveryReporter?
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingTopology = false
    private var isRestoringState = false
    private var activeWorkspaceId: UUID?
    private(set) var isDirty = false

    var isAutosaveObservationActive: Bool {
        isObservingTopology
    }

    init(
        atom: RepositoryTopologyAtom,
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        saveCoordinator: WorkspaceSQLiteSaveCoordinator? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil
    ) {
        self.atom = atom
        self.sqliteDatastore = sqliteDatastore
        self.saveCoordinator = saveCoordinator
        self.persistDebounceDuration = persistDebounceDuration
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
        self.recoveryReporter = recoveryReporter
    }

    func startObserving() {
        observeTopology()
    }

    func restoreAsync(for workspaceId: UUID) async {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        activeWorkspaceId = workspaceId
        guard let sqliteDatastore else { return }
        switch await sqliteDatastore.loadRepositoryTopologySnapshot(workspaceId: workspaceId) {
        case .loaded(let snapshot):
            isRestoringState = true
            WorkspacePersistenceTransformer.hydrateRepositoryTopology(snapshot, repositoryTopologyAtom: atom)
            isRestoringState = false
        case .uninitialized:
            break
        case .unavailable(let failure):
            repositoryTopologyStoreLogger.error(
                "Failed to restore repository topology: \(failure.description, privacy: .public)"
            )
            recoveryReporter?(.init(store: .workspace, workspaceId: workspaceId, recovery: .resetToDefaults))
        }
    }

    func flushAsync(for workspaceId: UUID) async throws {
        activeWorkspaceId = workspaceId
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
                let shouldIgnore = self.isRestoringState
                self.isObservingTopology = false
                self.observeTopology()
                guard !shouldIgnore else { return }
                self.schedulePersist()
            }
        }
    }

    private func schedulePersist() {
        guard activeWorkspaceId != nil else { return }
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
        guard let saveCoordinator else { return }
        _ = try await saveCoordinator.save(persistedAt: Date())
        isDirty = false
    }
}
