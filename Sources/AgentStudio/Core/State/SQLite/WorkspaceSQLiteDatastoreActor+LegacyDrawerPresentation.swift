import Foundation

extension WorkspaceSQLiteDatastoreActor {
    /// Opens and boot-migrates the application local database. The retired
    /// global drawer height key is cleared only after its import migration
    /// committed; a failed owner capture keeps the key and the import pending.
    static func openConfiguredLocalRepository(
        workspaceId: UUID,
        configuration: WorkspaceSQLiteDatastoreConfiguration,
        legacyDrawerPresentationCapture: LegacyDrawerPresentationImportCapture
    ) throws -> WorkspaceLocalRepository {
        let localDatabasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: configuration.localDatabaseURL,
            label: "AgentStudio.sqlite.local.\(workspaceId.uuidString)"
        )
        let localRepository = WorkspaceLocalRepository(
            workspaceId: workspaceId,
            databaseWriter: localDatabasePool
        )
        try localRepository.migrateBootRequired(
            legacyDrawerPresentationImport: legacyDrawerPresentationCapture.importToApply
        )
        if legacyDrawerPresentationCapture.importToApply != nil {
            // The per-owner rows are committed; the global key is no longer a runtime fallback.
            configuration.legacyDrawerPresentationSource?.clear()
        }
        return localRepository
    }

    /// Captures the legacy global drawer height and the persisted owning panes
    /// before the local migration transaction opens. Core is prepared before
    /// local, so its owning panes are readable here.
    func captureLegacyDrawerPresentationImport(
        configuration: WorkspaceSQLiteDatastoreConfiguration
    ) -> LegacyDrawerPresentationImportCapture {
        LegacyDrawerPresentationImportCapture.capture(
            source: configuration.legacyDrawerPresentationSource,
            enumerateOwners: { [backend] in
                guard let backend else { throw WorkspaceSQLiteDatastoreError.databasesNotPrepared }
                return try backend.coreRepository.fetchOwningLayoutPaneIDsByWorkspace()
            }
        )
    }
}
