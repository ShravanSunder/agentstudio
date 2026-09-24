import AgentStudioInfrastructure
import Foundation

extension WorkspaceSQLiteDatastoreActor {
    /// Opens and boot-migrates the application local database, then runs the
    /// one-time legacy drawer height import as a boot data step outside the
    /// migrator. The legacy key is the pending marker: it and its import cutoff
    /// are cleared together only after the imported rows commit, and both are
    /// kept when capture or the write fails.
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
        try localRepository.migrateBootRequired()
        if let legacyImport = legacyDrawerPresentationCapture.importToApply,
            (try? localRepository.importLegacyDrawerHeight(legacyImport)) != nil
        {
            configuration.legacyDrawerPresentationSource?.clear()
        }
        return localRepository
    }

    /// Records the import cutoff on the first boot that finds the legacy key,
    /// then captures the legacy global drawer height and the persisted owning
    /// panes created before that cutoff, before the local migration transaction
    /// opens. Core is prepared before local, so its owning panes are readable
    /// here.
    func captureLegacyDrawerPresentationImport(
        configuration: WorkspaceSQLiteDatastoreConfiguration
    ) -> LegacyDrawerPresentationImportCapture {
        LegacyDrawerPresentationImportCapture.capture(
            source: configuration.legacyDrawerPresentationSource,
            now: Date(),
            enumerateOwners: { [backend] in
                guard let backend else { throw WorkspaceSQLiteDatastoreError.databasesNotPrepared }
                return try backend.coreRepository.fetchOwningLayoutPaneIDsByWorkspace()
            }
        )
    }
}
