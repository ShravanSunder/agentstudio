import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer native context menu", .serialized)
struct RepoExplorerContextMenuPresenterTests {
    @Test("table receives the right click and owns the group menu")
    func tableOwnsContextMenu() throws {
        let repoID = UUIDv7.generate()
        let snapshot = groupSnapshot(repoID: repoID)
        let materializer = makeMaterializer()
        let window = makeWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }
        try apply(snapshot: snapshot, requestGeneration: 1, to: materializer)

        let scrollView = try #require(materializer.view as? NSScrollView)
        let tableView = try #require(scrollView.documentView as? RepoExplorerTableView)
        let rowRect = tableView.rect(ofRow: 0)
        let rightClick = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: tableView.convert(
                    NSPoint(x: rowRect.midX, y: rowRect.midY),
                    to: nil
                ),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        let menu = try #require(tableView.menu(for: rightClick))

        #expect(
            menu.items.map(\.title) == [
                LocalActionSpec.revealInFinder.actionSpec.label,
                LocalActionSpec.copyPath.actionSpec.label,
            ])
        #expect(menu.items.allSatisfy { $0.image == nil })
    }

    @Test("nested menu targets its stable row and fails closed after removal")
    func nestedMenuUsesStableRowIdentity() throws {
        let repoID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let destination = RepoExplorerPaneDestination(
            paneId: paneID,
            repoId: repoID,
            worktreeId: UUIDv7.generate(),
            worktreeLabel: "main",
            tabId: UUIDv7.generate(),
            tabIndex: 0,
            paneIndexInTab: 0,
            isActiveInTab: true,
            paneDisplayLabel: "Terminal"
        )
        let snapshot = groupSnapshot(repoID: repoID, paneDestinations: [destination])
        var focusedPaneIDs: [UUID] = []
        let materializer = makeMaterializer(
            interactions: RepoExplorerTableInteractions(
                onCommandRequest: { _ in },
                onToggleGroup: { _ in },
                onFocusPane: { focusedPaneIDs.append($0) }
            )
        )
        let window = makeWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }
        try apply(snapshot: snapshot, requestGeneration: 1, to: materializer)

        let rowID = RepoExplorerRowID.group(groupID: "repo-activity")
        let menu = try #require(materializer.makeContextMenu(forRowID: rowID))
        let paneMenuItem = try #require(
            menu.items.first(where: {
                $0.title == LocalActionSpec.goToPane.actionSpec.label
            })
        )
        let paneMenu = try #require(paneMenuItem.submenu)
        #expect(paneMenuItem.image == nil)
        paneMenu.performActionForItem(at: 0)
        #expect(focusedPaneIDs == [paneID])

        try apply(
            snapshot: nativePlanSnapshot(["replacement"]),
            baseline: nativePlanBaseline(
                snapshot: snapshot,
                revision: 1,
                visibleGeneration: 1
            ),
            requestGeneration: 2,
            to: materializer
        )
        paneMenu.performActionForItem(at: 0)

        #expect(focusedPaneIDs == [paneID])
        #expect(materializer.makeContextMenu(forRowID: rowID) == nil)
        #expect(paneMenu.items.map(\.title) == [destination.label])
    }

    @Test("worktree menu preserves command labels enablement and dispatch")
    func worktreeMenuPreservesCommandPresentation() throws {
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let row = worktreeRow(repoID: repoID, worktreeID: worktreeID)
        let requests = RepoExplorerWorktreeCommandPresentation.requests(
            worktreeId: worktreeID,
            repoId: repoID,
            isFavorite: false,
            showsFavoriteControl: true
        )
        let disabledRequest = try #require(
            requests.first(where: { $0.command == .showBridgeFiles })
        )
        let snapshot = RepoExplorerCommandPresentationSnapshot(
            generation: 7,
            results: Dictionary(
                uniqueKeysWithValues: requests.map { request in
                    (request, request != disabledRequest)
                }
            ),
            favoriteStateByRepositoryID: [repoID: false]
        )
        var dispatchedRequests: [RepoExplorerCommandPresentationRequest] = []
        let presenter = RepoExplorerContextMenuPresenter(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            interactions: RepoExplorerTableInteractions(
                onCommandRequest: { dispatchedRequests.append($0) },
                onToggleGroup: { _ in },
                onFocusPane: { _ in }
            ),
            isRowCurrent: { $0 == row.id }
        )

        let menu = try #require(
            presenter.makeMenu(for: row, commandPresentationSnapshot: snapshot)
        )
        let newTabMenu = try #require(menu.items[0].submenu)
        let currentPaneMenu = try #require(menu.items[1].submenu)

        #expect(
            menu.items.map(\.title) == [
                LocalActionSpec.createNewInTab.actionSpec.label,
                LocalActionSpec.createNewInPane.actionSpec.label,
                "",
                AppCommand.addRepoFavorite.definition.label,
                LocalActionSpec.openInEditorMenu.actionSpec.label,
                "",
                LocalActionSpec.revealInFinder.actionSpec.label,
                LocalActionSpec.copyPath.actionSpec.label,
            ])
        #expect(newTabMenu.items.map(\.title) == ["Terminal", "Review", "Files"])
        #expect(currentPaneMenu.items.map(\.title) == ["Terminal", "Review", "Files"])
        #expect(!currentPaneMenu.items[2].isEnabled)

        newTabMenu.performActionForItem(at: 0)
        #expect(dispatchedRequests.map(\.command) == [.openNewTerminalInTab])
        #expect(dispatchedRequests.first?.target == worktreeID)
        #expect(dispatchedRequests.first?.surface == .contextMenu)
    }

    private func makeMaterializer(
        interactions: RepoExplorerTableInteractions = .inert
    ) -> RepoExplorerTableMaterializer {
        RepoExplorerTableMaterializer(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            interactions: interactions,
            onVisibleWorktreeSnapshotChange: { _ in }
        )
    }

    private func makeWindow(_ materializer: RepoExplorerTableMaterializer) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = materializer.view
        window.layoutIfNeeded()
        return window
    }

    private func apply(
        snapshot: RepoExplorerMaterializationSnapshot,
        baseline: RepoExplorerMaterializationBaseline? = nil,
        requestGeneration: UInt64,
        to materializer: RepoExplorerTableMaterializer
    ) throws {
        let resolvedBaseline =
            baseline
            ?? nativePlanRowlessBaseline(.noRepositories, revision: 0)
        let presentation = nativePlanContent(snapshot)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: resolvedBaseline,
            candidate: presentation,
            requestGeneration: requestGeneration
        ).get()
        materializer.apply(
            RepoExplorerMaterializationContentCandidate(
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: requestGeneration),
                requestGeneration: requestGeneration,
                visibleGeneration: requestGeneration,
                snapshot: snapshot,
                tableUpdatePlan: try #require(plan.tableUpdatePlan())
            )
        ) { _ in }
    }

    private func groupSnapshot(
        repoID: UUID,
        paneDestinations: [RepoExplorerPaneDestination] = []
    ) -> RepoExplorerMaterializationSnapshot {
        let group = RepoExplorerMaterializedGroupHeaderPresentation(
            groupID: "repo-activity",
            icon: .repo,
            title: "Repository",
            organizationName: nil,
            colorHex: nil,
            isExpanded: true,
            repoIDs: [repoID],
            semanticRepoPath: URL(filePath: "/tmp/repository"),
            paneDestinations: paneDestinations
        )
        let presentation = RepoExplorerMaterializedRowPresentation.groupHeader(group)
        return RepoExplorerMaterializationSnapshot(rows: [
            RepoExplorerMaterializedRow(
                id: .group(groupID: group.groupID),
                contentRevision: RepoExplorerRowContentRevision(presentation: presentation),
                layout: RepoExplorerRowLayout.make(for: presentation),
                representedRepoID: repoID,
                representedWorktreeID: nil
            )
        ])
    }

    private func worktreeRow(repoID: UUID, worktreeID: UUID) -> RepoExplorerMaterializedRow {
        let groupID = "remote:agent-studio"
        let worktree = Worktree(
            id: worktreeID,
            repoId: repoID,
            name: "main",
            path: URL(filePath: "/tmp/agent-studio-context-menu"),
            isMainWorktree: true
        )
        let repository = RepoPresentationItem(
            id: repoID,
            name: "agent-studio",
            repoPath: worktree.path,
            stableKey: "agent-studio",
            worktrees: [worktree]
        )
        let rowID = RepoExplorerRowID.worktree(
            groupID: groupID,
            repoID: repoID,
            worktreeID: worktreeID
        )
        let presentation = RepoExplorerMaterializedRowPresentation.worktree(
            RepoExplorerMaterializedWorktreePresentation(
                rowID: rowID,
                groupID: groupID,
                repo: repository,
                worktree: worktree,
                checkoutTitle: "agent-studio",
                isMainCheckout: true,
                checkoutColorHex: "#F5C451",
                placementText: "",
                branchStatus: .unknown,
                branchName: "main",
                bridgeCommandResolution: .create,
                paneDestinations: []
            )
        )
        return RepoExplorerMaterializedRow(
            id: rowID,
            contentRevision: RepoExplorerRowContentRevision(presentation: presentation),
            layout: RepoExplorerRowLayout.make(for: presentation),
            representedRepoID: repoID,
            representedWorktreeID: worktreeID
        )
    }
}
