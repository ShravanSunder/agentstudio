import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalRepositoryTests")
struct WorkspaceLocalRepositoryTests {
    @Test("cursor state round trips through local cursor rows")
    func cursorStateRoundTripsThroughLocalCursorRows() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let tabId = UUID(uuidString: "10000000-0000-0000-0000-000000000011")!
        let arrangementId = UUID(uuidString: "10000000-0000-0000-0000-000000000021")!
        let paneId = UUID(uuidString: "10000000-0000-0000-0000-000000000031")!
        let drawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000041")!
        let childPaneId = UUID(uuidString: "10000000-0000-0000-0000-000000000051")!
        let cursorState = WorkspaceLocalRepository.CursorStateRecord(
            activeTabId: tabId,
            activeArrangementIdsByTabId: [tabId: arrangementId],
            activePaneIdsByArrangementId: [arrangementId: paneId],
            drawerExpansionByDrawerId: [drawerId: true],
            activeChildIdsByArrangementDrawer: [
                .init(arrangementId: arrangementId, drawerId: drawerId): childPaneId
            ]
        )

        try repository.replaceCursorState(
            cursorState: cursorState,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let restoredState = try repository.fetchCursorState()

        #expect(restoredState == cursorState)
    }

    @Test("drawer expansion setter collapses other drawers in one repository write")
    func drawerExpansionSetterCollapsesOtherDrawersInOneRepositoryWrite() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let firstDrawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000042")!
        let secondDrawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000043")!
        try repository.replaceCursorState(
            cursorState: .init(
                activeTabId: nil,
                activeArrangementIdsByTabId: [:],
                activePaneIdsByArrangementId: [:],
                drawerExpansionByDrawerId: [firstDrawerId: true, secondDrawerId: false],
                activeChildIdsByArrangementDrawer: [:]
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try repository.setDrawerExpanded(
            drawerId: secondDrawerId,
            isExpanded: true,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let restoredState = try repository.fetchCursorState()

        #expect(
            restoredState.drawerExpansionByDrawerId == [
                firstDrawerId: false,
                secondDrawerId: true,
            ]
        )
    }

    @Test("collapsing an already collapsed drawer leaves the expanded drawer alone")
    func collapsingAlreadyCollapsedDrawerLeavesExpandedDrawerAlone() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000102")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let expandedDrawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000142")!
        let collapsedDrawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000143")!
        try repository.replaceCursorState(
            cursorState: .init(
                activeTabId: nil,
                activeArrangementIdsByTabId: [:],
                activePaneIdsByArrangementId: [:],
                drawerExpansionByDrawerId: [expandedDrawerId: true, collapsedDrawerId: false],
                activeChildIdsByArrangementDrawer: [:]
            ),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try repository.setDrawerExpanded(
            drawerId: collapsedDrawerId,
            isExpanded: false,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(
            try repository.fetchCursorState().drawerExpansionByDrawerId == [
                expandedDrawerId: true,
                collapsedDrawerId: false,
            ]
        )
    }

    @Test("workspace memory round trips through local memory rows")
    func workspaceMemoryRoundTripsThroughLocalMemoryRows() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let repoId = UUID(uuidString: "10000000-0000-0000-0000-000000000013")!
        let worktreeId = UUID(uuidString: "10000000-0000-0000-0000-000000000023")!
        let cwdTarget = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/agent-studio"),
            title: "agent-studio",
            subtitle: "cwd",
            lastOpenedAt: Date(timeIntervalSince1970: 300)
        )
        let worktreeTarget = RecentWorkspaceTarget.forWorktree(
            path: URL(fileURLWithPath: "/tmp/agent-studio/sqlite"),
            worktree: .init(
                id: worktreeId,
                repoId: repoId,
                name: "sqlite",
                path: URL(fileURLWithPath: "/tmp/agent-studio/sqlite")
            ),
            repo: .init(
                id: repoId,
                name: "agent-studio",
                repoPath: URL(fileURLWithPath: "/tmp/agent-studio")
            ),
            lastOpenedAt: Date(timeIntervalSince1970: 301)
        )
        let memoryState = WorkspaceLocalRepository.WorkspaceMemoryRecord(
            windowState: .init(
                sidebarWidth: 312.5,
                windowFrame: CGRect(x: 10, y: 20, width: 900, height: 700)
            ),
            sidebarState: .init(
                filterText: "sqlite",
                isFilterVisible: true,
                sidebarCollapsed: true,
                sidebarSurface: .inbox
            ),
            expandedGroups: [SidebarGroupKey("repo:agent-studio")],
            recentTargets: [worktreeTarget, cwdTarget]
        )

        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: memoryState,
            updatedAt: Date(timeIntervalSince1970: 400)
        )
        let restoredState = try readWorkspaceMemoryLanes(repository)

        #expect(restoredState == memoryState)
    }

    @Test("window state replacement preserves sidebar groups and recent targets")
    func windowStateReplacementPreservesSidebarGroupsAndRecentTargets() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000203")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let initialMemoryState = WorkspaceLocalRepository.WorkspaceMemoryRecord(
            windowState: .init(sidebarWidth: 280, windowFrame: nil),
            sidebarState: .init(
                filterText: "repo",
                isFilterVisible: true,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            ),
            expandedGroups: [SidebarGroupKey("repo:agent-studio")],
            recentTargets: [
                RecentWorkspaceTarget.forCwd(
                    URL(fileURLWithPath: "/tmp/agent-studio"),
                    lastOpenedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let replacementWindowState = WorkspaceLocalRepository.WindowStateRecord(
            sidebarWidth: 420,
            windowFrame: CGRect(x: 20, y: 30, width: 1000, height: 800)
        )

        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: initialMemoryState,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try repository.replaceWindowState(
            replacementWindowState,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let restoredState = try readWorkspaceMemoryLanes(repository)

        #expect(restoredState.windowState == replacementWindowState)
        #expect(restoredState.sidebarState == initialMemoryState.sidebarState)
        #expect(restoredState.expandedGroups == initialMemoryState.expandedGroups)
        #expect(restoredState.recentTargets == initialMemoryState.recentTargets)
    }

    @Test("sidebar state replacement preserves window groups and recent targets")
    func sidebarStateReplacementPreservesWindowGroupsAndRecentTargets() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000204")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let initialMemoryState = WorkspaceLocalRepository.WorkspaceMemoryRecord(
            windowState: .init(
                sidebarWidth: 300,
                windowFrame: CGRect(x: 1, y: 2, width: 700, height: 500)
            ),
            sidebarState: .init(
                filterText: "old",
                isFilterVisible: false,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            ),
            expandedGroups: [SidebarGroupKey("repo:old")],
            recentTargets: [
                RecentWorkspaceTarget.forCwd(
                    URL(fileURLWithPath: "/tmp/old"),
                    lastOpenedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let replacementSidebarState = WorkspaceLocalRepository.SidebarStateRecord(
            filterText: "new",
            isFilterVisible: true,
            sidebarCollapsed: true,
            sidebarSurface: .inbox
        )

        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: initialMemoryState,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try repository.replaceSidebarState(
            replacementSidebarState,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let restoredState = try readWorkspaceMemoryLanes(repository)

        #expect(restoredState.windowState == initialMemoryState.windowState)
        #expect(restoredState.sidebarState == replacementSidebarState)
        #expect(restoredState.expandedGroups == initialMemoryState.expandedGroups)
        #expect(restoredState.recentTargets == initialMemoryState.recentTargets)
    }

    @Test("expanded groups replacement preserves window sidebar and recent targets")
    func expandedGroupsReplacementPreservesWindowSidebarAndRecentTargets() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000205")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let initialMemoryState = WorkspaceLocalRepository.WorkspaceMemoryRecord(
            windowState: .init(sidebarWidth: 300, windowFrame: nil),
            sidebarState: .init(
                filterText: "repo",
                isFilterVisible: true,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            ),
            expandedGroups: [SidebarGroupKey("repo:old")],
            recentTargets: [
                RecentWorkspaceTarget.forCwd(
                    URL(fileURLWithPath: "/tmp/recent"),
                    lastOpenedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let replacementExpandedGroups: Set<SidebarGroupKey> = [
            SidebarGroupKey("repo:new"),
            SidebarGroupKey("worktree:new"),
        ]

        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: initialMemoryState,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try repository.replaceExpandedGroups(
            replacementExpandedGroups,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let restoredState = try readWorkspaceMemoryLanes(repository)

        #expect(restoredState.windowState == initialMemoryState.windowState)
        #expect(restoredState.sidebarState == initialMemoryState.sidebarState)
        #expect(restoredState.expandedGroups == replacementExpandedGroups)
        #expect(restoredState.recentTargets == initialMemoryState.recentTargets)
    }

    @Test("recent targets replacement preserves window sidebar and expanded groups")
    func recentTargetsReplacementPreservesWindowSidebarAndExpandedGroups() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000206")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let initialMemoryState = WorkspaceLocalRepository.WorkspaceMemoryRecord(
            windowState: .init(sidebarWidth: 300, windowFrame: nil),
            sidebarState: .init(
                filterText: "repo",
                isFilterVisible: true,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            ),
            expandedGroups: [SidebarGroupKey("repo:agent-studio")],
            recentTargets: [
                RecentWorkspaceTarget.forCwd(
                    URL(fileURLWithPath: "/tmp/old"),
                    lastOpenedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        let replacementTargets = [
            RecentWorkspaceTarget.forCwd(
                URL(fileURLWithPath: "/tmp/new"),
                lastOpenedAt: Date(timeIntervalSince1970: 200)
            )
        ]

        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: initialMemoryState,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try repository.replaceRecentTargets(
            replacementTargets,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let restoredState = try readWorkspaceMemoryLanes(repository)

        #expect(restoredState.windowState == initialMemoryState.windowState)
        #expect(restoredState.sidebarState == initialMemoryState.sidebarState)
        #expect(restoredState.expandedGroups == initialMemoryState.expandedGroups)
        #expect(restoredState.recentTargets == replacementTargets)
    }

    @Test("empty local memory lanes are still marked initialized")
    func emptyLocalMemoryLanesAreStillMarkedInitialized() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000207")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository

        #expect(try repository.hasExpandedGroupsState() == false)
        #expect(try repository.hasRecentTargetsState() == false)

        try repository.replaceExpandedGroups([], updatedAt: Date(timeIntervalSince1970: 100))
        try repository.replaceRecentTargets([], updatedAt: Date(timeIntervalSince1970: 100))

        #expect(try repository.fetchExpandedGroups().isEmpty)
        #expect(try repository.fetchRecentTargets().isEmpty)
        #expect(try repository.hasExpandedGroupsState())
        #expect(try repository.hasRecentTargetsState())
    }

    @Test("cache state round trips through cache rows")
    func cacheStateRoundTripsThroughCacheRows() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let fixture = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId)
        let repository = fixture.repository
        let repoId = UUID(uuidString: "10000000-0000-0000-0000-000000000014")!
        let worktreeId = UUID(uuidString: "10000000-0000-0000-0000-000000000024")!
        let repoEnrichment = RepoEnrichment.resolvedRemote(
            repoId: repoId,
            raw: .init(origin: "git@github.com:ShravanSunder/agentstudio.git", upstream: nil),
            identity: .init(
                groupKey: "github.com/ShravanSunder",
                remoteSlug: "agentstudio",
                organizationName: "ShravanSunder",
                displayName: "agentstudio"
            ),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        let worktreeEnrichment = WorktreeEnrichment(
            worktreeId: worktreeId,
            repoId: repoId,
            branch: "sqlite",
            isMainWorktree: false,
            updatedAt: Date(timeIntervalSince1970: 600)
        )
        let cacheState = WorkspaceLocalRepository.CacheStateRecord(
            repoEnrichmentByRepoId: [repoId: repoEnrichment],
            worktreeEnrichmentByWorktreeId: [worktreeId: worktreeEnrichment],
            pullRequestCountByWorktreeId: [worktreeId: 7],
            notificationCountByWorktreeId: [worktreeId: 3],
            sourceRevision: 42,
            lastRebuiltAt: Date(timeIntervalSince1970: 700)
        )

        try repository.replaceCacheState(
            cacheState: cacheState,
            updatedAt: Date(timeIntervalSince1970: 800)
        )
        let restoredState = try repository.fetchCacheState()

        #expect(restoredState == cacheState)
        try assertCacheQueryColumns(
            databaseQueue: fixture.databaseQueue,
            workspaceId: workspaceId,
            repoId: repoId,
            worktreeId: worktreeId
        )
    }

    @Test("reset cache rows preserves local memory and recent targets")
    func resetCacheRowsPreservesLocalMemoryAndRecentTargets() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let repoId = UUID(uuidString: "10000000-0000-0000-0000-000000000015")!
        let tabId = UUID(uuidString: "10000000-0000-0000-0000-000000000115")!
        let arrangementId = UUID(uuidString: "10000000-0000-0000-0000-000000000125")!
        let paneId = UUID(uuidString: "10000000-0000-0000-0000-000000000135")!
        let drawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000145")!
        let target = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/agent-studio"),
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        let cursorState = WorkspaceLocalRepository.CursorStateRecord(
            activeTabId: tabId,
            activeArrangementIdsByTabId: [tabId: arrangementId],
            activePaneIdsByArrangementId: [arrangementId: paneId],
            drawerExpansionByDrawerId: [drawerId: true],
            activeChildIdsByArrangementDrawer: [
                .init(arrangementId: arrangementId, drawerId: drawerId): paneId
            ]
        )
        let memoryState = WorkspaceLocalRepository.WorkspaceMemoryRecord(
            windowState: .init(sidebarWidth: 280, windowFrame: nil),
            sidebarState: .init(
                filterText: "repo",
                isFilterVisible: true,
                sidebarCollapsed: false,
                sidebarSurface: .repos
            ),
            expandedGroups: [SidebarGroupKey("repo:agent-studio")],
            recentTargets: [target]
        )
        try repository.replaceCursorState(
            cursorState: cursorState,
            updatedAt: Date(timeIntervalSince1970: 90)
        )
        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: memoryState,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try repository.replaceCacheState(
            cacheState: .init(
                repoEnrichmentByRepoId: [repoId: .awaitingOrigin(repoId: repoId)],
                worktreeEnrichmentByWorktreeId: [:],
                pullRequestCountByWorktreeId: [:],
                notificationCountByWorktreeId: [:],
                sourceRevision: 3,
                lastRebuiltAt: Date(timeIntervalSince1970: 200)
            ),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        try repository.resetCacheRows()

        #expect(try repository.fetchCacheState() == .empty)
        #expect(try readWorkspaceMemoryLanes(repository) == memoryState)
        #expect(try repository.fetchCursorState() == cursorState)
    }
}

private func makeWorkspaceLocalRepositoryFixture(workspaceId: UUID) throws -> WorkspaceLocalRepositoryFixture {
    let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    return .init(
        repository: WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: databaseQueue),
        databaseQueue: databaseQueue
    )
}

private struct WorkspaceLocalRepositoryFixture {
    let repository: WorkspaceLocalRepository
    let databaseQueue: DatabaseQueue
}

private func seedWorkspaceMemoryLanes(
    _ repository: WorkspaceLocalRepository,
    memoryState: WorkspaceLocalRepository.WorkspaceMemoryRecord,
    updatedAt: Date
) throws {
    try repository.replaceWindowState(memoryState.windowState, updatedAt: updatedAt)
    try repository.replaceSidebarState(memoryState.sidebarState, updatedAt: updatedAt)
    try repository.replaceExpandedGroups(memoryState.expandedGroups, updatedAt: updatedAt)
    try repository.replaceRecentTargets(memoryState.recentTargets, updatedAt: updatedAt)
}

private func readWorkspaceMemoryLanes(
    _ repository: WorkspaceLocalRepository
) throws -> WorkspaceLocalRepository.WorkspaceMemoryRecord {
    .init(
        windowState: try repository.fetchWindowState(),
        sidebarState: try repository.fetchSidebarState(),
        expandedGroups: try repository.fetchExpandedGroups(),
        recentTargets: try repository.fetchRecentTargets()
    )
}

private func assertCacheQueryColumns(
    databaseQueue: DatabaseQueue,
    workspaceId: UUID,
    repoId: UUID,
    worktreeId: UUID
) throws {
    let row = try databaseQueue.read { database in
        let fetchedRow = try Row.fetchOne(
            database,
            sql: """
                SELECT
                    metadata.source_revision,
                    metadata.last_rebuilt_at,
                    repo.state,
                    repo.origin,
                    repo.remote_slug,
                    repo.organization_name,
                    repo.display_name,
                    worktree.branch,
                    worktree.is_main_worktree,
                    pull_request.repo_id AS pull_request_repo_id,
                    pull_request.count AS pull_request_count,
                    notification.repo_id AS notification_repo_id,
                    notification.count AS notification_count
                FROM cache_metadata metadata
                JOIN cache_repo_enrichment repo
                    ON repo.workspace_id = metadata.workspace_id
                    AND repo.repo_id = ?
                JOIN cache_worktree_enrichment worktree
                    ON worktree.workspace_id = metadata.workspace_id
                    AND worktree.worktree_id = ?
                JOIN cache_pull_request_count pull_request
                    ON pull_request.workspace_id = metadata.workspace_id
                    AND pull_request.worktree_id = worktree.worktree_id
                JOIN cache_notification_count notification
                    ON notification.workspace_id = metadata.workspace_id
                    AND notification.worktree_id = worktree.worktree_id
                WHERE metadata.workspace_id = ?
                """,
            arguments: [repoId.uuidString, worktreeId.uuidString, workspaceId.uuidString]
        )
        return try #require(fetchedRow)
    }
    let sourceRevision: Int64 = row["source_revision"]
    let lastRebuiltAt: Double = row["last_rebuilt_at"]
    let state: String = row["state"]
    let origin: String = row["origin"]
    let remoteSlug: String = row["remote_slug"]
    let organizationName: String = row["organization_name"]
    let displayName: String = row["display_name"]
    let branch: String = row["branch"]
    let isMainWorktree: Int = row["is_main_worktree"]
    let pullRequestRepoId: String = row["pull_request_repo_id"]
    let pullRequestCount: Int = row["pull_request_count"]
    let notificationRepoId: String = row["notification_repo_id"]
    let notificationCount: Int = row["notification_count"]

    #expect(sourceRevision == 42)
    #expect(lastRebuiltAt == 700)
    #expect(state == "resolvedRemote")
    #expect(origin == "git@github.com:ShravanSunder/agentstudio.git")
    #expect(remoteSlug == "agentstudio")
    #expect(organizationName == "ShravanSunder")
    #expect(displayName == "agentstudio")
    #expect(branch == "sqlite")
    #expect(isMainWorktree == 0)
    #expect(pullRequestRepoId == repoId.uuidString)
    #expect(pullRequestCount == 7)
    #expect(notificationRepoId == repoId.uuidString)
    #expect(notificationCount == 3)
}
