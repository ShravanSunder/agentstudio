import AgentStudioGit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Nested repository discovery continuity", .serialized)
struct RepositoryNestedDiscoveryContinuityTests {
    @Test("a retained child stays available when a new Git ancestor bounds scanner traversal")
    func retainedChildSurvivesNewGitAncestor() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let pipeline = try makePipeline(fixture: fixture, repoCache: atoms.repoCache)

            await pipeline.coordinator.startConsuming()
            do {
                let originalChild = try await discoverInitialChild(in: pipeline, fixture: fixture)
                try fixture.replacePlainAncestorWithRepository()
                let ancestorBoundaryReceipt = try await triggerAuthoritativeRescan(
                    in: pipeline,
                    fixture: fixture,
                    after: originalChild.receiptSequence
                )
                await assertEventuallyMain("coordinator publishes the new ancestor and retains the child") {
                    childIsAvailable(originalChild, in: pipeline.store, at: fixture.childPath)
                        && pipeline.store.repositoryTopologyAtom.repos.contains {
                            canonicalPath($0.repoPath) == fixture.ancestorPath
                        }
                }
                assertChildAvailableWithOriginalIdentity(originalChild, in: pipeline.store, fixture: fixture)

                try fixture.makeChildAbsent()
                let childAbsenceReceipt = try await triggerAuthoritativeRescan(
                    in: pipeline,
                    fixture: fixture,
                    after: ancestorBoundaryReceipt.sequence
                )
                #expect(
                    childAbsenceReceipt.observation.entries.allSatisfy {
                        canonicalPath($0.path) != fixture.childPath
                    })
                await assertEventuallyMain("authoritative validation records genuine child absence") {
                    childIsAbsent(originalChild, in: pipeline.store)
                }
                assertChildAbsentWithOriginalIdentity(originalChild, in: pipeline.store, fixture: fixture)

                try fixture.restoreChild()
                _ = try await triggerAuthoritativeRescan(
                    in: pipeline,
                    fixture: fixture,
                    after: childAbsenceReceipt.sequence
                )
                await assertEventuallyMain("same-path return restores the retained child identity") {
                    childIsAvailable(originalChild, in: pipeline.store, at: fixture.childPath)
                }
                assertChildAvailableWithOriginalIdentity(originalChild, in: pipeline.store, fixture: fixture)
            } catch {
                await pipeline.shutdown()
                throw error
            }
            await pipeline.shutdown()
        }
    }

    private func makeFixture() async throws -> NestedRepositoryFixture {
        let fileManager = FileManager.default
        let sourceCheckout = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let fixtureRoot = fileManager.temporaryDirectory.appending(
            path: "nested-discovery-continuity-\(UUIDv7.generate())")
        let watchedRoot = fixtureRoot.appending(path: "watched")
        let ancestorURL = watchedRoot.appending(path: "container")
        let childURL = ancestorURL.appending(path: "retained-child")
        let ancestorSeedURL = fixtureRoot.appending(path: "ancestor-seed")

        try fileManager.createDirectory(at: ancestorURL, withIntermediateDirectories: true)
        do {
            // Discovery needs real Git metadata, not hydrated LFS assets from the source checkout.
            let remoteClient = SystemGitRemoteClient(
                configuration: .init(
                    allowedProtocols: [.file], additionalEnvironment: ["GIT_LFS_SKIP_SMUDGE": "1"]))
            _ = try await remoteClient.clone(
                GitCloneRequest(
                    remoteURL: sourceCheckout.path,
                    destinationPath: childURL,
                    checkoutBranch: nil
                ))
            try fileManager.copyItem(at: childURL, to: ancestorSeedURL)
            return NestedRepositoryFixture(
                fixtureRoot: fixtureRoot,
                watchedRoot: watchedRoot,
                ancestorURL: ancestorURL,
                childURL: childURL,
                ancestorSeedURL: ancestorSeedURL
            )
        } catch {
            try? fileManager.removeItem(at: fixtureRoot)
            throw error
        }
    }

    private func makePipeline(
        fixture: NestedRepositoryFixture,
        repoCache: RepoCacheAtom
    ) throws -> NestedDiscoveryPipeline {
        let store = WorkspaceStore()
        let watch = try #require(store.mutationCoordinator.addWatchedPath(fixture.watchedRoot))
        let bus = EventBus<RuntimeEnvelope>()
        // Repository scanning and Git validation are production implementations. Only delivery of the
        // filesystem notification is controlled so the test can wait on an exact scan receipt.
        let filesystem = FilesystemActor(
            bus: bus,
            fseventStreamClient: ControllableFSEventStreamClient()
        )
        let coordinator = WorkspaceCacheCoordinator(
            bus: bus,
            workspaceStore: store,
            repoCache: repoCache,
            validateSourceObservations: { await filesystem.areCurrentWatchedFolderObservations($0) },
            scopeSyncHandler: { change in
                switch change {
                case .updateRepositoryScanBaseline(let repositories, let revision):
                    await filesystem.updateRepositoryScanBaseline(repositories, membershipRevision: revision)
                case .updateWatchedFolders(let paths, let repositories, let revision):
                    _ = await filesystem.refreshWatchedFolders(
                        paths,
                        restoring: repositories,
                        membershipRevision: revision
                    )
                case .registerForgeRepo, .unregisterForgeRepo, .refreshForgeRepo:
                    break
                }
            }
        )
        return NestedDiscoveryPipeline(
            store: store,
            watch: watch,
            filesystem: filesystem,
            coordinator: coordinator
        )
    }

    private func discoverInitialChild(
        in pipeline: NestedDiscoveryPipeline,
        fixture: NestedRepositoryFixture
    ) async throws -> DiscoveredChildIdentity {
        _ = await pipeline.filesystem.refreshWatchedFolders(
            [pipeline.watch],
            restoring: [],
            membershipRevision: pipeline.store.repositoryTopologyAtom.worktreePathIndexGeneration
        )
        await assertEventuallyMain("production discovery publishes the nested child") {
            pipeline.store.repositoryTopologyAtom.repos.contains {
                canonicalPath($0.repoPath) == fixture.childPath
            }
        }

        let repository = try #require(
            pipeline.store.repositoryTopologyAtom.repos.first {
                canonicalPath($0.repoPath) == fixture.childPath
            })
        let worktree = try #require(
            repository.worktrees.first {
                canonicalPath($0.path) == fixture.childPath
            })
        let receipts = await pipeline.filesystem.currentWatchedFolderObservationReceipts()
        let receiptSequence = try #require(receipts.map(\.sequence).max())
        return DiscoveredChildIdentity(
            repositoryID: repository.id,
            worktreeID: worktree.id,
            receiptSequence: receiptSequence
        )
    }

    private func triggerAuthoritativeRescan(
        in pipeline: NestedDiscoveryPipeline,
        fixture: NestedRepositoryFixture,
        after initialReceiptSequence: UInt64
    ) async throws -> WatchedFolderTopologyReceipt {
        let registrations = await pipeline.filesystem.watchedFolderScanState.registrationsBySourceID
        let registration = try #require(
            registrations.values.first { $0.watchedPath.id == pipeline.watch.id })
        await pipeline.filesystem.handleWatchedFolderFSEvent(
            FSEventBatch(
                worktreeId: registration.legacyCallbackRoutingID,
                paths: [fixture.ancestorURL.appending(path: ".git/HEAD").path]
            ))

        await assertEventuallyAsync("production scanner publishes a later authoritative receipt") {
            await pipeline.filesystem.currentWatchedFolderObservationReceipts().contains { receipt in
                guard receipt.observation.registration.sourceID.rootID == pipeline.watch.id,
                    receipt.sequence > initialReceiptSequence,
                    case .authoritative = receipt.observation.coverage
                else { return false }
                return true
            }
        }
        let receipts = await pipeline.filesystem.currentWatchedFolderObservationReceipts()
        return try #require(
            receipts.first { receipt in
                guard receipt.observation.registration.sourceID.rootID == pipeline.watch.id,
                    receipt.sequence > initialReceiptSequence,
                    case .authoritative = receipt.observation.coverage
                else { return false }
                return true
            }
        )
    }

    private func assertChildAvailableWithOriginalIdentity(
        _ child: DiscoveredChildIdentity,
        in store: WorkspaceStore,
        fixture: NestedRepositoryFixture
    ) {
        let topology = store.repositoryTopologyAtom
        #expect(canonicalPath(topology.repo(child.repositoryID)?.repoPath) == fixture.childPath)
        #expect(canonicalPath(topology.worktree(child.worktreeID)?.path) == fixture.childPath)
        #expect(topology.isRepoUnavailable(child.repositoryID) == false)
        #expect(topology.isWorktreeUnavailable(child.worktreeID) == false)
        #expect(topology.absenceRecords.repositories[child.repositoryID] == nil)
        #expect(topology.absenceRecords.worktrees[child.worktreeID] == nil)
        #expect(
            topology.repos.first { canonicalPath($0.repoPath) == fixture.ancestorPath }?.id
                != child.repositoryID
        )
    }

    private func assertChildAbsentWithOriginalIdentity(
        _ child: DiscoveredChildIdentity,
        in store: WorkspaceStore,
        fixture: NestedRepositoryFixture
    ) {
        let topology = store.repositoryTopologyAtom
        #expect(canonicalPath(topology.repo(child.repositoryID)?.repoPath) == fixture.childPath)
        #expect(canonicalPath(topology.worktree(child.worktreeID)?.path) == fixture.childPath)
        #expect(topology.isRepoUnavailable(child.repositoryID))
        #expect(topology.isWorktreeUnavailable(child.worktreeID))
        #expect(topology.absenceRecords.repositories[child.repositoryID] != nil)
        #expect(topology.absenceRecords.worktrees[child.worktreeID] != nil)
    }
}

private struct NestedRepositoryFixture {
    let fixtureRoot: URL
    let watchedRoot: URL
    let ancestorURL: URL
    let childURL: URL
    let ancestorSeedURL: URL
    let absentChildURL: URL
    let ancestorPath: String
    let childPath: String

    init(
        fixtureRoot: URL,
        watchedRoot: URL,
        ancestorURL: URL,
        childURL: URL,
        ancestorSeedURL: URL
    ) {
        self.fixtureRoot = fixtureRoot
        self.watchedRoot = watchedRoot
        self.ancestorURL = ancestorURL
        self.childURL = childURL
        self.ancestorSeedURL = ancestorSeedURL
        absentChildURL = fixtureRoot.appending(path: "absent-child")
        ancestorPath = canonicalPath(ancestorURL)
        childPath = canonicalPath(childURL)
    }

    func replacePlainAncestorWithRepository() throws {
        let displacedChild = fixtureRoot.appending(path: "relocating-child")
        let displacedPlainAncestor = fixtureRoot.appending(path: "displaced-plain-ancestor")
        try FileManager.default.moveItem(at: childURL, to: displacedChild)
        try FileManager.default.moveItem(at: ancestorURL, to: displacedPlainAncestor)
        try FileManager.default.moveItem(at: ancestorSeedURL, to: ancestorURL)
        try FileManager.default.moveItem(at: displacedChild, to: childURL)
    }

    func makeChildAbsent() throws {
        try FileManager.default.moveItem(at: childURL, to: absentChildURL)
    }

    func restoreChild() throws {
        try FileManager.default.moveItem(at: absentChildURL, to: childURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: fixtureRoot)
    }
}

@MainActor
private struct NestedDiscoveryPipeline {
    let store: WorkspaceStore
    let watch: WatchedPath
    let filesystem: FilesystemActor
    let coordinator: WorkspaceCacheCoordinator

    func shutdown() async {
        await coordinator.shutdown()
        await filesystem.shutdown()
    }
}

private struct DiscoveredChildIdentity {
    let repositoryID: UUID
    let worktreeID: UUID
    let receiptSequence: UInt64
}

@MainActor
private func childIsAvailable(
    _ child: DiscoveredChildIdentity,
    in store: WorkspaceStore,
    at expectedPath: String
) -> Bool {
    let topology = store.repositoryTopologyAtom
    return canonicalPath(topology.repo(child.repositoryID)?.repoPath) == expectedPath
        && canonicalPath(topology.worktree(child.worktreeID)?.path) == expectedPath
        && !topology.isRepoUnavailable(child.repositoryID)
        && !topology.isWorktreeUnavailable(child.worktreeID)
        && topology.absenceRecords.repositories[child.repositoryID] == nil
        && topology.absenceRecords.worktrees[child.worktreeID] == nil
}

@MainActor
private func childIsAbsent(
    _ child: DiscoveredChildIdentity,
    in store: WorkspaceStore
) -> Bool {
    let topology = store.repositoryTopologyAtom
    return topology.isRepoUnavailable(child.repositoryID)
        && topology.isWorktreeUnavailable(child.worktreeID)
        && topology.absenceRecords.repositories[child.repositoryID] != nil
        && topology.absenceRecords.worktrees[child.worktreeID] != nil
}

private func canonicalPath(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
}

private func canonicalPath(_ url: URL?) -> String? {
    url.map(canonicalPath)
}
