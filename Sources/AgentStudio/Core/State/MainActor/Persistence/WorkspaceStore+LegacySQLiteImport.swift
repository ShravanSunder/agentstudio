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
    var sqliteBackend: WorkspaceSQLiteStoreBackend
    var recoveryReporter: PersistenceRecoveryReporter?
    var materializeLegacyState: MaterializeLegacyState

    func importWorkspaces(mode: WorkspaceLegacySQLiteImportMode) -> WorkspaceLegacySQLiteImportOutcome {
        _ = persistor.ensureDirectory()
        let scan = persistor.loadLegacyWorkspaceStateFiles()
        quarantineCorruptFiles(scan.corruptFiles)
        guard !scan.loadedFiles.isEmpty else { return .noLegacyFiles }

        let pendingFiles = pendingFiles(from: scan.loadedFiles, mode: mode)
        guard !pendingFiles.isEmpty else {
            return mode.keepsCurrentSelection ? .noPendingFilesKeepingSelection : .noLegacyFiles
        }

        var importedFiles: [(file: LegacyFile, state: WorkspacePersistor.PersistableState)] = []
        var failedFiles: [LegacyFile] = []
        for legacyFile in pendingFiles {
            do {
                let materializedState = try materializeLegacyState(legacyFile)
                try sqliteBackend.saveImportedLegacySnapshot(
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
                markImportFailed(legacyFile, error: error)
            }
        }

        if mode.keepsCurrentSelection {
            return .retriedWithoutSelectionChange
        }
        guard let activeImport = activeImportedFile(from: importedFiles) else {
            return .failedNoUsableImport
        }
        do {
            try sqliteBackend.selectActiveWorkspace(activeImport.state.id, updatedAt: Date())
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
            markImportFailed(activeImport.file, error: error)
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
    ) -> [LegacyFile] {
        legacyFiles.filter { legacyFile in
            classifyLegacyFileForImport(legacyFile, mode: mode).shouldImport
        }
    }

    private func classifyLegacyFileForImport(
        _ legacyFile: LegacyFile,
        mode: WorkspaceLegacySQLiteImportMode
    ) -> LegacyWorkspaceFileImportClassification {
        do {
            if try sqliteBackend.hasCompletedSnapshot(workspaceId: legacyFile.state.id) {
                return .alreadyCompleted
            }
            guard
                let status = try sqliteBackend.coreRepository.fetchLegacyWorkspaceImportStatus(
                    workspaceId: legacyFile.state.id
                )
            else {
                return try missingStatusClassification(for: mode)
            }
            return status.coreImportedAt == nil || status.lastError != nil ? .pending : .skippedByStatus
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

    private func markImportFailed(_ legacyFile: LegacyFile, error: any Error) {
        do {
            try sqliteBackend.markLegacyWorkspaceImportFailed(
                legacyFile.state,
                sourceStatePath: legacyFile.url.path,
                error: error
            )
        } catch {
            workspaceLegacySQLiteImportLogger.error(
                "Failed to record legacy workspace import error: \(error.localizedDescription)"
            )
        }
    }
}

@MainActor
extension WorkspaceStore {
    @discardableResult
    func importLegacySQLiteWorkspacesInPlaceOnFirstBoot(
        _ sqliteBackend: WorkspaceSQLiteStoreBackend
    ) -> WorkspaceLegacySQLiteImportOutcome {
        runLegacySQLiteImport(sqliteBackend, mode: .initialInPlaceBootImport)
    }

    @discardableResult
    func resumeUnfinishedLegacySQLiteImportKeepingCurrentSelection(
        _ sqliteBackend: WorkspaceSQLiteStoreBackend
    ) -> WorkspaceLegacySQLiteImportOutcome {
        runLegacySQLiteImport(sqliteBackend, mode: .resumeUnfinishedImportKeepingCurrentSelection)
    }

    @discardableResult
    func resumeUnfinishedLegacySQLiteImportAfterIncompleteSQLiteRestore(
        _ sqliteBackend: WorkspaceSQLiteStoreBackend,
        hadActiveSelectionBeforeRestore: Bool
    ) -> WorkspaceLegacySQLiteImportOutcome {
        runLegacySQLiteImport(
            sqliteBackend,
            mode: .resumeIncompleteInitialImport(
                hadActiveSelectionBeforeRestore: hadActiveSelectionBeforeRestore
            )
        )
    }

    @discardableResult
    func materializeRestoredSQLiteState(
        from legacyState: WorkspacePersistor.PersistableState,
        sourceStatePath: String,
        using sqliteBackend: WorkspaceSQLiteStoreBackend
    ) -> WorkspaceLegacySQLiteMaterializationOutcome {
        do {
            let materializedState = materializedLegacyState(legacyState)
            try sqliteBackend.saveImportedLegacySnapshot(
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
        _ sqliteBackend: WorkspaceSQLiteStoreBackend,
        mode: WorkspaceLegacySQLiteImportMode
    ) -> WorkspaceLegacySQLiteImportOutcome {
        let stateBeforeImport = currentLiveSQLiteState()
        let importer = WorkspaceLegacySQLiteImporter(
            persistor: persistor,
            sqliteBackend: sqliteBackend,
            recoveryReporter: recoveryReporter,
            materializeLegacyState: { legacyFile in
                self.hydrateWorkspaceState(legacyFile.state)
                return self.materializedLegacyState(legacyFile.state)
            }
        )
        let outcome = importer.importWorkspaces(mode: mode)
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
