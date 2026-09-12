import AgentStudioInfrastructure
import Foundation
import Observation
import os.log

private let repositoryTopologyStoreLogger = Logger(subsystem: "com.agentstudio", category: "RepositoryTopologyStore")

@MainActor
package final class RepositoryTopologyStore {
    private let atom: RepositoryTopologyAtom
    private let sqliteDatastore: WorkspaceSQLiteDatastore?
    private let persistDebounceDuration: Duration
    private let delay: AsyncDelay
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingTopology = false
    private(set) var isDirty = false
    private var saveTail: Task<Void, Error>?
    private var saveTailGeneration: UInt64 = 0
    private var pendingReparenting: [PendingReparenting] = []

    private struct PendingReparenting: Sendable {
        let revision: UInt64
        let transitions: [RepositoryWorktreeReparenting]
    }

    package func recordReparenting(_ transitions: [RepositoryWorktreeReparenting], revision: UInt64) {
        guard !transitions.isEmpty else { return }
        pendingReparenting.append(.init(revision: revision, transitions: transitions))
    }

    package var isAutosaveObservationActive: Bool {
        isObservingTopology
    }

    package init(
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

    package func startObserving() {
        observeTopology()
    }

    package func flushAsync() async throws {
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
        let previous = saveTail
        saveTailGeneration &+= 1
        let generation = saveTailGeneration
        let operation = Task { @MainActor [self] in
            if let previous { _ = try? await previous.value }
            try await persistCurrentCapture()
        }
        saveTail = operation
        defer { if generation == saveTailGeneration { saveTail = nil } }
        try await operation.value
    }

    private func persistCurrentCapture() async throws {
        guard let sqliteDatastore else { return }
        let captureRevision = atom.lifecycleRevision
        let pending = pendingReparenting
        let repositories = atom.repos
        let unavailableRepositoryIDs = atom.unavailableRepoIds
        let watchedPaths = atom.watchedPaths
        let snapshot = await WorkspacePersistenceTransformer.makeRepositoryTopologySQLiteSnapshotOffMain(
            repositories: repositories,
            stableIdentity: RepositoryTopologyStableIdentity(
                repositoryStableKeysByID: atom.repositoryStableKeysByID,
                worktreeStableKeysByID: atom.worktreeStableKeysByID,
                watchedPathStableKeysByID: atom.watchedPathStableKeysByID
            ),
            unavailableRepositoryIDs: unavailableRepositoryIDs,
            watchedPaths: watchedPaths,
            persistedAt: Date(),
            absenceRecords: atom.absenceRecords
        )
        let reparenting = await Self.coalesceReparenting(pending, snapshot: snapshot)
        try await sqliteDatastore.saveRepositoryTopologySnapshot(
            snapshot, captureRevision: captureRevision, reparenting: reparenting
        )
        pendingReparenting.removeAll { $0.revision <= captureRevision }
        isDirty = atom.lifecycleRevision != captureRevision
    }
    @concurrent nonisolated private static func coalesceReparenting(
        _ pending: [PendingReparenting],
        snapshot: RepositoryTopologySQLiteSnapshot
    ) async -> [RepositoryWorktreeReparenting] {
        var transitionsByID: [UUID: RepositoryWorktreeReparenting] = [:]
        for batch in pending {
            for transition in batch.transitions {
                let first = transitionsByID[transition.worktreeID] ?? transition
                transitionsByID[transition.worktreeID] = .init(
                    worktreeID: transition.worktreeID,
                    expectedRepositoryID: first.expectedRepositoryID,
                    repositoryID: transition.repositoryID
                )
            }
        }
        return snapshot.worktrees.compactMap { worktree in
            guard let transition = transitionsByID[worktree.id],
                transition.repositoryID == worktree.repoId,
                transition.expectedRepositoryID != transition.repositoryID
            else { return nil }
            return transition
        }
    }

}
