import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("RepositoryTopologyAtom")
struct RepositoryTopologyAtomIdentityReconciliationTests {
    enum ExistingIdentityMatchKind: Sendable {
        case path
        case mainWorktree
        case name
    }

    @Test("ensure main worktree repairs with UUIDv7 without rewriting persisted identities")
    func ensureMainWorktreeRepairsEmptyUnavailableRepository() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-ensure-main-repair")
        let persistedRepositoryID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let persistedSiblingRepositoryID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let persistedSiblingWorktreeID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
        let siblingPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-ensure-main-sibling")
        installTopology(
            atom: atom,
            repositories: [
                Repo(
                    id: persistedRepositoryID,
                    name: repoPath.lastPathComponent,
                    repoPath: repoPath
                ),
                Repo(
                    id: persistedSiblingRepositoryID,
                    name: siblingPath.lastPathComponent,
                    repoPath: siblingPath,
                    worktrees: [
                        Worktree(
                            id: persistedSiblingWorktreeID,
                            repoId: persistedSiblingRepositoryID,
                            name: siblingPath.lastPathComponent,
                            path: siblingPath,
                            isMainWorktree: true
                        )
                    ]
                ),
            ],
            unavailableRepositoryIDs: [persistedRepositoryID]
        )
        let generationBeforeRepair = atom.worktreePathIndexGeneration

        let repairedWorktree = coordinator.ensureMainWorktree(at: repoPath)

        let repairedRepository = try #require(atom.repo(persistedRepositoryID))
        #expect(repairedRepository.worktrees == [repairedWorktree])
        #expect(UUIDv7.isV7(repairedWorktree.id))
        #expect(repairedRepository.id == persistedRepositoryID)
        #expect(atom.repo(persistedSiblingRepositoryID)?.worktrees.single?.id == persistedSiblingWorktreeID)
        #expect(repairedWorktree.repoId == persistedRepositoryID)
        #expect(repairedWorktree.path == repoPath.standardizedFileURL)
        #expect(repairedWorktree.isMainWorktree)
        #expect(!atom.isRepoUnavailable(persistedRepositoryID))
        #expect(atom.worktreePathIndexGeneration == generationBeforeRepair + 1)
        #expect(atom.repoAndWorktree(containing: repoPath)?.worktree.id == repairedWorktree.id)
    }

    @Test(
        "scanned reconciliation preserves identity by path, main-worktree role, and name",
        arguments: [
            ExistingIdentityMatchKind.path,
            ExistingIdentityMatchKind.mainWorktree,
            ExistingIdentityMatchKind.name,
        ]
    )
    func scannedReconciliationPreservesIdentityByEverySupportedMatch(
        matchKind: ExistingIdentityMatchKind
    ) throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-match")
        let repo = coordinator.addRepo(at: repoPath)
        let existingMainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        let existingNameMatchedWorktree: Worktree
        let scannedWorktrees: RepositoryScannedWorktrees
        switch matchKind {
        case .path:
            existingNameMatchedWorktree = existingMainWorktree
            scannedWorktrees = .init(
                main: .init(name: "renamed", path: repoPath),
                linked: []
            )
        case .mainWorktree:
            existingNameMatchedWorktree = existingMainWorktree
            scannedWorktrees = .init(
                main: .init(
                    name: "moved-main",
                    path: URL(fileURLWithPath: "/tmp/agentstudio-topology-moved-main")
                ),
                linked: []
            )
        case .name:
            let namedWorktree = Worktree(
                id: UUIDv7.generate(),
                repoId: repo.id,
                name: "name-match",
                path: URL(fileURLWithPath: "/tmp/agentstudio-topology-original-name-match")
            )
            _ = coordinator.reconcileDiscoveredWorktrees(
                repo.id,
                worktrees: [existingMainWorktree, namedWorktree]
            )
            existingNameMatchedWorktree = namedWorktree
            scannedWorktrees = .init(
                main: .init(name: existingMainWorktree.name, path: existingMainWorktree.path),
                linked: [
                    .init(
                        name: namedWorktree.name,
                        path: URL(fileURLWithPath: "/tmp/agentstudio-topology-name-match")
                    )
                ]
            )
        }

        let result = coordinator.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: scannedWorktrees,
            traceId: UUIDv7.generate()
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected reconciliation acceptance")
            return
        }
        #expect(atom.worktree(existingNameMatchedWorktree.id)?.id == existingNameMatchedWorktree.id)
        #expect(acceptance.delta.preservedWorktreeIds.contains(existingNameMatchedWorktree.id))
        #expect(acceptance.delta.addedWorktreeIds.isEmpty)
        #expect(acceptance.delta.removedWorktrees.isEmpty)
    }

    @Test("scanned reconciliation reports mixed preserved added and removed identities")
    func scannedReconciliationReportsMixedIdentityDelta() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-mixed")
        let preservedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-preserved")
        let removedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-removed")
        let addedPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-added")
        let repo = coordinator.addRepo(at: repoPath)
        let mainWorktree = try #require(atom.repo(repo.id)?.worktrees.single)
        let preservedWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repo.id,
            name: "preserved",
            path: preservedPath
        )
        let removedWorktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repo.id,
            name: "removed",
            path: removedPath
        )
        _ = coordinator.reconcileDiscoveredWorktrees(
            repo.id,
            worktrees: [mainWorktree, preservedWorktree, removedWorktree]
        )

        let result = coordinator.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: .init(
                main: .init(name: mainWorktree.name, path: mainWorktree.path),
                linked: [
                    .init(name: preservedWorktree.name, path: preservedPath),
                    .init(name: "added", path: addedPath),
                ]
            ),
            traceId: UUIDv7.generate()
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected mixed reconciliation acceptance")
            return
        }
        let finalWorktrees = try #require(atom.repo(repo.id)?.worktrees)
        let addedWorktree = try #require(finalWorktrees.first(where: { $0.path == addedPath }))
        #expect(acceptance.delta.preservedWorktreeIds == [mainWorktree.id, preservedWorktree.id])
        #expect(acceptance.delta.addedWorktreeIds == [addedWorktree.id])
        #expect(acceptance.delta.removedWorktrees == [.init(id: removedWorktree.id, path: removedPath)])
        #expect(acceptance.delta.didChange)
    }

    @Test("identical scanned reconciliation reports accepted no change")
    func identicalScannedReconciliationReportsAcceptedNoChange() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repoPath = URL(fileURLWithPath: "/tmp/agentstudio-topology-identical")
        let repo = coordinator.addRepo(at: repoPath)
        let existingWorktree = try #require(atom.repo(repo.id)?.worktrees.single)

        let result = coordinator.reconcileScannedWorktrees(
            repo.id,
            scannedWorktrees: .init(
                main: .init(
                    name: existingWorktree.name,
                    path: existingWorktree.path
                ),
                linked: []
            ),
            traceId: UUIDv7.generate()
        )

        guard case .accepted(let acceptance) = result else {
            Issue.record("expected identical reconciliation acceptance")
            return
        }
        #expect(!acceptance.delta.didChange)
        #expect(acceptance.delta.preservedWorktreeIds == [existingWorktree.id])
        #expect(acceptance.delta.addedWorktreeIds.isEmpty)
        #expect(acceptance.delta.removedWorktrees.isEmpty)
    }
}
