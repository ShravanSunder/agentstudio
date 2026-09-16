import AgentStudioCore
import Foundation
import GRDB

actor IPCContinuityRepository {
    private let datastore: WorkspaceSQLiteDatastoreActor

    init(datastore: WorkspaceSQLiteDatastoreActor) {
        self.datastore = datastore
    }

    func registerPaneCredential(_ credential: IPCPaneCredential) async throws {
        guard credential.verifierSHA256.count == 32 else {
            throw IPCContinuityRepositoryError.invalidVerifierLength
        }
        try await datastore.performApplicationLocalWrite { database in
            if let existing = try Self.fetchPaneCredential(
                database,
                paneID: credential.paneID,
                credentialRecordID: credential.credentialRecordID
            ) {
                guard existing == credential else {
                    throw IPCContinuityRepositoryError.conflictingCredentialRecord
                }
                return
            }
            try database.execute(
                sql: """
                    INSERT INTO local_ipc_credential(
                        credential_namespace, pane_id, workspace_id, runtime_id,
                        credential_record_id, generation_id, verifier_sha256, status
                    ) VALUES ('pane', ?, ?, NULL, ?, NULL, ?, ?)
                    """,
                arguments: [
                    credential.paneID.uuidString,
                    credential.workspaceID.uuidString,
                    credential.credentialRecordID.uuidString,
                    credential.verifierSHA256,
                    credential.status.rawValue,
                ]
            )
        }
    }

    func paneCredential(paneID: UUID, credentialRecordID: UUID) async throws -> IPCPaneCredential? {
        try await datastore.performApplicationLocalRead { database in
            try Self.fetchPaneCredential(database, paneID: paneID, credentialRecordID: credentialRecordID)
        }
    }

    func paneCredentials(paneID: UUID) async throws -> [IPCPaneCredential] {
        try await datastore.performApplicationLocalRead { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT pane_id, workspace_id, credential_record_id, verifier_sha256, status
                    FROM local_ipc_credential
                    WHERE credential_namespace = 'pane' AND pane_id = ?
                    ORDER BY credential_record_id
                    """,
                arguments: [paneID.uuidString]
            ).compactMap(Self.decodePaneCredential)
        }
    }

    func revokeAllPaneCredentials(paneID: UUID) async throws {
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    UPDATE local_ipc_credential SET status = 'revoked'
                    WHERE credential_namespace = 'pane' AND pane_id = ?
                    """,
                arguments: [paneID.uuidString]
            )
        }
    }

    func persistPreparedDiagnosticCredential(runtimeID: UUID, generation: UUID, verifier: Data) async throws {
        guard verifier.count == 32 else { throw IPCContinuityRepositoryError.invalidVerifierLength }
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    INSERT INTO local_ipc_credential(
                        credential_namespace, pane_id, workspace_id, runtime_id,
                        credential_record_id, generation_id, verifier_sha256, status
                    ) VALUES ('diagnostic', NULL, NULL, ?, NULL, ?, ?, 'prepared')
                    """,
                arguments: [runtimeID.uuidString, generation.uuidString, verifier]
            )
        }
    }

    func activatePreparedDiagnosticCredential(runtimeID: UUID, generation: UUID) async throws {
        try await updateDiagnosticCredentialStatus(
            runtimeID: runtimeID,
            generation: generation,
            from: .prepared,
            to: .active
        )
    }

    func revokeDiagnosticCredential(runtimeID: UUID, generation: UUID) async throws {
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    UPDATE local_ipc_credential SET status = 'revoked'
                    WHERE credential_namespace = 'diagnostic'
                        AND runtime_id = ? AND generation_id = ?
                    """,
                arguments: [runtimeID.uuidString, generation.uuidString]
            )
        }
    }

    func credential(matchingVerifier verifier: Data) async throws -> IPCContinuityResolvedCredential? {
        guard verifier.count == 32 else { return nil }
        return try await datastore.performApplicationLocalRead { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT credential_namespace, pane_id, workspace_id, runtime_id,
                        credential_record_id, generation_id, verifier_sha256, status
                    FROM local_ipc_credential WHERE verifier_sha256 = ?
                    """,
                arguments: [verifier]
            )
            guard rows.count <= 1 else { throw IPCContinuityRepositoryError.ambiguousVerifier }
            guard let row = rows.first else { return nil }
            if row["credential_namespace"] as String == "pane" {
                return Self.decodePaneCredential(row).map(IPCContinuityResolvedCredential.pane)
            }
            guard
                let runtimeID = UUID(uuidString: row["runtime_id"]),
                let generationID = UUID(uuidString: row["generation_id"]),
                let status = IPCDiagnosticCredentialStatus(rawValue: row["status"])
            else { return nil }
            return .diagnostic(
                runtimeID: runtimeID,
                generationID: generationID,
                verifierSHA256: row["verifier_sha256"],
                status: status
            )
        }
    }

    private static func fetchPaneCredential(
        _ database: Database,
        paneID: UUID,
        credentialRecordID: UUID
    ) throws -> IPCPaneCredential? {
        guard
            let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT pane_id, workspace_id, credential_record_id, verifier_sha256, status
                    FROM local_ipc_credential
                    WHERE credential_namespace = 'pane'
                        AND pane_id = ? AND credential_record_id = ?
                    """,
                arguments: [paneID.uuidString, credentialRecordID.uuidString]
            )
        else { return nil }
        return decodePaneCredential(row)
    }

    private static func decodePaneCredential(_ row: Row) -> IPCPaneCredential? {
        guard
            let paneID = UUID(uuidString: row["pane_id"]),
            let workspaceID = UUID(uuidString: row["workspace_id"]),
            let credentialRecordID = UUID(uuidString: row["credential_record_id"]),
            let status = IPCPaneCredentialStatus(rawValue: row["status"])
        else { return nil }
        return .init(
            paneID: paneID,
            workspaceID: workspaceID,
            credentialRecordID: credentialRecordID,
            verifierSHA256: row["verifier_sha256"],
            status: status
        )
    }

    private func updateDiagnosticCredentialStatus(
        runtimeID: UUID,
        generation: UUID,
        from: IPCDiagnosticCredentialStatus,
        to: IPCDiagnosticCredentialStatus
    ) async throws {
        try await datastore.performApplicationLocalWrite { database in
            try database.execute(
                sql: """
                    UPDATE local_ipc_credential SET status = ?
                    WHERE credential_namespace = 'diagnostic'
                        AND runtime_id = ? AND generation_id = ? AND status = ?
                    """,
                arguments: [to.rawValue, runtimeID.uuidString, generation.uuidString, from.rawValue]
            )
            guard database.changesCount == 1 else {
                throw IPCContinuityRepositoryError.cannotTransitionDiagnosticCredential
            }
        }
    }
}
