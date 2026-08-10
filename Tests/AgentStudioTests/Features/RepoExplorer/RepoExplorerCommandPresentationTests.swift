import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer command presentation")
struct RepoExplorerCommandPresentationTests {
    @Test("Create New leaves use concise destination-local labels")
    func createNewLeavesUseConciseDestinationLocalLabels() {
        #expect(
            RepoExplorerWorktreeCommandPresentation.createNewLeafLabel(for: .openNewTerminalInTab)
                == "Terminal"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.createNewLeafLabel(for: .openWorktreeInPane)
                == "Terminal"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.createNewLeafLabel(for: .openBridgeReviewInNewTab)
                == "Review"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.createNewLeafLabel(for: .showBridgeReview)
                == "Review"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.createNewLeafLabel(for: .openBridgeFilesInNewTab)
                == "Files"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.createNewLeafLabel(for: .showBridgeFiles)
                == "Files"
        )
        #expect(
            RepoExplorerWorktreeCommandPresentation.createNewLeafLabel(for: .openWorktree) == nil
        )
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
}
