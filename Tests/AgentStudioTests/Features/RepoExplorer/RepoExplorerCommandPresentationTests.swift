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

    @Test("surface-specific presentation requests keep grouping and sort choices distinct")
    func surfaceSpecificPresentationRequestsKeepChoicesDistinct() {
        let groupingRepo = RepoExplorerCommandPresentationRequest(
            command: .setReposGroupingRepo,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .noArguments
        )
        let groupingPane = RepoExplorerCommandPresentationRequest(
            command: .setPanesGroupingRepo,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .noArguments
        )
        let sortName = RepoExplorerCommandPresentationRequest(
            command: .setReposSortFieldName,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .noArguments
        )
        let sortRecent = RepoExplorerCommandPresentationRequest(
            command: .setPanesSortFieldActivity,
            surface: .inlineControl,
            target: nil,
            targetType: nil,
            arguments: .noArguments
        )

        #expect(Set([groupingRepo, groupingPane, sortName, sortRecent]).count == 4)
    }

    @Test("one visible worktree row produces one bounded request set")
    func visibleWorktreeRowProducesBoundedRequestSet() {
        let requests = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: UUID(),
            repoId: UUID(),
            isPinned: false,
            showsPinnedControl: true
        )

        #expect(requests.count == 10)
        #expect(requests.allSatisfy { $0.target != nil })
    }

    @Test("one visible pane produces independent pin requests")
    func visiblePaneProducesIndependentPinRequests() {
        let paneId = UUIDv7.generate()
        let requests = RepoExplorerPaneCommandPresentation.requests(
            paneId: paneId,
            isPinned: false
        )

        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.command == .pinPane })
        #expect(requests.allSatisfy { $0.target == paneId && $0.targetType == .pane })
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
        #expect(presentation?.commandSpec.label == "Refresh")
        #expect(
            presentation?.commandSpec.helpText
                == "Fetch latest remote references and refresh repository facts"
        )
        #expect(presentation?.isEnabled == false)
    }

    @Test("immutable snapshot distinguishes absent disabled and enabled presentation")
    func immutableSnapshotDistinguishesPresentationStates() {
        let worktreeId = UUID()
        let repoId = UUID()
        let requests = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: worktreeId,
            repoId: repoId,
            isPinned: false,
            showsPinnedControl: true
        )
        let openRequest = requests.first { request in
            request.command == .openWorktree && request.surface == .inlineControl
        }!
        let pinRequest = requests.first { request in
            request.command == .pinRepo && request.surface == .inlineControl
        }!
        let snapshot = RepoExplorerCommandPresentationSnapshot(
            generation: 7,
            results: [openRequest: true, pinRequest: false]
        )

        let presentation = RepoExplorerWorktreeCommandPresentation.resolve(
            worktreeId: worktreeId,
            repoId: repoId,
            isPinned: false,
            showsPinnedControl: true,
            snapshot: snapshot
        )

        #expect(presentation.inlineCommand(.openWorktree)?.isEnabled == true)
        #expect(presentation.inlineCommand(.pinRepo)?.isEnabled == false)
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
            isPinned: false,
            showsPinnedControl: true
        ).first!
        let snapshot = RepoExplorerCommandPresentationSnapshot(
            generation: 9,
            results: [request: true],
            pinnedStateByRepositoryID: [repoID: true]
        )
        let delta = RepoExplorerCommandPresentationDelta(
            commandGeneration: 9,
            target: target,
            snapshot: snapshot,
            affectedWorktreeIDs: [worktreeID],
            affectedRepositoryIDs: [repoID],
            affectedPaneIDs: [],
            affectedRequestIdentities: [request],
            toolbarChanged: false
        )

        #expect(delta.commandGeneration == delta.snapshot.generation)
        #expect(delta.target == target)
        #expect(delta.snapshot.results[request] == true)
        #expect(delta.snapshot.pinnedStateByRepositoryID[repoID] == true)
    }
}
