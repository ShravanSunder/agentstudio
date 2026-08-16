import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

private final class RepoProjectionInvalidationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var invalidationCount: Int {
        lock.withLock { storedCount }
    }

    func record() {
        lock.withLock {
            storedCount += 1
        }
    }
}

@MainActor
func makeRepoExplorerTestOcticonLoader(from testFilePath: String = #filePath) -> OcticonLoader {
    OcticonLoader(
        resourceRootURL: testAgentStudioResourceRootURL(from: testFilePath)
    )
}

@MainActor
private final class BridgeAttendanceSnapshotReadRecorder {
    private(set) var readCount = 0
    private let ordinalByPaneId: [UUID: UInt64]

    init(ordinalByPaneId: [UUID: UInt64]) {
        self.ordinalByPaneId = ordinalByPaneId
    }

    func readOrdinal(for paneId: UUID) -> UInt64? {
        readCount += 1
        return ordinalByPaneId[paneId]
    }
}

@MainActor
private final class PaneFocusRecordingDispatcher: AppCommandDispatching {
    private(set) var command: AppCommand?
    private(set) var target: UUID?
    private(set) var targetType: SearchItemType?

    func dispatch(_: AppCommand) {}

    func dispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        self.command = command
        self.target = target
        self.targetType = targetType
    }

    func canDispatch(_: AppCommand) -> Bool { true }
    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool { true }
    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? { nil }
    func dispatchMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}

private final class RepoExplorerProjectionInputInvalidationCounter: @unchecked Sendable {
    private(set) var count = 0
    private(set) var didFire = false

    func record() {
        didFire = true
        count += 1
    }
}

@MainActor
private func repoExplorerProjectionRequestKey(
    worktreeIds: [UUID],
    repoCache: RepoCacheAtom
) -> RepoExplorerProjectionRequestKey {
    let worktreeEnrichmentSnapshot = RepoExplorerView.worktreeEnrichmentSnapshot(
        for: worktreeIds,
        repoCache: repoCache
    )
    return RepoExplorerView.projectionRequestKey(
        for: RepoExplorerProjectionRequest(
            generation: 0,
            snapshot: RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                query: ""
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic,
            worktreeEnrichmentSnapshot: worktreeEnrichmentSnapshot,
            pullRequestFactsSnapshot: RepoExplorerView.pullRequestFactsSnapshot(
                for: worktreeEnrichmentSnapshot,
                repoCache: repoCache
            )
        )
    )
}

@MainActor
@Suite("RepoExplorerViewProjectionHelperTests")
struct RepoExplorerViewProjectionHelperTests {
    @Test("timeout-only repo enrichment wakes capture and changes scanning projection")
    func timeoutOnlyRepoEnrichmentWakesAndChangesProjection() {
        let repoCache = RepoCacheAtom()
        let repoId = UUIDv7.generate()
        let worktree = Worktree(
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/repo-explorer-timeout-observation")
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "timeout-observation",
            repoPath: worktree.path,
            stableKey: "timeout-observation",
            worktrees: [worktree]
        )
        let counter = RepoExplorerProjectionInputInvalidationCounter()

        withObservationTracking {
            _ = RepoExplorerView.observeRepoEnrichmentInputs(
                repositoryIDs: [repoId],
                repoCache: repoCache
            )
        } onChange: {
            counter.record()
        }
        let scanningProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(repos: [repo], repoEnrichmentByRepoId: [:], query: "")
        )

        repoCache.setRepoEnrichment(.statusUnavailable(repoId: repoId, reason: "timeout"))
        let unavailableEnrichment = [repoId: repoCache.repoEnrichment(for: repoId)!]
        let unavailableProjection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: unavailableEnrichment,
                query: ""
            )
        )

        #expect(counter.count == 1)
        #expect(scanningProjection.scanningRepoCount(enrichmentByRepoId: [:]) == 1)
        #expect(unavailableProjection.scanningRepoCount(enrichmentByRepoId: unavailableEnrichment) == 0)
        #expect(
            unavailableProjection.sections[0].loadingState(enrichmentByRepoId: unavailableEnrichment)
                == .statusUnavailable)
    }

    @Test("section subheading aligns with disclosure caret leading edge")
    func sectionSubheadingAlignsWithDisclosureCaretLeadingEdge() {
        #expect(
            RepoExplorerView.sectionHeaderLeadingInset
                == AppStyles.Shell.Sidebar.listRowLeadingInset)
    }

    @Test("projection fingerprint includes ordered section identity and favorite membership")
    func projectionFingerprintIncludesOrderedSectionIdentityAndFavoriteMembership() {
        let repoId = UUID(uuidString: "01989f63-8e2a-7000-8000-000000000001")!
        let worktree = Worktree(
            repoId: repoId,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio")
        )
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: worktree.path,
            stableKey: "agent-studio",
            worktrees: [worktree]
        )
        let group = RepoPresentationGroup(
            id: "repo:\(repoId.uuidString)",
            repoTitle: repo.name,
            organizationName: nil,
            repos: [repo]
        )
        let favoriteRepo = RepoPresentationItem(
            id: repo.id,
            name: repo.name,
            repoPath: repo.repoPath,
            stableKey: repo.stableKey,
            isFavorite: true,
            worktrees: repo.worktrees
        )
        let favoriteGroup = RepoPresentationGroup(
            id: group.id,
            repoTitle: group.repoTitle,
            organizationName: group.organizationName,
            repos: [favoriteRepo]
        )
        let repositoriesProjection = RepoExplorerSidebarProjection(
            sections: [
                RepoExplorerSidebarSection(
                    kind: .repositories,
                    resolvedGroups: [group],
                    loadingRepos: []
                )
            ],
            resolvedGroups: [group],
            loadingRepos: [],
            emptyState: .content
        )
        let favoritesProjection = RepoExplorerSidebarProjection(
            sections: [
                RepoExplorerSidebarSection(
                    kind: .favorites,
                    resolvedGroups: [group],
                    loadingRepos: []
                )
            ],
            resolvedGroups: [group],
            loadingRepos: [],
            emptyState: .content
        )
        let favoriteMembershipProjection = RepoExplorerSidebarProjection(
            sections: [
                RepoExplorerSidebarSection(
                    kind: .repositories,
                    resolvedGroups: [favoriteGroup],
                    loadingRepos: []
                )
            ],
            resolvedGroups: [favoriteGroup],
            loadingRepos: [],
            emptyState: .content
        )

        #expect(
            RepoExplorerView.projectionFingerprint(for: repositoriesProjection)
                != RepoExplorerView.projectionFingerprint(for: favoritesProjection))
        #expect(
            RepoExplorerView.projectionFingerprint(for: repositoriesProjection)
                != RepoExplorerView.projectionFingerprint(for: favoriteMembershipProjection))
    }

    @Test("missing relevant worktree facts wake capture and change the admitted request key")
    func missingRelevantWorktreeFactsWakeAndChangeRequestKeyWhenInserted() {
        let cache = RepoCacheAtom()
        let relevantWorktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let counter = RepoExplorerProjectionInputInvalidationCounter()
        cache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: relevantWorktreeId, repoId: repoId, branch: "main")
        )

        let initialRequestKey = withObservationTracking {
            repoExplorerProjectionRequestKey(
                worktreeIds: [relevantWorktreeId],
                repoCache: cache
            )
        } onChange: {
            counter.record()
        }

        let branchKey = RepoBranchKey(repoId: repoId, branch: "main")!
        cache.applyPullRequestFacts([
            branchKey: PullRequestFacts(openCount: 1, exactOpenURL: nil)
        ])
        let changedRequestKey = repoExplorerProjectionRequestKey(
            worktreeIds: [relevantWorktreeId],
            repoCache: cache
        )

        #expect(counter.count == 1)
        #expect(changedRequestKey != initialRequestKey)
    }

    @Test("unrelated worktree facts neither wake capture nor change the admitted request key")
    func unrelatedWorktreeFactsDoNotWakeOrChangeRequestKey() {
        let cache = RepoCacheAtom()
        let relevantWorktreeId = UUIDv7.generate()
        let unrelatedWorktreeId = UUIDv7.generate()
        let relevantRepoId = UUIDv7.generate()
        let unrelatedRepoId = UUIDv7.generate()
        let counter = RepoExplorerProjectionInputInvalidationCounter()
        cache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: relevantWorktreeId, repoId: relevantRepoId, branch: "main")
        )
        cache.setWorktreeEnrichment(
            WorktreeEnrichment(worktreeId: unrelatedWorktreeId, repoId: unrelatedRepoId, branch: "main")
        )
        let relevantBranchKey = RepoBranchKey(repoId: relevantRepoId, branch: "main")!
        let unrelatedBranchKey = RepoBranchKey(repoId: unrelatedRepoId, branch: "main")!
        cache.applyPullRequestFacts([
            relevantBranchKey: PullRequestFacts(openCount: 1, exactOpenURL: nil)
        ])

        let initialRequestKey = withObservationTracking {
            repoExplorerProjectionRequestKey(
                worktreeIds: [relevantWorktreeId],
                repoCache: cache
            )
        } onChange: {
            counter.record()
        }

        cache.applyPullRequestFacts([
            unrelatedBranchKey: PullRequestFacts(openCount: 2, exactOpenURL: nil)
        ])
        let requestKeyAfterUnrelatedChange = repoExplorerProjectionRequestKey(
            worktreeIds: [relevantWorktreeId],
            repoCache: cache
        )
        #expect(!counter.didFire)
        #expect(requestKeyAfterUnrelatedChange == initialRequestKey)

        cache.applyPullRequestFacts([
            relevantBranchKey: PullRequestFacts(openCount: 3, exactOpenURL: nil)
        ])
        let requestKeyAfterRelevantChange = repoExplorerProjectionRequestKey(
            worktreeIds: [relevantWorktreeId],
            repoCache: cache
        )
        #expect(counter.count == 1)
        #expect(requestKeyAfterRelevantChange != initialRequestKey)
    }

    @Test("pane navigation dispatches exact focusPane target")
    func paneNavigationDispatchesExactFocusTarget() {
        let dispatcher = PaneFocusRecordingDispatcher()
        let paneId = UUIDv7.generate()
        let view = RepoExplorerView(
            store: WorkspaceStore(startsObserving: false),
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
            bridgeAttendanceSnapshot: { _ in nil },
            commandDispatcher: dispatcher,
            onSetSortOrder: { _ in },
            onRefocusActivePane: {},
            onSidebarVisibleWorktreesChanged: {},
            onShowNotificationsForWorktree: { _ in },
            unreadCount: { _ in 0 }
        )

        view.focusPane(paneId)

        #expect(dispatcher.command == .focusPane)
        #expect(dispatcher.target == paneId)
        #expect(dispatcher.targetType == .pane)
    }

    @Test("Bridge attendance snapshot is read once and deterministically populates pane candidates")
    func bridgeAttendanceReadsOnlyDeclaredPaneKeys() throws {
        // Arrange
        let store = WorkspaceStore(startsObserving: false)
        let firstPane = store.createPane()
        let secondPane = store.createPane()
        let worktreeId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let snapshotRecorder = BridgeAttendanceSnapshotReadRecorder(
            ordinalByPaneId: [
                firstPane.id: 7,
                secondPane.id: 19,
            ]
        )
        let view = RepoExplorerView(
            store: store,
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
            bridgeAttendanceSnapshot: snapshotRecorder.readOrdinal,
            commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
            onSetSortOrder: { _ in },
            onRefocusActivePane: {},
            onSidebarVisibleWorktreesChanged: {},
            onShowNotificationsForWorktree: { _ in },
            unreadCount: { _ in 0 }
        )
        let paneLocationsByWorktreeId = [
            worktreeId: [
                WorkspacePaneLocation(
                    paneId: firstPane.id,
                    tabId: tabId,
                    tabIndex: 0,
                    paneIndexInTab: 0,
                    isActiveInTab: true
                ),
                WorkspacePaneLocation(
                    paneId: secondPane.id,
                    tabId: tabId,
                    tabIndex: 0,
                    paneIndexInTab: 1,
                    isActiveInTab: false
                ),
            ]
        ]

        // Act
        let candidatesByWorktreeId = view.bridgePaneCommandCandidatesByWorktreeId(
            paneLocationsByWorktreeId: paneLocationsByWorktreeId
        )

        // Assert
        let candidates = try #require(candidatesByWorktreeId[worktreeId])
        #expect(snapshotRecorder.readCount == 2)
        #expect(candidates.map(\.paneId) == [firstPane.id, secondPane.id])
        #expect(candidates.map(\.attendanceOrdinal) == [7, 19])
    }

    @Test("sidebar snapshot observation ignores pane titles and invalidates for residency")
    func sidebarSnapshotObservationIsTitleInsensitive() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-observation"))
            let worktree = try #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "Initial title",
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let invalidationRecorder = RepoProjectionInvalidationRecorder()
            withObservationTracking {
                _ = view.makeSidebarSnapshot(
                    repos: store.repositoryTopologyAtom.repos.map(RepoPresentationItem.init(repo:)),
                    repoEnrichmentByRepoId: [:],
                    groupingMode: .repo,
                    sortOrder: .ascending,
                    query: ""
                )
            } onChange: {
                invalidationRecorder.record()
            }

            store.paneAtom.updatePaneTitle(pane.id, title: "Updated title")

            #expect(invalidationRecorder.invalidationCount == 0)

            store.paneAtom.setResidency(.backgrounded, for: pane.id)

            #expect(invalidationRecorder.invalidationCount == 1)
        }
    }

    @Test("sidebar projection capture ignores unrelated topology metadata and observes rendered metadata")
    func sidebarProjectionCaptureIgnoresUnrelatedTopologyMetadataMutation() throws {
        try withTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let renderedRepo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-rendered"))
            let renderedWorktree = try #require(renderedRepo.worktrees.first)
            let unrelatedRepo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-unrelated"))
            let pane = store.createPane(
                launchDirectory: renderedWorktree.path,
                facets: PaneContextFacets(cwd: renderedWorktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            let view = RepoExplorerView(
                store: store,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
                bridgeAttendanceSnapshot: { _ in nil },
                commandDispatcher: FakeRepoExplorerAppCommandDispatcher(),
                onSetSortOrder: { _ in },
                onRefocusActivePane: {},
                onSidebarVisibleWorktreesChanged: {},
                onShowNotificationsForWorktree: { _ in },
                unreadCount: { _ in 0 }
            )
            let renderedRepos = [RepoPresentationItem(repo: renderedRepo)]
            let invalidationRecorder = RepoProjectionInvalidationRecorder()

            withObservationTracking {
                _ = view.makeSidebarSnapshot(
                    repos: renderedRepos,
                    repoEnrichmentByRepoId: [:],
                    groupingMode: .repo,
                    sortOrder: .ascending,
                    query: ""
                )
            } onChange: {
                invalidationRecorder.record()
            }

            store.mutationCoordinator.setRepoFavorite(unrelatedRepo.id, isFavorite: true)

            #expect(invalidationRecorder.invalidationCount == 0)

            store.mutationCoordinator.setRepoFavorite(renderedRepo.id, isFavorite: true)

            #expect(invalidationRecorder.invalidationCount == 1)
        }
    }

    @Test("source group icon uses same checkout color contract as worktree rows")
    func sourceGroupIconUsesCheckoutColorContract() {
        let repoId = UUIDv7.generate()
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [
                Worktree(
                    repoId: repoId,
                    name: "notification-inbox-redesign",
                    path: URL(fileURLWithPath: "/tmp/agent-studio.notification-inbox-redesign")
                )
            ]
        )
        let group = RepoPresentationGroup(
            id: "remote:ShravanSunder/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "ShravanSunder",
            repos: [repo]
        )

        let icon = RepoExplorerView.sourceGroupIcon(for: group)

        let expectedColorHex = RepoPresentationColoring.checkoutColorHex(
            for: repo,
            in: group
        )

        if case .coloredRepo(let colorHex) = icon {
            #expect(colorHex == expectedColorHex)
        } else {
            Issue.record("Expected RepoExplorer group header to use colored repo source icon")
        }
    }

    @Test("source group icon uses repo semantics for All Panes and tab semantics for By Tab")
    func sourceGroupIconUsesPerspectiveHeaderSemantics() {
        let group = RepoPresentationGroup(
            id: "pane:active",
            repoTitle: "Pane 1",
            organizationName: nil,
            repos: []
        )

        #expect(RepoExplorerView.sourceGroupIcon(for: group, groupingMode: .pane) == .repo)
        #expect(RepoExplorerView.sourceGroupIcon(for: group, groupingMode: .tab) == .tabGroup)
    }

    @Test("group icon mode is taken from the applied projection snapshot")
    func groupIconModeIsTakenFromAppliedProjectionSnapshot() {
        let group = RepoPresentationGroup(
            id: "pane:active",
            repoTitle: "Pane 1",
            organizationName: nil,
            repos: []
        )

        #expect(RepoExplorerView.groupIcon(for: group, projectionGroupingMode: .pane) == .repo)
        #expect(RepoExplorerView.groupIcon(for: group, projectionGroupingMode: .tab) == .tabGroup)
    }

    @Test("sort order changes have their own projection trigger")
    func sortOrderChangesHaveTheirOwnProjectionTrigger() {
        let repoId = UUIDv7.generate()
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [
                Worktree(
                    repoId: repoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/agent-studio")
                )
            ]
        )
        let previous = RepoExplorerProjectionRequest(
            generation: 1,
            snapshot: RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: [:],
                sortOrder: .ascending,
                query: ""
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic
        )
        let next = RepoExplorerProjectionRequest(
            generation: 2,
            snapshot: RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: [:],
                sortOrder: .descending,
                query: ""
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic
        )

        #expect(RepoExplorerView.sidebarProjectionTrigger(previous: previous, next: next) == .sortOrder)
    }

    @Test("query changes have their own search projection trigger")
    func queryChangesHaveTheirOwnSearchProjectionTrigger() {
        let previous = RepoExplorerProjectionRequest(
            generation: 1,
            snapshot: RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                query: ""
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .startupDiagnostic
        )
        let next = RepoExplorerProjectionRequest(
            generation: 2,
            snapshot: RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                query: "agent-studio"
            ),
            collapsedGroupIds: [],
            isFiltering: true,
            trigger: .startupDiagnostic
        )

        #expect(RepoExplorerView.sidebarProjectionTrigger(previous: previous, next: next) == .search)
    }

    @Test("branchStatus maps sync and line diff values from snapshot summary")
    func branchStatusMapsSnapshotSyncAndLineDiff() {
        let worktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUIDv7.generate().uuidString)"),
                summary: GitWorkingTreeSummary(
                    changed: 2,
                    staged: 1,
                    untracked: 0,
                    linesAdded: 12,
                    linesDeleted: 3,
                    aheadCount: 1,
                    behindCount: 0,
                    hasUpstream: true
                ),
                branch: "main"
            )
        )

        let status = RepoExplorerView.branchStatus(
            enrichment: enrichment,
            pullRequestFacts: PullRequestFacts(openCount: 1, exactOpenURL: nil)
        )

        #expect(status.isDirty)
        #expect(status.linesAdded == 12)
        #expect(status.linesDeleted == 3)
        #expect(status.syncState == .ahead(1))
        #expect(status.prCount == 1)
    }

    @Test("branchStatus keeps unknown local state when snapshot missing")
    func branchStatusFallsBackToUnknownWithoutLocalSnapshot() {
        let status = RepoExplorerView.branchStatus(
            enrichment: nil,
            pullRequestFacts: PullRequestFacts(openCount: 7, exactOpenURL: nil)
        )

        #expect(status.isDirty == GitBranchStatus.unknown.isDirty)
        #expect(status.syncState == GitBranchStatus.unknown.syncState)
        #expect(status.prCount == 7)
    }

    @Test("mergeBranchStatuses shares repository branch facts across worktrees")
    func mergeBranchStatusesSharesRepositoryBranchFacts() {
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let branch = "feature/shared"

        let merged = RepoExplorerView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [
                firstWorktreeId: WorktreeEnrichment(
                    worktreeId: firstWorktreeId,
                    repoId: repoId,
                    branch: branch,
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: firstWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUIDv7.generate().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 0, staged: 1, untracked: 0),
                        branch: branch
                    )
                ),
                secondWorktreeId: WorktreeEnrichment(
                    worktreeId: secondWorktreeId,
                    repoId: repoId,
                    branch: branch
                ),
            ],
            pullRequestFactsByBranch: [
                RepoBranchKey(repoId: repoId, branch: branch)!:
                    PullRequestFacts(openCount: 2, exactOpenURL: nil)
            ]
        )

        #expect(merged[firstWorktreeId]?.isDirty == true)
        #expect(merged[firstWorktreeId]?.prCount == 2)
        #expect(merged[secondWorktreeId]?.prCount == 2)
        #expect(merged[secondWorktreeId]?.syncState == .unknown)
    }

    @Test("sidebar branch status derives from worktree enrichment snapshots")
    func sidebarBranchStatusDerivesFromWorktreeEnrichmentSnapshots() {
        let worktreeId = UUIDv7.generate()
        let repoId = UUIDv7.generate()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "feature/sidebar-pipeline",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUIDv7.generate().uuidString)"),
                summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                branch: "feature/sidebar-pipeline"
            )
        )

        let merged = RepoExplorerView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [worktreeId: enrichment],
            pullRequestFactsByBranch: [
                RepoBranchKey(repoId: repoId, branch: enrichment.branch)!:
                    PullRequestFacts(openCount: 5, exactOpenURL: nil)
            ]
        )

        #expect(merged[worktreeId]?.isDirty == true)
        #expect(merged[worktreeId]?.prCount == 5)
        #expect(merged[worktreeId]?.syncState == .unknown)
    }
}
