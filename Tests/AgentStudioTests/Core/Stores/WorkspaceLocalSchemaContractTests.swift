import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("WorkspaceLocalSchemaContractTests")
struct WorkspaceLocalSchemaContractTests {
    @Test("local storage tokens match live core enum vocabularies")
    func localStorageTokensMatchLiveCoreEnumVocabularies() {
        let sidebarSurfaceStorageValues = Set(
            SidebarSurface.allCases.map { SQLiteLocalUXStorage.storageValue(for: $0) }
        )
        let recentTargetKindStorageValues = Set(
            RecentWorkspaceTarget.Kind.allCases.map { SQLiteLocalUXStorage.storageValue(for: $0) }
        )

        #expect(sidebarSurfaceStorageValues == Set(["repos", "inbox"]))
        #expect(recentTargetKindStorageValues == Set(["worktree", "cwdOnly"]))
    }

    @Test("notification claim lane storage matches mergeable lane vocabulary")
    func notificationClaimLaneStorageMatchesMergeableLaneVocabulary() {
        let claimLaneStorageValues = Set(InboxNotificationClaimLane.allCases.map(\.rawValue))
        let mergeableLaneStorageValues = Set(
            InboxNotificationClaimLane.allCases
                .filter(\.canMergeWithinActivitySession)
                .map(\.rawValue)
        )

        #expect(claimLaneStorageValues == SQLiteInboxNotificationClaimStorage.allLaneStorageValues)
        #expect(SQLiteInboxNotificationClaimStorage.allLaneSQLValues == "'activity', 'actionNeeded', 'safety'")
        #expect(mergeableLaneStorageValues == SQLiteInboxNotificationClaimStorage.mergeableLaneStorageValues)
        #expect(SQLiteInboxNotificationClaimStorage.mergeableLaneSQLValues == "'activity', 'actionNeeded'")
    }

    @Test("local lookup indexes are present")
    func localLookupIndexesArePresent() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let indexNames = try databaseQueue.read { database in
            try Set(
                String.fetchAll(
                    database,
                    sql: """
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'index'
                        """
                )
            )
        }

        let expectedIndexNames: Set<String> = [
            "idx_local_tab_cursor_workspace_id",
            "idx_local_arrangement_cursor_workspace_id",
            "idx_local_drawer_cursor_workspace_id",
            "idx_local_drawer_cursor_one_expanded_per_workspace",
            "idx_local_arrangement_drawer_cursor_workspace_id",
            "idx_local_arrangement_drawer_cursor_drawer_id",
            "idx_local_recent_workspace_target_workspace_id",
            "idx_local_persistence_lane_marker_workspace_id",
            "idx_local_notification_inbox_item_workspace_timestamp",
            "idx_local_notification_inbox_item_pane_id",
            "idx_local_notification_inbox_item_tab_id",
            "idx_local_notification_inbox_item_repo_id",
            "idx_local_notification_inbox_item_worktree_id",
            "idx_local_notification_inbox_item_claim_exact",
            "idx_local_notification_inbox_item_claim_session",
            "idx_cache_repo_enrichment_workspace_id",
            "idx_cache_worktree_enrichment_workspace_id",
            "idx_cache_worktree_enrichment_repo_id",
            "idx_cache_pull_request_count_workspace_id",
            "idx_cache_pull_request_count_repo_id",
            "idx_cache_notification_count_workspace_id",
            "idx_cache_notification_count_repo_id",
        ]

        #expect(expectedIndexNames.isSubset(of: indexNames))
        #expect(!indexNames.contains("idx_local_notification_inbox_item_claim_key"))
    }

    @Test("drawer expansion switch must collapse before expanding replacement")
    func drawerExpansionSwitchMustCollapseBeforeExpandingReplacement() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID().uuidString
        let firstDrawerId = UUID().uuidString
        let secondDrawerId = UUID().uuidString

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_drawer_cursor(drawer_id, workspace_id, is_expanded, updated_at)
                    VALUES (?, ?, ?, ?), (?, ?, ?, ?)
                    """,
                arguments: [
                    firstDrawerId, workspaceId, 1, 1.0,
                    secondDrawerId, workspaceId, 0, 1.0,
                ]
            )
        }

        expectSchemaContractDatabaseError(containing: "UNIQUE constraint failed") {
            try databaseQueue.write { database in
                try database.execute(
                    sql: """
                        UPDATE local_drawer_cursor
                        SET is_expanded = 1
                        WHERE drawer_id = ?
                        """,
                    arguments: [secondDrawerId]
                )
            }
        }

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE local_drawer_cursor
                    SET is_expanded = 0
                    WHERE drawer_id = ?
                    """,
                arguments: [firstDrawerId]
            )
            try database.execute(
                sql: """
                    UPDATE local_drawer_cursor
                    SET is_expanded = 1
                    WHERE drawer_id = ?
                    """,
                arguments: [secondDrawerId]
            )
        }
    }
}

private func expectSchemaContractDatabaseError(containing expectedMessage: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected DatabaseError containing '\(expectedMessage)'")
    } catch let error as DatabaseError {
        #expect(error.message?.contains(expectedMessage) == true)
    } catch {
        Issue.record("Expected DatabaseError, got \(error)")
    }
}
