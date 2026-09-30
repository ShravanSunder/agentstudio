import GRDB

enum CLIStoreMigrator {
    static let identityMigration = "001_cli_store_identity"
    static let outboxMigration = "002_cli_outbox"

    static func makeMigrator(channel: CLIStoreChannel) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(identityMigration) { _ in }
        migrator.registerMigration(outboxMigration) { _ in }
        return migrator
    }
}
