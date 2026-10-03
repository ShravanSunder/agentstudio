import Foundation

package enum CLILifecycleEvent: Equatable, Sendable {
    case sessionStart
    case sessionEnd(reason: String?)
}

/// The immutable lifecycle envelope; SQL and wire adapters validate at their boundaries.
package struct CLILifecycleReportRecord: Equatable, Sendable {
    package let reportID: UUID
    package let paneID: UUID
    package let providerIdentifier: String
    package let providerVersion: String
    package let providerMode: String
    package let event: CLILifecycleEvent
    package let conversationID: String
    package let correlationID: UUID
    package let recordedAt: Date
    package let bootSessionID: String

    package init(
        reportID: UUID, paneID: UUID, providerIdentifier: String, providerVersion: String,
        providerMode: String, event: CLILifecycleEvent, conversationID: String, correlationID: UUID,
        recordedAt: Date, bootSessionID: String
    ) {
        self.reportID = reportID
        self.paneID = paneID
        self.providerIdentifier = providerIdentifier
        self.providerVersion = providerVersion
        self.providerMode = providerMode
        self.event = event
        self.conversationID = conversationID
        self.correlationID = correlationID
        self.recordedAt = recordedAt
        self.bootSessionID = bootSessionID
    }
}

package struct CLILifecycleReport: Equatable, Sendable {
    package let sequence: Int64
    package let record: CLILifecycleReportRecord
    package init(sequence: Int64, record: CLILifecycleReportRecord) {
        self.sequence = sequence
        self.record = record
    }
}

package struct CLILifecycleDecodeIssue: Error, Equatable, Sendable {
    package enum Field: String, Sendable {
        case reportID = "report_id"
        case paneID = "pane_id"
        case providerIdentifier = "provider_identifier"
        case providerVersion = "provider_version"
        case providerMode = "provider_mode"
        case eventName = "event_name"
        case conversationID = "conversation_id"
        case endReason = "end_reason"
        case correlationID = "correlation_id"
        case recordedAt = "recorded_at"
        case bootSessionID = "boot_session_id"
    }
    package let sequence: Int64
    package let field: Field
}

package struct CLILifecycleReadBatch: Equatable, Sendable {
    package let reports: [CLILifecycleReport]
    package let issues: [CLILifecycleDecodeIssue]
}
