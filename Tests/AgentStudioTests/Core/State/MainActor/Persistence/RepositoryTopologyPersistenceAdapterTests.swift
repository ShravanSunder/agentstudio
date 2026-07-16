import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct RepositoryTopologyPersistenceAdapterTests {
    @Test("topology replacement rejects duplicate identity before atom mutation")
    func topologyReplacementRejectsDuplicateIdentity() throws {
        let repositoryID = UUIDv7.generate()
        let original = Repo(id: repositoryID, name: "original", repoPath: URL(filePath: "/tmp/original"))
        let duplicate = Repo(id: repositoryID, name: "duplicate", repoPath: URL(filePath: "/tmp/duplicate"))
        let atom = RepositoryTopologyAtom()
        atom.replaceTopology(try requireReplacement(repositories: [original]))

        let result = RepositoryTopologyReplacement.prepare(
            repositories: [original, duplicate],
            watchedPaths: [],
            unavailableRepositoryIDs: []
        )

        guard case .rejected(.duplicateRepositoryID(repositoryID)) = result else {
            Issue.record("expected duplicate repository rejection")
            return
        }
        #expect(atom.repos == [original])
    }

    @Test("topology construction preserves the exact participant rejection")
    func topologyConstructionPreservesExactParticipantRejection() throws {
        let repositories = (0..<2).map { index in
            Repo(name: "repository-\(index)", repoPath: URL(filePath: "/tmp/repository-\(index)"))
        }
        let atom = RepositoryTopologyAtom()
        atom.replaceTopology(try requireReplacement(repositories: repositories))
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = RepositoryTopologyPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)

        let result = adapter.makeParticipants(
            membershipLimits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 16)
        )

        guard case .rejected(let participantID, let rejection) = result else {
            Issue.record("expected participant construction rejection")
            return
        }
        #expect(participantID == .repositories)
        #expect(rejection == .baseMembershipKeyCountCapacityExceeded)
    }

    @Test("last repository participant read projects directly from the atom index")
    func lastRepositoryParticipantReadUsesAtomIndex() throws {
        let repositories = (0..<10_000).map { index in
            Repo(name: "repository-\(index)", repoPath: URL(filePath: "/tmp/repository-\(index)"))
        }
        let atom = RepositoryTopologyAtom()
        atom.replaceTopology(try requireReplacement(repositories: repositories))
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = RepositoryTopologyPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let participants = try requireParticipants(adapter)
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let repositoryParticipant = participants[0]
        #expect(repositoryParticipant.open(lease: lease) == .opened(baseMembershipCount: repositories.count))
        adapter.resetCurrentReadDiagnostics()

        let inspection = repositoryParticipant.inspectBaseSlot(
            lease: lease,
            slotCursor: repositories.count - 1
        )

        guard case .item(let projectedItem, let expectedItemID, _, _) = inspection else {
            Issue.record("expected final repository projection")
            return
        }
        #expect(expectedItemID == .repository(repositories.last!.id))
        #expect(projectedItem.item == .repository(adapterProjection(of: repositories.last!)))
        #expect(adapter.currentReadDiagnostics.repositoryLookupCount == 1)
    }

    @Test("active lease retains the exact topology replaced after its base")
    func activeLeaseRetainsTopologyReplacedAfterBase() throws {
        let repository = Repo(name: "base", repoPath: URL(filePath: "/tmp/base"))
        let worktree = Worktree(
            repoId: repository.id,
            name: "base",
            path: repository.repoPath,
            isMainWorktree: true
        )
        let baseRepository = Repo(
            id: repository.id,
            name: repository.name,
            repoPath: repository.repoPath,
            worktrees: [worktree]
        )
        let atom = RepositoryTopologyAtom()
        atom.replaceTopology(
            try requireReplacement(repositories: [baseRepository], unavailableRepositoryIDs: [repository.id])
        )
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = RepositoryTopologyPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let participants = try requireParticipants(adapter)
        let pager = makePager(participants: participants, revisionOwner: revisionOwner)
        let lease = try requireOpenedLease(pager.openLease())
        let emptyReplacement = try requireReplacement(repositories: [])

        _ = try revisionOwner.performSynchronousTransaction { preparation in
            try adapter.prepareReplacement(emptyReplacement, for: preparation)
        }
        let retainedItems = captureAllItems(pager: pager, lease: lease)

        #expect(retainedItems.contains(.repository(adapterProjection(of: baseRepository))))
        #expect(retainedItems.contains(.worktree(adapterProjection(of: worktree))))
        #expect(retainedItems.contains(.unavailableRepository(repository.id)))
        #expect(atom.repos.isEmpty)
        #expect(revisionOwner.committedRevision.rawValue == 1)
    }

    @Test("topology item byte estimate enforces page maximum bytes")
    func topologyItemByteEstimateEnforcesPageMaximumBytes() throws {
        let repository = Repo(
            name: String(repeating: "n", count: 64),
            repoPath: URL(filePath: "/tmp").appending(path: String(repeating: "p", count: 64)),
            tags: [String(repeating: "t", count: 64)]
        )
        let atom = RepositoryTopologyAtom()
        atom.replaceTopology(try requireReplacement(repositories: [repository]))
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let adapter = RepositoryTopologyPersistenceAdapter(atom: atom, revisionOwner: revisionOwner)
        let pager = makePager(participants: try requireParticipants(adapter), revisionOwner: revisionOwner)
        let lease = try requireOpenedLease(pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        guard case .requested(let request) = pager.makePageCaptureRequest(lease: lease, limits: limits) else {
            Issue.record("expected page request")
            return
        }

        guard case .rejected(.itemExceedsByteLimit(let participantID, _, let itemBytes, 16)) = pager.takePage(request)
        else {
            Issue.record("expected byte-limit rejection")
            return
        }
        #expect(participantID == .repositories)
        #expect(itemBytes > 16)
    }

    private func requireReplacement(
        repositories: [Repo],
        watchedPaths: [WatchedPath] = [],
        unavailableRepositoryIDs: Set<UUID> = []
    ) throws -> RepositoryTopologyReplacement {
        let result = RepositoryTopologyReplacement.prepare(
            repositories: repositories,
            watchedPaths: watchedPaths,
            unavailableRepositoryIDs: unavailableRepositoryIDs
        )
        guard case .prepared(let replacement) = result else {
            Issue.record("expected valid topology replacement")
            throw TestError.replacementRejected
        }
        return replacement
    }

    private func requireParticipants(
        _ adapter: RepositoryTopologyPersistenceAdapter
    ) throws -> [RepositoryTopologyParticipantFactoryResult.Participant] {
        let result = adapter.makeParticipants(
            membershipLimits: WorkspaceSnapshotParticipantFactoryPolicy.appDefault.fleetMembershipLimits
        )
        guard case .constructed(let participants) = result else {
            Issue.record("expected topology participants")
            throw TestError.participantConstructionRejected
        }
        return participants
    }

    private func makePager(
        participants: [RepositoryTopologyParticipantFactoryResult.Participant],
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) -> WorkspaceStateSnapshotPager<WorkspacePersistenceSnapshotParticipantID, WorkspacePersistenceSnapshotItem> {
        WorkspaceStateSnapshotPager(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner,
            leaseAuthority: .init(revisionOwner: revisionOwner),
            participants: participants,
            workLedger: MainActorWorkLedger(clock: PageCaptureIncrementingClock()),
            workRecordObserver: { _ in },
            workInvalidityObserver: { _ in },
            serviceClock: PageCaptureIncrementingClock()
        )
    }

    private func requireOpenedLease(
        _ result: WorkspaceStateSnapshotPagerOpenResult
    ) throws -> WorkspaceStateSnapshotLease {
        guard case .opened(let lease) = result else {
            throw TestError.leaseOpenRejected
        }
        return lease
    }

    private func captureAllItems(
        pager: WorkspaceStateSnapshotPager<WorkspacePersistenceSnapshotParticipantID, WorkspacePersistenceSnapshotItem>,
        lease: WorkspaceStateSnapshotLease
    ) -> [WorkspacePersistenceSnapshotItem] {
        let limits = requireLimits(maximumItems: 16, maximumBytes: 1_000_000)
        var items: [WorkspacePersistenceSnapshotItem] = []
        while case .requested(let request) = pager.makePageCaptureRequest(lease: lease, limits: limits) {
            switch pager.takePage(request) {
            case .page(let page):
                items.append(contentsOf: page.items.map(\.item))
                _ = pager.acknowledgePage(lease, pageID: page.pageID, disposition: .transferred)
            case .yielded:
                continue
            case .exhausted:
                return items
            default:
                Issue.record("unexpected page result")
                return items
            }
        }
        return items
    }

    private func adapterProjection(of repository: Repo) -> CanonicalRepo {
        CanonicalRepo(
            id: repository.id,
            name: repository.name,
            repoPath: repository.repoPath,
            createdAt: repository.createdAt,
            tags: repository.tags
        )
    }

    private func adapterProjection(of worktree: Worktree) -> CanonicalWorktree {
        CanonicalWorktree(
            id: worktree.id,
            repoId: worktree.repoId,
            name: worktree.name,
            path: worktree.path,
            isMainWorktree: worktree.isMainWorktree,
            tags: worktree.tags
        )
    }
}

private enum TestError: Error {
    case leaseOpenRejected
    case participantConstructionRejected
    case replacementRejected
}
