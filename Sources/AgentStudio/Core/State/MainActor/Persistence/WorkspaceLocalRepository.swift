import CoreGraphics
import Foundation
import GRDB

package struct WorkspaceLocalRepository: Sendable {
    struct ArrangementDrawerCursorKey: Hashable, Equatable, Sendable {
        let arrangementId: UUID
        let drawerId: UUID
    }

    struct CursorStateRecord: Equatable, Sendable {
        var activeTabId: UUID?
        var activeArrangementIdsByTabId: [UUID: UUID]
        var activePaneIdsByArrangementId: [UUID: UUID]
        var drawerExpansionByDrawerId: [UUID: Bool]
        var activeChildIdsByArrangementDrawer: [ArrangementDrawerCursorKey: UUID]
    }

    struct WindowStateRecord: Equatable, Sendable {
        var sidebarWidth: Double
        var windowFrame: CGRect?
    }

    struct SidebarStateRecord: Equatable, Sendable {
        var filterText: String
        var isFilterVisible: Bool
        var sidebarCollapsed: Bool
        var sidebarSurface: SidebarSurface
    }

    struct WorkspaceMemoryRecord: Equatable, Sendable {
        var windowState: WindowStateRecord?
        var sidebarState: SidebarStateRecord?
        var collapsedGroups: Set<SidebarGroupKey>
    }

    struct CacheStateRecord: Equatable, Sendable {
        var repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        var sourceRevision: UInt64
        var lastRebuiltAt: Date?

        static let empty = Self(
            repoEnrichmentByRepoId: [:],
            worktreeEnrichmentByWorktreeId: [:],
            sourceRevision: 0,
            lastRebuiltAt: nil
        )
    }

    package struct EditorPreferencesRecord: Equatable, Sendable {
        package private(set) var bookmarkedEditorId: String?

        package static let `default` = Self(bookmarkedEditorId: nil)

        package init(bookmarkedEditorId: String?) {
            self.bookmarkedEditorId = bookmarkedEditorId
        }
    }

    package struct RepoExplorerPreferencesRecord: Equatable, Sendable {
        package let groupingMode: String
        package let sortOrder: String
        package let visibilityMode: String

        private init(
            groupingMode: String,
            sortOrder: String,
            visibilityMode _: String
        ) {
            self.groupingMode = groupingMode
            self.sortOrder = sortOrder
            self.visibilityMode = SQLiteLocalUXStorage.repoExplorerVisibilityAll
        }

        package static let `default` = Self(
            groupingMode: SQLiteLocalUXStorage.repoExplorerGroupingRepo,
            sortOrder: SQLiteLocalUXStorage.repoExplorerSortAscending,
            visibilityMode: SQLiteLocalUXStorage.repoExplorerVisibilityAll
        )

        package static func validated(
            groupingMode: String,
            sortOrder: String,
            visibilityMode: String
        ) -> Self? {
            guard SQLiteLocalUXStorage.isValidRepoExplorerGrouping(groupingMode),
                SQLiteLocalUXStorage.isValidRepoExplorerSort(sortOrder)
            else { return nil }
            return Self(
                groupingMode: groupingMode,
                sortOrder: sortOrder,
                visibilityMode: SQLiteLocalUXStorage.repoExplorerVisibilityAll
            )
        }
    }

    package struct InboxNotificationPreferencesRecord: Equatable, Sendable {
        package struct ContentFilterTokens: Equatable, Sendable {
            package let contentMode: String
            package let rowStateFilter: String

            package init(contentMode: String, rowStateFilter: String) {
                self.contentMode = contentMode
                self.rowStateFilter = rowStateFilter
            }
        }

        package let grouping: String
        package let sortOrder: String
        package let bellEnabled: Bool
        package let globalContentMode: String
        package let globalRowStateFilter: String
        package let paneContentMode: String
        package let paneRowStateFilter: String

        private init(
            grouping: String,
            sortOrder: String,
            bellEnabled: Bool,
            globalContentMode: String,
            globalRowStateFilter: String,
            paneContentMode: String,
            paneRowStateFilter: String
        ) {
            self.grouping = grouping
            self.sortOrder = sortOrder
            self.bellEnabled = bellEnabled
            self.globalContentMode = globalContentMode
            self.globalRowStateFilter = globalRowStateFilter
            self.paneContentMode = paneContentMode
            self.paneRowStateFilter = paneRowStateFilter
        }

        package static let `default` = Self(
            grouping: SQLiteLocalUXStorage.inboxNotificationGroupingByTab,
            sortOrder: SQLiteLocalUXStorage.inboxNotificationSortNewestFirst,
            bellEnabled: false,
            globalContentMode: SQLiteLocalUXStorage.inboxNotificationContentRollUpAlerts,
            globalRowStateFilter: SQLiteLocalUXStorage.inboxNotificationRowStateUnreadOnly,
            paneContentMode: SQLiteLocalUXStorage.inboxNotificationContentRollUpAlerts,
            paneRowStateFilter: SQLiteLocalUXStorage.inboxNotificationRowStateUnreadOnly
        )

        package static func validated(
            grouping: String,
            sortOrder: String,
            bellEnabled: Bool,
            globalFilter: ContentFilterTokens,
            paneFilter: ContentFilterTokens
        ) -> Self? {
            guard SQLiteLocalUXStorage.isValidInboxNotificationGrouping(grouping),
                SQLiteLocalUXStorage.isValidInboxNotificationSort(sortOrder),
                SQLiteLocalUXStorage.isValidInboxNotificationContent(globalFilter.contentMode),
                SQLiteLocalUXStorage.isValidInboxNotificationRowState(globalFilter.rowStateFilter),
                SQLiteLocalUXStorage.isValidInboxNotificationContent(paneFilter.contentMode),
                SQLiteLocalUXStorage.isValidInboxNotificationRowState(paneFilter.rowStateFilter)
            else { return nil }
            return Self(
                grouping: grouping,
                sortOrder: sortOrder,
                bellEnabled: bellEnabled,
                globalContentMode: globalFilter.contentMode,
                globalRowStateFilter: globalFilter.rowStateFilter,
                paneContentMode: paneFilter.contentMode,
                paneRowStateFilter: paneFilter.rowStateFilter
            )
        }
    }

    package let workspaceId: UUID
    package let databaseWriter: any DatabaseWriter

    package init(workspaceId: UUID, databaseWriter: any DatabaseWriter) {
        self.workspaceId = workspaceId
        self.databaseWriter = databaseWriter
    }

    func migrate() throws {
        try WorkspaceLocalMigrations.migrate(databaseWriter)
    }

    func replaceCursorState(cursorState: CursorStateRecord, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceCursorRows(
                database,
                workspaceId: workspaceId,
                cursorState: cursorState,
                updatedAt: updatedAt
            )
        }
    }

    func replaceWorkspaceSnapshotLocalState(
        cursorState: CursorStateRecord,
        windowState: WindowStateRecord?,
        completedAt: Date
    ) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceWindowStateRows(
                database,
                workspaceId: workspaceId,
                windowState: windowState,
                updatedAt: completedAt
            )
            try WorkspaceLocalRepositoryStorage.replaceCursorRows(
                database,
                workspaceId: workspaceId,
                cursorState: cursorState,
                updatedAt: completedAt
            )
        }
    }

    func fetchCursorState() throws -> CursorStateRecord {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchCursorRows(database, workspaceId: workspaceId)
        }
    }

    func setDrawerExpanded(
        drawerId: UUID,
        isExpanded: Bool,
        updatedAt: Date
    ) throws {
        try databaseWriter.write { database in
            if isExpanded {
                try database.execute(
                    sql: """
                        UPDATE local_drawer_cursor
                        SET is_expanded = 0, updated_at = ?
                        WHERE workspace_id = ? AND drawer_id != ? AND is_expanded = 1
                        """,
                    arguments: [
                        updatedAt.timeIntervalSince1970,
                        workspaceId.uuidString,
                        drawerId.uuidString,
                    ]
                )
            }
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(workspace_id, drawer_id) DO UPDATE SET
                        is_expanded = excluded.is_expanded,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    drawerId.uuidString,
                    workspaceId.uuidString,
                    isExpanded ? 1 : 0,
                    updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func replaceWindowState(_ windowState: WindowStateRecord?, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceWindowStateRows(
                database,
                workspaceId: workspaceId,
                windowState: windowState,
                updatedAt: updatedAt
            )
        }
    }

    func fetchWindowState() throws -> WindowStateRecord? {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchWindowStateRows(database, workspaceId: workspaceId)
        }
    }

    func replaceSidebarState(_ sidebarState: SidebarStateRecord?, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceSidebarStateRows(
                database,
                workspaceId: workspaceId,
                sidebarState: sidebarState,
                updatedAt: updatedAt
            )
        }
    }

    func fetchSidebarState() throws -> SidebarStateRecord? {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchSidebarStateRows(database, workspaceId: workspaceId)
        }
    }

    func hasSidebarState() throws -> Bool {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.hasSidebarStateRows(database, workspaceId: workspaceId)
        }
    }

    func replaceCollapsedGroups(_ collapsedGroups: Set<SidebarGroupKey>, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceCollapsedGroupRows(
                database,
                workspaceId: workspaceId,
                collapsedGroups: collapsedGroups,
                updatedAt: updatedAt
            )
        }
    }

    func fetchCollapsedGroups() throws -> Set<SidebarGroupKey> {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchCollapsedGroupRows(database, workspaceId: workspaceId)
        }
    }

    func hasCollapsedGroupsState() throws -> Bool {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.hasCollapsedGroupStateRows(database, workspaceId: workspaceId)
        }
    }

    func replaceApplicationEntityRecency(_ recentEntities: [ApplicationEntityRecency]) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceApplicationEntityRecencyRows(
                database,
                recentEntities: recentEntities
            )
        }
    }

    func fetchApplicationEntityRecency() throws -> [ApplicationEntityRecency] {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchApplicationEntityRecencyRows(database)
        }
    }

    func replaceWorkspaceEntityRecency(_ recentEntities: [WorkspaceEntityRecency]) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceWorkspaceEntityRecencyRows(
                database,
                workspaceId: workspaceId,
                recentEntities: recentEntities
            )
        }
    }

    func fetchWorkspaceEntityRecency() throws -> [WorkspaceEntityRecency] {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchWorkspaceEntityRecencyRows(
                database,
                workspaceId: workspaceId
            )
        }
    }

    func deleteWorkspaceEntityRecency() throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.deleteWorkspaceEntityRecencyRows(
                database,
                workspaceId: workspaceId
            )
        }
    }

    func replaceCacheState(cacheState: CacheStateRecord, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.deleteCacheRows(database, workspaceId: workspaceId)
            try WorkspaceLocalRepositoryStorage.insertCacheRows(
                database,
                workspaceId: workspaceId,
                cacheState: cacheState,
                updatedAt: updatedAt
            )
        }
    }

    func fetchCacheState() throws -> CacheStateRecord {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchCacheRows(database, workspaceId: workspaceId)
        }
    }

    func hasCacheState() throws -> Bool {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.hasCacheStateRows(database, workspaceId: workspaceId)
        }
    }

    func resetCacheRows() throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.deleteCacheRows(database, workspaceId: workspaceId)
        }
    }

    func replaceEditorPreferences(_ preferences: EditorPreferencesRecord, updatedAt: Date) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceEditorPreferencesRows(
                database,
                workspaceId: workspaceId,
                preferences: preferences,
                updatedAt: updatedAt
            )
        }
    }

    func fetchEditorPreferences() throws -> EditorPreferencesRecord {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchEditorPreferencesRows(database, workspaceId: workspaceId)
        }
    }

    func replaceRepoExplorerPreferences(
        _ preferences: RepoExplorerPreferencesRecord,
        updatedAt: Date
    ) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceRepoExplorerPreferencesRows(
                database,
                workspaceId: workspaceId,
                preferences: preferences,
                updatedAt: updatedAt
            )
        }
    }

    func fetchRepoExplorerPreferences() throws -> RepoExplorerPreferencesRecord {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchRepoExplorerPreferencesRows(database, workspaceId: workspaceId)
        }
    }

    func replaceInboxNotificationPreferences(
        _ preferences: InboxNotificationPreferencesRecord,
        updatedAt: Date
    ) throws {
        try databaseWriter.write { database in
            try WorkspaceLocalRepositoryStorage.replaceInboxNotificationPreferencesRows(
                database,
                workspaceId: workspaceId,
                preferences: preferences,
                updatedAt: updatedAt
            )
        }
    }

    func fetchInboxNotificationPreferences() throws -> InboxNotificationPreferencesRecord {
        try databaseWriter.read { database in
            try WorkspaceLocalRepositoryStorage.fetchInboxNotificationPreferencesRows(
                database,
                workspaceId: workspaceId
            )
        }
    }
}

enum WorkspaceLocalRepositoryError: Error, Equatable {
    case unsupportedSidebarSurface(String)
    case malformedWorkspaceId(String)
    case malformedTabId(String)
    case malformedArrangementId(String)
    case malformedPaneId(String)
    case malformedDrawerId(String)
    case malformedRepoId(String)
    case malformedWorktreeId(String)
    case invalidWindowFramePayload
    case invalidCachePayload
    case missingRepoEnrichmentPayload(UUID)
    case missingWorktreeEnrichmentPayload(UUID)
}
