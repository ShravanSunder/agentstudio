import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Repository topology stable identity")
struct RepositoryTopologyStableIdentityTests {
    @Test("sealed topology installs supplied stable identity in both directions")
    func sealedTopologyInstallsSuppliedStableIdentityInBothDirections() throws {
        let atom = RepositoryTopologyAtom()
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let watchedPathID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agentstudio-stored-identity-repository")
        let watchedPath = WatchedPath(
            id: watchedPathID,
            path: URL(filePath: "/tmp/agentstudio-stored-identity-watched")
        )
        let repository = Repo(
            id: repositoryID,
            name: "stored-identity",
            repoPath: repositoryPath,
            worktrees: [
                Worktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: repositoryPath,
                    isMainWorktree: true
                )
            ]
        )
        let repositoryStableKey = "stored-repo-key"
        let watchedPathStableKey = "stored-watch-key"
        let preparation = RepositoryTopologyReplacement.prepare(
            repositories: [repository],
            watchedPaths: [watchedPath],
            unavailableRepositoryIDs: [],
            stableIdentity: RepositoryTopologyStableIdentity(
                repositoryStableKeysByID: [repositoryID: repositoryStableKey],
                worktreeStableKeysByID: [worktreeID: repositoryStableKey],
                watchedPathStableKeysByID: [watchedPathID: watchedPathStableKey]
            )
        )
        guard case .prepared(let replacement) = preparation else {
            Issue.record("expected supplied identity to prepare")
            return
        }

        atom.replaceTopology(replacement)
        atom.applyValidatedRepositoryMetadata(
            repositoryID: repositoryID,
            isFavorite: true,
            note: nil,
            tags: []
        )

        #expect(atom.repositoryStableKey(for: repositoryID) == repositoryStableKey)
        #expect(atom.worktreeStableKey(for: worktreeID) == repositoryStableKey)
        #expect(atom.repo(stableKey: repositoryStableKey)?.id == repositoryID)
        #expect(atom.worktree(stableKey: repositoryStableKey)?.id == worktreeID)
        #expect(atom.watchedPath(stableKey: watchedPathStableKey)?.id == watchedPathID)
        #expect(atom.repo(stableKey: StableKey.fromPath(repositoryPath)) == nil)
    }

    @Test("sealed topology rejects incomplete and unrelated stable identity maps")
    func sealedTopologyRejectsIncompleteAndUnrelatedStableIdentityMaps() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let unrelatedID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agentstudio-invalid-stored-identity")
        let repository = Repo(
            id: repositoryID,
            name: "invalid-stored-identity",
            repoPath: repositoryPath,
            worktrees: [
                Worktree(
                    id: worktreeID,
                    repoId: repositoryID,
                    name: "main",
                    path: repositoryPath,
                    isMainWorktree: true
                )
            ]
        )

        let missingRepository = RepositoryTopologyReplacement.prepare(
            repositories: [repository],
            watchedPaths: [],
            unavailableRepositoryIDs: [],
            stableIdentity: RepositoryTopologyStableIdentity(
                repositoryStableKeysByID: [:],
                worktreeStableKeysByID: [worktreeID: "main-key"],
                watchedPathStableKeysByID: [:]
            )
        )
        let unrelatedWorktree = RepositoryTopologyReplacement.prepare(
            repositories: [repository],
            watchedPaths: [],
            unavailableRepositoryIDs: [],
            stableIdentity: RepositoryTopologyStableIdentity(
                repositoryStableKeysByID: [repositoryID: "main-key"],
                worktreeStableKeysByID: [worktreeID: "main-key", unrelatedID: "unrelated-key"],
                watchedPathStableKeysByID: [:]
            )
        )

        #expect(topologyPreparationRejection(missingRepository) == .missingRepositoryStableKey(repositoryID))
        #expect(topologyPreparationRejection(unrelatedWorktree) == .unexpectedWorktreeStableKey(unrelatedID))
    }

    private func topologyPreparationRejection(
        _ preparation: RepositoryTopologyReplacementPreparation
    ) -> RepositoryTopologyIdentityRejection? {
        switch preparation {
        case .prepared:
            nil
        case .rejected(let rejection):
            rejection
        }
    }
}
