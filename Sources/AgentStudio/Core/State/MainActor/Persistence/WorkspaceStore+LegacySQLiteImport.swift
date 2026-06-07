import Foundation
import os.log

private let workspaceLegacySQLiteImportLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspaceLegacySQLiteImport"
)

@MainActor
enum WorkspaceLegacySQLiteImportMode: Equatable {
    case initialInPlaceBootImport
    case resumeUnfinishedImportKeepingCurrentSelection
    case resumeIncompleteInitialImport(hadActiveSelectionBeforeRestore: Bool)

    var keepsCurrentSelection: Bool {
        switch self {
        case .resumeUnfinishedImportKeepingCurrentSelection:
            return true
        case .initialInPlaceBootImport, .resumeIncompleteInitialImport:
            return false
        }
    }
}

@MainActor
enum WorkspaceLegacySQLiteImportOutcome {
    case noLegacyFiles
    case noPendingFilesKeepingSelection
    case importedInitialActive(WorkspacePersistor.PersistableState)
    case retriedWithoutSelectionChange
    case failedButImportedSome(WorkspacePersistor.PersistableState)
    case failedNoUsableImport
}

@MainActor
enum WorkspaceLegacySQLiteMaterializationOutcome {
    case saved
    case failed
}

enum LegacyWorkspaceFileImportClassification: Equatable {
    case pending
    case alreadyCompleted
    case skippedByStatus
    case unavailable(String)

    var shouldImport: Bool {
        if case .pending = self { return true }
        return false
    }
}

@MainActor
struct WorkspaceLegacySQLiteImporter {
    typealias LegacyFile = WorkspacePersistor.LegacyWorkspaceStateFile
    typealias MaterializeLegacyState = (LegacyFile) throws -> WorkspacePersistor.PersistableState

    var persistor: WorkspacePersistor
    var sqliteDatastore: WorkspaceSQLiteDatastore
    var recoveryReporter: PersistenceRecoveryReporter?
    var materializeLegacyState: MaterializeLegacyState

    func importWorkspaces(mode: WorkspaceLegacySQLiteImportMode) async -> WorkspaceLegacySQLiteImportOutcome {
        _ = persistor.ensureDirectory()
        let scan = persistor.loadLegacyWorkspaceStateFiles()
        quarantineCorruptFiles(scan.corruptFiles)
        guard !scan.loadedFiles.isEmpty else { return .noLegacyFiles }

        let pendingFiles = await pendingFiles(from: scan.loadedFiles, mode: mode)
        guard !pendingFiles.isEmpty else {
            return mode.keepsCurrentSelection ? .noPendingFilesKeepingSelection : .noLegacyFiles
        }

        var importedFiles: [(file: LegacyFile, state: WorkspacePersistor.PersistableState)] = []
        var failedFiles: [LegacyFile] = []
        for legacyFile in pendingFiles {
            do {
                let materializedState = try materializeLegacyState(legacyFile)
                try await sqliteDatastore.saveImportedLegacySnapshot(
                    WorkspacePersistenceTransformer.sqliteSnapshot(from: materializedState),
                    sourceStatePath: legacyFile.url.path
                )
                importedFiles.append((legacyFile, materializedState))
            } catch {
                failedFiles.append(legacyFile)
                workspaceLegacySQLiteImportLogger.error(
                    "Failed to materialize restored legacy workspace into SQLite: \(error.localizedDescription)"
                )
                recoveryReporter?(
                    .init(
                        store: .workspace,
                        workspaceId: legacyFile.state.id,
                        recovery: .saveFailed
                    )
                )
                await markImportFailed(legacyFile, error: error)
            }
        }

        if mode.keepsCurrentSelection {
            return .retriedWithoutSelectionChange
        }
        guard let activeImport = activeImportedFile(from: importedFiles) else {
            return .failedNoUsableImport
        }
        do {
            try await sqliteDatastore.selectActiveWorkspace(activeImport.state.id, updatedAt: Date())
            workspaceLegacySQLiteImportLogger.info(
                "Imported \(importedFiles.count, privacy: .public) pending legacy workspace file(s) into SQLite; selected active workspace \(activeImport.state.id.uuidString, privacy: .public)"
            )
            return failedFiles.isEmpty
                ? .importedInitialActive(activeImport.state)
                : .failedButImportedSome(activeImport.state)
        } catch {
            workspaceLegacySQLiteImportLogger.error(
                "Failed to select active workspace after legacy SQLite import: \(error.localizedDescription)"
            )
            recoveryReporter?(
                .init(
                    store: .workspace,
                    workspaceId: activeImport.state.id,
                    recovery: .resetToDefaults
                )
            )
            await markImportFailed(activeImport.file, error: error)
            return .failedNoUsableImport
        }
    }

    private func quarantineCorruptFiles(_ corruptFiles: [WorkspacePersistor.CorruptLegacyWorkspaceStateFile]) {
        for corruptFile in corruptFiles {
            let quarantine = persistor.quarantineCorruptCanonicalWorkspaceFiles(at: corruptFile.url)
            workspaceLegacySQLiteImportLogger.error(
                "Legacy workspace file \(corruptFile.url.lastPathComponent, privacy: .public) failed to decode during SQLite import; quarantined before continuing: \(corruptFile.error.localizedDescription)"
            )
            recoveryReporter?(
                .init(
                    store: .workspace,
                    workspaceId: quarantine?.workspaceId,
                    recovery: quarantine?.recovery ?? .quarantineFailed,
                    quarantinedFilename: quarantine?.recoveryFilename
                )
            )
        }
    }

    private func pendingFiles(
        from legacyFiles: [LegacyFile],
        mode: WorkspaceLegacySQLiteImportMode
    ) async -> [LegacyFile] {
        var pendingFiles: [LegacyFile] = []
        for legacyFile in legacyFiles {
            let classification = await classifyLegacyFileForImport(legacyFile, mode: mode)
            if classification.shouldImport {
                pendingFiles.append(legacyFile)
            }
        }
        return pendingFiles
    }

    private func classifyLegacyFileForImport(
        _ legacyFile: LegacyFile,
        mode: WorkspaceLegacySQLiteImportMode
    ) async -> LegacyWorkspaceFileImportClassification {
        do {
            if try await sqliteDatastore.hasCompletedSnapshot(workspaceId: legacyFile.state.id) {
                return .alreadyCompleted
            }
            switch await sqliteDatastore.legacyImportStatus(workspaceId: legacyFile.state.id) {
            case .missing:
                return try missingStatusClassification(for: mode)
            case .found(let status):
                return status.coreImportedAt == nil || status.lastError != nil ? .pending : .skippedByStatus
            case .unavailable(let failure):
                throw failure
            }
        } catch {
            workspaceLegacySQLiteImportLogger.error(
                "Skipping legacy workspace retry because import status lookup failed: \(error.localizedDescription)"
            )
            return .unavailable(String(describing: error))
        }
    }

    private func missingStatusClassification(
        for mode: WorkspaceLegacySQLiteImportMode
    ) throws -> LegacyWorkspaceFileImportClassification {
        switch mode {
        case .initialInPlaceBootImport:
            return .pending
        case .resumeUnfinishedImportKeepingCurrentSelection:
            return .skippedByStatus
        case .resumeIncompleteInitialImport(let hadActiveSelectionBeforeRestore):
            return hadActiveSelectionBeforeRestore ? .skippedByStatus : .pending
        }
    }

    private func activeImportedFile(
        from importedFiles: [(file: LegacyFile, state: WorkspacePersistor.PersistableState)]
    ) -> (file: LegacyFile, state: WorkspacePersistor.PersistableState)? {
        importedFiles.max { lhs, rhs in
            if lhs.file.modificationDate != rhs.file.modificationDate {
                return lhs.file.modificationDate < rhs.file.modificationDate
            }
            return lhs.state.id.uuidString > rhs.state.id.uuidString
        }
    }

    private func markImportFailed(_ legacyFile: LegacyFile, error: any Error) async {
        let outcome = await sqliteDatastore.markLegacyWorkspaceImportFailed(
            WorkspacePersistenceTransformer.sqliteSnapshot(from: legacyFile.state),
            sourceStatePath: legacyFile.url.path,
            error: error
        )
        if case .failedToRecord(let failure) = outcome {
            workspaceLegacySQLiteImportLogger.error(
                "Failed to record legacy workspace import error: \(failure.description)"
            )
        }
    }
}

@MainActor
extension WorkspaceStore {
    @discardableResult
    func importLegacySQLiteWorkspacesInPlaceOnFirstBoot(
        _ sqliteDatastore: WorkspaceSQLiteDatastore
    ) async -> WorkspaceLegacySQLiteImportOutcome {
        await runLegacySQLiteImport(sqliteDatastore, mode: .initialInPlaceBootImport)
    }

    @discardableResult
    func resumeUnfinishedLegacySQLiteImportKeepingCurrentSelection(
        _ sqliteDatastore: WorkspaceSQLiteDatastore
    ) async -> WorkspaceLegacySQLiteImportOutcome {
        await runLegacySQLiteImport(sqliteDatastore, mode: .resumeUnfinishedImportKeepingCurrentSelection)
    }

    @discardableResult
    func resumeUnfinishedLegacySQLiteImportAfterIncompleteSQLiteRestore(
        _ sqliteDatastore: WorkspaceSQLiteDatastore,
        hadActiveSelectionBeforeRestore: Bool
    ) async -> WorkspaceLegacySQLiteImportOutcome {
        await runLegacySQLiteImport(
            sqliteDatastore,
            mode: .resumeIncompleteInitialImport(
                hadActiveSelectionBeforeRestore: hadActiveSelectionBeforeRestore
            )
        )
    }

    @discardableResult
    func materializeRestoredSQLiteState(
        from legacyState: WorkspacePersistor.PersistableState,
        sourceStatePath: String,
        using sqliteDatastore: WorkspaceSQLiteDatastore
    ) async -> WorkspaceLegacySQLiteMaterializationOutcome {
        do {
            let materializedState = materializedLegacyState(legacyState)
            try await sqliteDatastore.saveImportedLegacySnapshot(
                WorkspacePersistenceTransformer.sqliteSnapshot(from: materializedState),
                sourceStatePath: sourceStatePath
            )
            return .saved
        } catch {
            workspaceLegacySQLiteImportLogger.error(
                "Failed to materialize restored legacy workspace into SQLite: \(error.localizedDescription)"
            )
            reportSaveFailed()
            return .failed
        }
    }

    private func runLegacySQLiteImport(
        _ sqliteDatastore: WorkspaceSQLiteDatastore,
        mode: WorkspaceLegacySQLiteImportMode
    ) async -> WorkspaceLegacySQLiteImportOutcome {
        let stateBeforeImport = currentLiveSQLiteState()
        let importer = WorkspaceLegacySQLiteImporter(
            persistor: persistor,
            sqliteDatastore: sqliteDatastore,
            recoveryReporter: recoveryReporter,
            materializeLegacyState: { legacyFile in
                self.hydrateWorkspaceState(legacyFile.state)
                return self.materializedLegacyState(legacyFile.state)
            }
        )
        let outcome = await importer.importWorkspaces(mode: mode)
        applyLegacySQLiteImportOutcome(outcome, stateBeforeImport: stateBeforeImport)
        return outcome
    }

    private func applyLegacySQLiteImportOutcome(
        _ outcome: WorkspaceLegacySQLiteImportOutcome,
        stateBeforeImport: WorkspacePersistor.PersistableState
    ) {
        switch outcome {
        case .importedInitialActive(let state), .failedButImportedSome(let state):
            hydrateWorkspaceState(state)
        case .noPendingFilesKeepingSelection, .retriedWithoutSelectionChange, .failedNoUsableImport:
            hydrateWorkspaceState(stateBeforeImport)
        case .noLegacyFiles:
            break
        }
    }

    private func materializedLegacyState(
        _ legacyState: WorkspacePersistor.PersistableState
    ) -> WorkspacePersistor.PersistableState {
        WorkspacePersistenceTransformer.makePersistableState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: legacyState.updatedAt
        )
    }

    private func currentLiveSQLiteState() -> WorkspacePersistor.PersistableState {
        WorkspacePersistenceTransformer.makeLiveSQLiteState(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: Date()
        )
    }
}
