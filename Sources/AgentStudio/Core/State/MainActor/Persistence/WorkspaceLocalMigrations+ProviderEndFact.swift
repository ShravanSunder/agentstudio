import GRDB

extension WorkspaceLocalMigrations {
    static func registerBindingProviderEndFact(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("016_add_binding_provider_end_fact") { database in
            let columnDefinitions = [
                "provider_end_reason TEXT",
                "provider_end_reason_text TEXT",
                "provider_ended_at TEXT",
                "started_from_historical_report INTEGER NOT NULL DEFAULT 0 CHECK (started_from_historical_report IN (0, 1))",
                "evidence_unordered INTEGER NOT NULL DEFAULT 0 CHECK (evidence_unordered IN (0, 1))",
                "unordered_fence_sequence INTEGER",
            ]
            for columnDefinition in columnDefinitions {
                try database.execute(sql: "ALTER TABLE sessions_pane_binding ADD COLUMN \(columnDefinition)")
            }
        }
    }
}
