import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Repository retention preparation", .serialized)
struct RepositoryRetentionPreparationTests {
    @Test("validation selects due and unknown-age locations plus their covering scopes")
    func validationSelectsAffectedScopes() async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/retention-scope-selection")
        let outer = try #require(coordinator.addWatchedPath(root.appending(path: "due")))
        let inner = try #require(coordinator.addWatchedPath(outer.path.appending(path: "nested")))
        let later = try #require(coordinator.addWatchedPath(root.appending(path: "later")))
        let legacy = try #require(coordinator.addWatchedPath(root.appending(path: "legacy")))
        let dueRepository = coordinator.addRepo(at: inner.path.appending(path: "repository"))
        let laterRepository = coordinator.addRepo(at: later.path.appending(path: "repository"))
        let legacyRepository = coordinator.addRepo(at: legacy.path.appending(path: "repository"))
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
        let laterStart = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID, uptimeNanoseconds: 86_400 * 1_000_000_000 + 1)
        #expect(coordinator.recordRepositoryAbsence(dueRepository.id, at: start))
        #expect(coordinator.recordRepositoryAbsence(laterRepository.id, at: laterStart))
        coordinator.markRepoUnavailable(legacyRepository.id)
        let due = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID, uptimeNanoseconds: 30 * 86_400 * 1_000_000_000 + 1)

        let scopeIDs = await RepositoryRetentionPreparation.validationScopeIDs(
            coordinator.captureRepositoryLifecycleInput(), at: due)

        #expect(scopeIDs == Set([outer.id, inner.id, legacy.id]))
    }

    @Test("legacy or untrusted age retains a bounded revalidation deadline", arguments: [true, false])
    func unknownAgeIsRetried(isLegacy: Bool) async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/retention-untrusted-age")
        _ = coordinator.addWatchedPath(root)
        let repo = coordinator.addRepo(at: root.appending(path: "repository"))
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "old-boot", uptimeNanoseconds: 1)
        if isLegacy {
            coordinator.markRepoUnavailable(repo.id)
        } else {
            #expect(coordinator.recordRepositoryAbsence(repo.id, at: start))
        }
        let untrusted = RepositoryRetentionTime(
            utc: start.utc.addingTimeInterval(-1), bootID: "next-boot", uptimeNanoseconds: 1)

        let delay = await RepositoryRetentionPreparation.nextDelay(
            coordinator.captureRepositoryLifecycleInput(), at: untrusted)

        #expect(delay == AppPolicies.RepositoryRetention.retryDelay)
        #expect(
            await RepositoryRetentionPreparation.nextDelay(coordinator.captureRepositoryLifecycleInput(), at: nil)
                == AppPolicies.RepositoryRetention.retryDelay)
        _ = coordinator.restoreObservedWorktrees(Set(repo.worktrees.map(\.id)))
        #expect(
            await RepositoryRetentionPreparation.nextDelay(coordinator.captureRepositoryLifecycleInput(), at: nil)
                == nil)
    }

    @Test("candidate preparation bounds the combined family and checkout batch", arguments: [1, 40])
    func combinedCandidateBound(repositoryCount: Int) async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/retention-preparation")
        let watch = try #require(coordinator.addWatchedPath(root))
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
        for index in 0..<repositoryCount {
            let repo = coordinator.addRepo(at: root.appending(path: "repo-\(index)"))
            #expect(coordinator.recordRepositoryAbsence(repo.id, at: start))
        }
        let due = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID,
            uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000)
        let observation = WatchedFolderTopologyObservation(
            root: root,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
                registrationGeneration: 1, rootGeneration: 1),
            entries: [],
            otherObservedPaths: [],
            coverage: .authoritative(due), baselineMembershipRevision: atom.worktreePathIndexGeneration,
            incompleteOtherScopes: []
        )

        let candidates = await RepositoryRetentionPreparation.candidates(
            coordinator.captureRepositoryLifecycleInput(), observations: [observation], at: due
        )

        #expect(candidates.count == min(repositoryCount * 2, AppPolicies.RepositoryRetention.collectionBatchLimit))
        for repositoryID in candidates.repositoryAbsences.keys {
            #expect(atom.repo(repositoryID)?.worktrees.allSatisfy { candidates.worktreeAbsences[$0.id] != nil } == true)
        }
    }

    @Test("an empty retained family cannot expire under incomplete overlapping coverage")
    func emptyFamilyRequiresCompleteOverlappingCoverage() async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/retention-empty-family")
        let watch = try #require(coordinator.addWatchedPath(root))
        var repo = coordinator.addRepo(at: root.appending(path: "repository"))
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)
        let absence = try #require(RepositoryRetentionPolicy.confirmedAbsence(retaining: nil, at: start))
        repo.worktrees = []
        let input = coordinator.captureRepositoryLifecycleInput()
        let emptyFamilyInput = RepositoryLifecycleInput(
            revision: input.revision, membershipRevision: input.membershipRevision, repositories: [repo],
            watchedPaths: input.watchedPaths, absenceRecords: .init(repositories: [repo.id: absence]),
            stableIdentity: input.stableIdentity
        )
        let due = RepositoryRetentionTime(
            utc: start.utc, bootID: start.bootID,
            uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000)
        let observation = WatchedFolderTopologyObservation(
            root: root,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
                registrationGeneration: 1, rootGeneration: 1),
            entries: [],
            otherObservedPaths: [],
            coverage: .authoritative(due), baselineMembershipRevision: input.membershipRevision,
            incompleteOtherScopes: [repo.repoPath]
        )

        let candidates = await RepositoryRetentionPreparation.candidates(
            emptyFamilyInput, observations: [observation], at: due)

        #expect(candidates.isEmpty)
        #expect(await RepositoryRetentionPreparation.nextDelay(emptyFamilyInput, at: start) == .seconds(30 * 86_400))
        let unknownAgeInput = RepositoryLifecycleInput(
            revision: input.revision, membershipRevision: input.membershipRevision, repositories: [repo],
            watchedPaths: input.watchedPaths, absenceRecords: .init(repositories: [repo.id: .unconfirmed]),
            stableIdentity: input.stableIdentity
        )
        guard
            case .prepared(let change) = await RepositoryLifecycleReconciliation.prepare(
                unknownAgeInput, observation: observation)
        else {
            Issue.record("expected preservation of the retained empty family")
            return
        }
        #expect(change.replacement.absenceRecords.repositories[repo.id] == .unconfirmed)
    }

    @Test("a current positive carried by an authoritative receipt vetoes collection")
    func carriedCurrentPositiveVetoesCollection() async throws {
        let atom = RepositoryTopologyAtom()
        let coordinator = makeTopologyMutationCoordinator(atom: atom)
        let root = URL(fileURLWithPath: "/tmp/retention-carried-positive")
        let watch = try #require(coordinator.addWatchedPath(root))
        let repository = coordinator.addRepo(at: root.appending(path: "repository"))
        let mainWorktree = try #require(repository.worktrees.first)
        let start = RepositoryRetentionTime(
            utc: Date(timeIntervalSince1970: 1_700_000_000),
            bootID: "fixture",
            uptimeNanoseconds: 1
        )
        #expect(coordinator.recordRepositoryAbsence(repository.id, at: start))
        let due = RepositoryRetentionTime(
            utc: start.utc,
            bootID: start.bootID,
            uptimeNanoseconds: start.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000
        )
        let currentPositive = RepoScanner.ResolvedGitEntry(
            path: mainWorktree.path,
            kind: .cloneRoot,
            repositoryKey: repository.stableKey
        )
        let observation = WatchedFolderTopologyObservation(
            root: root,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: watch.id),
                registrationGeneration: 1,
                rootGeneration: 1
            ),
            entries: [],
            otherObservedPaths: [mainWorktree.path],
            coverage: .authoritative(due),
            baselineMembershipRevision: atom.worktreePathIndexGeneration,
            incompleteOtherScopes: [],
            otherObservedEntries: [currentPositive]
        )

        let candidates = await RepositoryRetentionPreparation.candidates(
            coordinator.captureRepositoryLifecycleInput(),
            observations: [observation],
            at: due
        )

        #expect(candidates.isEmpty)
    }
}
