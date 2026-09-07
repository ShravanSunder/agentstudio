import Foundation

extension WorkspaceSQLiteDatastore {
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
