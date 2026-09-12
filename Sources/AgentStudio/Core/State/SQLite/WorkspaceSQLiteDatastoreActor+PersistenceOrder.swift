extension WorkspaceSQLiteDatastoreActor {
    func saveRepositoryTopologySnapshot(
        _ snapshot: RepositoryTopologySQLiteSnapshot,
        captureRevision: UInt64,
        reparenting: [RepositoryWorktreeReparenting] = []
    ) async throws {
        try await withWorkspacePersistenceOrder { datastore in
            if let accepted = datastore.acceptedRepositoryTopologyCaptureRevision,
                captureRevision < accepted
            {
                throw WorkspaceSQLiteDatastoreError.staleRepositoryTopologyCapture
            }
            let topology = WorkspaceSQLiteStateBridge.repositoryTopologyRecord(from: snapshot)
            try datastore.journalRepository().replaceRepositoryTopology(topology, reparenting: reparenting)
            datastore.acceptedRepositoryTopologyCaptureRevision = captureRevision
            if datastore.retentionSurvivingIdentity != nil {
                datastore.retentionSurvivingIdentity = datastore.survivingRepositoryRetentionIdentity(from: topology)
            }
        }
    }

    func saveWorkspaceSnapshotBundle(_ bundle: WorkspaceSQLiteSaveBundle) async throws {
        try await withWorkspacePersistenceOrder { datastore in
            _ = try await datastore.performWorkspaceSnapshotBundleSave(bundle, undoChange: nil)
        }
    }

    func workspaceBundleAdmittedForCurrentTopologyContext(
        _ bundle: WorkspaceSQLiteSaveBundle
    ) throws -> WorkspaceSQLiteSaveBundle {
        if let accepted = acceptedWorkspaceCaptureRevisions[bundle.id] {
            guard let captured = bundle.captureRevision else {
                throw WorkspaceSQLiteDatastoreError.missingWorkspaceCaptureRevision
            }
            guard captured.isAtLeast(accepted) else {
                throw WorkspaceSQLiteDatastoreError.staleWorkspaceCapture
            }
        }
        guard let acceptedTopologyContext = acceptedRepositoryTopologyCaptureRevision,
            let capturedTopologyContext = bundle.captureRevision?.topologyContextRevision,
            capturedTopologyContext < acceptedTopologyContext
        else {
            return bundle
        }
        var workspace = bundle.workspace
        workspace.panes = workspace.panes.map { pane in
            var sanitizedPane = pane
            var facets = sanitizedPane.metadata.facets
            facets.repoId = nil
            facets.worktreeId = nil
            sanitizedPane.metadata.updateFacets(facets)
            return sanitizedPane
        }
        return WorkspaceSQLiteSaveBundle(
            workspace: workspace,
            captureRevision: bundle.captureRevision
        )
    }

    func withWorkspacePersistenceOrder<TOutput: Sendable>(
        cancelBeforeAdmission: Bool = false,
        _ operation: @escaping @Sendable (isolated WorkspaceSQLiteDatastoreActor) async throws -> TOutput
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
            if cancelBeforeAdmission {
                try Task.checkCancellation()
            }
            return try await operation(self)
        }
        workspaceSaveTail = Task { _ = try await operationTask.value }
        defer {
            if workspaceSaveTailGeneration == tailGeneration {
                workspaceSaveTail = nil
            }
        }
        if cancelBeforeAdmission {
            return try await withTaskCancellationHandler {
                try await operationTask.value
            } onCancel: {
                operationTask.cancel()
            }
        }
        return try await operationTask.value
    }
}
