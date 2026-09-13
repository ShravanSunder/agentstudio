import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Repository retention publication admission", .serialized)
struct RepositoryRetentionPublicationAdmissionTests {
    @Test("boot reassociation waits for collection admission without changing canonical topology")
    func reassociationWaitsForCollectionReservation() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let originalPath = URL(fileURLWithPath: "/tmp/retention-boot-reassociation/original")
            let repository = store.addRepo(at: originalPath)
            let repairedPath = URL(fileURLWithPath: "/tmp/retention-boot-reassociation/repaired")
            let repairedCheckout = Worktree(
                id: UUIDv7.generate(), repoId: repository.id, name: "repaired", path: repairedPath, isMainWorktree: true
            )
            let coordinator = WorkspaceCacheCoordinator(
                workspaceStore: store, repoCache: RepoCacheAtom(), scopeSyncHandler: { _ in })
            coordinator.isCollectingRetainedLocations = true
            var finished = false
            let reassociation = Task {
                let result = await coordinator.reassociateRepo(
                    repoId: repository.id, to: repairedPath, discoveredWorktrees: [repairedCheckout])
                finished = true
                return result
            }
            await assertEventuallyMain("reassociation waits for admission or incorrectly finishes") {
                !coordinator.retentionMutationWaiters.isEmpty || finished
            }

            #expect(store.repositoryTopologyAtom.repo(repository.id)?.repoPath == originalPath)
            #expect(!finished)

            coordinator.isCollectingRetainedLocations = false
            let waiters = coordinator.retentionMutationWaiters
            coordinator.retentionMutationWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            let result = await reassociation.value
            if case .rejected = result { Issue.record("expected repaired topology after reservation release") }
            #expect(store.repositoryTopologyAtom.repo(repository.id)?.repoPath == repairedPath)
            await coordinator.shutdown()
        }
    }

    @Test("collection reservation acquired during source validation blocks scan publication")
    func reservationDuringValidationBlocksPublication() async throws {
        try await withAsyncTestCoreAtoms { _ in
            let store = WorkspaceStore()
            let root = URL(fileURLWithPath: "/tmp/retention-publication-admission")
            let watch = try #require(store.mutationCoordinator.addWatchedPath(root))
            let repository = store.addRepo(at: root.appending(path: "repository"))
            let checkout = try #require(repository.worktrees.first)
            store.markRepoUnavailable(repository.id)
            let gate = RetentionSourceValidationGate()
            let coordinator = WorkspaceCacheCoordinator(
                workspaceStore: store, repoCache: RepoCacheAtom(),
                validateSourceObservations: { _ in await gate.validate() }, scopeSyncHandler: { _ in })
            let observation = WatchedFolderTopologyObservation(
                root: root,
                registration: .init(
                    sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
                    registrationGeneration: 1, rootGeneration: 1),
                entries: [.init(path: repository.repoPath, kind: .cloneRoot, repositoryKey: repository.repoPath.path)],
                otherObservedPaths: [], coverage: .additive,
                baselineMembershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration,
                incompleteOtherScopes: [])
            var publicationFinished = false
            let publication = Task {
                await coordinator.consumeWatchedFolderObservation(observation, sequence: 1)
                publicationFinished = true
            }
            await assertEventuallyAsync("publication reaches final source validation") { await gate.isSuspended }

            // Control the reservation while the production source-validation await is suspended.
            coordinator.isCollectingRetainedLocations = true
            await gate.release()
            await assertEventuallyMain("publication either waits for the reservation or incorrectly finishes") {
                !coordinator.retentionMutationWaiters.isEmpty || publicationFinished
            }
            #expect(store.repositoryTopologyAtom.isRepoUnavailable(repository.id))
            #expect(coordinator.retentionMutationWaiters.count == 1)

            coordinator.isCollectingRetainedLocations = false
            let waiters = coordinator.retentionMutationWaiters
            coordinator.retentionMutationWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            await publication.value
            #expect(!store.repositoryTopologyAtom.isRepoUnavailable(repository.id))
            #expect(store.repositoryTopologyAtom.worktree(checkout.id)?.id == checkout.id)
            await coordinator.shutdown()
        }
    }
}

private actor RetentionSourceValidationGate {
    private var invocationCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isSuspended = false

    func validate() async -> Bool {
        invocationCount += 1
        if invocationCount == 2 {
            await withCheckedContinuation {
                continuation = $0
                isSuspended = true
            }
        }
        return true
    }

    func release() {
        continuation?.resume()
        continuation = nil
        isSuspended = false
    }
}
