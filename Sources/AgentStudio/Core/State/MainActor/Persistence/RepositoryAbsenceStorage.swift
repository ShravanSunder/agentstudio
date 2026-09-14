import Foundation
import GRDB

enum RepositoryAbsenceStorageError: Error {
    case invalidIdentity
    case invalidTiming
}

enum RepositoryAbsenceStorage {
    private enum Owner {
        case repository
        case worktree

        var table: String {
            switch self {
            case .repository: "unavailable_repo"
            case .worktree: "unavailable_worktree"
            }
        }

        var column: String {
            switch self {
            case .repository: "repo_id"
            case .worktree: "worktree_id"
            }
        }
    }

    static func read(_ database: Database) throws -> RepositoryTopologyAbsenceRecords {
        try RepositoryTopologyAbsenceRecords(
            repositories: read(database, owner: .repository),
            worktrees: read(database, owner: .worktree)
        )
    }

    static func clear(_ database: Database) throws {
        try database.execute(sql: "DELETE FROM unavailable_worktree")
        try database.execute(sql: "DELETE FROM unavailable_repo")
    }

    static func replace(_ database: Database, records: RepositoryTopologyAbsenceRecords) throws {
        try clear(database)
        try insert(database, records: records.repositories, owner: .repository)
        try insert(database, records: records.worktrees, owner: .worktree)
    }

    private static func read(_ database: Database, owner: Owner) throws -> [UUID: RepositoryLocationAbsence] {
        var records: [UUID: RepositoryLocationAbsence] = [:]
        for row in try Row.fetchAll(database, sql: "SELECT * FROM \(owner.table)") {
            let rawID: String = row[owner.column]
            guard let identifier = UUID(uuidString: rawID) else {
                throw RepositoryAbsenceStorageError.invalidIdentity
            }
            guard let firstAbsent: Double = row["first_absent_at_utc"] else {
                records[identifier] = .unconfirmed
                continue
            }
            let anchorUTC: Double = row["anchor_utc"]
            let bootID: String = row["anchor_boot_id"]
            let uptime: Int64 = row["anchor_uptime_ns"]
            let elapsed: Double = row["elapsed_before_anchor"]
            guard firstAbsent.isFinite, anchorUTC.isFinite, elapsed.isFinite,
                elapsed >= 0, uptime >= 0, !bootID.isEmpty
            else { throw RepositoryAbsenceStorageError.invalidTiming }
            records[identifier] = .confirmed(
                RepositoryAbsenceTiming(
                    firstAbsentAt: Date(timeIntervalSince1970: firstAbsent),
                    anchorUTC: Date(timeIntervalSince1970: anchorUTC),
                    anchorBootID: bootID,
                    anchorUptimeNanoseconds: uptime,
                    elapsedBeforeAnchor: elapsed
                )
            )
        }
        return records
    }

    private static func insert(
        _ database: Database,
        records: [UUID: RepositoryLocationAbsence],
        owner: Owner
    ) throws {
        for identifier in records.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let absence = records[identifier] else { continue }
            switch absence {
            case .unconfirmed:
                try database.execute(
                    sql: "INSERT INTO \(owner.table)(\(owner.column)) VALUES (?)",
                    arguments: [identifier.uuidString]
                )
            case .confirmed(let timing):
                try database.execute(
                    sql: """
                        INSERT INTO \(owner.table)(
                            \(owner.column), first_absent_at_utc, anchor_utc,
                            anchor_boot_id, anchor_uptime_ns, elapsed_before_anchor
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        identifier.uuidString,
                        timing.firstAbsentAt.timeIntervalSince1970,
                        timing.anchorUTC.timeIntervalSince1970,
                        timing.anchorBootID,
                        timing.anchorUptimeNanoseconds,
                        timing.elapsedBeforeAnchor,
                    ]
                )
            }
        }
    }
}
