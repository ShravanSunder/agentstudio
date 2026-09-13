import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Repository topology store", .serialized)
struct RepositoryTopologyStoreTests {
    @Test("timed absence survives unrelated topology saves and restore")
    func timedAbsenceSurvivesTopologyRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "topology-absence-roundtrip-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: directory.appending(path: "core.sqlite"),
            localDatabaseURL: directory.appending(path: "local.sqlite")
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected prepared databases")
            return
        }
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repository = coordinator.addRepo(at: directory.appending(path: "repository"))
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1
        )
        #expect(coordinator.recordRepositoryAbsence(repository.id, at: start))
        let original = atom.absenceRecords
        let store = RepositoryTopologyStore(atom: atom, sqliteDatastore: datastore)
        try await store.flushAsync()
        coordinator.setRepoPinned(repository.id, isPinned: true)
        #expect(
            !coordinator.recordRepositoryAbsence(
                repository.id,
                at: RepositoryRetentionTime(
                    utc: start.utc.addingTimeInterval(86_400), bootID: start.bootID,
                    uptimeNanoseconds: start.uptimeNanoseconds + 86_400_000_000_000
                )))
        try await store.flushAsync()

        guard case .loaded(let snapshot) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected saved absence records")
            return
        }
        #expect(snapshot.absenceRecords == original)
        guard case .prepared(let restored) = WorkspacePersistenceTransformer.prepareRepositoryTopology(snapshot) else {
            Issue.record("expected valid restored topology")
            return
        }
        #expect(restored.absenceRecords == original)
        #expect(snapshot.repos.first?.isPinned == true)
    }

    @Test("failed flush keeps observation armed and a later retry persists current topology")
    func failedFlushRetainsObservationAndRetryEligibility() async throws {
        // Arrange
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "repository-topology-store-retry-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: temporaryDirectory.appending(path: "core.sqlite"),
            localDatabaseURL: temporaryDirectory.appending(path: "local.sqlite")
        ).makeDatastore()
        let topologyAtom = RepositoryTopologyAtom()
        let topologyStore = RepositoryTopologyStore(atom: topologyAtom, sqliteDatastore: datastore)
        topologyStore.startObserving()

        // Act: the boot-style barrier runs before database preparation and fails.
        var initialFlushFailed = false
        do {
            try await topologyStore.flushAsync()
        } catch {
            initialFlushFailed = true
        }

        // Assert: failure does not disarm canonical observation.
        #expect(initialFlushFailed)
        #expect(topologyStore.isAutosaveObservationActive)

        // Act: a later accepted topology change is still observed and can be retried.
        let repositoryID = UUIDv7.generate()
        let repositoryPath = temporaryDirectory.appending(path: "repository")
        let repository = Repo(
            id: repositoryID,
            name: repositoryPath.lastPathComponent,
            repoPath: repositoryPath,
            worktrees: [
                Worktree(
                    id: UUIDv7.generate(),
                    repoId: repositoryID,
                    name: repositoryPath.lastPathComponent,
                    path: repositoryPath,
                    isMainWorktree: true
                )
            ]
        )
        guard
            case .prepared(let replacement) = RepositoryTopologyReplacement.prepare(
                repositories: [repository],
                watchedPaths: [],
                unavailableRepositoryIDs: []
            )
        else {
            Issue.record("expected valid topology replacement")
            return
        }
        topologyAtom.replaceTopology(replacement)
        for _ in 0..<20 where !topologyStore.isDirty {
            await Task.yield()
        }
        #expect(topologyStore.isDirty)
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected retry datastore preparation")
            return
        }
        try await topologyStore.flushAsync()

        // Assert
        #expect(topologyStore.isAutosaveObservationActive)
        #expect(!topologyStore.isDirty)
        guard case .loaded(let persistedTopology) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected persisted topology after retry")
            return
        }
        #expect(persistedTopology.repos.map(\.id) == [repositoryID])
    }
}
