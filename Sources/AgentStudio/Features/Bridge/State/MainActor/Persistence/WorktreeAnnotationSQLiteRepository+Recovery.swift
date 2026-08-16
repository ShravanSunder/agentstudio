import Foundation
import GRDB

extension WorktreeAnnotationSQLiteRepository {
    func recordRecoveryProvenance(
        quarantinedFilenames: [String],
        reason: String,
        recoveredAt: Date
    ) throws -> WorktreeAnnotationRecoveryProvenance {
        let provenanceID = WorktreeAnnotationRecoveryProvenanceID.generate()
        let filenamesJSON = try Self.encodeJSONString(quarantinedFilenames)
        return try databaseWriter.write { database in
            try database.execute(
                sql: """
                    INSERT INTO local_recovery_provenance(
                        id, recovery_kind, recovered_at, quarantined_filenames_json,
                        reason, acknowledged_at
                    ) VALUES (?, 'local_database_quarantine', ?, ?, ?, NULL)
                    """,
                arguments: [
                    provenanceID.databaseValue,
                    recoveredAt.timeIntervalSince1970,
                    filenamesJSON,
                    reason,
                ]
            )
            return try loadRecoveryProvenance(database, id: provenanceID)
        }
    }

    func fetchRecoveryProvenance(
        id: WorktreeAnnotationRecoveryProvenanceID
    ) throws -> WorktreeAnnotationRecoveryProvenance {
        try databaseWriter.read { database in
            try loadRecoveryProvenance(database, id: id)
        }
    }

    func fetchUnacknowledgedRecoveryProvenance() throws -> WorktreeAnnotationRecoveryProvenance? {
        try databaseWriter.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT * FROM local_recovery_provenance
                        WHERE acknowledged_at IS NULL
                        ORDER BY recovered_at DESC, id DESC
                        LIMIT 1
                        """
                )
            else {
                return nil
            }
            return try decodeRecoveryProvenance(row)
        }
    }

    func acknowledgeRecoveryProvenance(
        id: WorktreeAnnotationRecoveryProvenanceID,
        acknowledgedAt: Date
    ) throws -> WorktreeAnnotationRecoveryProvenance {
        try databaseWriter.write { database in
            try database.execute(
                sql: """
                    UPDATE local_recovery_provenance
                    SET acknowledged_at = COALESCE(acknowledged_at, ?)
                    WHERE id = ?
                    """,
                arguments: [acknowledgedAt.timeIntervalSince1970, id.databaseValue]
            )
            guard database.changesCount == 1 else { throw WorktreeAnnotationRepositoryError.notFound }
            return try loadRecoveryProvenance(database, id: id)
        }
    }

    func loadRecoveryProvenance(
        _ database: Database,
        id: WorktreeAnnotationRecoveryProvenanceID
    ) throws -> WorktreeAnnotationRecoveryProvenance {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM local_recovery_provenance WHERE id = ?",
                arguments: [id.databaseValue]
            )
        else {
            throw WorktreeAnnotationRepositoryError.notFound
        }
        return try decodeRecoveryProvenance(row)
    }

    func decodeRecoveryProvenance(_ row: Row) throws -> WorktreeAnnotationRecoveryProvenance {
        let filenamesJSON: String = row["quarantined_filenames_json"]
        return try WorktreeAnnotationRecoveryProvenance(
            id: decodeIdentity(row["id"] as String),
            recoveredAt: Date(timeIntervalSince1970: row["recovered_at"]),
            quarantinedFilenames: Self.jsonDecoder.decode([String].self, from: Data(filenamesJSON.utf8)),
            reason: row["reason"],
            acknowledgedAt: (row["acknowledged_at"] as Double?).map(Date.init(timeIntervalSince1970:))
        )
    }
}
