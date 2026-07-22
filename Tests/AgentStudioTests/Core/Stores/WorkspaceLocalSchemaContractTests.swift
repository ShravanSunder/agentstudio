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
        #expect(mergeableLaneStorageValues == SQLiteInboxNotificationClaimStorage.mergeableLaneStorageValues)
    }

    @Test("malformed recent targets disappear and valid typed targets survive")
    func malformedRecentTargetsDisappearAndValidTypedTargetsSurvive() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID()
        let repository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: databaseQueue)
        let validTarget = RecentWorkspaceTarget.forCwd(
            URL(fileURLWithPath: "/tmp/valid"),
            lastOpenedAt: Date(timeIntervalSince1970: 2)
        )
        try repository.replaceRecentTargets([validTarget], updatedAt: Date(timeIntervalSince1970: 2))
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_recent_workspace_target(
                        workspace_id, id, path, display_title, subtitle, repo_id, worktree_id, kind, last_opened_at
                    ) VALUES (?, 'malformed', '/tmp/malformed', 'Malformed', '', NULL, NULL, 'worktree', 1)
                    """,
                arguments: [workspaceId.uuidString]
            )
        }

        #expect(try repository.fetchRecentTargets() == [validTarget])
    }

    @Test("typed preferences round trip and malformed rows use defaults")
    func typedPreferencesRoundTripAndMalformedRowsUseDefaults() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()
        try WorkspaceLocalMigrations.migrate(databaseQueue)
        let workspaceId = UUID()
        let repository = WorkspaceLocalRepository(workspaceId: workspaceId, databaseWriter: databaseQueue)
        let repoPreferences = WorkspaceLocalRepository.RepoExplorerPreferencesRecord(
            groupingMode: .pane,
            sortOrder: .descending,
            visibilityMode: .favoritesOnly
        )
        try repository.replaceRepoExplorerPreferences(repoPreferences, updatedAt: Date(timeIntervalSince1970: 1))
        #expect(try repository.fetchRepoExplorerPreferences() == repoPreferences)

        try databaseQueue.write { database in
            try database.execute(
                sql: """
                    UPDATE local_repo_explorer_preferences
                    SET grouping_mode = 'unsupported'
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            )
        }
        #expect(try repository.fetchRepoExplorerPreferences() == .default)
    }

    @Test("local lookup indexes exactly match the target contract")
    func localLookupIndexesExactlyMatchTheTargetContract() throws {
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
            "idx_local_tab_cursor_workspace",
            "idx_local_arrangement_cursor_workspace",
            "idx_local_drawer_cursor_workspace",
            "idx_local_drawer_one_expanded_per_workspace",
            "idx_local_arrangement_drawer_cursor_workspace",
            "idx_local_recent_target_workspace_time",
            "idx_notification_workspace_timestamp",
            "idx_notification_workspace_pane",
            "idx_notification_workspace_tab",
            "idx_notification_workspace_repo",
            "idx_notification_workspace_worktree",
            "idx_notification_claim_exact",
            "idx_notification_claim_session",
            "idx_cache_worktree_repo",
            "idx_cache_pull_request_repo",
        ]

        let productIndexNames = Set(indexNames.filter { !$0.hasPrefix("sqlite_autoindex_") })
        #expect(productIndexNames == expectedIndexNames)
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
