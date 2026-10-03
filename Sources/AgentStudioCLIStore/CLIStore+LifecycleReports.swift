import Foundation
import GRDB

extension CLIStore {
    package func appendLifecycleReport(_ record: CLILifecycleReportRecord) -> Result<
        CLILifecycleReport, CLIStoreFailure
    > {
        guard !databaseQueue.configuration.readonly else { return .failure(.readOnly) }
        guard let milliseconds = Int64(exactly: (record.recordedAt.timeIntervalSince1970 * 1000).rounded()) else {
            return .failure(.unavailable)
        }
        do {
            return .success(
                try databaseQueue.write { database in
                    if let row = try Row.fetchOne(
                        database,
                        sql: "SELECT * FROM cli_lifecycle_report WHERE report_id=?",
                        arguments: [record.reportID.uuidString])
                    {
                        return try CLILifecycleSQLRecord(row: row).report
                    }
                    let name: String
                    let reason: String?
                    switch record.event {
                    case .sessionStart:
                        name = "sessionStart"
                        reason = nil
                    case .sessionEnd(let rawReason):
                        name = "sessionEnd"
                        reason = rawReason
                    }
                    try database.execute(
                        sql: """
                            INSERT INTO cli_lifecycle_report
                            (report_id,pane_id,provider_identifier,provider_version,provider_mode,event_name,
                             conversation_id,end_reason,correlation_id,recorded_at,boot_session_id)
                            VALUES (?,?,?,?,?,?,?,?,?,?,?)
                            """,
                        arguments: [
                            record.reportID.uuidString, record.paneID.uuidString, record.providerIdentifier,
                            record.providerVersion, record.providerMode, name, record.conversationID, reason,
                            record.correlationID.uuidString, milliseconds, record.bootSessionID,
                        ])
                    let row = try Row.fetchOne(
                        database, sql: "SELECT * FROM cli_lifecycle_report WHERE sequence=?",
                        arguments: [database.lastInsertedRowID])
                    guard let row else { throw CLIStoreFailure.unavailable }
                    return try CLILifecycleSQLRecord(row: row).report
                })
        } catch { return .failure(Self.lifecycleFailure(error)) }
    }

    package func lifecycleReportBoundary() -> Result<Int64, CLIStoreFailure> {
        do {
            return .success(
                try databaseQueue.read { database in
                    guard try database.tableExists("cli_lifecycle_report") else { return 0 }
                    return try Int64.fetchOne(
                        database, sql: "SELECT seq FROM sqlite_sequence WHERE name='cli_lifecycle_report'") ?? 0
                })
        } catch { return .failure(Self.lifecycleFailure(error)) }
    }

    package func readLifecycleReports(after mark: Int64, through boundary: Int64? = nil)
        -> Result<CLILifecycleReadBatch, CLIStoreFailure>
    {
        do {
            return .success(
                try databaseQueue.read { database in
                    guard try database.tableExists("cli_lifecycle_report") else {
                        return CLILifecycleReadBatch(reports: [], issues: [])
                    }
                    let rows = try Row.fetchAll(
                        database,
                        sql:
                            "SELECT * FROM cli_lifecycle_report WHERE sequence > ? AND sequence <= ? ORDER BY sequence",
                        arguments: [mark, boundary ?? Int64.max])
                    var reports: [CLILifecycleReport] = []
                    var issues: [CLILifecycleDecodeIssue] = []
                    for row in rows {
                        do { reports.append(try CLILifecycleSQLRecord(row: row).report) } catch let issue
                            as CLILifecycleDecodeIssue
                        { issues.append(issue) }
                    }
                    return CLILifecycleReadBatch(reports: reports, issues: issues)
                })
        } catch { return .failure(Self.lifecycleFailure(error)) }
    }

    package func purgeHandledLifecycleReports(expectedStoreID: UUID, through mark: Int64, now: Date)
        -> Result<Int, CLIStoreFailure>
    {
        guard !databaseQueue.configuration.readonly else { return .failure(.readOnly) }
        guard expectedStoreID == identity.storeID, mark > 0 else { return .success(0) }
        guard
            let cutoff = Int64(
                exactly: (now.addingTimeInterval(-CLIStorePolicy.handledRetention)
                    .timeIntervalSince1970 * CLIStorePolicy.millisecondsPerSecond).rounded(.up))
        else {
            return .failure(.unavailable)
        }
        do {
            return .success(
                try databaseQueue.write { database in
                    let identities = try Row.fetchAll(
                        database, sql: "SELECT store_id,channel FROM cli_store_identity LIMIT 2")
                    guard identities.count == 1, let row = identities.first,
                        let identifierText = try? row.decode(String.self, forColumn: "store_id"),
                        let currentID = UUID(uuidString: identifierText),
                        let channelText = try? row.decode(String.self, forColumn: "channel"),
                        let currentChannel = CLIStoreChannel(rawValue: channelText)
                    else { throw CLIStoreFailure.invalidIdentity }
                    guard currentChannel == identity.channel else { throw CLIStoreFailure.channelMismatch }
                    guard currentID == expectedStoreID else { return 0 }
                    try database.execute(
                        sql: "DELETE FROM cli_lifecycle_report WHERE sequence <= ? AND recorded_at < ?",
                        arguments: [mark, cutoff])
                    return database.changesCount
                })
        } catch { return .failure(Self.lifecycleFailure(error)) }
    }

    private static func lifecycleFailure(_ error: any Error) -> CLIStoreFailure {
        if let failure = error as? CLIStoreFailure { return failure }
        if let databaseError = error as? DatabaseError {
            switch databaseError.resultCode {
            case .SQLITE_BUSY, .SQLITE_LOCKED: return .busy
            case .SQLITE_READONLY: return .readOnly
            default: break
            }
        }
        return .unavailable
    }
}
