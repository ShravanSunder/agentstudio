import AgentStudioAppIPC
import AgentStudioCore
import Foundation
import GRDB

enum IPCContinuityRepositoryError: Error, Equatable {
    case invalidVerifierLength
    case conflictingCredentialRecord
    case ambiguousVerifier
}

actor IPCContinuityRepository {
    private let datastore: WorkspaceSQLiteDatastoreActor

    init(datastore: WorkspaceSQLiteDatastoreActor) {
        self.datastore = datastore
    }

    @discardableResult
    func registerPaneCredential(
        _ credential: IPCPaneCredential,
        if remainsEligible: @escaping @Sendable () -> Bool = { true }
    ) async throws -> Bool {
        guard credential.verifierSHA256.count == 32 else {
            throw IPCContinuityRepositoryError.invalidVerifierLength
        }
        return try await datastore.performApplicationLocalWrite { database in
            guard remainsEligible() else { return false }
            if let existing = try Self.fetchPaneCredential(
                database,
                paneID: credential.paneID,
                credentialRecordID: credential.credentialRecordID
            ) {
                guard existing == credential else {
                    throw IPCContinuityRepositoryError.conflictingCredentialRecord
                }
                return true
            }
            try database.execute(
                sql: """
                    INSERT INTO local_ipc_credential(
                        pane_id, workspace_id, credential_record_id, verifier_sha256, status
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    credential.paneID.uuidString,
                    credential.workspaceID.uuidString,
                    credential.credentialRecordID.uuidString,
                    credential.verifierSHA256,
                    credential.status.rawValue,
                ]
            )
            return true
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
                    WHERE pane_id = ?
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
                    WHERE pane_id = ?
                    """,
                arguments: [paneID.uuidString]
            )
        }
    }

    func credential(matchingVerifier verifier: Data) async throws -> IPCPaneCredential? {
        guard verifier.count == 32 else { return nil }
        return try await datastore.performApplicationLocalRead { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT pane_id, workspace_id, credential_record_id, verifier_sha256, status
                    FROM local_ipc_credential WHERE verifier_sha256 = ?
                    """,
                arguments: [verifier]
            )
            guard rows.count <= 1 else { throw IPCContinuityRepositoryError.ambiguousVerifier }
            guard let row = rows.first else { return nil }
            return Self.decodePaneCredential(row)
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
                    WHERE pane_id = ? AND credential_record_id = ?
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

}

extension IPCContinuityRepository: AgentStudioIPCCredentialContinuityPort {
    func registerIssuedPaneCredential(
        _ credential: AgentStudioIPCIssuedPaneCredential,
        if remainsEligible: @escaping @Sendable () -> Bool
    ) async throws -> Bool {
        try await registerPaneCredential(
            IPCPaneCredential(
                paneID: credential.paneID,
                workspaceID: credential.workspaceID,
                credentialRecordID: credential.credentialRecordID,
                verifierSHA256: credential.verifierSHA256,
                status: .registered
            ),
            if: remainsEligible
        )
    }
}
