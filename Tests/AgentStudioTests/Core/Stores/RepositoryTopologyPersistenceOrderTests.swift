import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Repository topology persistence order", .serialized)
struct RepositoryTopologyPersistenceOrderTests {
    @Test("a delayed topology capture cannot restore unavailable records")
    func delayedCaptureCannotRestoreUnavailableRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "topology-order-\(UUIDv7.generate())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: root.appending(path: "core.sqlite"),
            localDatabaseURL: root.appending(path: "local.sqlite")
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected prepared fixture databases")
            return
        }
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: root.appending(path: "repository"))
        let store = RepositoryTopologyStore(atom: atom, sqliteDatastore: datastore)
        let olderCaptureRevision = atom.lifecycleRevision
        try await store.flushAsync()
        guard case .loaded(let olderCapture) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected original persisted topology")
            return
        }
        #expect(
            coordinator.recordRepositoryAbsence(
                repo.id,
                at: .init(utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
            ))
        try await store.flushAsync()
        let confirmedAbsence = atom.absenceRecords

        do {
            try await datastore.saveRepositoryTopologySnapshot(olderCapture, captureRevision: olderCaptureRevision)
            Issue.record("older topology capture should be rejected")
        } catch {
            #expect(error as? WorkspaceSQLiteDatastoreError == .staleRepositoryTopologyCapture)
        }

        guard case .loaded(let persisted) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected current persisted topology")
            return
        }
        #expect(persisted.absenceRecords == confirmedAbsence)
        #expect(persisted.unavailableRepoIds == [repo.id])
    }
    @Test("coalesced family changes persist the original checkout once under its latest owner")
    func coalescedReparentingPersistsLatestOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "topology-reparent-\(UUIDv7.generate())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: root.appending(path: "core.sqlite"), localDatabaseURL: root.appending(path: "local.sqlite")
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected prepared fixture databases")
            return
        }
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let watched = try #require(coordinator.addWatchedPath(root))
        let first = coordinator.addRepo(at: root.appending(path: "first"))
        let second = coordinator.addRepo(at: root.appending(path: "second"))
        let third = coordinator.addRepo(at: root.appending(path: "third"))
        let checkout = Worktree(
            id: UUIDv7.generate(), repoId: first.id, name: "checkout", path: root.appending(path: "checkout"),
            note: "checkout note"
        )
        _ = coordinator.reconcileDiscoveredWorktrees(first.id, worktrees: first.worktrees + [checkout])
        let store = RepositoryTopologyStore(atom: atom, sqliteDatastore: datastore)
        try await store.flushAsync()

        for owner in [second, third] {
            var entries = [first, second, third].map {
                RepoScanner.ResolvedGitEntry(path: $0.repoPath, kind: .cloneRoot, repositoryKey: $0.repoPath.path)
            }
            entries.append(
                .init(
                    path: checkout.path, kind: .linkedWorktree(parentClonePath: owner.repoPath),
                    repositoryKey: owner.repoPath.path
                ))
            let observation = WatchedFolderTopologyObservation(
                root: root,
                registration: .init(
                    sourceID: .init(kind: .watchedParentMembership, rootID: watched.id),
                    registrationGeneration: 1, rootGeneration: 1),
                entries: entries, otherObservedPaths: [],
                coverage: .authoritative(
                    .init(utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)),
                baselineMembershipRevision: atom.worktreePathIndexGeneration, incompleteOtherScopes: []
            )
            guard
                case .prepared(let change) = await RepositoryLifecycleReconciliation.prepare(
                    coordinator.captureRepositoryLifecycleInput(), observation: observation
                )
            else {
                Issue.record("expected same-location family transition")
                return
            }
            #expect(coordinator.applyRepositoryLifecycleChange(change))
            store.recordReparenting(change.reparenting, revision: atom.lifecycleRevision)
        }
        try await store.flushAsync()
        try await store.flushAsync()

        guard case .loaded(let persisted) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected persisted final owner")
            return
        }
        let retained = try #require(persisted.worktrees.first { $0.id == checkout.id })
        #expect(retained.repoId == third.id)
        #expect(retained.note == checkout.note)
        #expect(persisted.worktrees.count == 4)
        #expect(persisted.repos.count == 3)
    }

}
