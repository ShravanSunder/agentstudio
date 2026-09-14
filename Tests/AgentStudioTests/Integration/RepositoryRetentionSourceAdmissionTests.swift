import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repository retention source admission", .serialized)
struct RepositoryRetentionSourceAdmissionTests {
    enum Scenario: CaseIterable, Sendable { case supersededBeforeReservation, unrelatedWatch }

    @Test("expiry preserves source currentness and scans only affected watches", arguments: Scenario.allCases)
    func expiryAdmissionUsesCurrentAffectedScopes(_ scenario: Scenario) async throws {
        try await withAsyncTestCoreAtoms { _ in
            let root = FileManager.default.temporaryDirectory.appending(
                path: "retention-source-admission-\(UUIDv7.generate())")
            let watchedRoot = root.appending(path: "due")
            let unrelatedRoot = root.appending(path: "unrelated")
            try FileManager.default.createDirectory(at: watchedRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: unrelatedRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let datastore = WorkspaceSQLiteDatastoreFactory(
                coreDatabaseURL: root.appending(path: "core.sqlite"),
                localDatabaseURL: root.appending(path: "local.sqlite")
            ).makeDatastore()
            guard case .prepared = await datastore.prepareDatabasesForBoot() else {
                Issue.record("expected prepared persistence fixture")
                return
            }
            let store = WorkspaceStore()
            let watch = try #require(store.mutationCoordinator.addWatchedPath(watchedRoot))
            let unrelatedWatch = try #require(store.mutationCoordinator.addWatchedPath(unrelatedRoot))
            let repository = store.addRepo(at: watchedRoot.appending(path: "repository"))
            let start = try await RepositoryRetentionTime.current()
            #expect(store.mutationCoordinator.recordRepositoryAbsence(repository.id, at: start))
            let persistence = RepositoryTopologyStore(atom: store.repositoryTopologyAtom, sqliteDatastore: datastore)
            try await persistence.flushAsync()
            let scans = ControllableWatchedFolderScanSchedulerResults()
            scans.setResults([watch: [], unrelatedWatch: []])
            let filesystem = FilesystemActor(
                bus: EventBus<RuntimeEnvelope>(), fseventStreamClient: ControllableFSEventStreamClient(),
                watchedFolderScanScheduler: scans.makeScheduler())
            _ = await filesystem.refreshWatchedFolders(
                [watch, unrelatedWatch], restoring: store.repositoryTopologyAtom.repos,
                membershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration)
            let initialScanCount = scans.requestedWatchedPathIDs.count
            let reference = RetentionAdmissionCoordinatorReference()
            let supersession = RetentionAdmissionSupersession()
            let coordinator = WorkspaceCacheCoordinator(
                workspaceStore: store, repoCache: RepoCacheAtom(), topologyPersistence: persistence,
                retentionNow: {
                    if scenario == .supersededBeforeReservation, await supersession.consumeArmedSupersession() {
                        scans.setResults([watch: [], unrelatedWatch: []], partial: true)
                        let registrations = await filesystem.watchedFolderScanState.registrationsBySourceID
                        if let registration = registrations.values.first(where: { $0.watchedPath.id == watch.id }) {
                            await filesystem.handleWatchedFolderFSEvent(
                                FSEventBatch(
                                    worktreeId: registration.legacyCallbackRoutingID,
                                    paths: [watchedRoot.appending(path: ".git/index").path]))
                        }
                    }
                    return .init(
                        utc: start.utc, bootID: start.bootID,
                        uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000)
                },
                refreshRetentionScopes: { paths, repositories, revision, scopeIDs in
                    _ = await filesystem.refreshWatchedFolders(
                        paths, restoring: repositories, membershipRevision: revision, scanning: scopeIDs)
                    return await filesystem.currentWatchedFolderObservationReceipts()
                },
                validateSourceObservations: { observations in
                    let current = await filesystem.areCurrentWatchedFolderObservations(observations)
                    if current,
                        let observation = observations.first(where: { $0.registration.sourceID.rootID == watch.id }),
                        await reference.hasApplied(observation.registration.sourceID)
                    {
                        await supersession.arm()
                    }
                    return current
                }, scopeSyncHandler: { _ in })
            reference.coordinator = coordinator
            do {
                await coordinator.collectRetainedRepositories()

                let registrations = await filesystem.watchedFolderScanState.registrationsBySourceID
                #expect(Set(registrations.values.map { $0.watchedPath.id }) == Set([watch.id, unrelatedWatch.id]))
                switch scenario {
                case .supersededBeforeReservation:
                    #expect(await supersession.didSupersede)
                    #expect(store.repositoryTopologyAtom.repo(repository.id) != nil)
                    guard case .loaded(let snapshot) = await datastore.loadRepositoryTopologySnapshot() else {
                        Issue.record("expected durable topology readback")
                        await coordinator.shutdown()
                        await filesystem.shutdown()
                        return
                    }
                    #expect(snapshot.repos.contains { $0.id == repository.id })
                case .unrelatedWatch:
                    let retentionRequests = scans.requestedWatchedPathIDs.dropFirst(initialScanCount)
                    #expect(!retentionRequests.contains(unrelatedWatch.id))
                    #expect(retentionRequests.contains(watch.id))
                    #expect(store.repositoryTopologyAtom.repo(repository.id) == nil)
                }
            }
            await coordinator.shutdown()
            await filesystem.shutdown()
        }
    }
}

@MainActor
private final class RetentionAdmissionCoordinatorReference {
    weak var coordinator: WorkspaceCacheCoordinator?

    func hasApplied(_ sourceID: FilesystemSourceID) -> Bool {
        coordinator?.appliedScopeSequences[sourceID] != nil
    }
}

private actor RetentionAdmissionSupersession {
    private var isArmed = false
    private(set) var didSupersede = false

    func arm() { isArmed = true }

    func consumeArmedSupersession() -> Bool {
        guard isArmed, !didSupersede else { return false }
        didSupersede = true
        return true
    }
}
