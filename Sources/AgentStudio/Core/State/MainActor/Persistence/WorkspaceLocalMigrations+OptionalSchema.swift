import GRDB

// Optional schema admission registers each feature frontier in product order.
extension WorkspaceLocalMigrations {
    package static var migrator: DatabaseMigrator {
        var migrator = bootRequiredMigrator
        registerSessionsSchema(in: &migrator)
        registerIPCCredentialSchema(in: &migrator)
        registerOpaquePaneCredentialRecords(in: &migrator)
        registerPaneOnlyCredentialRecords(in: &migrator)
        registerBindingProviderEndFact(in: &migrator)
        registerPaneForegroundObservation(in: &migrator)
        registerCLIReportCursor(in: &migrator)
        registerCLIOutboxCursor(in: &migrator)
        return migrator
    }
}
