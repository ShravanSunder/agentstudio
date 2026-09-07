import Foundation

extension WorkspaceSQLiteDatastore {
    package func nextUndoDeadline(bootID: String) async throws -> Int64? {
        try await withWorkspacePersistenceOrder { datastore in
            try datastore.journalRepository().nextUndoDeadline(bootID: bootID)
        }
    }

    package func expireAllUndoCloses(time: WorkspaceUndoJournalTime) async throws -> [WorkspaceUndoCloseRetirement] {
        try await withWorkspacePersistenceOrder { datastore in
            try datastore.requireJournalMutationAdmission()
            try validateUndoJournalTime(time)
            let repository = try datastore.journalRepository()
            var retired: [WorkspaceUndoCloseRetirement] = []
            for workspaceID in try repository.workspaceIDsWithAvailableUndo() {
                try repository.recoverUndoCloseDeadlines(workspaceID: workspaceID, time: time)
                retired.append(contentsOf: try repository.expireUndoCloses(workspaceID: workspaceID, time: time))
            }
            // Also finishes startup reconciliation if the boot clock was initially unavailable.
            try repository.reconcileUnownedTerminalSessions(at: time)
            return retired
        }
    }

    /// Called after valid canonical composition is loaded and before runtime hosts are admitted.
    package func recoverUndoJournal(
        workspaceID: UUID, time: WorkspaceUndoJournalTime?
    ) async throws -> WorkspaceUndoJournalRecovery {
        try await withWorkspacePersistenceOrder { datastore in
            let repository = try datastore.journalRepository()
            var retiredCloses: [WorkspaceUndoCloseRetirement] = []
            if let time {
                try datastore.requireJournalMutationAdmission()
                try validateUndoJournalTime(time)
                for ownerWorkspaceID in try repository.workspaceIDsWithAvailableUndo() {
                    try repository.recoverUndoCloseDeadlines(workspaceID: ownerWorkspaceID, time: time)
                    retiredCloses.append(
                        contentsOf: try repository.expireUndoCloses(workspaceID: ownerWorkspaceID, time: time))
                }
                try repository.reconcileUnownedTerminalSessions(at: time)
                try repository.pruneCompletedUndoHistory(workspaceID: workspaceID)
            }
            return .init(
                availableCloses: try repository.fetchAvailableUndoCloses(workspaceID: workspaceID),
                retiredCloses: retiredCloses,
                pendingSessionIDs: try repository.pendingTerminalSessionIDs()
            )
        }
    }

    func requireJournalMutationAdmission(reconciling workspaceID: UUID? = nil) throws {
        let unresolved =
            workspaceID.map { failedStructuralWorkspaceIDs.subtracting([$0]) }
            ?? failedStructuralWorkspaceIDs
        guard unresolved.isEmpty else { throw WorkspaceSQLiteDatastoreError.unreconciledStructuralSave }
    }

    /// A journal mutation acknowledges core durability; local UI state follows normal autosave.
    @discardableResult
    func commitWorkspaceSnapshotWithUndo(
        _ bundle: WorkspaceSQLiteSaveBundle,
        change: WorkspaceUndoJournalChange,
        publish: (@MainActor @Sendable (WorkspaceUndoJournalReceipt) -> WorkspaceCompositionRevision)? = nil
    ) async throws -> WorkspaceUndoJournalReceipt {
        guard bundle.captureRevision == nil || publish != nil else {
            throw WorkspaceSQLiteDatastoreError.missingWorkspacePublication
        }
        return try await withWorkspacePersistenceOrder { datastore in
            guard let receipt = try await datastore.performWorkspaceSnapshotBundleSave(bundle, undoChange: change)
            else {
                preconditionFailure("Journal mutation must return its committed receipt")
            }
            if let publish {
                let revision = await publish(receipt)
                datastore.acceptedWorkspaceCaptureRevisions[bundle.id] = revision
            }
            return receipt
        }
    }

    package func fetchAvailableUndoCloses(workspaceID: UUID) async throws -> [WorkspaceUndoCloseRecord] {
        try await withWorkspacePersistenceOrder { datastore in
            try datastore.journalRepository().fetchAvailableUndoCloses(workspaceID: workspaceID)
        }
    }

    package func recoverUndoCloseDeadlines(workspaceID: UUID, time: WorkspaceUndoJournalTime) async throws {
        try await withWorkspacePersistenceOrder { datastore in
            try datastore.requireJournalMutationAdmission()
            try datastore.journalRepository().recoverUndoCloseDeadlines(workspaceID: workspaceID, time: time)
        }
    }

    package func expireUndoCloses(
        workspaceID: UUID,
        time: WorkspaceUndoJournalTime
    ) async throws -> [WorkspaceUndoCloseRetirement] {
        try await withWorkspacePersistenceOrder { datastore in
            try datastore.requireJournalMutationAdmission()
            return try datastore.journalRepository().expireUndoCloses(workspaceID: workspaceID, time: time)
        }
    }
}
