import AgentStudioPrimitives
import GRDB

enum CLIStoreMigrator {
    static let identityMigration = "001_cli_store_identity"
    static let outboxMigration = "002_cli_outbox"
    static let lifecycleMigration = "003_cli_lifecycle_report"
    static let knownMigrations: Set<String> = [identityMigration, outboxMigration, lifecycleMigration]

    static func makeMigrator(channel: CLIStoreChannel) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(identityMigration) { database in
            try database.execute(
                sql: """
                    CREATE TABLE cli_store_identity (
                        store_id TEXT PRIMARY KEY NOT NULL,
                        channel TEXT NOT NULL
                    )
                    """)
            try database.execute(
                sql: "INSERT INTO cli_store_identity (store_id, channel) VALUES (?, ?)",
                arguments: [UUIDv7.generate().uuidString, channel.rawValue]
            )
        }
        migrator.registerMigration(outboxMigration) { database in
            // The app cursor survives purge, so an id must never be reused.
            try database.execute(
                sql: """
                    CREATE TABLE cli_outbox (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        kind TEXT NOT NULL,
                        pane_id TEXT NOT NULL,
                        message_id TEXT NOT NULL UNIQUE,
                        payload_json TEXT NOT NULL,
                        created_at INTEGER NOT NULL
                    )
                    """)
        }
        migrator.registerMigration(lifecycleMigration) { database in
            try database.execute(
                sql: """
                    CREATE TABLE cli_lifecycle_report (
                        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                        report_id TEXT NOT NULL UNIQUE,
                        pane_id TEXT NOT NULL,
                        provider_identifier TEXT NOT NULL,
                        provider_version TEXT NOT NULL,
                        provider_mode TEXT NOT NULL,
                        event_name TEXT NOT NULL,
                        conversation_id TEXT NOT NULL,
                        end_reason TEXT,
                        correlation_id TEXT NOT NULL,
                        recorded_at INTEGER NOT NULL,
                        boot_session_id TEXT NOT NULL
                    )
                    """)
        }
        return migrator
    }
}
