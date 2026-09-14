import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Individual checkout absence", .serialized)
struct RepositoryWorktreeAbsenceTests {
    @Test("existing-directory URL hints cannot discard package-validated main and linked checkouts")
    func directoryURLHintsPreserveValidatedCheckouts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "lifecycle-directory-hint-\(UUIDv7.generate())")
        let main = root.appending(path: "main")
        let linked = root.appending(path: "linked")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // The package's canonicalWorktreeURL intentionally constructs these URLs with isDirectory: false.
        let mainEvidence = URL(fileURLWithPath: main.resolvingSymlinksInPath().path, isDirectory: false)
        let linkedEvidence = URL(fileURLWithPath: linked.resolvingSymlinksInPath().path, isDirectory: false)
        let entries: [RepoScanner.ResolvedGitEntry] = [
            .init(path: mainEvidence, kind: .cloneRoot, repositoryKey: "fixture-family"),
            .init(
                path: linkedEvidence, kind: .linkedWorktree(parentClonePath: mainEvidence),
                repositoryKey: "fixture-family"),
        ]
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let watched = try #require(coordinator.addWatchedPath(root))

        guard
            case .prepared(let change) = await RepositoryLifecycleReconciliation.prepare(
                coordinator.captureRepositoryLifecycleInput(),
                observation: observation(watched: watched, atom: atom, entries: entries))
        else {
            Issue.record("expected package-validated directory evidence to reconcile")
            return
        }
        #expect(coordinator.applyRepositoryLifecycleChange(change))
        let repository = try #require(atom.repos.first)
        #expect(!atom.isRepoUnavailable(repository.id))
        #expect(Set(repository.worktrees.map { $0.path.path }) == Set([mainEvidence.path, linkedEvidence.path]))
        #expect(repository.worktrees.filter(\.isMainWorktree).count == 1)
        #expect(atom.absenceRecords.worktrees.isEmpty)
    }

    @Test("one missing checkout is not launchable while its sibling remains available")
    func hiddenCheckoutLeavesActivePathIndex() throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let repo = coordinator.addRepo(at: URL(fileURLWithPath: "/tmp/checkout-absence-main"))
        let main = try #require(repo.worktrees.first)
        let linked = Worktree(
            id: UUIDv7.generate(), repoId: repo.id, name: "feature",
            path: URL(fileURLWithPath: "/tmp/checkout-absence-feature")
        )
        _ = coordinator.reconcileDiscoveredWorktrees(repo.id, worktrees: [main, linked])
        let observedTime = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1
        )
        #expect(atom.repoAndWorktree(containing: linked.path)?.worktree.id == linked.id)

        #expect(coordinator.recordWorktreeAbsence(linked.id, at: observedTime))

        #expect(!atom.isRepoUnavailable(repo.id))
        #expect(atom.worktree(linked.id) != nil)
        #expect(atom.repoAndWorktree(containing: linked.path) == nil)
        #expect(atom.validatedAssociation(repoId: repo.id, worktreeId: linked.id) == nil)
        #expect(atom.activationWorktree(for: .worktree(worktreeStableKey: linked.stableKey)) == nil)
        #expect(atom.repoAndWorktree(containing: main.path)?.worktree.id == main.id)
        #expect(coordinator.restoreObservedWorktrees([linked.id]))
        #expect(atom.repoAndWorktree(containing: linked.path)?.worktree.id == linked.id)
    }
    @Test("conflicting family evidence for one checkout defers the entire observation")
    func conflictingFamilyEvidenceDoesNotChooseAnOwner() async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/conflicting-family-evidence")
        let watched = try #require(coordinator.addWatchedPath(root))
        let first = coordinator.addRepo(at: root.appending(path: "first"))
        let second = coordinator.addRepo(at: root.appending(path: "second"))
        let checkoutPath = root.appending(path: "checkout")
        let checkout = Worktree(id: UUIDv7.generate(), repoId: first.id, name: "checkout", path: checkoutPath)
        _ = coordinator.reconcileDiscoveredWorktrees(first.id, worktrees: first.worktrees + [checkout])
        let observation = WatchedFolderTopologyObservation(
            root: root,
            registration: FSEventRegistrationToken(
                sourceID: .init(kind: .watchedParentMembership, rootID: watched.id),
                registrationGeneration: 1, rootGeneration: 1
            ),
            entries: [
                .init(
                    path: checkoutPath, kind: .linkedWorktree(parentClonePath: first.repoPath), repositoryKey: "first"),
                .init(
                    path: checkoutPath, kind: .linkedWorktree(parentClonePath: second.repoPath), repositoryKey: "second"
                ),
            ],
            otherObservedPaths: [],
            coverage: .authoritative(
                .init(utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)),
            baselineMembershipRevision: atom.worktreePathIndexGeneration,
            incompleteOtherScopes: []
        )

        let result = await RepositoryLifecycleReconciliation.prepare(
            coordinator.captureRepositoryLifecycleInput(), observation: observation
        )

        guard case .invalid = result else {
            Issue.record("conflicting validated families must not select the last observed owner")
            return
        }
        #expect(atom.repos.map(\.id) == [first.id, second.id])
    }

    @Test("a vanished alias retains stored keys and canonical return reuses both identities")
    func vanishedAliasRetainsIdentityOnCanonicalReturn() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "lifecycle-alias-\(UUIDv7.generate())")
        let canonical = root.appending(path: "canonical")
        let alias = root.appending(path: "alias")
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: canonical)
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let watched = try #require(coordinator.addWatchedPath(root))
        let repo = coordinator.addRepo(at: alias)
        let main = try #require(repo.worktrees.first)
        let storedKey = try #require(atom.repositoryStableKey(for: repo.id))
        try FileManager.default.removeItem(at: alias)

        let hidden = await RepositoryLifecycleReconciliation.prepare(
            coordinator.captureRepositoryLifecycleInput(),
            observation: observation(watched: watched, atom: atom, entries: [])
        )
        guard case .prepared(let absence) = hidden else {
            Issue.record("expected absent alias reconciliation")
            return
        }
        #expect(coordinator.applyRepositoryLifecycleChange(absence))
        #expect(atom.repositoryStableKey(for: repo.id) == storedKey)
        #expect(atom.worktreeStableKey(for: main.id) == storedKey)

        let returned = await RepositoryLifecycleReconciliation.prepare(
            coordinator.captureRepositoryLifecycleInput(),
            observation: observation(
                watched: watched, atom: atom,
                entries: [
                    .init(path: canonical, kind: .cloneRoot, repositoryKey: "common:\(canonical.path)/.git")
                ])
        )
        guard case .prepared(let available) = returned else {
            Issue.record("expected canonical return reconciliation")
            return
        }
        #expect(coordinator.applyRepositoryLifecycleChange(available))
        #expect(atom.repos.map(\.id) == [repo.id])
        #expect(atom.repos.flatMap(\.worktrees).map(\.id) == [main.id])
        #expect(!atom.isWorktreeUnavailable(main.id))
    }

    private func observation(
        watched: WatchedPath, atom: RepositoryTopologyAtom, entries: [RepoScanner.ResolvedGitEntry]
    ) -> WatchedFolderTopologyObservation {
        WatchedFolderTopologyObservation(
            root: watched.path,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: watched.id),
                registrationGeneration: 1, rootGeneration: 1
            ),
            entries: entries, otherObservedPaths: [],
            coverage: .authoritative(
                .init(utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)),
            baselineMembershipRevision: atom.worktreePathIndexGeneration, incompleteOtherScopes: []
        )
    }

}
