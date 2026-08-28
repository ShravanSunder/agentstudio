import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer command presentation")
struct RepoExplorerCommandPresentationTests {
    @Test("captured repository updates reserve the control slot without claiming loading")
    func capturedRepositoryUpdateDoesNotClaimLoading() {
        let repoID = UUIDv7.generate()
        let captured = RepositoryFactUpdateProgress.captured(
            repoId: repoID,
            attemptId: UUIDv7.generate()
        )
        let inProgress = RepositoryFactUpdateProgress.admitted(
            repoId: repoID,
            attemptId: UUIDv7.generate(),
            applicableSources: [.localGit],
            terminalResultsBySource: [:]
        )
        let settled = inProgress.settled([.localGit: .completed])

        #expect(RepoExplorerRepositoryUpdatePresentation.keepsActivitySlotVisible(captured))
        #expect(!RepoExplorerRepositoryUpdatePresentation.isLoading(captured))
        #expect(RepoExplorerRepositoryUpdatePresentation.isLoading(inProgress))
        #expect(!RepoExplorerRepositoryUpdatePresentation.keepsActivitySlotVisible(settled))
        #expect(!RepoExplorerRepositoryUpdatePresentation.isLoading(settled))
    }

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

    @Test("repository update presentation uses one exact targeted command request")
    func repositoryUpdatePresentationUsesExactTarget() {
        let repoID = UUIDv7.generate()
        let request = RepoExplorerRepositoryCommandPresentation.request(repoID: repoID)
        let disabledSnapshot = RepoExplorerCommandPresentationSnapshot(
            generation: 1,
            results: [request: false]
        )

        let presentation = RepoExplorerRepositoryCommandPresentation.resolve(
            repoID: repoID,
            snapshot: disabledSnapshot
        )

        #expect(request.command == .updateRepositoryFacts)
        #expect(request.surface == .inlineControl)
        #expect(request.target == repoID)
        #expect(request.targetType == .repo)
        #expect(presentation?.commandSpec.label == "Update Repository")
        #expect(presentation?.commandSpec.helpText == "Update local Git, remote references, and pull request facts")
        #expect(presentation?.isEnabled == false)
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
            worktreeIDs: [worktreeID],
            repositoryIDs: []
        )
        let retargeted = RepoExplorerVisibleWorktreeSnapshot(
            target: RepoExplorerCommandPresentationTarget(
                materializationHostLifetimeID: replacementLifetimeID,
                materializationGeneration: 4,
                visibleRevision: 7
            ),
            worktreeIDs: [worktreeID],
            repositoryIDs: []
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
