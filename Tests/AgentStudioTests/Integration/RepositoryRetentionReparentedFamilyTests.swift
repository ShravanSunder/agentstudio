import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Repository retention after family reparenting", .serialized)
struct RepositoryRetentionReparentedFamilyTests {
    enum InsufficientEvidence: CaseIterable, Sendable {
        case additive
        case incompleteAuthoritative
    }

    private static let retentionStart = RepositoryRetentionTime(
        utc: Date(timeIntervalSince1970: 1_700_000_000), bootID: "fixture", uptimeNanoseconds: 1)

    @Test("a different-family positive at the old locator does not block empty-family collection")
    func authoritativeReplacementTimesAndCollectsOnlyTheEmptyFormerFamily() async throws {
        let testRoot = FileManager.default.temporaryDirectory.appending(
            path: "retention-reparented-family-\(UUIDv7.generate())"
        )
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: testRoot.appending(path: "core.sqlite"),
            localDatabaseURL: testRoot.appending(path: "local.sqlite")
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("expected prepared persistence fixture")
            return
        }

        let store = WorkspaceStore()
        let watchedRoot = testRoot.appending(path: "watched")
        try FileManager.default.createDirectory(at: watchedRoot, withIntermediateDirectories: true)
        let watchedPath = try #require(store.mutationCoordinator.addWatchedPath(watchedRoot))
        let replacedPath = watchedRoot.appending(path: "replaced-location")
        let currentFamilyPath = watchedRoot.appending(path: "current-family")
        let formerFamily = store.addRepo(at: replacedPath)
        let originalCheckout = try #require(formerFamily.worktrees.first)
        let currentFamily = store.addRepo(at: currentFamilyPath)
        let topologyStore = RepositoryTopologyStore(
            atom: store.repositoryTopologyAtom,
            sqliteDatastore: datastore
        )
        try await topologyStore.flushAsync()

        let firstAbsenceTime = Self.retentionStart
        let firstObservation = replacementObservation(
            watchedRoot: watchedRoot,
            watchedPath: watchedPath,
            replacedPath: replacedPath,
            currentFamilyPath: currentFamilyPath,
            coverage: .authoritative(firstAbsenceTime),
            baselineMembershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration
        )
        guard
            case .prepared(let replacement) = await RepositoryLifecycleReconciliation.prepare(
                store.mutationCoordinator.captureRepositoryLifecycleInput(),
                observation: firstObservation
            )
        else {
            Issue.record("expected authoritative same-path family replacement")
            return
        }

        let expectedAbsence = try #require(
            RepositoryRetentionPolicy.confirmedAbsence(retaining: nil, at: firstAbsenceTime)
        )
        #expect(replacement.replacement.absenceRecords.repositories[formerFamily.id] == expectedAbsence)
        #expect(store.mutationCoordinator.applyRepositoryLifecycleChange(replacement))
        topologyStore.recordReparenting(
            replacement.reparenting,
            revision: store.repositoryTopologyAtom.lifecycleRevision
        )
        try await topologyStore.flushAsync()

        let reparentedCheckout = try #require(store.repositoryTopologyAtom.worktree(originalCheckout.id))
        #expect(reparentedCheckout.repoId == currentFamily.id)
        #expect(store.repositoryTopologyAtom.repo(formerFamily.id)?.worktrees.isEmpty == true)
        #expect(reparentedCheckout.stableKey == formerFamily.stableKey)

        try await datastore.saveApplicationEntityRecency(
            sharedLocationRecency(stableKey: formerFamily.stableKey, at: firstAbsenceTime.utc))

        let dueTime = RepositoryRetentionTime(
            utc: firstAbsenceTime.utc,
            bootID: firstAbsenceTime.bootID,
            uptimeNanoseconds: firstAbsenceTime.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000
        )
        let dueObservation = replacementObservation(
            watchedRoot: watchedRoot,
            watchedPath: watchedPath,
            replacedPath: replacedPath,
            currentFamilyPath: currentFamilyPath,
            coverage: .authoritative(dueTime),
            baselineMembershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration
        )
        let currentInput = store.mutationCoordinator.captureRepositoryLifecycleInput()
        let candidates = await RepositoryRetentionPreparation.candidates(
            currentInput,
            observations: [dueObservation],
            at: dueTime
        )

        #expect(candidates.repositoryAbsences == [formerFamily.id: expectedAbsence])
        #expect(candidates.worktreeAbsences.isEmpty)

        let committed = try await topologyStore.collect(
            candidates,
            expectedRevision: currentInput.revision,
            at: dueTime
        )
        #expect(store.mutationCoordinator.applyRepositoryLifecycleChange(committed))
        var cleanupResult = await topologyStore.reconcileLocalOrphans()
        while cleanupResult == .progress {
            cleanupResult = await topologyStore.reconcileLocalOrphans()
        }
        #expect(cleanupResult == .complete)

        #expect(store.repositoryTopologyAtom.repo(formerFamily.id) == nil)
        #expect(store.repositoryTopologyAtom.repo(currentFamily.id) != nil)
        #expect(store.repositoryTopologyAtom.worktree(originalCheckout.id)?.repoId == currentFamily.id)
        try await assertDurableCollection(
            datastore, formerFamily: formerFamily, reparentedCheckout: reparentedCheckout)
    }

    private func sharedLocationRecency(stableKey: String, at time: Date) throws -> [ApplicationEntityRecency] {
        try [
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: stableKey), interaction: .opened, lastInteractedAt: time),
            ApplicationEntityRecency(
                entity: .worktree(worktreeStableKey: stableKey), interaction: .opened, lastInteractedAt: time),
        ]
    }

    private func assertDurableCollection(
        _ datastore: WorkspaceSQLiteDatastoreActor, formerFamily: Repo, reparentedCheckout: Worktree
    ) async throws {
        guard case .loaded(let durableTopology) = await datastore.loadRepositoryTopologySnapshot() else {
            Issue.record("expected durable topology after collection")
            return
        }
        #expect(!durableTopology.repos.contains { $0.id == formerFamily.id })
        #expect(durableTopology.repos.contains { $0.id == reparentedCheckout.repoId })
        #expect(durableTopology.worktrees.first { $0.id == reparentedCheckout.id }?.repoId == reparentedCheckout.repoId)

        guard case .loaded(let retainedRecency) = await datastore.loadApplicationEntityRecency() else {
            Issue.record("expected local recency after orphan cleanup")
            return
        }
        let retainedEntities = Set(retainedRecency.map(\.entity))
        #expect(
            retainedEntities.contains(.worktree(worktreeStableKey: reparentedCheckout.stableKey))
        )
        #expect(
            !retainedEntities.contains(.repository(repositoryStableKey: formerFamily.stableKey))
        )
    }

    @Test(
        "additive or incomplete replacement evidence cannot time or collect the empty former family",
        arguments: InsufficientEvidence.allCases
    )
    func insufficientEvidencePreservesUntimedFormerFamily(_ evidence: InsufficientEvidence) async throws {
        let store = WorkspaceStore()
        let watchedRoot = URL(
            fileURLWithPath: "/tmp/retention-reparented-family-control-\(UUIDv7.generate())"
        )
        let watchedPath = try #require(store.mutationCoordinator.addWatchedPath(watchedRoot))
        let replacedPath = watchedRoot.appending(path: "replaced-location")
        let currentFamilyPath = watchedRoot.appending(path: "current-family")
        let formerFamily = store.addRepo(at: replacedPath)
        let originalCheckout = try #require(formerFamily.worktrees.first)
        let currentFamily = store.addRepo(at: currentFamilyPath)
        let observationTime = Self.retentionStart
        let coverage: WatchedFolderTopologyCoverage
        let incompleteOtherScopes: [URL]
        switch evidence {
        case .additive:
            coverage = .additive
            incompleteOtherScopes = []
        case .incompleteAuthoritative:
            coverage = .authoritative(observationTime)
            incompleteOtherScopes = [replacedPath]
        }
        let observation = replacementObservation(
            watchedRoot: watchedRoot,
            watchedPath: watchedPath,
            replacedPath: replacedPath,
            currentFamilyPath: currentFamilyPath,
            coverage: coverage,
            baselineMembershipRevision: store.repositoryTopologyAtom.worktreePathIndexGeneration,
            incompleteOtherScopes: incompleteOtherScopes
        )
        guard
            case .prepared(let replacement) = await RepositoryLifecycleReconciliation.prepare(
                store.mutationCoordinator.captureRepositoryLifecycleInput(),
                observation: observation
            )
        else {
            Issue.record("expected same-path family replacement to retain the former family")
            return
        }
        #expect(store.mutationCoordinator.applyRepositoryLifecycleChange(replacement))

        #expect(store.repositoryTopologyAtom.worktree(originalCheckout.id)?.repoId == currentFamily.id)
        #expect(store.repositoryTopologyAtom.repo(formerFamily.id)?.worktrees.isEmpty == true)
        #expect(store.repositoryTopologyAtom.absenceRecords.repositories[formerFamily.id] == .unconfirmed)

        let dueTime = RepositoryRetentionTime(
            utc: observationTime.utc,
            bootID: observationTime.bootID,
            uptimeNanoseconds: observationTime.uptimeNanoseconds + 30 * 86_400 * 1_000_000_000
        )
        let candidates = await RepositoryRetentionPreparation.candidates(
            store.mutationCoordinator.captureRepositoryLifecycleInput(),
            observations: [observation],
            at: dueTime
        )
        #expect(candidates.isEmpty)
    }

    private func replacementObservation(
        watchedRoot: URL,
        watchedPath: WatchedPath,
        replacedPath: URL,
        currentFamilyPath: URL,
        coverage: WatchedFolderTopologyCoverage,
        baselineMembershipRevision: UInt64,
        incompleteOtherScopes: [URL] = []
    ) -> WatchedFolderTopologyObservation {
        WatchedFolderTopologyObservation(
            root: watchedRoot,
            registration: .init(
                sourceID: .init(kind: .watchedParentMembership, rootID: watchedPath.id),
                registrationGeneration: 1,
                rootGeneration: 1
            ),
            entries: [
                .init(
                    path: currentFamilyPath,
                    kind: .cloneRoot,
                    repositoryKey: currentFamilyPath.path
                ),
                .init(
                    path: replacedPath,
                    kind: .linkedWorktree(parentClonePath: currentFamilyPath),
                    repositoryKey: currentFamilyPath.path
                ),
            ],
            otherObservedPaths: [],
            coverage: coverage,
            baselineMembershipRevision: baselineMembershipRevision,
            incompleteOtherScopes: incompleteOtherScopes
        )
    }
}
