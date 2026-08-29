import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer table row-height invalidation", .serialized)
struct RepoExplorerTableRowHeightInvalidationTests {
    @Test("context-menu row keeps opening height until deferred content installs")
    func contextMenuRowKeepsOpeningHeightUntilDeferredContentInstalls() async throws {
        let fixtures = (0..<6).map(makeWorktreeFixture(index:))
        let fixture = fixtures[5]
        var openingStatuses = confirmedEmptyStatuses(for: fixtures)
        openingStatuses[fixture.worktree.id] = resolvedStatus()
        let openingSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: openingStatuses
        )
        let updatedSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: confirmedEmptyStatuses(for: fixtures)
        )
        let materializer = RepoExplorerTableMaterializer(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            onVisibleWorktreeSnapshotChange: { _ in }
        )
        let window = makeMaterializerWindow(materializer, height: 36)
        defer {
            materializer.detach()
            window.close()
        }

        try apply(
            snapshot: openingSnapshot,
            baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
            requestGeneration: 1,
            to: materializer
        )
        let scrollView = try #require(materializer.view as? NSScrollView)
        let tableView = try #require(scrollView.documentView as? NSTableView)
        let rowIndex = try #require(openingSnapshot.rowIndexByID[fixture.rowID])
        let precedingRowIndex = rowIndex - 1
        materializer.scroll(to: fixture.rowID, offset: 0)
        let openingHeight = tableView.rect(ofRow: rowIndex).height
        let openingFrameHeight = tableView.frame.height
        let updatedHeight = updatedSnapshot.rows[rowIndex].layout.metrics.fallbackHeight
        let openingCell = try #require(
            tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: true)
                as? RepoExplorerTableRowCell
        )
        let openingCellIdentity = ObjectIdentifier(openingCell)
        let openingBinding = try #require(openingCell.currentBindingIdentity)
        let openingAnchor = try #require(materializer.currentTopVisibleAnchor)
        let rootMenu = NSMenu()
        let childMenu = NSMenu()
        let rootMenuIdentity = ObjectIdentifier(rootMenu)
        let childMenuIdentity = ObjectIdentifier(childMenu)

        materializer.menuDidBeginTracking(rootMenuIdentity, clickedRow: rowIndex)
        materializer.menuDidBeginTracking(childMenuIdentity, clickedRow: -1)
        materializer.menuDidEndTracking(rootMenuIdentity)
        try apply(
            snapshot: updatedSnapshot,
            baseline: nativePlanBaseline(
                snapshot: openingSnapshot,
                revision: 1,
                visibleGeneration: 1
            ),
            requestGeneration: 2,
            to: materializer
        )

        #expect(openingHeight > updatedHeight)
        #expect(tableView.rect(ofRow: rowIndex).height == openingHeight)
        #expect(tableView.frame.height == openingFrameHeight)
        #expect(
            tableView.rect(ofRow: precedingRowIndex).maxY
                == tableView.rect(ofRow: rowIndex).minY
        )
        #expect(tableView.rect(ofRow: rowIndex).maxY == tableView.frame.height)
        let trackedCell = try #require(
            tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false)
                as? RepoExplorerTableRowCell
        )
        #expect(ObjectIdentifier(trackedCell) == openingCellIdentity)
        #expect(trackedCell.currentBindingIdentity == openingBinding)
        #expect(materializer.currentTopVisibleAnchor == openingAnchor)

        materializer.menuDidEndTracking(childMenuIdentity)
        for _ in 0..<100 {
            if tableView.rect(ofRow: rowIndex).height == updatedHeight,
                trackedCell.currentBindingIdentity?.visibleGeneration == 2
            {
                break
            }
            await Task.yield()
        }

        #expect(tableView.rect(ofRow: rowIndex).height == updatedHeight)
        #expect(tableView.frame.height == updatedSnapshot.fallbackContentHeight)
        #expect(
            tableView.rect(ofRow: precedingRowIndex).maxY
                == tableView.rect(ofRow: rowIndex).minY
        )
        #expect(tableView.rect(ofRow: rowIndex).maxY == tableView.frame.height)
        #expect(trackedCell.currentBindingIdentity?.visibleGeneration == 2)
        #expect(materializer.currentTopVisibleAnchor == openingAnchor)
    }

    @Test("offscreen worktree chip heights survive scrolling and filtered membership")
    func offscreenWorktreeChipHeightsSurviveScrollingAndFilteredMembership() throws {
        let fixtures = (0..<6).map(makeWorktreeFixture(index:))
        let loadingFixture = fixtures[4]
        let resolvedFixture = fixtures[5]
        let initialSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: confirmedEmptyStatuses(for: fixtures)
        )
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

    @Test("loading and chip height changes preserve a partially visible top row")
    func contentHeightChangesPreservePartiallyVisibleTopRow() throws {
        let fixtures = (0..<6).map(makeWorktreeFixture(index:))
        let anchorFixture = fixtures[2]
        let initialSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: confirmedEmptyStatuses(for: fixtures)
        )
        let loadingStatuses = Dictionary(
            uniqueKeysWithValues: fixtures.map { ($0.worktree.id, loadingStatus()) }
        )
        let resolvedStatuses = Dictionary(
            uniqueKeysWithValues: fixtures.map { ($0.worktree.id, resolvedStatus()) }
        )
        let loadingSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: loadingStatuses
        )
        let resolvedSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: resolvedStatuses
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
        let anchorIndex = try #require(initialSnapshot.rowIndexByID[anchorFixture.rowID])
        let partialRowOffset: CGFloat = 10
        scrollView.contentView.scroll(
            to: NSPoint(
                x: 0,
                y: tableView.rect(ofRow: anchorIndex).minY + partialRowOffset
            )
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(materializer.currentTopVisibleAnchor?.rowID == anchorFixture.rowID)
        #expect(materializer.currentTopVisibleAnchor?.offset == -partialRowOffset)

        try apply(
            snapshot: loadingSnapshot,
            baseline: nativePlanBaseline(
                snapshot: initialSnapshot,
                revision: 1,
                visibleGeneration: 1
            ),
            requestGeneration: 2,
            to: materializer
        )
        #expect(materializer.currentTopVisibleAnchor?.rowID == anchorFixture.rowID)
        #expect(materializer.currentTopVisibleAnchor?.offset == -partialRowOffset)

        try apply(
            snapshot: resolvedSnapshot,
            baseline: nativePlanBaseline(
                snapshot: loadingSnapshot,
                revision: 2,
                visibleGeneration: 2
            ),
            requestGeneration: 3,
            to: materializer
        )
        #expect(materializer.currentTopVisibleAnchor?.rowID == anchorFixture.rowID)
        #expect(materializer.currentTopVisibleAnchor?.offset == -partialRowOffset)

        try apply(
            snapshot: initialSnapshot,
            baseline: nativePlanBaseline(
                snapshot: resolvedSnapshot,
                revision: 3,
                visibleGeneration: 3
            ),
            requestGeneration: 4,
            to: materializer
        )
        #expect(materializer.currentTopVisibleAnchor?.rowID == anchorFixture.rowID)
        #expect(materializer.currentTopVisibleAnchor?.offset == -partialRowOffset)
    }

    @Test("repeated confirmed-empty refresh cycles preserve every row rect and scroll anchor")
    func repeatedConfirmedEmptyRefreshCyclesPreserveGeometry() throws {
        let fixtures = (0..<6).map(makeWorktreeFixture(index:))
        let anchorFixture = fixtures[2]
        let confirmedEmptySnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: confirmedEmptyStatuses(for: fixtures)
        )
        let refreshingSnapshot = worktreeSnapshot(
            fixtures: fixtures,
            statusesByWorktreeID: refreshingConfirmedEmptyStatuses(for: fixtures)
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
            snapshot: confirmedEmptySnapshot,
            baseline: nativePlanRowlessBaseline(.noRepositories, revision: 0),
            requestGeneration: 1,
            to: materializer
        )
        let scrollView = try #require(materializer.view as? NSScrollView)
        let tableView = try #require(scrollView.documentView as? NSTableView)
        let anchorIndex = try #require(confirmedEmptySnapshot.rowIndexByID[anchorFixture.rowID])
        let partialRowOffset: CGFloat = 10
        scrollView.contentView.scroll(
            to: NSPoint(
                x: 0,
                y: tableView.rect(ofRow: anchorIndex).minY + partialRowOffset
            )
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let baselineRects = fixtures.map { fixture in
            tableView.rect(
                ofRow: confirmedEmptySnapshot.rowIndexByID[fixture.rowID] ?? -1
            )
        }
        let baselineAnchor = try #require(materializer.currentTopVisibleAnchor)
        var currentSnapshot = confirmedEmptySnapshot
        var currentGeneration: UInt64 = 1

        for _ in 0..<4 {
            for nextSnapshot in [refreshingSnapshot, confirmedEmptySnapshot] {
                let nextGeneration = currentGeneration + 1
                try apply(
                    snapshot: nextSnapshot,
                    baseline: nativePlanBaseline(
                        snapshot: currentSnapshot,
                        revision: currentGeneration,
                        visibleGeneration: currentGeneration
                    ),
                    requestGeneration: nextGeneration,
                    to: materializer
                )

                #expect(materializer.currentTopVisibleAnchor == baselineAnchor)
                #expect(
                    fixtures.map { fixture in
                        tableView.rect(
                            ofRow: nextSnapshot.rowIndexByID[fixture.rowID] ?? -1
                        )
                    } == baselineRects
                )
                currentSnapshot = nextSnapshot
                currentGeneration = nextGeneration
            }
        }
    }

    private func loadingStatus() -> GitBranchStatus {
        GitBranchStatus(
            isDirty: false,
            syncState: .unknown,
            prCount: nil,
            pullRequestIsLoading: true,
            linesAdded: 0,
            linesDeleted: 0,
            untrackedFileCount: 0
        )
    }

    private func resolvedStatus() -> GitBranchStatus {
        GitBranchStatus(
            isDirty: true,
            syncState: .diverged(ahead: 7, behind: 3),
            prCount: 2,
            linesAdded: 184,
            linesDeleted: 19,
            untrackedFileCount: 1
        )
    }

    private func confirmedEmptyStatus() -> GitBranchStatus {
        GitBranchStatus(
            isDirty: false,
            syncState: .synced,
            prCount: 0,
            linesAdded: 0,
            linesDeleted: 0,
            untrackedFileCount: 0
        )
    }

    private func confirmedEmptyStatuses(
        for fixtures: [WorktreeHeightFixture]
    ) -> [UUID: GitBranchStatus] {
        Dictionary(
            uniqueKeysWithValues: fixtures.map { ($0.worktree.id, confirmedEmptyStatus()) }
        )
    }

    private func refreshingConfirmedEmptyStatuses(
        for fixtures: [WorktreeHeightFixture]
    ) -> [UUID: GitBranchStatus] {
        Dictionary(
            uniqueKeysWithValues: fixtures.map { fixture in
                (
                    fixture.worktree.id,
                    GitBranchStatus(
                        isDirty: false,
                        syncState: .synced,
                        prCount: 0,
                        pullRequestIsLoading: true,
                        linesAdded: 0,
                        linesDeleted: 0,
                        untrackedFileCount: 0
                    )
                )
            }
        )
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
        _ materializer: RepoExplorerTableMaterializer,
        height: CGFloat = 70
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: height),
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
