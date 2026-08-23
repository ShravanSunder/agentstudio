import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer command presentation")
struct RepoExplorerCommandPresentationTests {
    @Test("typed presentation requests keep grouping and sort choices distinct")
    func typedPresentationRequestsKeepArgumentChoicesDistinct() {
        let groupingRepo = RepoExplorerCommandPresentationRequest(
            command: .setRepoSidebarGroupingRepo,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .noArguments
        )
        let groupingPane = RepoExplorerCommandPresentationRequest(
            command: .setRepoSidebarGroupingPane,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .noArguments
        )
        let sortName = RepoExplorerCommandPresentationRequest(
            command: .setRepoSidebarSortOrder,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .repoSidebarSortOrder(.ascending)
        )
        let sortRecent = RepoExplorerCommandPresentationRequest(
            command: .setRepoSidebarSortOrder,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .repoSidebarSortOrder(.descending)
        )

        #expect(Set([groupingRepo, groupingPane, sortName, sortRecent]).count == 4)
    }

    @Test("one visible worktree row produces one bounded request set")
    func visibleWorktreeRowProducesBoundedRequestSet() {
        let requests = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: UUID(),
            repoId: UUID(),
            isFavorite: false,
            showsFavoriteControl: true
        )

        #expect(requests.count == 10)
        #expect(requests.allSatisfy { $0.target != nil })
    }

    @Test("immutable snapshot distinguishes absent disabled and enabled presentation")
    func immutableSnapshotDistinguishesPresentationStates() {
        let worktreeId = UUID()
        let repoId = UUID()
        let requests = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: worktreeId,
            repoId: repoId,
            isFavorite: false,
            showsFavoriteControl: true
        )
        let openRequest = requests.first { request in
            request.command == .openWorktree && request.surface == .inlineControl
        }!
        let favoriteRequest = requests.first { request in
            request.command == .addRepoFavorite && request.surface == .inlineControl
        }!
        let snapshot = RepoExplorerCommandPresentationSnapshot(
            generation: 7,
            results: [openRequest: true, favoriteRequest: false]
        )

        let presentation = RepoExplorerWorktreeCommandPresentation.resolve(
            worktreeId: worktreeId,
            repoId: repoId,
            isFavorite: false,
            showsFavoriteControl: true,
            snapshot: snapshot
        )

        #expect(presentation.inlineCommand(.openWorktree)?.isEnabled == true)
        #expect(presentation.inlineCommand(.addRepoFavorite)?.isEnabled == false)
        #expect(presentation.contextMenuCommand(.openWorktree)?.isEnabled == nil)
    }

    @Test("visible worktree snapshot identity includes materialization generation and visible revision")
    func visibleWorktreeSnapshotIdentityIncludesTarget() {
        let worktreeID = UUIDv7.generate()
        let firstLifetimeID = RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate())
        let replacementLifetimeID = RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate())
        let first = RepoExplorerVisibleWorktreeSnapshot(
            target: RepoExplorerCommandPresentationTarget(
                materializationHostLifetimeID: firstLifetimeID,
                materializationGeneration: 4,
                visibleRevision: 7
            ),
            worktreeIDs: [worktreeID]
        )
        let retargeted = RepoExplorerVisibleWorktreeSnapshot(
            target: RepoExplorerCommandPresentationTarget(
                materializationHostLifetimeID: replacementLifetimeID,
                materializationGeneration: 4,
                visibleRevision: 7
            ),
            worktreeIDs: [worktreeID]
        )

        #expect(first != retargeted)
        #expect(first.worktreeIDs == retargeted.worktreeIDs)
    }

    @Test("command delta carries one complete snapshot and explicit target")
    func commandDeltaCarriesCompleteSnapshotAndTarget() {
        let worktreeID = UUIDv7.generate()
        let repoID = UUIDv7.generate()
        let target = RepoExplorerCommandPresentationTarget(
            materializationHostLifetimeID: RepoExplorerMaterializationHostLifetimeID(
                rawValue: UUIDv7.generate()
            ),
            materializationGeneration: 5,
            visibleRevision: 3
        )
        let request = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: worktreeID,
            repoId: repoID,
            isFavorite: false,
            showsFavoriteControl: true
        ).first!
        let snapshot = RepoExplorerCommandPresentationSnapshot(
            generation: 9,
            results: [request: true],
            favoriteStateByRepositoryID: [repoID: true]
        )
        let delta = RepoExplorerCommandPresentationDelta(
            commandGeneration: 9,
            target: target,
            snapshot: snapshot,
            affectedWorktreeIDs: [worktreeID],
            affectedRepositoryIDs: [repoID],
            affectedRequestIdentities: [request],
            toolbarChanged: false
        )

        #expect(delta.commandGeneration == delta.snapshot.generation)
        #expect(delta.target == target)
        #expect(delta.snapshot.results[request] == true)
        #expect(delta.snapshot.favoriteStateByRepositoryID[repoID] == true)
    }
}
