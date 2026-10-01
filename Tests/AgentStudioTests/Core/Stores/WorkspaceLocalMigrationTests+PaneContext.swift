import Foundation
import GRDB
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

extension WorkspaceLocalMigrationTests {
    @Test("fresh local database creates exactly the clean product schema")
    func freshLocalDatabaseCreatesExactlyTheCleanProductSchema() throws {
        let databaseQueue = try SQLiteDatabaseFactory.makeInMemoryQueue()

        try WorkspaceLocalMigrations.migrate(databaseQueue)

        let tableNames = try databaseQueue.read { database in
            try Set(
                String.fetchAll(
                    database,
                    sql: """
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                        """
                )
            )
        }
        let expectedTableNames = Set([
            "local_workspace_cursor",
            "local_tab_cursor",
            "local_arrangement_cursor",
            "local_drawer_cursor",
            "local_arrangement_drawer_cursor",
            "local_window_state",
            "local_window_sidebar_collapsed_group",
            "local_entity_recency",
            "local_workspace_entity_recency",
            "local_repository_activity",
            "local_repository_activity_cursor",
            "local_notification_inbox_collapsed_group",
            "local_notification_inbox_item",
            "local_editor_preferences",
            "local_repo_explorer_preferences",
            "local_inbox_notification_preferences",
            "cache_metadata",
            "cache_repo_enrichment",
            "cache_worktree_enrichment",
            "annotation_session",
            "annotation_thread",
            "annotation_message",
            "annotation_message_draft",
            "annotation_output_attempt",
            "annotation_output_attempt_message",
            "annotation_output_event",
            "local_recovery_provenance",
            "sessions_conversation",
            "sessions_pane_binding",
            "sessions_source",
            "sessions_evidence",
            "sessions_message",
            "sessions_attention",
            "sessions_result",
            "sessions_operation",
            "sessions_loss",
            "local_ipc_credential",
            "local_drawer_presentation",
        ]).union(["sessions_provider_question", "sessions_provider_question_option"])
            .union([
                "pane_state", "pane_state_action", "pane_request", "pane_event",
                "pane_request_action", "pane_event_action", "pane_request_choice",
                "pane_request_property", "pane_request_property_choice", "pane_request_required",
                "pane_request_answer_value", "pane_write_order", "pane_epoch_claim",
                "pane_answer_position", "pane_retirement",
            ])

        #expect(tableNames == expectedTableNames)
        #expect(!tableNames.contains("local_persistence_lane_marker"))
        #expect(!tableNames.contains("local_workspace_sqlite_snapshot_status"))
        #expect(!tableNames.contains("cache_notification_count"))
    }
}
