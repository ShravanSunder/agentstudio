import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer table row-height invalidation", .serialized)
struct RepoExplorerTableRowHeightInvalidationTests {
    @Test("offscreen worktree chip heights survive scrolling and filtered membership")
    func offscreenWorktreeChipHeightsSurviveScrollingAndFilteredMembership() throws {
        let fixtures = (0..<6).map(makeWorktreeFixture(index:))
        let loadingFixture = fixtures[4]
        let resolvedFixture = fixtures[5]
        let initialSnapshot = worktreeSnapshot(fixtures: fixtures)
        let enrichedStatuses = [
            loadingFixture.worktree.id: GitBranchStatus(
                isDirty: false,
                syncState: .unknown,
                prCount: nil,
                pullRequestIsLoading: true,
                linesAdded: 0,
                linesDeleted: 0,
                untrackedFileCount: 0
            ),
            resolvedFixture.worktree.id: GitBranchStatus(
                isDirty: true,
                syncState: .diverged(ahead: 7, behind: 3),
                prCount: 2,
                linesAdded: 184,
                linesDeleted: 19,
                untrackedFileCount: 1
            ),
        ]
        let enrichedSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: enrichedStatuses
        )
        let filteredSnapshot = worktreeSnapshot(
            fixtures: [loadingFixture, resolvedFixture],
            statusesByWorktreeID: enrichedStatuses
        )
        let materializer = RepoExplorerTableMaterializer(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            onVisibleWorktreeSnapshotChange: { _ in }
        )
        let window = makeMaterializerWindow(materializer)
        defer {
            materializer.detach()
            window.close()
        }

        try apply(
            snapshot: initialSnapshot,
            baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
            requestGeneration: 1,
            to: materializer
        )
        let scrollView = try #require(materializer.view as? NSScrollView)
        let tableView = try #require(scrollView.documentView as? NSTableView)
        let loadingInitialIndex = try #require(initialSnapshot.rowIndexByID[loadingFixture.rowID])
        let resolvedInitialIndex = try #require(initialSnapshot.rowIndexByID[resolvedFixture.rowID])
        let representedRows = tableView.rows(in: scrollView.contentView.documentVisibleRect)
        #expect(!NSLocationInRange(loadingInitialIndex, representedRows))
        #expect(!NSLocationInRange(resolvedInitialIndex, representedRows))

        let loadingInitialHeight = tableView.rect(ofRow: loadingInitialIndex).height
        let resolvedInitialHeight = tableView.rect(ofRow: resolvedInitialIndex).height
        try apply(
            snapshot: enrichedSnapshot,
            baseline: nativePlanBaseline(
                snapshot: initialSnapshot,
                revision: 1,
                visibleGeneration: 1
            ),
            requestGeneration: 2,
            to: materializer
        )

        let loadingEnrichedIndex = try #require(enrichedSnapshot.rowIndexByID[loadingFixture.rowID])
        let resolvedEnrichedIndex = try #require(enrichedSnapshot.rowIndexByID[resolvedFixture.rowID])
        let loadingOffscreenHeight = tableView.rect(ofRow: loadingEnrichedIndex).height
        let resolvedOffscreenHeight = tableView.rect(ofRow: resolvedEnrichedIndex).height
        materializer.scroll(to: loadingFixture.rowID, offset: 0)
        let loadingScrolledHeight = tableView.rect(ofRow: loadingEnrichedIndex).height

        try apply(
            snapshot: filteredSnapshot,
            baseline: nativePlanBaseline(
                snapshot: enrichedSnapshot,
                revision: 2,
                visibleGeneration: 2
            ),
            requestGeneration: 3,
            to: materializer
        )
        let loadingFilteredIndex = try #require(filteredSnapshot.rowIndexByID[loadingFixture.rowID])
        let resolvedFilteredIndex = try #require(filteredSnapshot.rowIndexByID[resolvedFixture.rowID])
        let loadingFilteredRect = tableView.rect(ofRow: loadingFilteredIndex)
        let resolvedFilteredRect = tableView.rect(ofRow: resolvedFilteredIndex)
        let expectedLoadingHeight = filteredSnapshot.rows[loadingFilteredIndex].layout.metrics.fallbackHeight
        let expectedResolvedHeight = filteredSnapshot.rows[resolvedFilteredIndex].layout.metrics.fallbackHeight

        #expect(expectedLoadingHeight > loadingInitialHeight)
        #expect(expectedResolvedHeight > resolvedInitialHeight)
        #expect(loadingOffscreenHeight == expectedLoadingHeight)
        #expect(resolvedOffscreenHeight == expectedResolvedHeight)
        #expect(loadingScrolledHeight == expectedLoadingHeight)
        #expect(loadingFilteredRect.height == expectedLoadingHeight)
        #expect(resolvedFilteredRect.height == expectedResolvedHeight)
        #expect(loadingFilteredRect.maxY == resolvedFilteredRect.minY)
        #expect(resolvedFilteredRect.maxY == filteredSnapshot.fallbackContentHeight)
    }

    private func apply(
        snapshot: RepoExplorerMaterializationSnapshot,
        baseline: RepoExplorerMaterializationBaseline,
        requestGeneration: UInt64,
        to materializer: RepoExplorerTableMaterializer
    ) throws {
        let presentation = nativePlanContent(snapshot)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: presentation,
            requestGeneration: requestGeneration
        ).get()
        let tablePlan = try #require(plan.tableUpdatePlan())
        var disposition: RepoExplorerMaterializationChildDisposition?

        materializer.apply(
            RepoExplorerMaterializationContentCandidate(
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: requestGeneration),
                requestGeneration: requestGeneration,
                visibleGeneration: requestGeneration,
                snapshot: snapshot,
                tableUpdatePlan: tablePlan
            )
        ) { disposition = $0 }

        #expect(disposition == .accepted)
    }

    private func worktreeSnapshot(
        fixtures: [WorktreeHeightFixture],
        statusesByWorktreeID: [UUID: GitBranchStatus] = [:]
    ) -> RepoExplorerMaterializationSnapshot {
        RepoExplorerMaterializationSnapshot(
            rows: fixtures.map { fixture in
                let presentation = RepoExplorerMaterializedRowPresentation.worktree(
                    RepoExplorerMaterializedWorktreePresentation(
                        rowID: fixture.rowID,
                        groupID: fixture.groupID,
                        repo: fixture.repo,
                        worktree: fixture.worktree,
                        checkoutTitle: fixture.worktree.name,
                        isMainCheckout: false,
                        checkoutColorHex: "#F5C451",
                        placementText: "",
                        branchStatus: statusesByWorktreeID[fixture.worktree.id] ?? .unknown,
                        branchName: fixture.worktree.name,
                        bridgeCommandResolution: .create,
                        paneDestinations: []
                    )
                )
                return RepoExplorerMaterializedRow(
                    id: fixture.rowID,
                    contentRevision: RepoExplorerRowContentRevision(presentation: presentation),
                    layout: RepoExplorerRowLayout.make(for: presentation),
                    representedRepoID: fixture.repo.id,
                    representedWorktreeID: fixture.worktree.id
                )
            }
        )
    }

    private func makeWorktreeFixture(index: Int) -> WorktreeHeightFixture {
        let repoID = UUIDv7.generate()
        let worktree = Worktree(
            id: UUIDv7.generate(),
            repoId: repoID,
            name: "worktree-\(index)",
            path: URL(fileURLWithPath: "/tmp/repo-explorer-row-height-\(index)")
        )
        let groupID = "group-\(index)"
        return WorktreeHeightFixture(
            groupID: groupID,
            repo: RepoPresentationItem(
                id: repoID,
                name: "repository-\(index)",
                repoPath: worktree.path,
                stableKey: "repository-\(index)",
                worktrees: [worktree]
            ),
            worktree: worktree,
            rowID: .worktree(
                groupID: groupID,
                repoID: repoID,
                worktreeID: worktree.id
            )
        )
    }

    private func makeMaterializerWindow(
        _ materializer: RepoExplorerTableMaterializer
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 70),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = materializer.view
        window.layoutIfNeeded()
        return window
    }
}

private struct WorktreeHeightFixture {
    let groupID: String
    let repo: RepoPresentationItem
    let worktree: Worktree
    let rowID: RepoExplorerRowID
}
