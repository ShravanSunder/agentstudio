import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class RepositoryTopologyStableIdentityObservationFlag: @unchecked Sendable {
    var didFire = false
}

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

    @Test("same-ID stable identity replacement invalidates lookups without metadata noise")
    func sameIDStableIdentityReplacementInvalidatesLookupsWithoutMetadataNoise() throws {
        // Arrange
        let atom = RepositoryTopologyAtom()
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let repositoryPath = URL(filePath: "/tmp/agentstudio-observed-stable-identity")
        let repository = Repo(
            id: repositoryID,
            name: "observed-stable-identity",
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
        let originalStableKey = "original-stable-key"
        let replacementStableKey = "replacement-stable-key"
        let originalReplacement = try #require(
            preparedTopology(
                repositories: [repository],
                repositoryStableKeysByID: [repositoryID: originalStableKey],
                worktreeStableKeysByID: [worktreeID: originalStableKey]
            )
        )
        atom.replaceTopology(originalReplacement)
        let identityInvalidation = RepositoryTopologyStableIdentityObservationFlag()

        withObservationTracking {
            _ = atom.repositoryStableKey(for: repositoryID)
            _ = atom.worktreeStableKey(for: worktreeID)
            _ = atom.repo(stableKey: originalStableKey)
            _ = atom.worktree(stableKey: originalStableKey)
        } onChange: {
            identityInvalidation.didFire = true
        }

        // Act
        let identityReplacement = try #require(
            preparedTopology(
                repositories: [repository],
                repositoryStableKeysByID: [repositoryID: replacementStableKey],
                worktreeStableKeysByID: [worktreeID: replacementStableKey]
            )
        )
        atom.replaceTopology(identityReplacement)

        // Assert
        #expect(identityInvalidation.didFire)
        #expect(atom.repositoryStableKey(for: repositoryID) == replacementStableKey)
        #expect(atom.worktreeStableKey(for: worktreeID) == replacementStableKey)
        #expect(atom.repo(stableKey: originalStableKey) == nil)
        #expect(atom.worktree(stableKey: originalStableKey) == nil)
        #expect(atom.repo(stableKey: replacementStableKey)?.id == repositoryID)
        #expect(atom.worktree(stableKey: replacementStableKey)?.id == worktreeID)

        // Arrange
        var metadataOnlyRepository = repository
        metadataOnlyRepository.isFavorite = true
        let metadataOnlyReplacement = try #require(
            preparedTopology(
                repositories: [metadataOnlyRepository],
                repositoryStableKeysByID: [repositoryID: replacementStableKey],
                worktreeStableKeysByID: [worktreeID: replacementStableKey]
            )
        )
        let metadataInvalidation = RepositoryTopologyStableIdentityObservationFlag()
        withObservationTracking {
            _ = atom.repositoryStableKey(for: repositoryID)
            _ = atom.worktreeStableKey(for: worktreeID)
        } onChange: {
            metadataInvalidation.didFire = true
        }

        // Act
        atom.replaceTopology(metadataOnlyReplacement)

        // Assert
        #expect(metadataInvalidation.didFire == false)
    }

    private func preparedTopology(
        repositories: [Repo],
        repositoryStableKeysByID: [UUID: String],
        worktreeStableKeysByID: [UUID: String]
    ) -> RepositoryTopologyReplacement? {
        switch RepositoryTopologyReplacement.prepare(
            repositories: repositories,
            watchedPaths: [],
            unavailableRepositoryIDs: [],
            stableIdentity: RepositoryTopologyStableIdentity(
                repositoryStableKeysByID: repositoryStableKeysByID,
                worktreeStableKeysByID: worktreeStableKeysByID,
                watchedPathStableKeysByID: [:]
            )
        ) {
        case .prepared(let replacement):
            return replacement
        case .rejected(let rejection):
            Issue.record("expected stable identity to prepare, got \(rejection)")
            return nil
        }
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
