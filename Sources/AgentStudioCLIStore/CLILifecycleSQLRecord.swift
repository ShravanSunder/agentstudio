import Foundation
import GRDB

/// Decode once at the SQL boundary; refusals carry a field, never the private value.
struct CLILifecycleSQLRecord {
    let report: CLILifecycleReport

    init(row: Row) throws {
        let sequence = try row.decode(Int64.self, forColumn: "sequence")
        func decode<Value: DatabaseValueConvertible>(_ field: CLILifecycleDecodeIssue.Field) throws -> Value {
            do { return try row.decode(Value.self, forColumn: field.rawValue) } catch {
                throw CLILifecycleDecodeIssue(sequence: sequence, field: field)
            }
        }
        func identifier(_ field: CLILifecycleDecodeIssue.Field) throws -> UUID {
            let value: String = try decode(field)
            guard let identifier = UUID(uuidString: value) else {
                throw CLILifecycleDecodeIssue(sequence: sequence, field: field)
            }
            return identifier
        }
        func text(_ field: CLILifecycleDecodeIssue.Field) throws -> String {
            let value: String = try decode(field)
            guard !value.isEmpty else { throw CLILifecycleDecodeIssue(sequence: sequence, field: field) }
            return value
        }
        let name: String = try decode(.eventName)
        let reason: String? = try decode(.endReason)
        let event: CLILifecycleEvent
        switch name {
        case "sessionStart": event = .sessionStart
        case "sessionEnd": event = .sessionEnd(reason: reason)
        default: throw CLILifecycleDecodeIssue(sequence: sequence, field: .eventName)
        }
        let milliseconds: Int64 = try decode(.recordedAt)
        report = CLILifecycleReport(
            sequence: sequence,
            record: .init(
                reportID: try identifier(.reportID), paneID: try identifier(.paneID),
                providerIdentifier: try text(.providerIdentifier), providerVersion: try text(.providerVersion),
                providerMode: try text(.providerMode), event: event, conversationID: try text(.conversationID),
                correlationID: try identifier(.correlationID),
                recordedAt: Date(timeIntervalSince1970: Double(milliseconds) / CLIStorePolicy.millisecondsPerSecond),
                bootSessionID: try text(.bootSessionID)))
    }
}
