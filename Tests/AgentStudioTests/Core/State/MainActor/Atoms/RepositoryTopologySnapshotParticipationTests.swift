import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct RepositoryTopologySnapshotParticipationTests {
    @Test("topology construction preserves the exact participant and rejection")
    func topologyConstructionPreservesExactParticipantAndRejection() {
        // Arrange
        let atom = RepositoryTopologyAtom()
        let repositories = (0..<2).map { index in
            Repo(
                id: UUIDv7.generate(),
                name: "repository-\(index)",
                repoPath: URL(filePath: "/tmp/topology-limit-repository-\(index)")
            )
        }
        #expect(atom.hydrate(runtimeRepos: repositories, watchedPaths: [], unavailableRepoIds: []) == .applied)

        // Act
        let result = atom.makeSnapshotParticipants(
            membershipLimits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 16)
        )

        // Assert
        guard case .rejected(let participantID, let rejection) = result else {
            Issue.record("expected topology participant construction rejection")
            return
        }
        #expect(participantID == .repositories)
        #expect(rejection == .baseMembershipKeyCountCapacityExceeded)
    }

    @Test("hydrate rejects duplicate topology identity before canonical mutation")
    func hydrateRejectsDuplicateTopologyIdentity() {
        let atom = RepositoryTopologyAtom()
        let repositoryID = UUIDv7.generate()
        let original = Repo(id: repositoryID, name: "original", repoPath: URL(filePath: "/tmp/original"))
        #expect(atom.hydrate(runtimeRepos: [original], watchedPaths: [], unavailableRepoIds: []) == .applied)

        let duplicate = Repo(id: repositoryID, name: "duplicate", repoPath: URL(filePath: "/tmp/duplicate"))
        let result = atom.hydrate(runtimeRepos: [original, duplicate], watchedPaths: [], unavailableRepoIds: [])

        #expect(result == .rejected(.duplicateRepositoryID(repositoryID)))
        #expect(atom.repos == [original])
    }

    @Test("last-key snapshot lookup performs one indexed read")
    func lastKeySnapshotLookupIsIndexed() throws {
        let atom = RepositoryTopologyAtom()
        let repositories = (0..<10_000).map { index in
            Repo(
                id: UUIDv7.generate(),
                name: "repository-\(index)",
                repoPath: URL(filePath: "/tmp/repository-\(index)")
            )
        }
        #expect(atom.hydrate(runtimeRepos: repositories, watchedPaths: [], unavailableRepoIds: []) == .applied)
        atom.resetSnapshotCurrentReadDiagnostics()

        #expect(atom.snapshotRepository(for: repositories.last!.id)?.id == repositories.last!.id)
        #expect(atom.snapshotCurrentReadDiagnostics.repositoryLookupCount == 1)
    }

    @Test("failed fourth participant preparation leaves canonical state and revision unchanged")
    func failedParticipantPreparationIsAtomic() {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let repository = Repo(name: "base", repoPath: URL(filePath: "/tmp/base"))
        #expect(atom.hydrate(runtimeRepos: [repository], watchedPaths: [], unavailableRepoIds: []) == .applied)
        guard
            case .constructed = atom.makeSnapshotParticipants(
                membershipLimits: WorkspaceSnapshotParticipantFactoryPolicy.appDefault.fleetMembershipLimits
            )
        else {
            Issue.record("expected topology participants to construct")
            return
        }
        let stateBefore = atom.repos
        let duplicateUnavailableMutation = RepositoryTopologyStagedMutationBatch(
            unavailableRepositories: [.remove(UUIDv7.generate())]
        )

        #expect(throws: RepositoryTopologyStagedMutationError.self) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    duplicateUnavailableMutation,
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(atom.repos == stateBefore)
        #expect(atom.unavailableRepoIds.isEmpty)
        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.snapshotPreparationDiagnostics.allSatisfy { $0.status == .available })
    }

    @Test("typed participant batch applies values and tombstones at one outer revision")
    func participantBatchAppliesValuesAndTombstones() throws {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let removedRepository = Repo(name: "removed", repoPath: URL(filePath: "/tmp/removed"))
        let removedWorktree = Worktree(
            repoId: removedRepository.id,
            name: "removed",
            path: removedRepository.repoPath,
            isMainWorktree: true
        )
        let hydratedRepository = Repo(
            id: removedRepository.id,
            name: removedRepository.name,
            repoPath: removedRepository.repoPath,
            worktrees: [removedWorktree]
        )
        let removedWatchedPath = WatchedPath(path: URL(filePath: "/tmp/watched-removed"))
        #expect(
            atom.hydrate(
                runtimeRepos: [hydratedRepository],
                watchedPaths: [removedWatchedPath],
                unavailableRepoIds: [removedRepository.id]
            ) == .applied
        )
        _ = try requireConstructedTopologyParticipants(atom)
        let insertedRepository = CanonicalRepo(
            id: UUIDv7.generate(),
            name: "inserted",
            repoPath: URL(filePath: "/tmp/inserted")
        )
        let insertedWorktree = CanonicalWorktree(
            id: UUIDv7.generate(),
            repoId: insertedRepository.id,
            name: "inserted",
            path: insertedRepository.repoPath,
            isMainWorktree: true
        )
        let insertedWatchedPath = WatchedPath(path: URL(filePath: "/tmp/watched-inserted"))
        let batch = RepositoryTopologyStagedMutationBatch(
            repositories: [.remove(removedRepository.id), .insert(insertedRepository)],
            worktrees: [.remove(removedWorktree.id), .insert(insertedWorktree)],
            watchedPaths: [.remove(removedWatchedPath.id), .insert(insertedWatchedPath)],
            unavailableRepositories: [.remove(removedRepository.id), .insert(insertedRepository.id)]
        )

        let receipt = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareSnapshotMutation(batch, for: preparation, revisionOwner: revisionOwner)
        }

        #expect(receipt.revision.rawValue == 1)
        #expect(atom.snapshotRepository(for: removedRepository.id) == nil)
        #expect(atom.snapshotWorktree(for: removedWorktree.id) == nil)
        #expect(atom.snapshotWatchedPath(for: removedWatchedPath.id) == nil)
        #expect(atom.snapshotRepository(for: insertedRepository.id) == insertedRepository)
        #expect(atom.snapshotWorktree(for: insertedWorktree.id) == insertedWorktree)
        #expect(atom.snapshotWatchedPath(for: insertedWatchedPath.id) == insertedWatchedPath)
        #expect(atom.isRepoUnavailable(insertedRepository.id))
        #expect(atom.repos.map(\.id) == [insertedRepository.id])
    }

    @Test("strict inserts reject repository worktree and watched path identity collisions")
    func strictInsertsRejectIdentityCollisions() throws {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let repository = Repo(name: "original", repoPath: URL(filePath: "/tmp/original"))
        let worktree = Worktree(
            repoId: repository.id,
            name: "original",
            path: repository.repoPath,
            isMainWorktree: true
        )
        let hydratedRepository = Repo(
            id: repository.id,
            name: repository.name,
            repoPath: repository.repoPath,
            worktrees: [worktree]
        )
        let watchedPath = WatchedPath(path: URL(filePath: "/tmp/watched-original"))
        #expect(
            atom.hydrate(
                runtimeRepos: [hydratedRepository],
                watchedPaths: [watchedPath],
                unavailableRepoIds: []
            ) == .applied
        )
        _ = try requireConstructedTopologyParticipants(atom)
        let originalRepositories = atom.repos
        let originalWatchedPaths = atom.watchedPaths

        let collidingRepository = CanonicalRepo(
            id: repository.id,
            name: "replacement",
            repoPath: URL(filePath: "/tmp/replacement")
        )
        #expect(
            throws: RepositoryTopologyStagedMutationError.entityInsertAlreadyExists(
                .repository,
                repository.id
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(repositories: [.insert(collidingRepository)]),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        let collidingWorktree = CanonicalWorktree(
            id: worktree.id,
            repoId: repository.id,
            name: "replacement",
            path: URL(filePath: "/tmp/worktree-replacement")
        )
        #expect(
            throws: RepositoryTopologyStagedMutationError.entityInsertAlreadyExists(
                .worktree,
                worktree.id
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(worktrees: [.insert(collidingWorktree)]),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        let collidingWatchedPath = WatchedPath(
            id: watchedPath.id,
            path: URL(filePath: "/tmp/watched-replacement")
        )
        #expect(
            throws: RepositoryTopologyStagedMutationError.entityInsertAlreadyExists(
                .watchedPath,
                watchedPath.id
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(watchedPaths: [.insert(collidingWatchedPath)]),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(atom.repos == originalRepositories)
        #expect(atom.watchedPaths == originalWatchedPaths)
        #expect(revisionOwner.committedRevision == .zero)
    }

    @Test("strict updates and removals require an existing entity")
    func strictUpdatesAndRemovalsRequireExistingEntity() throws {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        _ = try requireConstructedTopologyParticipants(atom)
        let missingRepository = CanonicalRepo(
            id: UUIDv7.generate(),
            name: "missing",
            repoPath: URL(filePath: "/tmp/missing")
        )
        let missingWorktreeID = UUIDv7.generate()
        let missingWatchedPathID = UUIDv7.generate()

        #expect(
            throws: RepositoryTopologyStagedMutationError.entityUpdateMissing(
                .repository,
                missingRepository.id
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(repositories: [.update(missingRepository)]),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }
        #expect(
            throws: RepositoryTopologyStagedMutationError.entityRemoveMissing(
                .worktree,
                missingWorktreeID
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(worktrees: [.remove(missingWorktreeID)]),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }
        #expect(
            throws: RepositoryTopologyStagedMutationError.entityRemoveMissing(
                .watchedPath,
                missingWatchedPathID
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(watchedPaths: [.remove(missingWatchedPathID)]),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(atom.repos.isEmpty)
        #expect(atom.watchedPaths.isEmpty)
        #expect(revisionOwner.committedRevision == .zero)
    }

    @Test("repository removal requires exact dependent tombstones")
    func repositoryRemovalRequiresExactDependentTombstones() throws {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let repository = Repo(name: "removed", repoPath: URL(filePath: "/tmp/removed"))
        let worktree = Worktree(
            repoId: repository.id,
            name: "removed",
            path: repository.repoPath,
            isMainWorktree: true
        )
        let hydratedRepository = Repo(
            id: repository.id,
            name: repository.name,
            repoPath: repository.repoPath,
            worktrees: [worktree]
        )
        #expect(
            atom.hydrate(
                runtimeRepos: [hydratedRepository],
                watchedPaths: [],
                unavailableRepoIds: [repository.id]
            ) == .applied
        )
        _ = try requireConstructedTopologyParticipants(atom)

        #expect(
            throws: RepositoryTopologyStagedMutationError.repositoryRemovalMissingWorktreeTombstone(
                repositoryID: repository.id,
                worktreeID: worktree.id
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(repositories: [.remove(repository.id)]),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }
        #expect(
            throws: RepositoryTopologyStagedMutationError.repositoryRemovalMissingUnavailableTombstone(
                repository.id
            )
        ) {
            try revisionOwner.performSynchronousTransaction { preparation in
                try atom.prepareSnapshotMutation(
                    .init(
                        repositories: [.remove(repository.id)],
                        worktrees: [.remove(worktree.id)]
                    ),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(atom.repos == [hydratedRepository])
        #expect(atom.unavailableRepoIds == [repository.id])
        #expect(revisionOwner.committedRevision == .zero)
    }

    @Test("active lease retains repository dependents after exact removal commit")
    func activeLeaseRetainsRepositoryDependentsAfterRemoval() throws {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let repository = Repo(name: "removed", repoPath: URL(filePath: "/tmp/removed"))
        let worktree = Worktree(
            repoId: repository.id,
            name: "removed",
            path: repository.repoPath,
            isMainWorktree: true
        )
        let hydratedRepository = Repo(
            id: repository.id,
            name: repository.name,
            repoPath: repository.repoPath,
            worktrees: [worktree]
        )
        #expect(
            atom.hydrate(
                runtimeRepos: [hydratedRepository],
                watchedPaths: [],
                unavailableRepoIds: [repository.id]
            ) == .applied
        )
        let participants = try requireConstructedTopologyParticipants(atom)
        let expectedRepository = try #require(atom.snapshotRepository(for: repository.id))
        let expectedWorktree = try #require(atom.snapshotWorktree(for: worktree.id))
        let pager = makeTopologyPager(participants: participants, revisionOwner: revisionOwner)
        let lease = try requireOpenedTopologyLease(pager.openLease())

        _ = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareSnapshotMutation(
                .init(
                    repositories: [.remove(repository.id)],
                    worktrees: [.remove(worktree.id)],
                    unavailableRepositories: [.remove(repository.id)]
                ),
                for: preparation,
                revisionOwner: revisionOwner
            )
        }
        let retainedItems = captureAllTopologyItems(pager: pager, lease: lease)

        #expect(retainedItems.contains(.repository(expectedRepository)))
        #expect(retainedItems.contains(.worktree(expectedWorktree)))
        #expect(retainedItems.contains(.unavailableRepository(repository.id)))
        #expect(atom.snapshotRepository(for: repository.id) == nil)
        #expect(atom.snapshotWorktree(for: worktree.id) == nil)
        #expect(!atom.isRepoUnavailable(repository.id))
        #expect(revisionOwner.committedRevision.rawValue == 1)
    }

    @Test("topology item byte estimate enforces page maximum bytes")
    func topologyItemByteEstimateEnforcesPageMaximumBytes() throws {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let repository = Repo(
            name: String(repeating: "n", count: 64),
            repoPath: URL(filePath: "/tmp").appending(path: String(repeating: "p", count: 64)),
            tags: [String(repeating: "t", count: 64)]
        )
        #expect(atom.hydrate(runtimeRepos: [repository], watchedPaths: [], unavailableRepoIds: []) == .applied)
        let participants = try requireConstructedTopologyParticipants(atom)
        let pager = makeTopologyPager(participants: participants, revisionOwner: revisionOwner)
        let lease = try requireOpenedTopologyLease(pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let request = try requireRequestedTopologyPage(
            pager.makePageCaptureRequest(lease: lease, limits: limits)
        )

        let result = pager.takePage(request)

        guard
            case .rejected(
                .itemExceedsByteLimit(
                    participantID: .repositories,
                    itemID: .repository(repository.id),
                    itemBytes: let itemBytes,
                    maximumBytes: 16
                )
            ) = result
        else {
            Issue.record("expected repository item to exceed the byte limit")
            return
        }
        #expect(itemBytes > 16)
    }

    @Test("rediscovering an unavailable repository updates snapshot participation")
    func rediscoveringUnavailableRepositoryUpdatesSnapshotParticipation() throws {
        let atom = RepositoryTopologyAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let repository = Repo(name: "existing", repoPath: URL(filePath: "/tmp/existing"))
        #expect(
            atom.hydrate(
                runtimeRepos: [repository],
                watchedPaths: [],
                unavailableRepoIds: [repository.id]
            ) == .applied
        )

        _ = atom.addRepo(at: repository.repoPath)
        let participants = try requireConstructedTopologyParticipants(atom)
        let pager = makeTopologyPager(participants: participants, revisionOwner: revisionOwner)
        let lease = try requireOpenedTopologyLease(pager.openLease())
        let capturedItems = captureAllTopologyItems(pager: pager, lease: lease)

        #expect(!atom.isRepoUnavailable(repository.id))
        #expect(!capturedItems.contains(.unavailableRepository(repository.id)))
    }

    private func makeTopologyPager(
        participants: [WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >],
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspaceStateSnapshotPager<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPager(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner,
            leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority(revisionOwner: revisionOwner),
            participants: participants,
            membershipLimits: WorkspaceSnapshotParticipantFactoryPolicy.appDefault.fleetMembershipLimits,
            workLedger: MainActorWorkLedger(clock: PageCaptureIncrementingClock()),
            workRecordObserver: { _ in },
            workInvalidityObserver: { _ in },
            serviceClock: PageCaptureIncrementingClock()
        )
    }

    private func captureAllTopologyItems(
        pager: WorkspaceStateSnapshotPager<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >,
        lease: WorkspaceStateSnapshotLease
    ) -> [WorkspacePersistenceSnapshotItem] {
        let limits = requireLimits(maximumItems: 16, maximumBytes: 1_000_000)
        var items: [WorkspacePersistenceSnapshotItem] = []
        while true {
            guard case .requested(let request) = pager.makePageCaptureRequest(lease: lease, limits: limits) else {
                Issue.record("expected topology page request")
                return items
            }
            switch pager.takePage(request) {
            case .page(let page):
                items.append(contentsOf: page.items.map(\.item))
                _ = pager.acknowledgePage(lease, pageID: page.pageID, disposition: .transferred)
            case .yielded:
                continue
            case .exhausted:
                _ = pager.closeLease(lease, disposition: .completed)
                return items
            case .replayed:
                Issue.record("unexpected topology page replay")
                return items
            case .rejected(let rejection):
                Issue.record("unexpected topology page rejection: \(rejection)")
                return items
            }
        }
    }

    private func requireRequestedTopologyPage(
        _ result: WorkspaceStateSnapshotPageCaptureRequestResult
    ) throws -> WorkspaceStateSnapshotPageCaptureRequest {
        guard case .requested(let request) = result else {
            Issue.record("expected topology page request")
            throw RepositoryTopologyTestError.pageRequestRejected
        }
        return request
    }

    private func requireOpenedTopologyLease(
        _ result: WorkspaceStateSnapshotPagerOpenResult
    ) throws -> WorkspaceStateSnapshotLease {
        guard case .opened(let lease) = result else {
            Issue.record("expected topology lease to open, got \(result)")
            throw RepositoryTopologyTestError.leaseOpenRejected
        }
        return lease
    }

    private func requireConstructedTopologyParticipants(
        _ atom: RepositoryTopologyAtom
    ) throws -> [WorkspaceStateSnapshotPagerParticipant<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >] {
        let result = atom.makeSnapshotParticipants(
            membershipLimits: WorkspaceSnapshotParticipantFactoryPolicy.appDefault.fleetMembershipLimits
        )
        guard case .constructed(let participants) = result else {
            Issue.record("expected topology participant construction, got \(result)")
            throw RepositoryTopologyTestError.participantConstructionRejected
        }
        return participants
    }
}

private enum RepositoryTopologyTestError: Error {
    case leaseOpenRejected
    case pageRequestRejected
    case participantConstructionRejected
}
