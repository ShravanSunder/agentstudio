extension WorkspaceSQLiteDatastore {
    func saveWorkspaceSnapshotBundle(_ bundle: WorkspaceSQLiteSaveBundle) async throws {
        try await withWorkspacePersistenceOrder { datastore in
            _ = try await datastore.performWorkspaceSnapshotBundleSave(bundle, undoChange: nil)
        }
    }

    func validateWorkspaceCapture(_ bundle: WorkspaceSQLiteSaveBundle) throws {
        guard let accepted = acceptedWorkspaceCaptureRevisions[bundle.id] else { return }
        guard let captured = bundle.captureRevision else {
            throw WorkspaceSQLiteDatastoreError.missingWorkspaceCaptureRevision
        }
        guard captured.isAtLeast(accepted) else {
            throw WorkspaceSQLiteDatastoreError.staleWorkspaceCapture
        }
    }

    func withWorkspacePersistenceOrder<TOutput: Sendable>(
        _ operation: @escaping @Sendable (isolated WorkspaceSQLiteDatastore) async throws -> TOutput
    ) async throws -> TOutput {
        let previousTail = workspaceSaveTail
        workspaceSaveTailGeneration &+= 1
        let tailGeneration = workspaceSaveTailGeneration
        let operationTask = Task { [self] in
            if let previousTail {
                do {
                    try await previousTail.value
                } catch {
                    // Ordering survives a failed operation; journal admission checks durable health separately.
                }
            }
            return try await operation(self)
        }
        workspaceSaveTail = Task { _ = try await operationTask.value }
        defer {
            if workspaceSaveTailGeneration == tailGeneration {
                workspaceSaveTail = nil
            }
        }
        return try await operationTask.value
    }
}
