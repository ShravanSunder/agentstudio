import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Repository lifecycle scope", .serialized)
struct RepositoryLifecycleScopeTests {
    @Test("family conflicts outside an observation do not block its unrelated discoveries")
    func unrelatedFamilyConflictDoesNotBlockDiscovery() async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/lifecycle-unrelated-family-conflict")
        let watch = try #require(coordinator.addWatchedPath(root))
        let discovered = root.appending(path: "repository")
        let unrelatedCheckout = URL(fileURLWithPath: "/tmp/other-scope/checkout")
        let otherClaims = ["first", "second"].map { family in
            RepoScanner.ResolvedGitEntry(
                path: unrelatedCheckout,
                kind: .linkedWorktree(parentClonePath: URL(fileURLWithPath: "/tmp/other-scope/\(family)")),
                repositoryKey: family)
        }
        let observation = WatchedFolderTopologyObservation(
            root: root,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
                registrationGeneration: 1, rootGeneration: 1),
            entries: [.init(path: discovered, kind: .cloneRoot, repositoryKey: discovered.path)],
            otherObservedPaths: [], coverage: .additive,
            baselineMembershipRevision: atom.worktreePathIndexGeneration, incompleteOtherScopes: [],
            otherObservedEntries: otherClaims)

        guard
            case .prepared(let change) = await RepositoryLifecycleReconciliation.prepare(
                coordinator.captureRepositoryLifecycleInput(), observation: observation)
        else {
            Issue.record("unrelated current claims cannot veto this discovery")
            return
        }
        #expect(coordinator.applyRepositoryLifecycleChange(change))
        #expect(atom.repos.contains { $0.repoPath == discovered })
    }

    @Test("reparenting the last linked checkout retains the old family with unknown absence age")
    func lastCheckoutReparentingRetainsEmptyFamily() async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/lifecycle-last-checkout")
        let watch = try #require(coordinator.addWatchedPath(root))
        let oldFamily = coordinator.addRepo(at: root.appending(path: "old"))
        let linked = Worktree(
            id: UUIDv7.generate(), repoId: oldFamily.id, name: "linked", path: root.appending(path: "linked"))
        _ = coordinator.reconcileDiscoveredWorktrees(oldFamily.id, worktrees: [linked])
        _ = coordinator.restoreObservedWorktrees([linked.id])
        #expect(!atom.isRepoUnavailable(oldFamily.id))
        let newFamily = coordinator.addRepo(at: root.appending(path: "new"))
        let observation = WatchedFolderTopologyObservation(
            root: root,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: watch.id), registrationGeneration: 1,
                rootGeneration: 1),
            entries: [
                .init(path: newFamily.repoPath, kind: .cloneRoot, repositoryKey: newFamily.repoPath.path),
                .init(
                    path: linked.path, kind: .linkedWorktree(parentClonePath: newFamily.repoPath),
                    repositoryKey: newFamily.repoPath.path),
            ],
            otherObservedPaths: [], coverage: .additive, baselineMembershipRevision: atom.worktreePathIndexGeneration,
            incompleteOtherScopes: []
        )

        guard
            case .prepared(let change) = await RepositoryLifecycleReconciliation.prepare(
                coordinator.captureRepositoryLifecycleInput(), observation: observation
            )
        else {
            Issue.record("expected valid reparenting with a retained empty old family")
            return
        }
        #expect(coordinator.applyRepositoryLifecycleChange(change))
        #expect(atom.worktree(linked.id)?.repoId == newFamily.id)
        #expect(atom.repo(oldFamily.id)?.worktrees.isEmpty == true)
        #expect(atom.absenceRecords.repositories[oldFamily.id] == .unconfirmed)
    }

    @Test("a disjoint root's absence cannot hide a sibling checkout in the same family")
    func disjointScopePreservesSiblingCheckout() async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let firstRoot = URL(fileURLWithPath: "/tmp/lifecycle-scope-a")
        let secondRoot = URL(fileURLWithPath: "/tmp/lifecycle-scope-b")
        let firstWatch = try #require(coordinator.addWatchedPath(firstRoot))
        _ = coordinator.addWatchedPath(secondRoot)
        let repo = coordinator.addRepo(at: firstRoot.appending(path: "main"))
        let main = try #require(repo.worktrees.first)
        let sibling = Worktree(
            id: UUIDv7.generate(), repoId: repo.id, name: "sibling", path: secondRoot.appending(path: "linked"))
        _ = coordinator.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, sibling])
        let observation = WatchedFolderTopologyObservation(
            root: firstRoot,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: firstWatch.id),
                registrationGeneration: 1, rootGeneration: 1),
            entries: [], otherObservedPaths: [],
            coverage: .authoritative(
                .init(utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)),
            baselineMembershipRevision: atom.worktreePathIndexGeneration, incompleteOtherScopes: [secondRoot]
        )

        guard
            case .prepared(let change) = await RepositoryLifecycleReconciliation.prepare(
                coordinator.captureRepositoryLifecycleInput(), observation: observation
            )
        else {
            Issue.record("expected scoped absence")
            return
        }
        #expect(coordinator.applyRepositoryLifecycleChange(change))
        #expect(atom.isWorktreeUnavailable(main.id))
        #expect(!atom.isWorktreeUnavailable(sibling.id))
        #expect(!atom.isRepoUnavailable(repo.id))
        #expect(atom.repos.first?.worktrees.map(\.id) == [main.id, sibling.id])
        #expect(atom.activationWorktree(for: .repository(repositoryStableKey: repo.stableKey))?.id == sibling.id)
    }
}
