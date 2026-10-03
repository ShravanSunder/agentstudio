import AgentStudioPrimitives
import Foundation
import GRDB

@testable import AgentStudioCLIStore

struct LifecycleStoreFileFixture: Sendable {
    let rootURL: URL
    let databaseURL: URL
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(path: "cli-lifecycle-\(UUIDv7.generate())")
        databaseURL = rootURL.appending(path: "cli.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func writer() throws -> CLIStore { try CLIStore.openWriter(url: databaseURL, channel: .debug).get() }
    func reader() throws -> CLIStore { try CLIStore.openReader(url: databaseURL, expectedChannel: .debug).get() }
    func remove() { try? FileManager.default.removeItem(at: rootURL) }

    func seed(_ records: [CLILifecycleReportRecord]) throws -> [CLILifecycleReport] {
        let store = try writer()
        return try store.databaseQueue.write { database in
            try records.map { record in
                let eventName: String
                let reason: String?
                switch record.event {
                case .sessionStart:
                    eventName = "sessionStart"
                    reason = nil
                case .sessionEnd(let value):
                    eventName = "sessionEnd"
                    reason = value
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
                        record.providerVersion, record.providerMode, eventName, record.conversationID, reason,
                        record.correlationID.uuidString, Int64(record.recordedAt.timeIntervalSince1970 * 1000),
                        record.bootSessionID,
                    ])
                return CLILifecycleReport(sequence: database.lastInsertedRowID, record: record)
            }
        }
    }

}

func lifecycleStoreRecord(
    paneID: UUID = UUIDv7.generate(), event: CLILifecycleEvent = .sessionStart,
    conversationID: String = UUIDv7.generate().uuidString,
    at date: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> CLILifecycleReportRecord {
    .init(
        reportID: UUIDv7.generate(), paneID: paneID, providerIdentifier: "codex", providerVersion: "0.154.0",
        providerMode: "cli", event: event, conversationID: conversationID, correlationID: UUIDv7.generate(),
        recordedAt: date, bootSessionID: "test-boot")
}
