import Foundation
import GRDB

enum WorkspaceSQLiteStartupSchemaPreparer {
    static func migratePreexistingDatabaseIfRequired(
        at databaseURL: URL,
        label: String,
        migrator: DatabaseMigrator
    ) throws {
        let schemaReader = try SQLiteDatabaseFactory.makeBytePreservingStartupReader(
            at: databaseURL,
            label: label
        )
        let hasCurrentSchema = try schemaReader.read { database in
            try migrator.hasCompletedMigrations(database)
        }
        try schemaReader.close()
        guard !hasCurrentSchema else { return }

        let migrationPool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: databaseURL,
            label: "\(label).migration"
        )
        try migrator.migrate(migrationPool)
        try migrationPool.close()
    }
}
