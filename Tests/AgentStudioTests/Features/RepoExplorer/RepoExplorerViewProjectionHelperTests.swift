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

    func readSnapshot() -> [UUID: UInt64] {
        readCount += 1
        return ordinalByPaneId
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

@MainActor
@Suite("RepoExplorerViewProjectionHelperTests")
struct RepoExplorerViewProjectionHelperTests {
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

    @Test("pane navigation dispatches exact focusPane target")
    func paneNavigationDispatchesExactFocusTarget() {
        let dispatcher = PaneFocusRecordingDispatcher()
        let paneId = UUIDv7.generate()
        let view = RepoExplorerView(
            store: WorkspaceStore(startsObserving: false),
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            repoExplorerPrefs: RepoExplorerSidebarPrefsAtom(),
            bridgeAttendanceSnapshot: { [:] },
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
    func bridgeAttendanceSnapshotIsReadOncePerProjection() throws {
        // Arrange
        let store = WorkspaceStore(startsObserving: false)
        let firstPane = store.createPane()
        let secondPane = store.createPane()
        let worktreeId = UUID()
        let tabId = UUID()
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
            bridgeAttendanceSnapshot: snapshotRecorder.readSnapshot,
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
        #expect(snapshotRecorder.readCount == 1)
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
                bridgeAttendanceSnapshot: { [:] },
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

    @Test("source group icon uses same checkout color contract as worktree rows")
    func sourceGroupIconUsesCheckoutColorContract() {
        let repoId = UUID()
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

    @Test("source group icon uses repo semantics for By Pane and tab semantics for By Tab")
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
        let repoId = UUID()
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
        let worktreeId = UUID()
        let repoId = UUID()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "main",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
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
            pullRequestCount: 1
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
            pullRequestCount: 7
        )

        #expect(status.isDirty == GitBranchStatus.unknown.isDirty)
        #expect(status.syncState == GitBranchStatus.unknown.syncState)
        #expect(status.prCount == 7)
    }

    @Test("mergeBranchStatuses merges local snapshots with independent PR counts")
    func mergeBranchStatusesMergesSources() {
        let localOnlyWorktreeId = UUID()
        let prOnlyWorktreeId = UUID()
        let repoId = UUID()

        let merged = RepoExplorerView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [
                localOnlyWorktreeId: WorktreeEnrichment(
                    worktreeId: localOnlyWorktreeId,
                    repoId: repoId,
                    branch: "",
                    snapshot: GitWorkingTreeSnapshot(
                        worktreeId: localOnlyWorktreeId,
                        rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                        summary: GitWorkingTreeSummary(changed: 0, staged: 1, untracked: 0),
                        branch: nil
                    )
                )
            ],
            pullRequestCountsByWorktreeId: [prOnlyWorktreeId: 2]
        )

        #expect(merged[localOnlyWorktreeId]?.isDirty == true)
        #expect(merged[localOnlyWorktreeId]?.prCount == nil)
        #expect(merged[prOnlyWorktreeId]?.prCount == 2)
        #expect(merged[prOnlyWorktreeId]?.syncState == .unknown)
    }

    @Test("sidebar branch status derives from worktree enrichment snapshots")
    func sidebarBranchStatusDerivesFromWorktreeEnrichmentSnapshots() {
        let worktreeId = UUID()
        let repoId = UUID()
        let enrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "feature/sidebar-pipeline",
            snapshot: GitWorkingTreeSnapshot(
                worktreeId: worktreeId,
                rootPath: URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)"),
                summary: GitWorkingTreeSummary(changed: 2, staged: 1, untracked: 0),
                branch: "feature/sidebar-pipeline"
            )
        )

        let merged = RepoExplorerView.mergeBranchStatuses(
            worktreeEnrichmentsByWorktreeId: [worktreeId: enrichment],
            pullRequestCountsByWorktreeId: [worktreeId: 5]
        )

        #expect(merged[worktreeId]?.isDirty == true)
        #expect(merged[worktreeId]?.prCount == 5)
        #expect(merged[worktreeId]?.syncState == .unknown)
    }
}
