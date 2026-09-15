import AgentStudioCore
import Foundation
import GRDB

actor IPCContinuityRepository {
    private let datastore: WorkspaceSQLiteDatastoreActor

    init(datastore: WorkspaceSQLiteDatastoreActor) {
        self.datastore = datastore
    }

    func persistPreparedPaneCredential(
        paneID: UUID,
        workspaceID: UUID,
        generation: UUID,
        verifier: Data
    ) async throws {
        guard verifier.count == 32 else { throw IPCContinuityRepositoryError.invalidVerifierLength }
        try await datastore.performApplicationLocalWrite { database in
            let existing = try IPCContinuityRepository.fetchCredential(database, paneID: paneID, generation: generation)
            if let existing {
                guard existing.workspaceID == workspaceID, existing.verifier == verifier, existing.status == .prepared
                else {
                    throw IPCContinuityRepositoryError.conflictingPreparedCredential
                }
                return
            }
            try database.execute(
                sql: """
                    INSERT INTO local_ipc_credential
                    (credential_namespace, pane_id, workspace_id, runtime_id, generation_id, verifier_sha256, status)
                    VALUES ('pane', ?, ?, NULL, ?, ?, 'prepared')
                    """,
                arguments: [paneID.uuidString, workspaceID.uuidString, generation.uuidString, verifier]
            )
        }
    }

    func activatePreparedPaneCredential(paneID: UUID, generation: UUID) async throws {
        try await datastore.performApplicationLocalWrite { database in
            guard
                let credential = try IPCContinuityRepository.fetchCredential(
                    database, paneID: paneID, generation: generation)
            else {
                throw IPCContinuityRepositoryError.cannotActivateCredential
            }
            switch credential.status {
            case .prepared:
                try database.execute(
                    sql: """
                        UPDATE local_ipc_credential SET status = 'active'
                        WHERE credential_namespace = 'pane' AND pane_id = ? AND generation_id = ? AND status = 'prepared'
                        """,
                    arguments: [paneID.uuidString, generation.uuidString]
                )
            case .active:
                return
            case .revoked:
                throw IPCContinuityRepositoryError.cannotActivateRevokedCredential
            case .superseded:
                throw IPCContinuityRepositoryError.cannotActivateCredential
            }
        }
    }

    func revokePreparedPaneCredential(paneID: UUID, generation: UUID) async throws {
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    UPDATE local_ipc_credential SET status = 'revoked'
                    WHERE credential_namespace = 'pane' AND pane_id = ? AND generation_id = ? AND status = 'prepared'
                    """,
                arguments: [paneID.uuidString, generation.uuidString]
            )
        }
    }

    func supersedeActivePaneCredential(paneID: UUID, generation: UUID) async throws {
        try await updatePaneCredentialStatus(paneID: paneID, generation: generation, from: .active, to: .superseded)
    }

    func revokeActivePaneCredential(paneID: UUID, generation: UUID) async throws {
        try await updatePaneCredentialStatus(paneID: paneID, generation: generation, from: .active, to: .revoked)
    }

    func persistPreparedDiagnosticCredential(runtimeID: UUID, generation: UUID, verifier: Data) async throws {
        guard verifier.count == 32 else { throw IPCContinuityRepositoryError.invalidVerifierLength }
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    INSERT INTO local_ipc_credential
                    (credential_namespace, pane_id, workspace_id, runtime_id, generation_id, verifier_sha256, status)
                    VALUES ('diagnostic', NULL, NULL, ?, ?, ?, 'prepared')
                    """, arguments: [runtimeID.uuidString, generation.uuidString, verifier])
        }
    }

    func activatePreparedDiagnosticCredential(runtimeID: UUID, generation: UUID) async throws {
        try await updateDiagnosticCredentialStatus(
            runtimeID: runtimeID, generation: generation, from: .prepared, to: .active)
    }

    func revokeDiagnosticCredential(runtimeID: UUID, generation: UUID) async throws {
        try await updateDiagnosticCredentialStatus(
            runtimeID: runtimeID, generation: generation, from: .active, to: .revoked)
    }

    func credential(for paneID: UUID, generation: UUID) async throws -> IPCContinuityCredential? {
        try await datastore.performApplicationLocalRead { database in
            try IPCContinuityRepository.fetchCredential(database, paneID: paneID, generation: generation)
        }
    }

    func credential(matchingVerifier verifier: Data) async throws -> IPCContinuityResolvedCredential? {
        guard verifier.count == 32 else { return nil }
        return try await datastore.performApplicationLocalRead { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT credential_namespace, pane_id, workspace_id, runtime_id, generation_id, verifier_sha256, status
                    FROM local_ipc_credential WHERE verifier_sha256 = ?
                    """,
                arguments: [verifier]
            )
            guard rows.count <= 1 else { throw IPCContinuityRepositoryError.ambiguousVerifier }
            guard let row = rows.first,
                let status = IPCContinuityCredentialStatus(rawValue: row["status"]),
                let generation = UUID(uuidString: row["generation_id"])
            else { return nil }
            if row["credential_namespace"] as String == "pane",
                let paneID = UUID(uuidString: row["pane_id"]),
                let workspaceID = UUID(uuidString: row["workspace_id"])
            {
                return .pane(
                    .init(
                        paneID: paneID, workspaceID: workspaceID, generation: generation,
                        verifier: row["verifier_sha256"], status: status))
            }
            guard let runtimeID = UUID(uuidString: row["runtime_id"]) else { return nil }
            return .diagnostic(
                runtimeID: runtimeID, generation: generation, verifier: row["verifier_sha256"], status: status)
        }
    }

    private static func fetchCredential(
        _ database: Database,
        paneID: UUID,
        generation: UUID
    ) throws -> IPCContinuityCredential? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT pane_id, workspace_id, generation_id, verifier_sha256, status
                    FROM local_ipc_credential
                    WHERE credential_namespace = 'pane' AND pane_id = ? AND generation_id = ?
                    """,
                arguments: [paneID.uuidString, generation.uuidString]
            ),
            let storedPaneID = UUID(uuidString: row["pane_id"]),
            let workspaceID = UUID(uuidString: row["workspace_id"]),
            let storedGeneration = UUID(uuidString: row["generation_id"]),
            let status = IPCContinuityCredentialStatus(rawValue: row["status"])
        else { return nil }
        return .init(
            paneID: storedPaneID,
            workspaceID: workspaceID,
            generation: storedGeneration,
            verifier: row["verifier_sha256"],
            status: status
        )
    }

    private func updatePaneCredentialStatus(
        paneID: UUID, generation: UUID, from: IPCContinuityCredentialStatus, to: IPCContinuityCredentialStatus
    ) async throws {
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    UPDATE local_ipc_credential SET status = ?
                    WHERE credential_namespace = 'pane' AND pane_id = ? AND generation_id = ? AND status = ?
                    """, arguments: [to.rawValue, paneID.uuidString, generation.uuidString, from.rawValue])
        }
    }

    private func updateDiagnosticCredentialStatus(
        runtimeID: UUID, generation: UUID, from: IPCContinuityCredentialStatus, to: IPCContinuityCredentialStatus
    ) async throws {
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    UPDATE local_ipc_credential SET status = ?
                    WHERE credential_namespace = 'diagnostic' AND runtime_id = ? AND generation_id = ? AND status = ?
                    """, arguments: [to.rawValue, runtimeID.uuidString, generation.uuidString, from.rawValue])
        }
    }
}
