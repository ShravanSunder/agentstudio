import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

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

    @Test("null local cursor rows restore as absent cursor memory")
    func nullLocalCursorRowsRestoreAsAbsentCursorMemory() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000101")!
        let fixture = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId)
        let tabId = UUID(uuidString: "10000000-0000-0000-0000-000000000111")!
        let arrangementId = UUID(uuidString: "10000000-0000-0000-0000-000000000121")!
        let drawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000141")!
        try fixture.databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_workspace_cursor(workspace_id, active_tab_id, updated_at)
                    VALUES (?, NULL, ?)
                    """,
                arguments: [workspaceId.uuidString, 100.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_tab_cursor(tab_id, workspace_id, active_arrangement_id, updated_at)
                    VALUES (?, ?, NULL, ?)
                    """,
                arguments: [tabId.uuidString, workspaceId.uuidString, 100.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_arrangement_cursor(arrangement_id, workspace_id, active_pane_id, updated_at)
                    VALUES (?, ?, NULL, ?)
                    """,
                arguments: [arrangementId.uuidString, workspaceId.uuidString, 100.0]
            )
            try database.execute(
                sql: """
                    INSERT INTO local_arrangement_drawer_cursor(
                        arrangement_id, drawer_id, workspace_id, active_child_id, updated_at
                    )
                    VALUES (?, ?, ?, NULL, ?)
                    """,
                arguments: [arrangementId.uuidString, drawerId.uuidString, workspaceId.uuidString, 100.0]
            )
        }

        let restoredState = try fixture.repository.fetchCursorState()

        #expect(restoredState.activeTabId == nil)
        #expect(restoredState.activeArrangementIdsByTabId.isEmpty)
        #expect(restoredState.activePaneIdsByArrangementId.isEmpty)
        #expect(restoredState.activeChildIdsByArrangementDrawer.isEmpty)
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
            collapsedGroups: [SidebarGroupKey("repo:agent-studio")]
        )

        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: memoryState,
            updatedAt: Date(timeIntervalSince1970: 400)
        )
        let restoredState = try readWorkspaceMemoryLanes(repository)

        #expect(restoredState == memoryState)
    }

    @Test("window state replacement preserves sidebar groups")
    func windowStateReplacementPreservesSidebarGroups() throws {
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
            collapsedGroups: [SidebarGroupKey("repo:agent-studio")]
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
        #expect(restoredState.collapsedGroups == initialMemoryState.collapsedGroups)
    }

    @Test("sidebar state replacement preserves window and groups")
    func sidebarStateReplacementPreservesWindowAndGroups() throws {
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
            collapsedGroups: [SidebarGroupKey("repo:old")]
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
        #expect(restoredState.collapsedGroups == initialMemoryState.collapsedGroups)
    }

    @Test("collapsed groups replacement preserves window and sidebar")
    func collapsedGroupsReplacementPreservesWindowAndSidebar() throws {
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
            collapsedGroups: [SidebarGroupKey("repo:old")]
        )
        let replacementCollapsedGroups: Set<SidebarGroupKey> = [
            SidebarGroupKey("repo:new"),
            SidebarGroupKey("worktree:new"),
        ]

        try seedWorkspaceMemoryLanes(
            repository,
            memoryState: initialMemoryState,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try repository.replaceCollapsedGroups(
            replacementCollapsedGroups,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let restoredState = try readWorkspaceMemoryLanes(repository)

        #expect(restoredState.windowState == initialMemoryState.windowState)
        #expect(restoredState.sidebarState == initialMemoryState.sidebarState)
        #expect(restoredState.collapsedGroups == replacementCollapsedGroups)
    }

    @Test("empty row sets remain empty without marker rows")
    func emptyRowSetsRemainEmptyWithoutMarkerRows() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000207")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository

        #expect(try repository.hasCollapsedGroupsState() == false)

        try repository.replaceCollapsedGroups([], updatedAt: Date(timeIntervalSince1970: 100))

        #expect(try repository.fetchCollapsedGroups().isEmpty)
        #expect(try repository.hasCollapsedGroupsState())
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
            repoId: repoId,
            worktreeId: worktreeId
        )
    }

    @Test("reset cache rows preserves local memory")
    func resetCacheRowsPreservesLocalMemory() throws {
        let workspaceId = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
        let repository = try makeWorkspaceLocalRepositoryFixture(workspaceId: workspaceId).repository
        let repoId = UUID(uuidString: "10000000-0000-0000-0000-000000000015")!
        let tabId = UUID(uuidString: "10000000-0000-0000-0000-000000000115")!
        let arrangementId = UUID(uuidString: "10000000-0000-0000-0000-000000000125")!
        let paneId = UUID(uuidString: "10000000-0000-0000-0000-000000000135")!
        let drawerId = UUID(uuidString: "10000000-0000-0000-0000-000000000145")!
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
            collapsedGroups: [SidebarGroupKey("repo:agent-studio")]
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
    try repository.replaceCollapsedGroups(memoryState.collapsedGroups, updatedAt: updatedAt)
}

private func readWorkspaceMemoryLanes(
    _ repository: WorkspaceLocalRepository
) throws -> WorkspaceLocalRepository.WorkspaceMemoryRecord {
    .init(
        windowState: try repository.fetchWindowState(),
        sidebarState: try repository.fetchSidebarState(),
        collapsedGroups: try repository.fetchCollapsedGroups()
    )
}

private func assertCacheQueryColumns(
    databaseQueue: DatabaseQueue,
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
                    pull_request.count AS pull_request_count
                FROM cache_metadata metadata
                JOIN cache_repo_enrichment repo
                    ON repo.repo_id = ?
                JOIN cache_worktree_enrichment worktree
                    ON worktree.worktree_id = ?
                JOIN cache_pull_request_count pull_request
                    ON pull_request.worktree_id = worktree.worktree_id
                WHERE metadata.singleton_id = 1
                """,
            arguments: [repoId.uuidString, worktreeId.uuidString]
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
}
